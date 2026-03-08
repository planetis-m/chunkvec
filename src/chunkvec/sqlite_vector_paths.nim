import std/os

const ExtensionFilename* =
  when defined(windows):
    "vector.dll"
  elif defined(macosx):
    "vector.dylib"
  else:
    "vector.so"

proc extensionPath*(): string =
  result = getAppDir() / ExtensionFilename
