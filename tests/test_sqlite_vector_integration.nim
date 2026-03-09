import std/[os, strutils]
import ../src/chunkvec/[chunk_store, constants, sqlite_vector_paths, types]

proc unitVector(index: int): seq[float32] =
  result = newSeq[float32](EmbeddingDimension)
  result[index] = 1.0'f32

proc artifactCount(db: DbConn): int =
  result = parseInt(db.getValue(sql("SELECT COUNT(*) FROM " & ArtifactTableName & ";")))

proc insertTestChunk(db: DbConn; artifactId: int64; ordinal: int; text: string;
    position: int; label: string) =
  db.exec(sql(
    "INSERT INTO " & TableName &
    "(artifact_id, ordinal, text, " & EmbeddingColumn & ", position, label) " &
    "VALUES (?, ?, ?, x'00', ?, ?);"
  ), artifactId, ordinal, text, position, label)

proc testSqliteVectorRoundTrip() =
  let repoRoot = getCurrentDir()
  let dbPath = repoRoot / "test_files" / "vector_test.sqlite"
  let extPath = repoRoot / ExtensionFilename
  if fileExists(dbPath):
    removeFile(dbPath)

  var db = openDatabase(dbPath)
  defer:
    db.close()
    if fileExists(dbPath):
      removeFile(dbPath)

  db.loadExtension(extPath)
  db.initSchema()
  db.initializeVectorTable(EmbeddingDimension)

  let sourceArtifactId = db.createArtifact("notes.txt", "ml-unit-1", source)
  let derivedArtifactId = db.createArtifact("notes.txt", "ml-unit-1", derived)
  let secondArtifactId = db.createArtifact("notes.txt", "ml-unit-2", derived)
  var stmt = db.prepareInsertStatement()
  defer: stmt.finalize()

  db.beginTransaction()
  db.exec(
    stmt,
    sourceArtifactId,
    1,
    "alpha",
    unitVector(0),
    7,
    "Intro_Basics"
  )
  db.exec(
    stmt,
    derivedArtifactId,
    2,
    "beta",
    unitVector(1),
    8,
    "Appendix"
  )
  db.exec(
    stmt,
    secondArtifactId,
    3,
    "gamma",
    unitVector(0),
    7,
    "Deep Intro"
  )
  db.commitTransaction()
  db.rebuildQuantization()

  let rows = db.searchChunks(unitVector(0), 1)
  doAssert rows.len == 1
  doAssert rows[0].text == "alpha"
  doAssert rows[0].source == "notes.txt"
  doAssert rows[0].metadata == ChunkMetadata(
    docId: "ml-unit-1",
    kind: source,
    position: 7,
    label: "Intro_Basics"
  )

  let docRows = db.searchChunks(unitVector(0), 3,
    SearchFilters(docId: "ml-unit-1"))
  doAssert docRows.len == 2
  doAssert docRows[0].metadata.docId == "ml-unit-1"
  doAssert docRows[1].metadata.docId == "ml-unit-1"

  let kindRows = db.searchChunks(unitVector(0), 3,
    SearchFilters(kind: derived))
  doAssert kindRows.len == 2
  doAssert kindRows[0].text == "gamma"
  doAssert kindRows[1].text == "beta"

  let labelRows = db.searchChunks(unitVector(0), 3,
    SearchFilters(labelSubstring: "introbas"))
  doAssert labelRows.len == 1
  doAssert labelRows[0].text == "alpha"

  let combinedRows = db.searchChunks(unitVector(0), 3,
    SearchFilters(
      docId: "ml-unit-2",
      kind: derived,
      position: 7,
      labelSubstring: "deep intro"
    ))
  doAssert combinedRows.len == 1
  doAssert combinedRows[0].text == "gamma"

proc testRejectDuplicateArtifact() =
  let repoRoot = getCurrentDir()
  let dbPath = repoRoot / "test_files" / "vector_test.sqlite"
  if fileExists(dbPath):
    removeFile(dbPath)

  var db = openDatabase(dbPath)
  defer:
    db.close()
    if fileExists(dbPath):
      removeFile(dbPath)

  db.initSchema()
  discard db.createArtifact("notes.txt", "ml-unit-1", source)
  doAssertRaises(ValueError):
    discard db.createArtifact("notes-v2.txt", "ml-unit-1", source)

proc testRollbackDropsPendingArtifact() =
  let repoRoot = getCurrentDir()
  let dbPath = repoRoot / "test_files" / "vector_test.sqlite"
  if fileExists(dbPath):
    removeFile(dbPath)

  var db = openDatabase(dbPath)
  defer:
    db.close()
    if fileExists(dbPath):
      removeFile(dbPath)

  db.initSchema()
  db.beginTransaction()
  discard db.createArtifact("notes.txt", "ml-unit-1", source)
  db.rollbackTransaction()

  doAssert db.artifactCount() == 0

proc testRejectOrphanChunkInsert() =
  let repoRoot = getCurrentDir()
  let dbPath = repoRoot / "test_files" / "vector_test.sqlite"
  if fileExists(dbPath):
    removeFile(dbPath)

  var db = openDatabase(dbPath)
  defer:
    db.close()
    if fileExists(dbPath):
      removeFile(dbPath)

  db.initSchema()
  doAssertRaises(DbError):
    db.insertTestChunk(999'i64, 1, "orphan", 1, "Orphan")

proc testRejectDuplicateOrdinalWithinArtifact() =
  let repoRoot = getCurrentDir()
  let dbPath = repoRoot / "test_files" / "vector_test.sqlite"
  if fileExists(dbPath):
    removeFile(dbPath)

  var db = openDatabase(dbPath)
  defer:
    db.close()
    if fileExists(dbPath):
      removeFile(dbPath)

  db.initSchema()
  let artifactId = db.createArtifact("notes.txt", "ml-unit-1", source)
  db.insertTestChunk(artifactId, 1, "alpha", 7, "Intro_Basics")
  doAssertRaises(DbError):
    db.insertTestChunk(artifactId, 1, "beta", 8, "Appendix")

when isMainModule:
  testSqliteVectorRoundTrip()
  testRejectDuplicateArtifact()
  testRollbackDropsPendingArtifact()
  testRejectOrphanChunkInsert()
  testRejectDuplicateOrdinalWithinArtifact()
