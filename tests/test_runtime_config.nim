import ../src/chunkvec/runtime_config
import ../src/chunkvec/types

proc testParseStoreArgs() =
  let cfg = buildRuntimeConfig(@[
    "--doc=chapter1-source",
    "--kind=source",
    "--source=course/week-1-notes.md",
    "input.txt",
    "db.sqlite"
  ])
  doAssert cfg.inputPath == "input.txt"
  doAssert cfg.dbPath == "db.sqlite"
  doAssert cfg.sourcePath == "course/week-1-notes.md"
  doAssert cfg.searchFilters.docId == "chapter1-source"
  doAssert cfg.searchFilters.kind == source

proc testParseQueryFilters() =
  let cfg = buildRuntimeConfig(@[
    "--doc=chapter1-source",
    "--kind=source",
    "--page=12",
    "--label=regularization",
    "query.txt",
    "db.sqlite"
  ])
  doAssert cfg.inputPath == "query.txt"
  doAssert cfg.dbPath == "db.sqlite"
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
    "input.txt",
    "db.sqlite"
  ])
  doAssert cfg.inputPath == "input.txt"
  doAssert cfg.dbPath == "db.sqlite"
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
