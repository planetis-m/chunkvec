import std/os
import ../src/chunkvec/[chunk_store, constants, sqlite_vector_paths, types]

proc unitVector(index: int): seq[float32] =
  result = newSeq[float32](EmbeddingDimension)
  result[index] = 1.0'f32

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

  var stmt = db.prepareInsertStatement()
  defer: stmt.finalize()

  db.beginTransaction()
  db.exec(
    stmt,
    "notes.txt",
    1,
    "alpha",
    unitVector(0),
    "ml-unit-1",
    "source",
    7,
    "Intro_Basics"
  )
  db.exec(
    stmt,
    "notes.txt",
    2,
    "beta",
    unitVector(1),
    "ml-unit-1",
    "derived",
    8,
    "Appendix"
  )
  db.exec(
    stmt,
    "notes.txt",
    3,
    "gamma",
    unitVector(0),
    "ml-unit-2",
    "derived",
    7,
    "Deep Intro"
  )
  db.commitTransaction()
  db.rebuildQuantization()

  let rows = db.searchChunks(unitVector(0), 1)
  doAssert rows.len == 1
  doAssert rows[0].text == "alpha"
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

when isMainModule:
  testSqliteVectorRoundTrip()
