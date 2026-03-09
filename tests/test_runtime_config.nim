import ../src/chunkvec/runtime_config
import ../src/chunkvec/types

proc testParseSourcePath() =
  let cfg = buildRuntimeConfig(@[
    "--source=course/week-1-notes.md",
    "input.txt",
    "db.sqlite"
  ])
  doAssert cfg.inputPath == "input.txt"
  doAssert cfg.dbPath == "db.sqlite"
  doAssert cfg.sourcePath == "course/week-1-notes.md"

proc testParseQueryFilters() =
  let cfg = buildRuntimeConfig(@[
    "--doc=chapter1-source",
    "--kind=source",
    "--position=12",
    "--label=regularization",
    "query.txt",
    "db.sqlite"
  ])
  doAssert cfg.inputPath == "query.txt"
  doAssert cfg.dbPath == "db.sqlite"
  doAssert cfg.searchFilters == SearchFilters(
    docId: "chapter1-source",
    kind: source,
    position: 12,
    labelSubstring: "regularization"
  )

proc testParseWithoutSourcePath() =
  let cfg = buildRuntimeConfig(@[
    "input.txt",
    "db.sqlite"
  ])
  doAssert cfg.inputPath == "input.txt"
  doAssert cfg.dbPath == "db.sqlite"
  doAssert cfg.sourcePath.len == 0
  doAssert not cfg.searchFilters.hasFilters

when isMainModule:
  testParseSourcePath()
  testParseQueryFilters()
  testParseWithoutSourcePath()
