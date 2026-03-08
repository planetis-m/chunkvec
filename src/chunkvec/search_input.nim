import std/[parseutils, strutils]
import ./[marker_parser, types]

const
  SearchMarkerName = "search"

proc parseSearchMarker(source: string; text: string; filters: var SearchFilters;
    startPos: int): int =
  var page = NoPageFilter
  var section = ""

  proc parseSearchAttr(attrName: string; text: string; pos: var int) =
    case attrName
    of "page":
      let parsed = parseInt(text, page, pos)
      if parsed == 0:
        failParse(source, "search input", "page must be an integer")
      pos.inc(parsed)
    of "section":
      let parsed = parseQuotedValue(text, section, pos)
      if parsed == 0:
        failParse(source, "search input", "section must use a double-quoted string")
      pos.inc(parsed)
    else:
      failParse(source, "search input", "unknown attribute " & attrName)

  let parsedLen = parseMarker(text, startPos, SearchMarkerName, parseSearchAttr)
  if parsedLen == 0:
    return 0

  filters = SearchFilters(pageNumber: page, sectionSubstring: section)
  result = parsedLen

proc consumeNewline(text: string; pos: var int): bool =
  if pos < text.len and text[pos] == '\r':
    inc pos
    if pos < text.len and text[pos] == '\n':
      inc pos
    result = true
  elif pos < text.len and text[pos] == '\n':
    inc pos
    result = true

proc requireBlankLineSeparator(source: string; text: string; pos: var int) =
  pos.inc(skipWhile(text, {' ', '\t'}, pos))
  if not consumeNewline(text, pos):
    failParse(source, "search input", "marker must be followed by a blank line")

  let blankLineStart = pos
  pos.inc(skipWhile(text, {' ', '\t'}, pos))
  if pos == blankLineStart:
    discard
  if not consumeNewline(text, pos):
    failParse(source, "search input", "marker must be followed by a blank line")

proc parseSearchInput*(source, text: string): SearchInput =
  let startPos = skipWhitespace(text)
  if startPos < text.len and text[startPos] == '<':
    var filters = initSearchFilters()
    let markerLen = parseSearchMarker(source, text, filters, startPos)
    if markerLen == 0:
      failParse(source, "search input", "expected <search ...> marker")
    var queryStart = startPos + markerLen
    requireBlankLineSeparator(source, text, queryStart)
    result = SearchInput(
      queryText: text[queryStart .. ^1].strip(),
      filters: filters
    )
  else:
    result = SearchInput(
      queryText: text.strip(),
      filters: initSearchFilters()
    )
