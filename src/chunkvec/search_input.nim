import std/[parseutils, strutils]
import ./types

const
  SearchMarkerName = "search"

proc failParse(source: string; message: string) {.noreturn.} =
  raise newException(ValueError,
    source & ": invalid search input: " & message)

proc skipMarkerWhitespace(text: string; pos: var int) =
  pos.inc(skipWhitespace(text, pos))

proc parseQuotedValue(source: string; text: string; pos: var int): string =
  if pos >= text.len or text[pos] != '"':
    failParse(source, "section must use a double-quoted string")

  inc pos
  let valueStart = pos
  while pos < text.len and text[pos] != '"':
    inc pos
  if pos >= text.len:
    failParse(source, "unterminated quoted string in marker")

  result = text[valueStart ..< pos]
  inc pos

proc parseSearchMarker(source: string; text: string; startPos: int): tuple[
    filters: SearchFilters, nextPos: int] =
  result.filters = initSearchFilters()
  var pos = startPos
  if pos >= text.len or text[pos] != '<':
    failParse(source, "missing <search ...> marker")
  inc pos

  var markerName = ""
  let markerLen = parseIdent(text, markerName, pos)
  if markerLen == 0 or markerName != SearchMarkerName:
    failParse(source, "expected <search ...> marker")
  pos.inc(markerLen)

  while true:
    skipMarkerWhitespace(text, pos)
    if pos >= text.len:
      failParse(source, "unterminated marker")
    if text[pos] == '>':
      inc pos
      break

    var attrName = ""
    let attrLen = parseIdent(text, attrName, pos)
    if attrLen == 0:
      failParse(source, "expected attribute name in marker")
    pos.inc(attrLen)

    skipMarkerWhitespace(text, pos)
    if pos >= text.len or text[pos] != '=':
      failParse(source, "expected '=' after attribute " & attrName)
    inc pos
    skipMarkerWhitespace(text, pos)

    case attrName
    of "page":
      if result.filters.pageNumber != NoPageFilter:
        failParse(source, "duplicate page attribute")
      var pageNumber = 0
      let parsed = parseInt(text, pageNumber, pos)
      if parsed == 0:
        failParse(source, "page must be an integer")
      result.filters.pageNumber = pageNumber
      pos.inc(parsed)
    of "section":
      if result.filters.sectionSubstring.len > 0:
        failParse(source, "duplicate section attribute")
      result.filters.sectionSubstring = parseQuotedValue(source, text, pos)
    else:
      failParse(source, "unknown attribute " & attrName)

  result.nextPos = pos

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
