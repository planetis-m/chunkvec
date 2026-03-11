version       = "0.7.0"
author        = "planetis"
description   = "Store and search embeddings for pre-chunked text with SQLite vector search"
license       = "AGPL-3.0"
srcDir        = "src"
bin           = @["cvstore", "cvquery"]

requires "nim >= 2.2.8"
requires "db_connector"
requires "https://github.com/planetis-m/mimalloc_nim"
requires "https://github.com/planetis-m/jsonx"
requires "https://github.com/planetis-m/relay"
requires "https://github.com/planetis-m/openai"
