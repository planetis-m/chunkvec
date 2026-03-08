import std/parseutils

type
  MarkerAttrParser* = proc(attrName: string; text: string; pos: var int)

proc skipMarkerWhitespace*(text: string; pos: var int) =
  pos.inc(skipWhitespace(text, pos))

proc parseQuotedValue*(text: string; pos: var int): string =
  if pos >= text.len or text[pos] != '"':
    raise newException(ValueError, "expected quoted string")

  inc pos
  let valueStart = pos
  while pos < text.len and text[pos] != '"':
    inc pos
  if pos >= text.len:
    raise newException(ValueError, "unterminated quoted string")

  result = text[valueStart ..< pos]
  inc pos

proc parseMarker*(text: string; startPos: int; markerName: string;
    parseAttr: MarkerAttrParser): int =
  var pos = startPos
  if pos >= text.len or text[pos] != '<':
    raise newException(ValueError, "missing marker")
  inc pos

  var parsedName = ""
  let markerLen = parseIdent(text, parsedName, pos)
  if markerLen == 0 or parsedName != markerName:
    raise newException(ValueError, "unexpected marker")
  pos.inc(markerLen)

  while true:
    skipMarkerWhitespace(text, pos)
    if pos >= text.len:
      raise newException(ValueError, "unterminated marker")
    if text[pos] == '>':
      inc pos
      break

    var attrName = ""
    let attrLen = parseIdent(text, attrName, pos)
    if attrLen == 0:
      raise newException(ValueError, "expected attribute name")
    pos.inc(attrLen)

    skipMarkerWhitespace(text, pos)
    if pos >= text.len or text[pos] != '=':
      raise newException(ValueError, "expected '=' after attribute")
    inc pos
    skipMarkerWhitespace(text, pos)

    parseAttr(attrName, text, pos)

  result = pos
