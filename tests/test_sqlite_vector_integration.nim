import std/[os, strutils]
import ../src/chunkvec/[chunk_store, constants, sqlite_vector_paths, types]

proc unitVector(index: int): seq[float32] =
  result = newSeq[float32](EmbeddingDimension)
  result[index] = 1.0'f32

proc storedChunk(text: string; page: int; label: string): InputChunk =
  InputChunk(text: text, page: page, label: label)

proc containsChunk(chunks: seq[InputChunk]; expected: InputChunk): bool =
  for chunk in chunks:
    if chunk == expected:
      return true

proc assertSameChunks(actual, expected: seq[InputChunk]) =
  doAssert actual.len == expected.len
  for chunk in expected:
    doAssert actual.containsChunk(chunk)

proc testSqliteVectorRoundTrip() =
  let repoRoot = getCurrentDir()
  let dbPath = repoRoot / "test_files" / "vector_test.sqlite"
  let extPath = repoRoot / ExtensionFilename
  createDir(parentDir(dbPath))
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
  doAssert parseInt(
    db.getValue(sql"SELECT COUNT(*) FROM pragma_table_info('chunks') WHERE name = 'ordinal';")
  ) == 0

  var stmt = db.prepareInsertStatement()
  defer: stmt.finalize()

  db.beginTransaction()
  db.exec(
    stmt,
    "notes.txt",
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
    page: 7,
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
      page: 7,
      labelSubstring: "deep intro"
    ))
  doAssert combinedRows.len == 1
  doAssert combinedRows[0].text == "gamma"

  var selectedChunks = @[
    storedChunk("alpha", 7, "Intro_Basics"),
    storedChunk("alpha revised", 7, "Intro_Basics"),
    storedChunk("alpha", 9, "Intro_Basics")
  ]
  let selectedSkipped = db.selectMissingChunks("notes.txt", "ml-unit-1", source, selectedChunks)
  doAssert selectedSkipped == 1
  assertSameChunks(selectedChunks, @[
    storedChunk("alpha revised", 7, "Intro_Basics"),
    storedChunk("alpha", 9, "Intro_Basics")
  ])

  var allSkippedChunks = @[
    storedChunk("alpha", 7, "Intro_Basics")
  ]
  let allSkipped = db.selectMissingChunks("notes.txt", "ml-unit-1", source, allSkippedChunks)
  doAssert allSkipped == 1
  doAssert allSkippedChunks.len == 0

  var allMissingChunks = @[
    storedChunk("delta", 10, "New_Topic"),
    storedChunk("epsilon", 11, "Wrap_Up")
  ]
  let allMissing = db.selectMissingChunks("notes.txt", "ml-unit-1", source, allMissingChunks)
  doAssert allMissing == 0
  assertSameChunks(allMissingChunks, @[
    storedChunk("delta", 10, "New_Topic"),
    storedChunk("epsilon", 11, "Wrap_Up")
  ])

  var wrongKindChunks = @[
    storedChunk("alpha", 7, "Intro_Basics")
  ]
  let wrongKind = db.selectMissingChunks("notes.txt", "ml-unit-1", derived, wrongKindChunks)
  doAssert wrongKind == 0
  doAssert wrongKindChunks == @[storedChunk("alpha", 7, "Intro_Basics")]

  var wrongSourceChunks = @[
    storedChunk("alpha", 7, "Intro_Basics")
  ]
  let wrongSource = db.selectMissingChunks("other-notes.txt", "ml-unit-1", source,
    wrongSourceChunks)
  doAssert wrongSource == 0
  doAssert wrongSourceChunks == @[storedChunk("alpha", 7, "Intro_Basics")]

when isMainModule:
  testSqliteVectorRoundTrip()
