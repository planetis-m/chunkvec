import std/[strformat, strutils]
import ./bindings/sqlite3
import ./[constants, logging, types]

type
  Database* = object
    handle: Sqlite3

  Statement* = object
    handle: Sqlite3Stmt

proc dbError(db: Database; action: string): ref IOError {.noinline.} =
  let message =
    if db.handle.isNil:
      action
    else:
      action & ": " & $sqlite3_errmsg(db.handle)
  result = newException(IOError, message)

proc checkRc(db: Database; rc: cint; action: string) =
  if rc != SQLITE_OK:
    raise db.dbError(action)

proc checkStmtRc(db: Database; stmt: Statement; rc: cint; action: string) =
  if rc != SQLITE_OK:
    if not stmt.handle.isNil:
      discard sqlite3_finalize(stmt.handle)
    raise db.dbError(action)

proc openDatabase*(path: string): Database =
  var handle: Sqlite3 = nil
  let rc = sqlite3_open(path, handle)
  result = Database(handle: handle)
  if rc != SQLITE_OK:
    raise result.dbError("failed to open sqlite database at " & path)

proc close*(db: var Database) =
  if not db.handle.isNil:
    discard sqlite3_close_v2(db.handle)
    db.handle = nil

proc finalize*(stmt: var Statement) =
  if not stmt.handle.isNil:
    discard sqlite3_finalize(stmt.handle)
    stmt.handle = nil

proc exec(db: Database; sql, action: string) =
  var errMsg: cstring
  let rc = sqlite3_exec(db.handle, sql, nil, nil, addr errMsg)
  if rc != SQLITE_OK:
    var message = action
    if not errMsg.isNil:
      message &= ": " & $errMsg
      sqlite3_free(cast[pointer](errMsg))
    raise newException(IOError, message)

proc prepare(db: Database; sql, action: string): Statement =
  var stmt: Sqlite3Stmt = nil
  let rc = sqlite3_prepare_v2(db.handle, sql, -1, stmt, nil)
  result = Statement(handle: stmt)
  db.checkStmtRc(result, rc, action)

proc reset(stmt: Statement; db: Database; action: string) =
  db.checkRc(sqlite3_reset(stmt.handle), action)
  db.checkRc(sqlite3_clear_bindings(stmt.handle), action)

proc bindText(stmt: Statement; db: Database; index: int; value: string; action: string) =
  db.checkRc(sqlite3_bind_text(stmt.handle, index.cint, value, value.len.cint,
    sqliteTransient()), action)

proc bindBlob(stmt: Statement; db: Database; index: int; value: string; action: string) =
  let dataPtr = if value.len == 0: nil else: unsafeAddr value[0]
  db.checkRc(sqlite3_bind_blob(stmt.handle, index.cint, cast[pointer](dataPtr),
    value.len.cint, sqliteTransient()), action)

proc bindInt(stmt: Statement; db: Database; index, value: int; action: string) =
  db.checkRc(sqlite3_bind_int(stmt.handle, index.cint, value.cint), action)

proc bindInt64(stmt: Statement; db: Database; index: int; value: int64; action: string) =
  db.checkRc(sqlite3_bind_int64(stmt.handle, index.cint, value), action)

proc bindNull(stmt: Statement; db: Database; index: int; action: string) =
  db.checkRc(sqlite3_bind_null(stmt.handle, index.cint), action)

proc stepDone(stmt: Statement; db: Database; action: string) =
  let rc = sqlite3_step(stmt.handle)
  if rc != SQLITE_DONE:
    raise db.dbError(action)

proc textColumn(stmt: Statement; index: int): string =
  let value = sqlite3_column_text(stmt.handle, index.cint)
  if not value.isNil:
    result = $value

