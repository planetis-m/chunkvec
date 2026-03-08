import std/[parseutils, strutils]
import ./[marker_parser, types]

const
  MarkerName = "page"
  MarkerPrefix = "<" & MarkerName

proc failParse(source: string; ordinal: int; message: string) {.noreturn.} =
  raise newException(ValueError,
    source & ": invalid chunk " & $ordinal & ": " & message)

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

proc parsePageMarker(source: string; ordinal: int; text: string; startPos: int): tuple[
    metadata: ChunkMetadata, nextPos: int] =
  var metadata: ChunkMetadata
  var nextPos = 0
  var sawPageNumber = false

  proc parsePageAttr(attrName: string; text: string; pos: var int) =
    case attrName
    of "n":
      var pageNumber = 0
      let parsed = parseInt(text, pageNumber, pos)
      if parsed == 0:
        failParse(source, ordinal, "n must be an integer")
      metadata.pageNumber = pageNumber
      sawPageNumber = true
      pos.inc(parsed)
    of "section":
      try:
        metadata.section = parseQuotedValue(text, pos)
      except ValueError:
        failParse(source, ordinal, "section must use a double-quoted string")
    else:
      failParse(source, ordinal, "unknown attribute " & attrName)

  try:
    nextPos = parseMarker(text, startPos, MarkerName, parsePageAttr)
  except ValueError:
    failParse(source, ordinal, "expected <page ...> marker")

  if not sawPageNumber:
    failParse(source, ordinal, "missing required n attribute")

  result = (metadata: metadata, nextPos: nextPos)

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
