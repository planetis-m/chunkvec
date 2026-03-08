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
  db.initializeVectorTable()

  var stmt = db.prepareInsertStatement()
  defer: stmt.finalize()

  db.beginTransaction()
  db.exec(
    stmt,
    "notes.txt",
    1,
    "alpha",
    unitVector(0),
    7,
    "Intro_Basics"
  )
  db.exec(
    stmt,
    "notes.txt",
    2,
    "beta",
    unitVector(1),
    8,
    "Appendix"
  )
  db.exec(
    stmt,
    "notes.txt",
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
  doAssert rows[0].metadata == ChunkMetadata(pageNumber: 7, section: "Intro_Basics")

  let pageRows = db.searchChunks(unitVector(0), 3,
    SearchFilters(pageNumber: 7))
  doAssert pageRows.len == 2
  doAssert pageRows[0].metadata.pageNumber == 7
  doAssert pageRows[1].metadata.pageNumber == 7

  let sectionRows = db.searchChunks(unitVector(0), 3,
    SearchFilters(sectionSubstring: "introbas"))
  doAssert sectionRows.len == 1
  doAssert sectionRows[0].text == "alpha"

  let combinedRows = db.searchChunks(unitVector(0), 3,
    SearchFilters(
      pageNumber: 7,
      sectionSubstring: "deep intro"
    ))
  doAssert combinedRows.len == 1
  doAssert combinedRows[0].text == "gamma"

when isMainModule:
  testSqliteVectorRoundTrip()