proc loadExtension*(db: Database; extensionPath: string) =
  db.checkRc(sqlite3_enable_load_extension(db.handle, 1),
    "failed to enable sqlite extension loading")

  var errMsg: cstring
  let rc = sqlite3_load_extension(db.handle, extensionPath, nil, addr errMsg)
  if rc != SQLITE_OK:
    var message = "failed to load sqlite extension " & extensionPath
    if not errMsg.isNil:
      message &= ": " & $errMsg
      sqlite3_free(cast[pointer](errMsg))
    raise newException(IOError, message)

  db.checkRc(sqlite3_enable_load_extension(db.handle, 0),
    "failed to disable sqlite extension loading")

proc initSchema*(db: Database) =
  db.exec(fmt"""
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
);
CREATE INDEX IF NOT EXISTS idx_chunks_source_ordinal
  ON {TableName}(source, ordinal);
CREATE TABLE IF NOT EXISTS {MetaTableName} (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
""", "failed to initialize sqlite schema")

proc beginTransaction*(db: Database) =
  db.exec("BEGIN IMMEDIATE TRANSACTION;", "failed to begin transaction")

proc commitTransaction*(db: Database) =
  db.exec("COMMIT;", "failed to commit transaction")

proc rollbackTransaction*(db: Database) =
  db.exec("ROLLBACK;", "failed to roll back transaction")

proc readMetadata*(db: Database): DbMetadata =
  var stmt = db.prepare(
    fmt"SELECT key, value FROM {MetaTableName};",
    "failed to prepare metadata query"
  )
  defer: stmt.finalize()

  var seenModel = false
  var seenDimension = false
  var seenDistance = false
  var seenQtype = false

  while true:
    let rc = sqlite3_step(stmt.handle)
    if rc == SQLITE_ROW:
      let key = stmt.textColumn(0)
      let value = stmt.textColumn(1)
      case key
      of "model":
        result.model = value
        seenModel = true
      of "dimension":
        result.dimension = parseInt(value)
        seenDimension = true
      of "distance":
        result.distance = value
        seenDistance = true
      of "qtype":
        result.qtype = value
        seenQtype = true
      else:
        discard
    elif rc == SQLITE_DONE:
      break
    else:
      raise db.dbError("failed to read sqlite metadata")

  result.initialized = seenModel and seenDimension and seenDistance and seenQtype

proc writeMetadata*(db: Database; meta: DbMetadata) =
  var stmt = db.prepare(
    fmt"INSERT OR REPLACE INTO {MetaTableName}(key, value) VALUES (?, ?);",
    "failed to prepare metadata upsert"
  )
  defer: stmt.finalize()

  for pair in [
    ("model", meta.model),
    ("dimension", $meta.dimension),
    ("distance", meta.distance),
    ("qtype", meta.qtype)
  ]:
    stmt.reset(db, "failed to reset metadata upsert")
    stmt.bindText(db, 1, pair[0], "failed to bind metadata key")
    stmt.bindText(db, 2, pair[1], "failed to bind metadata value")
    stmt.stepDone(db, "failed to write sqlite metadata")

proc initializeVectorTable*(db: Database; meta: DbMetadata) =
  if not meta.initialized:
    return

  let options = fmt"type=FLOAT32,dimension={meta.dimension},distance={meta.distance}"
  var stmt = db.prepare(
    fmt"SELECT vector_init('{TableName}', '{EmbeddingColumn}', '{options}');",
    "failed to prepare vector_init"
  )
  defer: stmt.finalize()
  let rc = sqlite3_step(stmt.handle)
  if rc != SQLITE_ROW and rc != SQLITE_DONE:
    raise db.dbError("failed to execute vector_init")

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

proc prepareInsertStatement*(db: Database): Statement =
  result = db.prepare(
    fmt"""
INSERT INTO {TableName}(
  source,
  ordinal,
  text,
  {EmbeddingColumn},
  page,
  section,
  metadata_json
) VALUES (?, ?, ?, vector_as_f32(?), ?, ?, ?);
""",
    "failed to prepare chunk insert"
  )

