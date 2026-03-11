import std/[parseutils, strutils]
import ./types

const
  ChunkMarkerName = "chunk"
  ChunkMarkerPrefix = "<chunk"

proc failParse(message: string) {.noreturn.} =
  raise newException(ValueError, message)

proc skipMarkerWhitespace(text: string; pos: var int) =
  pos.inc(skipWhitespace(text, pos))

proc parseQuotedValue(text: string; value: var string; start: int): int =
  var pos = start
  if pos >= text.len or text[pos] != '"':
    return 0

  inc pos
  let valueStart = pos
  let valueLen = skipUntil(text, '"', pos)
  if pos + valueLen >= text.len:
    return 0

  value = text.substr(valueStart, valueStart + valueLen - 1)
  pos.inc(valueLen)
  inc pos
  result = pos - start

proc parseChunkMarkerHeader(text, markerName: string; startPos: int;
    chunk: var InputChunk; parseAttr:
    proc(text, attrName: string; pos: var int; chunk: var InputChunk) {.nimcall.}): int =
  var pos = startPos
  if pos >= text.len or text[pos] != '<':
    return 0

  inc pos

  var parsedName = ""
  let markerLen = parseIdent(text, parsedName, pos)
  if markerLen == 0 or parsedName != markerName:
    return 0

  pos.inc(markerLen)

  while true:
    skipMarkerWhitespace(text, pos)
    if pos >= text.len:
      return 0
    if text[pos] == '>':
      inc pos
      return pos - startPos

    var attrName = ""
    let attrLen = parseIdent(text, attrName, pos)
    if attrLen == 0:
      return 0

    pos.inc(attrLen)
    skipMarkerWhitespace(text, pos)
    if pos >= text.len or text[pos] != '=':
      return 0

    inc pos
    skipMarkerWhitespace(text, pos)
    parseAttr(text, attrName, pos, chunk)

proc parseChunkMetadataAttr(text, attrName: string; pos: var int;
    chunk: var InputChunk) {.nimcall.} =
  case attrName
  of "page":
    let parsed = parseInt(text, chunk.page, pos)
    if parsed == 0:
      failParse("page must be an integer")
    pos.inc(parsed)
  of "label":
    let parsed = parseQuotedValue(text, chunk.label, pos)
    if parsed == 0:
      failParse("label must use a double-quoted string")
    pos.inc(parsed)
  else:
    failParse("unknown attribute " & attrName)

proc markerAtLineStart(text: string; pos: int; prefix: string): bool =
  if pos < 0 or pos + prefix.len > text.len:
    return false
  if skip(text, prefix, pos) == 0:
    return false

  var i = pos - 1
  while i >= 0 and text[i] notin {'\n', '\r'}:
    if text[i] notin {' ', '\t'}:
      return false
    dec i

  result = true

proc findNextMarker(text: string; startPos: int; prefix: string): int =
  result = text.len
  var pos = startPos
  while pos < text.len:
    let i = text.find(prefix, pos)
    if i < 0:
      break
    if markerAtLineStart(text, i, prefix):
      result = i
      break
    pos = i + prefix.len

proc trimChunkBounds(text: string; startPos, endPos: int): Slice[int] =
  var first = startPos
  var last = endPos

  while first < last and text[first].isSpaceAscii:
    inc first
  while last > first and text[last - 1].isSpaceAscii:
    dec last

  result = first ..< last

proc parseChunkMarker(text: string; chunk: var InputChunk; startPos: int): int =
  chunk = InputChunk(
    text: "",
    page: NoPageFilter,
    label: ""
  )

  let parsedLen = parseChunkMarkerHeader(text, ChunkMarkerName, startPos, chunk,
    parseChunkMetadataAttr)
  if parsedLen == 0:
    return 0
  result = parsedLen

proc parseInputChunks*(text: string): seq[InputChunk] =
  var pos = skipWhitespace(text)

  while pos < text.len:
    if not markerAtLineStart(text, pos, ChunkMarkerPrefix):
      failParse("missing <chunk ...> marker")

    var chunk: InputChunk
    let markerLen = parseChunkMarker(text, chunk, pos)
    if markerLen == 0:
      failParse("expected <chunk ...> marker")

    let bodyStart = pos + markerLen
    let nextMarkerPos = findNextMarker(text, bodyStart, ChunkMarkerPrefix)
    let bodyBounds = trimChunkBounds(text, bodyStart, nextMarkerPos)
    if bodyBounds.a >= bodyBounds.b:
      failParse("chunk body is empty")

    chunk.text = text[bodyBounds]
    result.add(chunk)

    pos = nextMarkerPos

proc loadInputChunks*(path: string): seq[InputChunk] =
  result = parseInputChunks(readFile(path))
