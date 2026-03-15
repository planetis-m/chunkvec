import std/[hashes, sets, strutils]
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
  text TEXT NOT NULL,
  """ & EmbeddingColumn & """ BLOB NOT NULL,
  doc_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('source', 'derived')),
  page INTEGER NOT NULL,
  label TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);"""
  ))
  db.exec(sql(
    """CREATE INDEX IF NOT EXISTS idx_chunks_doc_kind_page
  ON """ & TableName & """(doc_id, kind, page);"""
  ))

proc beginTransaction*(db: DbConn) =
  db.exec(sql"BEGIN IMMEDIATE TRANSACTION;")

proc commitTransaction*(db: DbConn) =
  db.exec(sql"COMMIT;")

proc rollbackTransaction*(db: DbConn) =
  db.exec(sql"ROLLBACK;")

proc initializeVectorTable*(db: DbConn; embeddingDimension: int) =
  let options =
    "type=" & VectorType &
    ",dimension=" & $embeddingDimension &
    ",distance=" & DistanceMetric
  discard db.getValue(sql"SELECT vector_init(?, ?, ?);", TableName, EmbeddingColumn, options)

proc prepareInsertStatement*(db: DbConn): SqlPrepared =
  result = db.prepare(
    """INSERT INTO """ & TableName & """(
  source,
  text,
  """ & EmbeddingColumn & """,
  doc_id,
  kind,
  page,
  label
) VALUES (?, ?, ?, ?, ?, ?, ?);
"""
  )

type
  ChunkResumeKey = object
    page: int
    label: string
    text: string

proc toResumeKey(chunk: InputChunk): ChunkResumeKey =
  ChunkResumeKey(
    page: chunk.page,
    label: chunk.label,
    text: chunk.text
  )

proc selectMissingChunks*(db: DbConn; sourcePath, docId: string; kind: ChunkKind;
    chunks: var seq[InputChunk]): int =
  var stmt: SqlPrepared
  var existing = initHashSet[ChunkResumeKey]()
  try:
    stmt = db.prepare(
      """SELECT
  page,
  label,
  text
FROM """ & TableName & """
WHERE source = ?
  AND doc_id = ?
  AND kind = ?;"""
    )
    stmt.bindParam(1, sourcePath)
    stmt.bindParam(2, docId)
    stmt.bindParam(3, $kind)

    for row in db.instantRows(stmt):
      existing.incl(ChunkResumeKey(
        page: sqlite3.column_int(row, 0).int,
        label: row.textColumn(1),
        text: row.textColumn(2)
      ))
  finally:
    if not stmt.isNil:
      stmt.finalize()

  var i = 0
  while i < chunks.len:
    if existing.contains(chunks[i].toResumeKey()):
      inc result
      chunks.del(i)
    else:
      inc i

proc rebuildQuantization*(db: DbConn) =
  let options = "qtype=" & QuantizationType
  discard db.getValue(sql"SELECT vector_quantize(?, ?, ?);", TableName, EmbeddingColumn, options)
  discard db.getValue(sql"SELECT vector_quantize_preload(?, ?);", TableName, EmbeddingColumn)

proc rowCount*(db: DbConn): int =
  result = parseInt(db.getValue(sql("SELECT COUNT(*) FROM " & TableName & ";")))

proc readSearchResult(row: InstantRow): SearchResult =
  result = SearchResult(
    id: sqlite3.column_int64(row, 0),
    distance: sqlite3.column_double(row, 1).float,
    source: row.textColumn(2),
    text: row.textColumn(3),
    metadata: ChunkMetadata(
      docId: row.textColumn(4),
      kind: parseChunkKind(row.textColumn(5)),
      page: sqlite3.column_int(row, 6).int,
      label: row.textColumn(7)
    )
  )

proc runTopKSearch(db: DbConn; queryVector: seq[float32]; topK: int): seq[SearchResult] =
  let query =
    """SELECT
  c.id,
  v.distance,
  c.source,
  c.text,
  c.doc_id,
  c.kind,
  c.page,
  c.label
FROM """ & TableName & """ AS c
JOIN vector_quantize_scan('""" & TableName & """', '""" &
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
      result.add(readSearchResult(row))
  finally:
    if not stmt.isNil:
      stmt.finalize()

proc normalizedLabelExpr(column: string): string =
  result = "lower(replace(" & column & ", '_', ''))"

template addWherePrefix() =
  if haveWhereClause:
    query.add("AND ")
  else:
    query.add("WHERE ")
    haveWhereClause = true

proc runFilteredSearch(db: DbConn; queryVector: seq[float32]; filters: SearchFilters;
    topK: int): seq[SearchResult] =
  var query =
    """SELECT
  c.id,
  v.distance,
  c.source,
  c.text,
  c.doc_id,
  c.kind,
  c.page,
  c.label
FROM """ & TableName & """ AS c
JOIN vector_quantize_scan('""" & TableName & """', '""" &
    EmbeddingColumn & """', ?) AS v
  ON c.id = v.rowid
"""

  var haveWhereClause = false
  if filters.docId.len > 0:
    query.add("WHERE c.doc_id = ?\n")
    haveWhereClause = true
  if filters.kind != none:
    addWherePrefix()
    query.add("c.kind = ?\n")
  if filters.page != NoPageFilter:
    addWherePrefix()
    query.add("c.page = ?\n")
  if filters.labelSubstring.len > 0:
    addWherePrefix()
    query.add("instr(" & normalizedLabelExpr("c.label") & ", ?) > 0\n")

  query.add("ORDER BY v.distance ASC, c.id ASC\n")
  query.add("LIMIT ?;")

  let normalizedLabel = filters.labelSubstring.normalize()

  var stmt: SqlPrepared
  try:
    stmt = db.prepare(query)
    var paramIdx = 1
    stmt.bindParam(paramIdx, queryVector)
    inc paramIdx
    if filters.docId.len > 0:
      stmt.bindParam(paramIdx, filters.docId)
      inc paramIdx
    if filters.kind != none:
      stmt.bindParam(paramIdx, $filters.kind)
      inc paramIdx
    if filters.page != NoPageFilter:
      stmt.bindParam(paramIdx, filters.page)
      inc paramIdx
    if filters.labelSubstring.len > 0:
      stmt.bindParam(paramIdx, normalizedLabel)
      inc paramIdx
    stmt.bindParam(paramIdx, topK)

    for row in db.instantRows(stmt):
      result.add(readSearchResult(row))
  finally:
    if not stmt.isNil:
      stmt.finalize()

proc searchChunks*(db: DbConn; queryVector: seq[float32]; topK: int;
    filters = SearchFilters()): seq[SearchResult] =
  if filters.hasFilters:
    result = db.runFilteredSearch(queryVector, filters, topK)
  else:
    result = db.runTopKSearch(queryVector, topK)
