import ../src/chunkvec/[input_chunks, types]

proc testJsonHeaderChunk() =
  let chunk = parseChunkBody("slides.md", 1,
    "{" & '"' & "page" & '"' & ":12," & '"' & "section" & '"' & ":" &
    '"' & "Intro" & '"' & "}\n\nHello\nworld")
  doAssert chunk.source == "slides.md"
  doAssert chunk.ordinal == 1
  doAssert chunk.metadataJson == "{\"page\":12,\"section\":\"Intro\"}"
  doAssert chunk.text == "Hello\nworld"

proc testArrayHeaderChunk() =
  let chunk = parseChunkBody("slides.md", 2, "[1,2,3]\n\nHello")
  doAssert chunk.metadataJson == "[1,2,3]"
  doAssert chunk.text == "Hello"

proc testPlainTextChunk() =
  let chunk = parseChunkBody("notes.txt", 3, "just text")
  doAssert chunk.metadataJson.len == 0
  doAssert chunk.text == "just text"

proc testOpaqueHeaderChunk() =
  let chunk = parseChunkBody("notes.txt", 4, "{oops}\n\nhello")
  doAssert chunk.metadataJson == "{oops}"
  doAssert chunk.text == "hello"

when isMainModule:
  testJsonHeaderChunk()
  testArrayHeaderChunk()
  testPlainTextChunk()
  testOpaqueHeaderChunk()
