import std/os

proc sqliteVectorExtensionFilename*(): string =
  when defined(windows):
    result = "vector.dll"
  elif defined(macosx):
    result = "vector.dylib"
  else:
    result = "vector.so"

proc appLocalSqliteVectorExtensionPath*(): string =
  result = getAppDir() / sqliteVectorExtensionFilename()