proc insertChunk*(db: Database; stmt: Statement; record: ChunkRecord) =
  stmt.reset(db, "failed to reset insert statement")
  stmt.bindText(db, 1, record.chunk.source, "failed to bind source")
  stmt.bindInt(db, 2, record.chunk.ordinal, "failed to bind ordinal")
  stmt.bindText(db, 3, record.chunk.text, "failed to bind text")
  stmt.bindBlob(db, 4, record.embeddingBlob, "failed to bind embedding blob")

  if record.chunk.hasPage:
    stmt.bindInt(db, 5, record.chunk.page, "failed to bind page")
  else:
    stmt.bindNull(db, 5, "failed to bind null page")

  if record.chunk.section.len > 0:
    stmt.bindText(db, 6, record.chunk.section, "failed to bind section")
  else:
    stmt.bindNull(db, 6, "failed to bind null section")

  if record.chunk.metadataJson.len > 0:
    stmt.bindText(db, 7, record.chunk.metadataJson, "failed to bind metadata json")
  else:
    stmt.bindNull(db, 7, "failed to bind null metadata json")

  stmt.stepDone(db, "failed to insert chunk row")

proc rebuildQuantization*(db: Database; meta: DbMetadata) =
  if not meta.initialized:
    return

  var quantizeStmt = db.prepare(
    fmt"SELECT vector_quantize('{TableName}', '{EmbeddingColumn}', 'qtype={meta.qtype}');",
    "failed to prepare vector_quantize"
  )
  defer: quantizeStmt.finalize()
  let quantizeRc = sqlite3_step(quantizeStmt.handle)
  if quantizeRc != SQLITE_ROW and quantizeRc != SQLITE_DONE:
    raise db.dbError("failed to execute vector_quantize")

  var preloadStmt = db.prepare(
    fmt"SELECT vector_quantize_preload('{TableName}', '{EmbeddingColumn}');",
    "failed to prepare vector_quantize_preload"
  )
  defer: preloadStmt.finalize()
  let preloadRc = sqlite3_step(preloadStmt.handle)
  if preloadRc != SQLITE_ROW and preloadRc != SQLITE_DONE:
    raise db.dbError("failed to execute vector_quantize_preload")

proc rowCount*(db: Database): int =
  var stmt = db.prepare(
    fmt"SELECT COUNT(*) FROM {TableName};",
    "failed to prepare row count"
  )
  defer: stmt.finalize()
  if sqlite3_step(stmt.handle) != SQLITE_ROW:
    raise db.dbError("failed to count chunk rows")
  result = sqlite3_column_int(stmt.handle, 0).int

proc runSearch(db: Database; scanProc: string; queryBlob: string;
    topK: int): seq[SearchResult] =
  let sql = fmt"""
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
  var stmt = db.prepare(sql, "failed to prepare vector search")
  defer: stmt.finalize()

  stmt.bindBlob(db, 1, queryBlob, "failed to bind query embedding")
  stmt.bindInt(db, 2, topK, "failed to bind top-k")

  while true:
    let rc = sqlite3_step(stmt.handle)
    if rc == SQLITE_ROW:
      var row = SearchResult(
        id: sqlite3_column_int64(stmt.handle, 0),
        distance: sqlite3_column_double(stmt.handle, 1).float,
        source: stmt.textColumn(2),
        ordinal: sqlite3_column_int(stmt.handle, 3).int,
        text: stmt.textColumn(4),
        hasPage: false,
        page: 0,
        section: ""
      )
      if sqlite3_column_type(stmt.handle, 5) != SQLITE_NULL:
        row.hasPage = true
        row.page = sqlite3_column_int(stmt.handle, 5).int
      if sqlite3_column_type(stmt.handle, 6) != SQLITE_NULL:
        row.section = stmt.textColumn(6)
      result.add(row)
    elif rc == SQLITE_DONE:
      break
    else:
      raise db.dbError("failed to execute vector search")

proc searchChunks*(db: Database; queryBlob: string; topK: int): seq[SearchResult] =
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
