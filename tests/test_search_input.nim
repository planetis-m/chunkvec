import ../src/chunkvec/[search_input, types]

proc testPlainQueryInput() =
  let parsed = parseSearchInput("query.txt", "How do embeddings help search?\n")
  doAssert parsed.queryText == "How do embeddings help search?"
  doAssert not parsed.filters.hasFilters
  doAssert parsed.filters.position == NoPositionFilter

proc testMarkerWithPageAndSection() =
  let parsed = parseSearchInput("query.txt",
    """<search doc="ml-unit-1" kind=source position=12 label="Intro_Basics">

How do embeddings help search?""")
  doAssert parsed.queryText == "How do embeddings help search?"
  doAssert parsed.filters == SearchFilters(
    docId: "ml-unit-1",
    kind: source,
    position: 12,
    labelSubstring: "Intro_Basics"
  )

proc testRejectUnknownAttribute() =
  doAssertRaises(ValueError):
    discard parseSearchInput("query.txt",
      """<search position=12 title="Intro">

How do embeddings help search?""")

proc testRejectMissingBlankLine() =
  doAssertRaises(ValueError):
    discard parseSearchInput("query.txt",
      """<search position=12>
How do embeddings help search?""")

proc testRejectEmptyQueryText() =
  let parsed = parseSearchInput("query.txt",
    """<search label="Intro">

""")
  doAssert parsed.queryText.len == 0

when isMainModule:
  testPlainQueryInput()
  testMarkerWithPageAndSection()
  testRejectUnknownAttribute()
  testRejectMissingBlankLine()
  testRejectEmptyQueryText()
