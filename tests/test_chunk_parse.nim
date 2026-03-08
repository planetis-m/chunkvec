import ../src/chunkvec/[input_chunks, types]

proc testPageMarkerChunk() =
  let chunks = parseInputChunks("slides.md",
    """<page n=12 section="Intro">
Hello
world""")
  doAssert chunks.len == 1
  doAssert chunks[0].source == "slides.md"
  doAssert chunks[0].ordinal == 1
  doAssert chunks[0].metadata == ChunkMetadata(pageNumber: 12, section: "Intro")
  doAssert chunks[0].text == "Hello\nworld"

proc testMultipleChunks() =
  let chunks = parseInputChunks("slides.md",
    """<page section="Intro" n=12>
Hello

<page n=13>
World""")
  doAssert chunks.len == 2
  doAssert chunks[0].metadata == ChunkMetadata(pageNumber: 12, section: "Intro")
  doAssert chunks[0].text == "Hello"
  doAssert chunks[1].metadata == ChunkMetadata(pageNumber: 13, section: "")
  doAssert chunks[1].text == "World"

proc testRejectUnknownAttribute() =
  doAssertRaises(ValueError):
    discard parseInputChunks("slides.md", """<page n=12 title="Intro">
Hello""")

proc testRejectMissingMarker() =
  doAssertRaises(ValueError):
    discard parseInputChunks("notes.txt", "just text")

proc testRejectEmptyChunkBody() =
  doAssertRaises(ValueError):
    discard parseInputChunks("slides.md", "<page n=1>\n\n")

when isMainModule:
  testPageMarkerChunk()
  testMultipleChunks()
  testRejectUnknownAttribute()
  testRejectMissingMarker()
  testRejectEmptyChunkBody()
