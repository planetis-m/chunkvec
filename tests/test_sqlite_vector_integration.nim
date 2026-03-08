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
  db.insertChunk(stmt, ChunkRecord(
    chunk: InputChunk(
      source: "notes.txt",
      ordinal: 1,
      text: "alpha",
      hasPage: true,
      page: 7,
      section: "Intro",
      metadataJson: "{\"page\":7,\"section\":\"Intro\"}"
    ),
    embedding: unitVector(0)
  ))
  db.insertChunk(stmt, ChunkRecord(
    chunk: InputChunk(
      source: "notes.txt",
      ordinal: 2,
      text: "beta",
      hasPage: false,
      page: 0,
      section: "",
      metadataJson: ""
    ),
    embedding: unitVector(1)
  ))
  db.commitTransaction()
  db.rebuildQuantization()

  let rows = db.searchChunks(unitVector(0), 1)
  doAssert rows.len == 1
  doAssert rows[0].text == "alpha"
  doAssert rows[0].hasPage
  doAssert rows[0].page == 7

when isMainModule:
  testSqliteVectorRoundTrip()
