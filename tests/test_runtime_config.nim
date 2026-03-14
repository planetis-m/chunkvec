import std/[appdirs, paths, strutils]
from std/dirs import dirExists
import ../src/chunkvec/[constants, runtime_config, types]

proc expectedDbPath(): string =
  let workspacePath = getCurrentDir()
  let workspaceHash = toHex(int(hash(workspacePath)))
  result = $(
    getDataDir() / Path(AppDataDirName) /
    Path($lastPathPart(workspacePath) & workspaceHash) /
    Path(DatabaseFilename)
  )

proc testParseStoreArgs() =
  let cfg = buildRuntimeConfig(@[
    "--doc=chapter1-source",
    "--kind=source",
    "--source=course/week-1-notes.md",
    "input.txt"
  ])
  doAssert cfg.inputPath == "input.txt"
  doAssert cfg.dbPath == expectedDbPath()
  doAssert dirExists(parentDir(Path(cfg.dbPath)))
  doAssert cfg.sourcePath == "course/week-1-notes.md"
  doAssert cfg.searchFilters.docId == "chapter1-source"
  doAssert cfg.searchFilters.kind == source

proc testParseQueryFilters() =
  let cfg = buildRuntimeConfig(@[
    "--doc=chapter1-source",
    "--kind=source",
    "--page=12",
    "--label=regularization",
    "query.txt"
  ])
  doAssert cfg.inputPath == "query.txt"
  doAssert cfg.dbPath == expectedDbPath()
  doAssert cfg.searchFilters == SearchFilters(
    docId: "chapter1-source",
    kind: source,
    page: 12,
    labelSubstring: "regularization"
  )

proc testParseStoreWithoutSourcePath() =
  let cfg = buildRuntimeConfig(@[
    "--doc=chapter1-notes",
    "--kind=derived",
    "input.txt"
  ])
  doAssert cfg.inputPath == "input.txt"
  doAssert cfg.dbPath == expectedDbPath()
  doAssert cfg.sourcePath.len == 0
  doAssert cfg.searchFilters == SearchFilters(
    docId: "chapter1-notes",
    kind: derived,
    page: NoPageFilter,
    labelSubstring: ""
  )

when isMainModule:
  testParseStoreArgs()
  testParseQueryFilters()
  testParseStoreWithoutSourcePath()
