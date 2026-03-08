import std/[strutils, parseutils]

type
  MarkerAttrParser* = proc(attrName: string; text: string; pos: var int)

proc failParse*(source, subject, message: string) {.noreturn.} =
  raise newException(ValueError,
    source & ": invalid " & subject & ": " & message)

proc skipMarkerWhitespace*(text: string; pos: var int) =
  pos.inc(skipWhitespace(text, pos))

proc parseQuotedValue*(text: string; value: var string; start: int): int =
  var pos = start
  if pos >= text.len or text[pos] != '"':
    return 0

  inc pos
  let valueStart = pos
  while pos < text.len and text[pos] != '"':
    inc pos
  if pos >= text.len:
    return 0

  value = text[valueStart ..< pos]
  inc pos
  result = pos - start

proc parseMarker*(text: string; startPos: int; markerName: string;
    parseAttr: MarkerAttrParser): int =
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
      break

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

    parseAttr(attrName, text, pos)

  result = pos - startPos

proc markerAtLineStart*(text: string; pos: int; prefix: string): bool =
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

proc findNextMarker*(text: string; startPos: int; prefix: string): int =
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
