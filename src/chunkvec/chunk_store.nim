import std/strutils
import db_connector/[db_sqlite, sqlite3]
import ./[constants, types]

export db_sqlite

proc packFloat32Blob(values: openArray[float32]): seq[byte] =
  result = newSeq[byte](values.len * sizeof(float32))
  if result.len > 0:
    copyMem(addr result[0], addr values[0], result.len)

when defined(windows):
  when defined(nimOldDlls):
    const SqliteDynlib = "sqlite3.dll"
  elif defined(cpu64):
    const SqliteDynlib = "sqlite3_64.dll"
  else:
    const SqliteDynlib = "sqlite3_32.dll"
elif defined(macosx):
  const SqliteDynlib = "libsqlite3(|.0).dylib"
else:
  const SqliteDynlib = "libsqlite3.so(|.0)"

proc sqlite3EnableLoadExtension(db: DbConn; onoff: int32): int32 {.
    cdecl, dynlib: SqliteDynlib, importc: "sqlite3_enable_load_extension".}
proc sqlite3LoadExtension(db: DbConn; file: cstring; procName: cstring;
    errMsg: ptr cstring): int32 {.
    cdecl, dynlib: SqliteDynlib, importc: "sqlite3_load_extension".}

proc sqliteError(db: DbConn; action: string): ref IOError {.noinline.} =
  let message =
    if db.isNil:
      action
    else:
      action & ": " & $sqlite3.errmsg(db)
  result = newException(IOError, message)

proc checkSqliteRc(db: DbConn; rc: int32; action: string) =
  if rc != SQLITE_OK:
    raise db.sqliteError(action)

proc textColumn(row: InstantRow; index: int32): string =
  let value = unsafeColumnAt(row, index)
  if not value.isNil:
    result = $value

proc isNil(stmt: SqlPrepared): bool {.inline.} =
  result = sqlite3.PStmt(stmt).isNil

proc resetStatement(db: DbConn; stmt: SqlPrepared; action: string) =
  if sqlite3.reset(sqlite3.PStmt(stmt)) != SQLITE_OK:
    raise db.sqliteError(action)
  if sqlite3.clear_bindings(sqlite3.PStmt(stmt)) != SQLITE_OK:
    raise db.sqliteError(action)

proc openDatabase*(path: string): DbConn =
  result = db_sqlite.open(path, "", "", "")

proc loadExtension*(db: DbConn; extensionPath: string) =
  db.checkSqliteRc(
    sqlite3EnableLoadExtension(db, 1),
    "failed to enable sqlite extension loading"
  )

  var errMsg: cstring = nil
  let rc = sqlite3LoadExtension(db, extensionPath, nil, addr errMsg)
  if rc != SQLITE_OK:
    var message = "failed to load sqlite extension " & extensionPath
    if not errMsg.isNil:
      message &= ": " & $errMsg
      sqlite3.free(errMsg)
    raise newException(IOError, message)

  db.checkSqliteRc(sqlite3EnableLoadExtension(db, 0), "failed to disable sqlite extension loading")

proc initSchema*(db: DbConn) =
  db.exec(sql(
    """CREATE TABLE IF NOT EXISTS """ & TableName & """ (
  id INTEGER PRIMARY KEY,
  source TEXT NOT NULL,
  ordinal INTEGER NOT NULL,
  text TEXT NOT NULL,
  """ & EmbeddingColumn & """ BLOB NOT NULL,
  page INTEGER,
  section TEXT,
  metadata_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);"""
  ))
  db.exec(sql(
    """CREATE INDEX IF NOT EXISTS idx_chunks_source_ordinal
  ON """ & TableName & """(source, ordinal);"""
  ))

proc beginTransaction*(db: DbConn) =
  db.exec(sql"BEGIN IMMEDIATE TRANSACTION;")

proc commitTransaction*(db: DbConn) =
  db.exec(sql"COMMIT;")

proc rollbackTransaction*(db: DbConn) =
  db.exec(sql"ROLLBACK;")

proc initializeVectorTable*(db: DbConn) =
  let options =
    "type=" & VectorType &
    ",dimension=" & $EmbeddingDimension &
    ",distance=" & DistanceMetric
  discard db.getValue(sql"SELECT vector_init(?, ?, ?);", TableName, EmbeddingColumn, options)

proc prepareInsertStatement*(db: DbConn): SqlPrepared =
  result = db.prepare(
    """INSERT INTO """ & TableName & """(
  source,
  ordinal,
  text,
  """ & EmbeddingColumn & """,
  page,
  section,
  metadata_json
) VALUES (?, ?, ?, vector_as_f32(?), ?, ?, ?);
"""
  )

proc insertChunk*(db: DbConn; stmt: SqlPrepared; record: ChunkRecord) =
  db.resetStatement(stmt, "failed to reset insert statement")

  stmt.bindParam(1, record.chunk.source)
  stmt.bindParam(2, record.chunk.ordinal)
  stmt.bindParam(3, record.chunk.text)
  stmt.bindParam(4, packFloat32Blob(record.embedding))

  if record.chunk.hasPage:
    stmt.bindParam(5, record.chunk.page)
  else:
    stmt.bindNull(5)

  if record.chunk.section.len > 0:
    stmt.bindParam(6, record.chunk.section)
  else:
    stmt.bindNull(6)

  if record.chunk.metadataJson.len > 0:
    stmt.bindParam(7, record.chunk.metadataJson)
  else:
    stmt.bindNull(7)

  if not db.tryExec(stmt):
    raise db.sqliteError("failed to insert chunk row")

proc rebuildQuantization*(db: DbConn) =
  let options = "qtype=" & QuantizationType
  discard db.getValue(sql"SELECT vector_quantize(?, ?, ?);", TableName, EmbeddingColumn, options)
  discard db.getValue(sql"SELECT vector_quantize_preload(?, ?);", TableName, EmbeddingColumn)

proc rowCount*(db: DbConn): int =
  result = parseInt(db.getValue(sql("SELECT COUNT(*) FROM " & TableName & ";")))

proc runSearch(db: DbConn; scanProc: string; queryVector: openArray[float32];
    topK: int): seq[SearchResult] =
  let query =
    """SELECT
  c.id,
  v.distance,
  c.source,
  c.ordinal,
  c.text,
  c.page,
  c.section
FROM """ & TableName & """ AS c
JOIN """ & scanProc & """('""" & TableName & """', '""" &
    EmbeddingColumn & """', ?, ?) AS v
  ON c.id = v.rowid
ORDER BY v.distance ASC, c.id ASC;
"""

  var stmt: SqlPrepared
  try:
    stmt = db.prepare(query)
    stmt.bindParam(1, packFloat32Blob(queryVector))
    stmt.bindParam(2, topK)

    for row in db.instantRows(stmt):
      var resultRow = SearchResult(
        id: sqlite3.column_int64(row, 0),
        distance: sqlite3.column_double(row, 1).float,
        source: row.textColumn(2),
        ordinal: sqlite3.column_int(row, 3).int,
        text: row.textColumn(4),
        hasPage: false,
        page: 0,
        section: ""
      )

      if sqlite3.column_type(row, 5) != SQLITE_NULL:
        resultRow.hasPage = true
        resultRow.page = sqlite3.column_int(row, 5).int

      if sqlite3.column_type(row, 6) != SQLITE_NULL:
        resultRow.section = row.textColumn(6)

      result.add(resultRow)
  finally:
    if not stmt.isNil:
      stmt.finalize()

proc searchChunks*(db: DbConn; queryVector: openArray[float32];
    topK: int): seq[SearchResult] =
  result = db.runSearch("vector_quantize_scan", queryVector, topK)
