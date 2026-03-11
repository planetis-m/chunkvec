import std/os
import ../src/chunkvec/[input_chunks, types]

proc testPageMarkerChunk() =
  let chunks = parseInputChunks("""<chunk page=12 label="Intro">
Hello
world""")
  doAssert chunks.len == 1
  doAssert chunks[0].page == 12
  doAssert chunks[0].label == "Intro"
  doAssert chunks[0].text == "Hello\nworld"

proc testMultipleChunks() =
  let chunks = parseInputChunks("""<chunk label="Intro" page=12>
Hello

<chunk page=13>
World""")
  doAssert chunks.len == 2
  doAssert chunks[0].page == 12
  doAssert chunks[0].label == "Intro"
  doAssert chunks[0].text == "Hello"
  doAssert chunks[1].page == 13
  doAssert chunks[1].label.len == 0
  doAssert chunks[1].text == "World"

proc testRejectUnknownAttribute() =
  doAssertRaises(ValueError):
    discard parseInputChunks("""<chunk page=12 title="Intro">
Hello""")

proc testRejectMissingMarker() =
  doAssertRaises(ValueError):
    discard parseInputChunks("just text")

proc testRejectInlineDoc() =
  doAssertRaises(ValueError):
    discard parseInputChunks("""<chunk doc="ml-unit-1" page=12>
Hello""")

proc testRejectInlineKind() =
  doAssertRaises(ValueError):
    discard parseInputChunks(
      """<chunk kind=derived page=12>
Hello""")

proc testAllowMissingPage() =
  let chunks = parseInputChunks("""<chunk label="Intro">
Hello""")
  doAssert chunks.len == 1
  doAssert chunks[0].page == NoPageFilter
  doAssert chunks[0].label == "Intro"

proc testRejectEmptyChunkBody() =
  doAssertRaises(ValueError):
    discard parseInputChunks("<chunk page=1>\n\n")

proc testLoadInputChunks() =
  let path = "tests/test_chunk_parse_input.txt"
  writeFile(path, """<chunk page=1 label="Intro">
Hello""")
  defer:
    removeFile(path)
  let chunks = loadInputChunks(path)
  doAssert chunks.len == 1
  doAssert chunks[0].page == 1
  doAssert chunks[0].label == "Intro"

proc testRejectLegacyPositionAttr() =
  doAssertRaises(ValueError):
    discard parseInputChunks("""<chunk position=12>
Hello""")

proc testRejectLegacyPosAttr() =
  doAssertRaises(ValueError):
    discard parseInputChunks("""<chunk pos=12>
Hello""")

when isMainModule:
  testPageMarkerChunk()
  testMultipleChunks()
  testRejectUnknownAttribute()
  testRejectMissingMarker()
  testRejectInlineDoc()
  testRejectInlineKind()
  testAllowMissingPage()
  testRejectLegacyPositionAttr()
  testRejectLegacyPosAttr()
  testRejectEmptyChunkBody()
  testLoadInputChunks()
