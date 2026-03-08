import std/[parseutils, strutils]
import ./[marker_parser, types]

const
  SearchMarkerName = "search"

proc failParse(source: string; message: string) {.noreturn.} =
  raise newException(ValueError,
    source & ": invalid search input: " & message)

proc parseSearchMarker(source: string; text: string; startPos: int): tuple[
    filters: SearchFilters, nextPos: int] =
  var filters = initSearchFilters()
  var nextPos = 0

  proc parseSearchAttr(attrName: string; text: string; pos: var int) =
    case attrName
    of "page":
      var pageNumber = 0
      let parsed = parseInt(text, pageNumber, pos)
      if parsed == 0:
        failParse(source, "page must be an integer")
      filters.pageNumber = pageNumber
      pos.inc(parsed)
    of "section":
      try:
        filters.sectionSubstring = parseQuotedValue(text, pos)
      except ValueError:
        failParse(source, "section must use a double-quoted string")
    else:
      failParse(source, "unknown attribute " & attrName)

  try:
    nextPos = parseMarker(text, startPos, SearchMarkerName, parseSearchAttr)
  except ValueError:
    failParse(source, "expected <search ...> marker")

  result = (filters: filters, nextPos: nextPos)

proc skipLineSpaces(text: string; pos: var int) =
  while pos < text.len and text[pos] in {' ', '\t'}:
    inc pos

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
  skipLineSpaces(text, pos)
  if not consumeNewline(text, pos):
    failParse(source, "marker must be followed by a blank line")

  let blankLineStart = pos
  skipLineSpaces(text, pos)
  if pos == blankLineStart:
    discard
  if not consumeNewline(text, pos):
    failParse(source, "marker must be followed by a blank line")

proc parseSearchInput*(source, text: string): SearchInput =
  let startPos = skipWhitespace(text)
  if startPos < text.len and text[startPos] == '<':
    let marker = parseSearchMarker(source, text, startPos)
    var queryStart = marker.nextPos
    requireBlankLineSeparator(source, text, queryStart)
    result = SearchInput(
      queryText: text[queryStart .. ^1].strip(),
      filters: marker.filters
    )
  else:
    result = SearchInput(
      queryText: text.strip(),
      filters: initSearchFilters()
    )
