import std/os

proc sqliteVectorExtensionFilename*(): string =
  when defined(windows):
    result = "vector.dll"
  elif defined(macosx):
    result = "vector.dylib"
  else:
    result = "vector.so"

proc defaultSqliteVectorExtensionRelativePath*(): string =
  result = "third_party" / "sqlite" / sqliteVectorExtensionFilename()

proc normalizeSqliteVectorExtensionPath*(path: string): string =
  let parts = splitFile(path)
  let usesVectorName = parts.name == "vector"
  let hasKnownExtension = parts.ext.len == 0 or
    parts.ext == ".so" or
    parts.ext == ".dylib" or
    parts.ext == ".dll"

  if fileExists(path):
    result = path
  elif usesVectorName and hasKnownExtension:
    if parts.dir.len == 0:
      result = sqliteVectorExtensionFilename()
    else:
      result = parts.dir / sqliteVectorExtensionFilename()
  else:
    result = path
