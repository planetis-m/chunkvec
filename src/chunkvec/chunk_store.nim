import std/[strformat, strutils]
import db_connector/[db_sqlite, sqlite3]
import ./[constants, logging, types]

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

proc raiseIoError(action: string): ref IOError {.noinline.} =
  result = newException(IOError, action & ": " & getCurrentExceptionMsg())

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
  try:
    result = db_sqlite.open(path, "", "", "")
  except CatchableError:
    raise raiseIoError("failed to open sqlite database at " & path)

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

  db.checkSqliteRc(
    sqlite3EnableLoadExtension(db, 0),
    "failed to disable sqlite extension loading"
  )

proc initSchema*(db: DbConn) =
  try:
    db.exec(sql(fmt"""
CREATE TABLE IF NOT EXISTS {TableName} (
  id INTEGER PRIMARY KEY,
  source TEXT NOT NULL,
  ordinal INTEGER NOT NULL,
  text TEXT NOT NULL,
  {EmbeddingColumn} BLOB NOT NULL,
  page INTEGER,
  section TEXT,
  metadata_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);"""))
    db.exec(sql(fmt"""
CREATE INDEX IF NOT EXISTS idx_chunks_source_ordinal
  ON {TableName}(source, ordinal);"""))
    db.exec(sql(fmt"""
CREATE TABLE IF NOT EXISTS {MetaTableName} (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);"""))
  except CatchableError:
    raise raiseIoError("failed to initialize sqlite schema")

proc beginTransaction*(db: DbConn) =
  try:
    db.exec(sql"BEGIN IMMEDIATE TRANSACTION;")
  except CatchableError:
    raise raiseIoError("failed to begin transaction")

proc commitTransaction*(db: DbConn) =
  try:
    db.exec(sql"COMMIT;")
  except CatchableError:
    raise raiseIoError("failed to commit transaction")

proc rollbackTransaction*(db: DbConn) =
  try:
    db.exec(sql"ROLLBACK;")
  except CatchableError:
    raise raiseIoError("failed to roll back transaction")

proc readMetadata*(db: DbConn): DbMetadata =
  try:
    for row in db.fastRows(sql(fmt"SELECT key, value FROM {MetaTableName};")):
      let key = row[0]
      let value = row[1]
      case key
      of "model":
        result.model = value
      of "dimension":
        result.dimension = parseInt(value)
      of "distance":
        result.distance = value
      of "qtype":
        result.qtype = value
      else:
        discard

    result.initialized =
      result.model.len > 0 and
      result.dimension > 0 and
      result.distance.len > 0 and
      result.qtype.len > 0
  except CatchableError:
    raise raiseIoError("failed to read sqlite metadata")

proc writeMetadata*(db: DbConn; meta: DbMetadata) =
  var stmt: SqlPrepared
  try:
    stmt = db.prepare(
      fmt"INSERT OR REPLACE INTO {MetaTableName}(key, value) VALUES (?, ?);"
    )

    for pair in [
      ("model", meta.model),
      ("dimension", $meta.dimension),
      ("distance", meta.distance),
      ("qtype", meta.qtype)
    ]:
      db.exec(stmt, pair[0], pair[1])
  except CatchableError:
    raise raiseIoError("failed to write sqlite metadata")
  finally:
    if not stmt.isNil:
      stmt.finalize()

proc initializeVectorTable*(db: DbConn; meta: DbMetadata) =
  if not meta.initialized:
    return

  let options = fmt"type=FLOAT32,dimension={meta.dimension},distance={meta.distance}"
  try:
    discard db.getValue(
      sql(fmt"SELECT vector_init('{TableName}', '{EmbeddingColumn}', '{options}');")
    )
  except CatchableError:
    raise raiseIoError("failed to execute vector_init")

proc configuredMetadata*(model: string; dimension: int): DbMetadata =
  DbMetadata(
    initialized: true,
    model: model,
    dimension: dimension,
    distance: DistanceMetric,
    qtype: QuantizationType
  )

proc ensureMetadataCompatible*(meta: DbMetadata; model: string; dimension: int) =
  if not meta.initialized:
    return
  if meta.model != model:
    raise newException(ValueError,
      "database model mismatch: expected " & meta.model & ", got " & model)
  if meta.dimension != dimension:
    raise newException(ValueError,
      "database embedding dimension mismatch: expected " & $meta.dimension &
      ", got " & $dimension)

proc prepareInsertStatement*(db: DbConn): SqlPrepared =
  try:
    result = db.prepare(fmt"""
INSERT INTO {TableName}(
  source,
  ordinal,
  text,
  {EmbeddingColumn},
  page,
  section,
  metadata_json
) VALUES (?, ?, ?, vector_as_f32(?), ?, ?, ?);
""")
  except CatchableError:
    raise raiseIoError("failed to prepare chunk insert")

proc insertChunk*(db: DbConn; stmt: SqlPrepared; record: ChunkRecord) =
  db.resetStatement(stmt, "failed to reset insert statement")

  try:
    stmt.bindParam(1, record.chunk.source)
    stmt.bindParam(2, record.chunk.ordinal)
    stmt.bindParam(3, record.chunk.text)
    stmt.bindParam(4, record.embeddingBlob)

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

    if sqlite3.step(sqlite3.PStmt(stmt)) != SQLITE_DONE:
      raise db.sqliteError("failed to insert chunk row")
  except CatchableError:
    raise raiseIoError("failed to insert chunk row")

proc rebuildQuantization*(db: DbConn; meta: DbMetadata) =
  if not meta.initialized:
    return

  try:
    discard db.getValue(
      sql(fmt"SELECT vector_quantize('{TableName}', '{EmbeddingColumn}', 'qtype={meta.qtype}');")
    )
  except CatchableError:
    raise raiseIoError("failed to execute vector_quantize")

  try:
    discard db.getValue(
      sql(fmt"SELECT vector_quantize_preload('{TableName}', '{EmbeddingColumn}');")
    )
  except CatchableError:
    raise raiseIoError("failed to execute vector_quantize_preload")

proc rowCount*(db: DbConn): int =
  try:
    result = parseInt(db.getValue(sql(fmt"SELECT COUNT(*) FROM {TableName};")))
  except CatchableError:
    raise raiseIoError("failed to count chunk rows")

proc runSearch(db: DbConn; scanProc: string; queryBlob: openArray[byte];
    topK: int): seq[SearchResult] =
  let query = fmt"""
SELECT
  c.id,
  v.distance,
  c.source,
  c.ordinal,
  c.text,
  c.page,
  c.section
FROM {TableName} AS c
JOIN {scanProc}('{TableName}', '{EmbeddingColumn}', ?, ?) AS v
  ON c.id = v.rowid
ORDER BY v.distance ASC, c.id ASC;
"""

  var stmt: SqlPrepared
  try:
    stmt = db.prepare(query)
    stmt.bindParam(1, queryBlob)
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
  except CatchableError:
    raise raiseIoError("failed to execute vector search")
  finally:
    if not stmt.isNil:
      stmt.finalize()

proc searchChunks*(db: DbConn; queryBlob: openArray[byte];
    topK: int): seq[SearchResult] =
  try:
    result = db.runSearch("vector_quantize_scan", queryBlob, topK)
  except CatchableError:
    let message = getCurrentExceptionMsg()
    if message.toLowerAscii().contains("vector_quantize") or
        message.toLowerAscii().contains("quantization"):
      logWarn("quantized search unavailable; falling back to full scan")
      result = db.runSearch("vector_full_scan", queryBlob, topK)
    else:
      raise
