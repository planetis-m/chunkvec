import std/strutils
import ../src/chunkvec/[input_chunks, types]

proc testJsonHeaderChunk() =
  let chunk = parseChunkBody("slides.md", 1,
    "{" & '"' & "page" & '"' & ":12," & '"' & "section" & '"' & ":" &
    '"' & "Intro" & '"' & "}\n\nHello\nworld")
  doAssert chunk.source == "slides.md"
  doAssert chunk.ordinal == 1
  doAssert chunk.hasPage
  doAssert chunk.page == 12
  doAssert chunk.section == "Intro"
  doAssert chunk.metadataJson.contains("\"page\":12")
  doAssert chunk.text == "Hello\nworld"

proc testPlainTextChunk() =
  let chunk = parseChunkBody("notes.txt", 2, "just text")
  doAssert not chunk.hasPage
  doAssert chunk.section.len == 0
  doAssert chunk.metadataJson.len == 0
  doAssert chunk.text == "just text"

when isMainModule:
  testJsonHeaderChunk()
  testPlainTextChunk()
