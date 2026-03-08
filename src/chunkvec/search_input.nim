import std/[parseutils, strutils]
import ./[marker_parser, types]

const
  SearchMarkerName = "search"

proc parseSearchMarker(text: string; filters: var SearchFilters; startPos: int): int =
  var docId = ""
  var kind = ChunkKind.none
  var position = NoPositionFilter
  var label = ""

  proc parseSearchAttr(attrName: string; text: string; pos: var int) =
    case attrName
    of "doc":
      let parsed = parseQuotedValue(text, docId, pos)
      if parsed == 0:
        failParse("doc must use a double-quoted string")
      pos.inc(parsed)
    of "kind":
      var kindName = ""
      let parsed = parseIdent(text, kindName, pos)
      kind = parseChunkKind(kindName)
      if parsed == 0 or kind == ChunkKind.none:
        failParse("kind must be one of source, derived, assessment")
      pos.inc(parsed)
    of "position":
      let parsed = parseInt(text, position, pos)
      if parsed == 0:
        failParse("position must be an integer")
      pos.inc(parsed)
    of "label":
      let parsed = parseQuotedValue(text, label, pos)
      if parsed == 0:
        failParse("label must use a double-quoted string")
      pos.inc(parsed)
    else:
      failParse("unknown attribute " & attrName)

  let parsedLen = parseMarker(text, startPos, SearchMarkerName, parseSearchAttr)
  if parsedLen == 0:
    return 0

  filters = SearchFilters(
    docId: docId,
    kind: kind,
    position: position,
    labelSubstring: label
  )
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

proc requireBlankLineSeparator(text: string; pos: var int) =
  pos.inc(skipWhile(text, {' ', '\t'}, pos))
  if not consumeNewline(text, pos):
    failParse("marker must be followed by a blank line")

  let blankLineStart = pos
  pos.inc(skipWhile(text, {' ', '\t'}, pos))
  if pos == blankLineStart:
    discard
  if not consumeNewline(text, pos):
    failParse("marker must be followed by a blank line")

proc parseSearchInput*(source, text: string): SearchInput =
  let startPos = skipWhitespace(text)
  if startPos < text.len and text[startPos] == '<':
    var filters = initSearchFilters()
    let markerLen = parseSearchMarker(text, filters, startPos)
    if markerLen == 0:
      failParse("expected <search ...> marker")
    var queryStart = startPos + markerLen
    requireBlankLineSeparator(text, queryStart)
    result = SearchInput(
      queryText: text[queryStart .. ^1].strip(),
      filters: filters
    )
  else:
    result = SearchInput(
      queryText: text.strip(),
      filters: initSearchFilters()
    )
