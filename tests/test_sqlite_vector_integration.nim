import std/os
import ../src/chunkvec/[chunk_store, sqlite_vector_paths, types]

proc testSqliteVectorRoundTrip() =
  let repoRoot = getCurrentDir()
  let dbPath = repoRoot / "test_files" / "vector_test.sqlite"
  let extensionPath = repoRoot / sqliteVectorExtensionFilename()
  if fileExists(dbPath):
    removeFile(dbPath)

  var db = openDatabase(dbPath)
  defer:
    db.close()
    if fileExists(dbPath):
      removeFile(dbPath)

  db.loadExtension(extensionPath)
  db.initSchema()

  let meta = configuredMetadata("Qwen/Qwen3-Embedding-0.6B", 3)
  db.writeMetadata(meta)
  db.initializeVectorTable(meta)

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
    embedding: @[1.0'f32, 0.0'f32, 0.0'f32],
    dimension: 3
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
    embedding: @[0.0'f32, 1.0'f32, 0.0'f32],
    dimension: 3
  ))
  db.commitTransaction()
  db.rebuildQuantization(meta)

  let rows = db.searchChunks([1.0'f32, 0.0'f32, 0.0'f32], 1)
  doAssert rows.len == 1
  doAssert rows[0].text == "alpha"
  doAssert rows[0].hasPage
  doAssert rows[0].page == 7

when isMainModule:
  testSqliteVectorRoundTrip()
