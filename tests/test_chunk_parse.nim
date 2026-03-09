import ../src/chunkvec/[input_chunks, types]

proc testPageMarkerChunk() =
  let chunks = parseInputChunks("slides.md",
    """<chunk doc="ml-unit-1" kind=source position=12 label="Intro">
Hello
world""")
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
    """<chunk label="Intro" position=12 kind=source doc="ml-unit-1">
Hello

<chunk doc="ml-unit-1" kind=derived position=13>
World""")
  doAssert chunks.len == 2
  doAssert chunks[0].metadata == ChunkMetadata(
    docId: "ml-unit-1",
    kind: source,
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
    discard parseInputChunks("slides.md", """<chunk doc="ml-unit-1" kind=source position=12 title="Intro">
Hello""")

proc testRejectMissingMarker() =
  doAssertRaises(ValueError):
    discard parseInputChunks("notes.txt", "just text")

proc testRejectMissingRequiredDoc() =
  doAssertRaises(ValueError):
    discard parseInputChunks("slides.md", """<chunk kind=source position=12>
Hello""")

proc testRejectAssessmentKind() =
  doAssertRaises(ValueError):
    discard parseInputChunks("slides.md",
      """<chunk doc="ml-unit-1" kind=assessment position=12>
Hello""")

proc testRejectEmptyChunkBody() =
  doAssertRaises(ValueError):
    discard parseInputChunks("slides.md",
      "<chunk doc=\"ml-unit-1\" kind=source position=1>\n\n")

when isMainModule:
  testPageMarkerChunk()
  testMultipleChunks()
  testRejectUnknownAttribute()
  testRejectMissingMarker()
  testRejectMissingRequiredDoc()
  testRejectAssessmentKind()
  testRejectEmptyChunkBody()
