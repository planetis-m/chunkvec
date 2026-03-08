import std/strutils
import ./[chunk_split, types]

proc parseChunkBody*(source: string; ordinal: int; body: string): InputChunk =
  let lines = body.splitLines()
  result = InputChunk(
    source: source,
    ordinal: ordinal,
    text: body.strip(),
    metadataJson: ""
  )

  if lines.len < 3:
    return
  if lines[1].strip().len != 0:
    return

  let headerText = lines[0].strip()
  if headerText.len == 0:
    return

  var textLines: seq[string]
  for i in 2 ..< lines.len:
    textLines.add(lines[i])

  let parsedText = textLines.join("\n").strip()
  if parsedText.len == 0:
    return

  result.text = parsedText
  result.metadataJson = headerText

proc parseInputChunks*(source, text, marker: string): seq[InputChunk] =
  let pieces = splitChunks(text, marker)
  for i in 0 ..< pieces.len:
    result.add(parseChunkBody(source, i + 1, pieces[i]))

proc loadInputChunks*(path, marker: string): seq[InputChunk] =
  result = parseInputChunks(path, readFile(path), marker)
