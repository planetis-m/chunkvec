import std/os
import ../src/chunkvec/[input_chunks, types]

proc testPageMarkerChunk() =
  let chunks = parseInputChunks("slides.md",
    """<chunk pos=12 label="Intro">
Hello
world""", "ml-unit-1", source)
  doAssert chunks.len == 1
  doAssert chunks[0].source == "slides.md"
  doAssert chunks[0].ordinal == 1
  doAssert chunks[0].metadata == ChunkMetadata(
    docId: "ml-unit-1",
    kind: source,
    position: 12,
    label: "Intro"
  )
  doAssert chunks[0].text == "Hello\nworld"

proc testMultipleChunks() =
  let chunks = parseInputChunks("slides.md",
    """<chunk label="Intro" pos=12>
Hello

<chunk pos=13>
World""", "ml-unit-1", derived)
  doAssert chunks.len == 2
  doAssert chunks[0].metadata == ChunkMetadata(
    docId: "ml-unit-1",
    kind: derived,
    position: 12,
    label: "Intro"
  )
  doAssert chunks[0].text == "Hello"
  doAssert chunks[1].metadata == ChunkMetadata(
    docId: "ml-unit-1",
    kind: derived,
    position: 13,
    label: ""
  )
  doAssert chunks[1].text == "World"

proc testRejectUnknownAttribute() =
  doAssertRaises(ValueError):
    discard parseInputChunks("slides.md", """<chunk pos=12 title="Intro">
Hello""", "ml-unit-1", source)

proc testRejectMissingMarker() =
  doAssertRaises(ValueError):
    discard parseInputChunks("notes.txt", "just text", "ml-unit-1", source)

proc testRejectInlineDoc() =
  doAssertRaises(ValueError):
    discard parseInputChunks("slides.md", """<chunk doc="ml-unit-1" pos=12>
Hello""", "ignored-doc", source)

proc testRejectInlineKind() =
  doAssertRaises(ValueError):
    discard parseInputChunks("slides.md",
      """<chunk kind=derived pos=12>
Hello""", "ml-unit-1", source)

proc testRejectMissingRequiredPosition() =
  doAssertRaises(ValueError):
    discard parseInputChunks("slides.md", """<chunk label="Intro">
Hello""", "ml-unit-1", source)

proc testRejectEmptyChunkBody() =
  doAssertRaises(ValueError):
    discard parseInputChunks("slides.md",
      "<chunk pos=1>\n\n", "ml-unit-1", source)

proc testLoadInputChunksUsesSourcePath() =
  let path = "tests/test_chunk_parse_input.txt"
  writeFile(path, """<chunk pos=1 label="Intro">
Hello""")
  defer:
    removeFile(path)
  let chunks = loadInputChunks(path, "course/week-1-notes.md", "ml-unit-1", source)
  doAssert chunks.len == 1
  doAssert chunks[0].source == "course/week-1-notes.md"

proc testLoadInputChunksKeepsEmptySourcePath() =
  let path = "tests/test_chunk_parse_input.txt"
  writeFile(path, """<chunk pos=1 label="Intro">
Hello""")
  defer:
    removeFile(path)
  let chunks = loadInputChunks(path, "", "ml-unit-1", source)
  doAssert chunks.len == 1
  doAssert chunks[0].source.len == 0

proc testRejectLegacyPositionAttr() =
  doAssertRaises(ValueError):
    discard parseInputChunks("slides.md", """<chunk position=12>
Hello""", "ml-unit-1", source)

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
  testLoadInputChunksUsesSourcePath()
  testLoadInputChunksKeepsEmptySourcePath()
