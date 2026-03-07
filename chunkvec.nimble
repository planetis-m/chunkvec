version       = "0.1.0"
author        = "planetis"
description   = "Store and retrieve embeddings for pre-chunked study text using DeepInfra and SQLite Vector"
license       = "AGPL-3.0"
srcDir        = "src"
bin           = @["chunkvec_ingest", "chunkvec_search"]

requires "nim >= 2.2.8"
requires "https://github.com/planetis-m/mimalloc_nim"
requires "https://github.com/planetis-m/jsonx"
requires "https://github.com/planetis-m/relay"
requires "https://github.com/planetis-m/openai"
