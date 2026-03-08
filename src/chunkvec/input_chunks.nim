import std/[parseutils, strutils]
import ./[marker_parser, parse_errors, types]

const
  PageMarkerName = "page"
  PageMarkerPrefix = "<page"

proc trimChunkBounds(text: string; startPos, endPos: int): Slice[int] =
  var first = startPos
  var last = endPos

  while first < last and text[first].isSpaceAscii:
    inc first
  while last > first and text[last - 1].isSpaceAscii:
    dec last

  result = first ..< last

proc parsePageMarker(source: string; text: string; metadata: var ChunkMetadata;
    startPos: int): int =
  var page = 0
  var havePage = false
  var section = ""

  proc parsePageAttr(attrName: string; text: string; pos: var int) =
    case attrName
    of "n":
      let parsed = parseInt(text, page, pos)
      if parsed == 0:
        failParse(source, "input", "n must be an integer")
      havePage = true
      pos.inc(parsed)
    of "section":
      let parsed = parseQuotedValue(text, section, pos)
      if parsed == 0:
        failParse(source, "input", "section must use a double-quoted string")
      pos.inc(parsed)
    else:
      failParse(source, "input", "unknown attribute " & attrName)

  let parsedLen = parseMarker(text, startPos, PageMarkerName, parsePageAttr)
  if parsedLen == 0:
    return 0
  if not havePage:
    failParse(source, "input", "missing required n attribute")

  metadata = ChunkMetadata(pageNumber: page, section: section)
  result = parsedLen

proc parseInputChunks*(source, text: string): seq[InputChunk] =
  var pos = skipWhitespace(text)
  var ordinal = 1

  while pos < text.len:
    if not markerAtLineStart(text, pos, PageMarkerPrefix):
      failParse(source, "input", "missing <page ...> marker")

    var metadata: ChunkMetadata
    let markerLen = parsePageMarker(source, text, metadata, pos)
    if markerLen == 0:
      failParse(source, "input", "expected <page ...> marker")

    let bodyStart = pos + markerLen
    let nextMarkerPos = findNextMarker(text, bodyStart, PageMarkerPrefix)
    let bodyBounds = trimChunkBounds(text, bodyStart, nextMarkerPos)
    if bodyBounds.a >= bodyBounds.b:
      failParse(source, "input", "chunk body is empty")

    result.add(InputChunk(
      source: source,
      ordinal: ordinal,
      text: text[bodyBounds],
      metadata: metadata
    ))

    pos = nextMarkerPos
    inc ordinal

proc loadInputChunks*(path: string): seq[InputChunk] =
  result = parseInputChunks(path, readFile(path))
