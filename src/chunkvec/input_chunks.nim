import std/[parseutils, strutils]
import ./[marker_parser, types]

const
  ChunkMarkerName = "chunk"
  ChunkMarkerPrefix = "<chunk"

proc trimChunkBounds(text: string; startPos, endPos: int): Slice[int] =
  var first = startPos
  var last = endPos

  while first < last and text[first].isSpaceAscii:
    inc first
  while last > first and text[last - 1].isSpaceAscii:
    dec last

  result = first ..< last

proc parseChunkMarker(text: string; metadata: var ChunkMetadata; startPos: int): int =
  var docId = ""
  var kind = none
  var position = NoPositionFilter
  var label = ""

  let parsedLen = parseMarker(ChunkMarkerName, pos, attrName):
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
  if parsedLen == 0:
    return 0
  if docId.len == 0:
    failParse("missing required doc attribute")
  if kind == none:
    failParse("missing required kind attribute")
  if position == NoPositionFilter:
    failParse("missing required position attribute")

  metadata = ChunkMetadata(
    docId: docId,
    kind: kind,
    position: position,
    label: label
  )
  result = parsedLen

proc parseInputChunks*(source, text: string): seq[InputChunk] =
  var pos = skipWhitespace(text)
  var ordinal = 1

  while pos < text.len:
    if not markerAtLineStart(text, pos, ChunkMarkerPrefix):
      failParse("missing <chunk ...> marker")

    var metadata: ChunkMetadata
    let markerLen = parseChunkMarker(text, metadata, pos)
    if markerLen == 0:
      failParse("expected <chunk ...> marker")

    let bodyStart = pos + markerLen
    let nextMarkerPos = findNextMarker(text, bodyStart, ChunkMarkerPrefix)
    let bodyBounds = trimChunkBounds(text, bodyStart, nextMarkerPos)
    if bodyBounds.a >= bodyBounds.b:
      failParse("chunk body is empty")

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
