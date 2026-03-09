import std/os
import ../src/chunkvec/[input_chunks, types]

proc testPageMarkerChunk() =
  let chunks = parseInputChunks("""<chunk pos=12 label="Intro">
Hello
world""")
  doAssert chunks.len == 1
  doAssert chunks[0].ordinal == 1
  doAssert chunks[0].position == 12
  doAssert chunks[0].label == "Intro"
  doAssert chunks[0].text == "Hello\nworld"

proc testMultipleChunks() =
  let chunks = parseInputChunks("""<chunk label="Intro" pos=12>
Hello

<chunk pos=13>
World""")
  doAssert chunks.len == 2
  doAssert chunks[0].position == 12
  doAssert chunks[0].label == "Intro"
  doAssert chunks[0].text == "Hello"
  doAssert chunks[1].position == 13
  doAssert chunks[1].label.len == 0
  doAssert chunks[1].text == "World"

proc testRejectUnknownAttribute() =
  doAssertRaises(ValueError):
    discard parseInputChunks("""<chunk pos=12 title="Intro">
Hello""")

proc testRejectMissingMarker() =
  doAssertRaises(ValueError):
    discard parseInputChunks("just text")

proc testRejectInlineDoc() =
  doAssertRaises(ValueError):
    discard parseInputChunks("""<chunk doc="ml-unit-1" pos=12>
Hello""")

proc testRejectInlineKind() =
  doAssertRaises(ValueError):
    discard parseInputChunks(
      """<chunk kind=derived pos=12>
Hello""")

proc testRejectMissingRequiredPosition() =
  doAssertRaises(ValueError):
    discard parseInputChunks("""<chunk label="Intro">
Hello""")

proc testRejectEmptyChunkBody() =
  doAssertRaises(ValueError):
    discard parseInputChunks("<chunk pos=1>\n\n")

proc testLoadInputChunks() =
  let path = "tests/test_chunk_parse_input.txt"
  writeFile(path, """<chunk pos=1 label="Intro">
Hello""")
  defer:
    removeFile(path)
  let chunks = loadInputChunks(path)
  doAssert chunks.len == 1
  doAssert chunks[0].position == 1
  doAssert chunks[0].label == "Intro"

proc testRejectLegacyPositionAttr() =
  doAssertRaises(ValueError):
    discard parseInputChunks("""<chunk position=12>
Hello""")

when isMainModule:
  testPageMarkerChunk()
  testMultipleChunks()
  testRejectUnknownAttribute()
  testRejectMissingMarker()
  testRejectInlineDoc()
  testRejectInlineKind()
  testRejectMissingRequiredPosition()
  testRejectLegacyPositionAttr()
  testRejectEmptyChunkBody()
  testLoadInputChunks()
