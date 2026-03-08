import std/strutils
import db_connector/[db_sqlite, sqlite3]
import ./[constants, types]

export db_sqlite

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

proc checkSqliteRc(db: DbConn; rc: int32) =
  if rc != SQLITE_OK:
    dbError(db)

proc bindParam*(ps: SqlPrepared; paramIdx: int; val: seq[float32]; copy = true) =
  let len = val.len * sizeof(float32)
  if bind_blob(ps.PStmt, paramIdx.int32, if val.len > 0: cast[pointer](addr val[0]) else: nil, len.int32,
      if copy: SQLITE_TRANSIENT else: SQLITE_STATIC) != SQLITE_OK:
    dbBindParamError(paramIdx, val)

proc textColumn(row: InstantRow; index: int32): string =
  let value = unsafeColumnAt(row, index)
  if not value.isNil:
    result = $value

proc isNil(stmt: SqlPrepared): bool {.inline.} =
  result = sqlite3.PStmt(stmt).isNil

proc openDatabase*(path: string): DbConn =
  result = db_sqlite.open(path, "", "", "")

proc loadExtension*(db: DbConn; extensionPath: string) =
  db.checkSqliteRc(sqlite3EnableLoadExtension(db, 1))

  var errMsg: cstring = nil
  let rc = sqlite3LoadExtension(db, extensionPath, nil, addr errMsg)
  if rc != SQLITE_OK:
    var message = "failed to load sqlite extension " & extensionPath
    if not errMsg.isNil:
      message.add ": " & $errMsg
      sqlite3.free(errMsg)
    raise newException(IOError, message)

  db.checkSqliteRc(sqlite3EnableLoadExtension(db, 0))

proc initSchema*(db: DbConn) =
  db.exec(sql(
    """CREATE TABLE IF NOT EXISTS """ & TableName & """ (
  id INTEGER PRIMARY KEY,
  source TEXT NOT NULL,
  ordinal INTEGER NOT NULL,
  text TEXT NOT NULL,
  """ & EmbeddingColumn & """ BLOB NOT NULL,
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
  metadata_json
) VALUES (?, ?, ?, ?, ?);
"""
  )

proc rebuildQuantization*(db: DbConn) =
  let options = "qtype=" & QuantizationType
  discard db.getValue(sql"SELECT vector_quantize(?, ?, ?);", TableName, EmbeddingColumn, options)
  discard db.getValue(sql"SELECT vector_quantize_preload(?, ?);", TableName, EmbeddingColumn)

proc rowCount*(db: DbConn): int =
  result = parseInt(db.getValue(sql("SELECT COUNT(*) FROM " & TableName & ";")))

proc runSearch(db: DbConn; scanProc: string; queryVector: seq[float32];
    topK: int): seq[SearchResult] =
  let query =
    """SELECT
  c.id,
  v.distance,
  c.source,
  c.ordinal,
  c.text,
  c.metadata_json
FROM """ & TableName & """ AS c
JOIN """ & scanProc & """('""" & TableName & """', '""" &
    EmbeddingColumn & """', ?, ?) AS v
  ON c.id = v.rowid
ORDER BY v.distance ASC, c.id ASC;
"""

  var stmt: SqlPrepared
  try:
    stmt = db.prepare(query)
    stmt.bindParam(1, queryVector)
    stmt.bindParam(2, topK)

    for row in db.instantRows(stmt):
      var resultRow = SearchResult(
        id: sqlite3.column_int64(row, 0),
        distance: sqlite3.column_double(row, 1).float,
        source: row.textColumn(2),
        ordinal: sqlite3.column_int(row, 3).int,
        text: row.textColumn(4),
        metadataJson: row.textColumn(5)
      )

      result.add(resultRow)
  finally:
    if not stmt.isNil:
      stmt.finalize()

proc searchChunks*(db: DbConn; queryVector: seq[float32];
    topK: int): seq[SearchResult] =
  result = db.runSearch("vector_quantize_scan", queryVector, topK)
