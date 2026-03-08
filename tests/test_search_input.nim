import ../src/chunkvec/[search_input, types]

proc testPlainQueryInput() =
  let parsed = parseSearchInput("query.txt", "How do embeddings help search?\n")
  doAssert parsed.queryText == "How do embeddings help search?"
  doAssert not parsed.filters.hasFilters
  doAssert parsed.filters.pageNumber == NoPageFilter

proc testMarkerWithPageAndSection() =
  let parsed = parseSearchInput("query.txt",
    """<search page=12 section="Intro_Basics">

How do embeddings help search?""")
  doAssert parsed.queryText == "How do embeddings help search?"
  doAssert parsed.filters == SearchFilters(
    pageNumber: 12,
    sectionSubstring: "Intro_Basics"
  )

proc testRejectUnknownAttribute() =
  doAssertRaises(ValueError):
    discard parseSearchInput("query.txt",
      """<search page=12 title="Intro">

How do embeddings help search?""")

proc testRejectMissingBlankLine() =
  doAssertRaises(ValueError):
    discard parseSearchInput("query.txt",
      """<search page=12>
How do embeddings help search?""")

proc testRejectEmptyQueryText() =
  let parsed = parseSearchInput("query.txt",
    """<search section="Intro">

""")
  doAssert parsed.queryText.len == 0

when isMainModule:
  testPlainQueryInput()
  testMarkerWithPageAndSection()
  testRejectUnknownAttribute()
  testRejectMissingBlankLine()
  testRejectEmptyQueryText()
