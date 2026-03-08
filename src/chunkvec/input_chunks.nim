import std/[parseutils, strutils]
import ./types

const
  MarkerName = "page"
  MarkerPrefix = "<" & MarkerName

proc failParse(source: string; ordinal: int; message: string) {.noreturn.} =
  raise newException(ValueError,
    source & ": invalid chunk " & $ordinal & ": " & message)

proc skipMarkerWhitespace(text: string; pos: var int) =
  pos.inc(skipWhitespace(text, pos))

proc trimChunkBounds(text: string; startPos, endPos: int): Slice[int] =
  var first = startPos
  var last = endPos

  while first < last and text[first].isSpaceAscii:
    inc first
  while last > first and text[last - 1].isSpaceAscii:
    dec last

  result = first ..< last

proc isMarkerStart(text: string; pos: int): bool =
  if pos < 0 or pos + MarkerPrefix.len > text.len:
    return false
  if text[pos ..< pos + MarkerPrefix.len] != MarkerPrefix:
    return false

  var linePos = pos - 1
  while linePos >= 0 and text[linePos] notin {'\n', '\r'}:
    if text[linePos] notin {' ', '\t'}:
      return false
    dec linePos

  result = true

proc findNextMarkerStart(text: string; startPos: int): int =
  result = text.len
  var pos = startPos
  while pos < text.len:
    if text[pos] == '<' and text.isMarkerStart(pos):
      result = pos
      break
    inc pos

proc parseQuotedValue(source: string; ordinal: int; text: string; pos: var int): string =
  if pos >= text.len or text[pos] != '"':
    failParse(source, ordinal, "section must use a double-quoted string")

  inc pos
  let valueStart = pos
  while pos < text.len and text[pos] != '"':
    inc pos
  if pos >= text.len:
    failParse(source, ordinal, "unterminated quoted string in marker")

  result = text[valueStart ..< pos]
  inc pos

proc parsePageMarker(source: string; ordinal: int; text: string; startPos: int): tuple[
    metadata: ChunkMetadata, nextPos: int] =
  var pos = startPos
  if pos >= text.len or text[pos] != '<':
    failParse(source, ordinal, "missing <page ...> marker")
  inc pos

  var markerName = ""
  let markerLen = parseIdent(text, markerName, pos)
  if markerLen == 0 or markerName != MarkerName:
    failParse(source, ordinal, "expected <page ...> marker")
  pos.inc(markerLen)

  var sawPageNumber = false
  var sawSection = false

  while true:
    skipMarkerWhitespace(text, pos)
    if pos >= text.len:
      failParse(source, ordinal, "unterminated marker")
    if text[pos] == '>':
      inc pos
      break

    var attrName = ""
    let attrLen = parseIdent(text, attrName, pos)
    if attrLen == 0:
      failParse(source, ordinal, "expected attribute name in marker")
    pos.inc(attrLen)

    skipMarkerWhitespace(text, pos)
    if pos >= text.len or text[pos] != '=':
      failParse(source, ordinal, "expected '=' after attribute " & attrName)
    inc pos
    skipMarkerWhitespace(text, pos)

    case attrName
    of "n":
      if sawPageNumber:
        failParse(source, ordinal, "duplicate n attribute")
      var pageNumber = 0
      let parsed = parseInt(text, pageNumber, pos)
      if parsed == 0:
        failParse(source, ordinal, "n must be an integer")
      result.metadata.pageNumber = pageNumber
      sawPageNumber = true
      pos.inc(parsed)
    of "section":
      if sawSection:
        failParse(source, ordinal, "duplicate section attribute")
      result.metadata.section = parseQuotedValue(source, ordinal, text, pos)
      sawSection = true
    else:
      failParse(source, ordinal, "unknown attribute " & attrName)

  if not sawPageNumber:
    failParse(source, ordinal, "missing required n attribute")

  result.nextPos = pos

proc parseInputChunks*(source, text: string): seq[InputChunk] =
  var pos = skipWhitespace(text)
  var ordinal = 1

  while pos < text.len:
    if not text.isMarkerStart(pos):
      failParse(source, ordinal, "missing <page ...> marker")

    let marker = parsePageMarker(source, ordinal, text, pos)
    let nextMarkerPos = findNextMarkerStart(text, marker.nextPos)
    let bodyBounds = trimChunkBounds(text, marker.nextPos, nextMarkerPos)
    if bodyBounds.a >= bodyBounds.b:
      failParse(source, ordinal, "chunk body is empty")

    result.add(InputChunk(
      source: source,
      ordinal: ordinal,
      text: text[bodyBounds],
      metadata: marker.metadata
    ))

    pos = nextMarkerPos
    inc ordinal

proc loadInputChunks*(path: string): seq[InputChunk] =
  result = parseInputChunks(path, readFile(path))
