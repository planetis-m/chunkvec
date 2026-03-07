import std/strutils

proc splitChunks*(text, marker: string): seq[string] =
  for part in text.split(marker):
    let chunk = part.strip()
    if chunk.len > 0:
      result.add(chunk)
