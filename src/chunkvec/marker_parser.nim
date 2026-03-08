import std/[strutils, parseutils]

proc failParse*(message: string) {.noreturn.} =
  raise newException(ValueError, message)

proc skipMarkerWhitespace*(text: string; pos: var int) =
  pos.inc(skipWhitespace(text, pos))

proc parseQuotedValue*(text: string; value: var string; start: int): int =
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

template parseMarker*(markerName: string; posName, attrName, parseAttr: untyped): int =
  var posName = startPos
  if posName >= text.len or text[posName] != '<':
    0
  else:
    inc posName

    var parsedName = ""
    let markerLen = parseIdent(text, parsedName, posName)
    if markerLen == 0 or parsedName != markerName:
      0
    else:
      posName.inc(markerLen)

      var parsedOk = true
      while parsedOk:
        skipMarkerWhitespace(text, posName)
        if posName >= text.len:
          parsedOk = false
        elif text[posName] == '>':
          inc posName
          break
        else:
          var attrName = ""
          let attrLen = parseIdent(text, attrName, posName)
          if attrLen == 0:
            parsedOk = false
          else:
            posName.inc(attrLen)
            skipMarkerWhitespace(text, posName)
            if posName >= text.len or text[posName] != '=':
              parsedOk = false
            else:
              inc posName
              skipMarkerWhitespace(text, posName)
              parseAttr

      if parsedOk:
        posName - startPos
      else:
        0

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
