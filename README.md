# chunkvec

Ordered embedding ingest and local search for marked-up text files.

`chunkvec` reads text that already contains chunk boundaries via `<page ...>`
markers, sends those chunks to DeepInfra's OpenAI-compatible embeddings API,
stores the results in SQLite with `sqlite-vector`, and later answers semantic
queries locally from that database.

## Core guarantees

- input is one marked-up text file, output is one SQLite database
- chunk order is preserved with explicit `ordinal` values
- page and optional section metadata stay attached to each stored row
- ingest does bounded in-flight embedding work with retry handling
- search does one embedding request for the query, then nearest-neighbor lookup
  locally through `sqlite-vector`

## Design

`chunkvec` uses the same small two-command shape as `chunktts`:

1. `chunkvec_ingest`:
- reads one input text file
- parses required leading `<page ...>` markers
- sends embedding requests with bounded in-flight work and retries
- inserts successful chunks into SQLite in original order
- initializes and quantizes the `sqlite-vector` column

2. `chunkvec_search`:
- reads one query text file
- optionally parses a leading `<search ...>` filter header
- embeds that query through the same built-in model
- prints top matches from the local SQLite database

The public contract is intentionally small: one marked-up text file in, one
SQLite database out, then local search from one query file.

## Installation

### Prebuilt binaries

Download a release asset for your platform from:

- <https://github.com/planetis-m/chunkvec/releases/latest>

Runtime dependencies:

- Linux: `libcurl` and `sqlite3`
- macOS: `curl` and `sqlite`
- Windows: no extra runtime install if the archive bundles the required DLLs

Keep `chunkvec_ingest`, `chunkvec_search`, `config.json`, and the platform
`vector` runtime library in the same directory.

### Build from source

<details>
<summary>Linux x86_64</summary>

```bash
sudo apt-get update
sudo apt-get install -y libcurl4-openssl-dev sqlite3 libsqlite3-dev
atlas install
nim c -d:release -o:chunkvec_ingest src/chunkvec_ingest.nim
nim c -d:release -o:chunkvec_search src/chunkvec_search.nim
cp third_party/sqlite/vector.so .
```

</details>

<details>
<summary>macOS arm64</summary>

```bash
brew install curl sqlite
atlas install
nim c -d:release -o:chunkvec_ingest src/chunkvec_ingest.nim
nim c -d:release -o:chunkvec_search src/chunkvec_search.nim
# Place vector.dylib beside the two executables.
```

</details>

<details>
<summary>Windows x86_64 (PowerShell)</summary>

```powershell
atlas install
nim c -d:release -o:chunkvec_ingest.exe src/chunkvec_ingest.nim
nim c -d:release -o:chunkvec_search.exe src/chunkvec_search.nim
# Place vector.dll beside the two executables.
```

</details>

## Runtime configuration

Optional `config.json` next to the executables overrides built-in defaults.
If `DEEPINFRA_API_KEY` is set, it overrides `api_key` from `config.json`.

Supported keys:

- `api_key`
- `api_url`
- `model`
- `embedding_dimension`
- `max_inflight`
- `max_retries`
- `total_timeout_ms`
- `top_k`

Example:

```json
{
  "api_url": "https://api.deepinfra.com/v1/openai/embeddings",
  "model": "Qwen/Qwen3-Embedding-0.6B",
  "embedding_dimension": 1024,
  "max_inflight": 32,
  "max_retries": 5,
  "total_timeout_ms": 120000,
  "top_k": 8
}
```

Built-in defaults:

- endpoint: `https://api.deepinfra.com/v1/openai/embeddings`
- model: `Qwen/Qwen3-Embedding-0.6B`
- embedding dimension: `1024`
- max inflight: `32`
- max retries: `5`
- total timeout: `120000 ms`
- top-k search results: `8`
- `sqlite-vector` runtime path: the app directory, using the platform filename

## CLI

```bash
./chunkvec_ingest INPUT.txt DB.sqlite
./chunkvec_search QUERY.txt DB.sqlite
./chunkvec_ingest --help
./chunkvec_search --help
```

- `chunkvec_ingest` takes `INPUT.txt DB.sqlite`
- `chunkvec_search` takes `QUERY.txt DB.sqlite`
- `stdout` is used only for search results
- logs and fatal errors go to `stderr`

## Input format

`chunkvec_ingest` requires every chunk to start with a `<page ...>` marker.

Minimal example:

```text
<page n=1>
First chunk.

<page n=2>
Second chunk.

<page n=3>
Third chunk.
```

Page plus section metadata:

```text
<page n=12 section="Backpropagation">
Gradient descent updates weights using the negative gradient.

<page n=13 section="Regularization">
Dropout disables random activations during training.
```

Rules:

- leading file whitespace before the first marker is ignored
- every chunk must start with `<page ...>`
- `n` is required and must be an integer
- `section` is optional and must be double-quoted when present
- unknown marker attributes are rejected
- surrounding whitespace around each chunk body is trimmed
- empty chunk bodies are rejected

## Quick start

Prepare an input file:

```text
<page n=4 section="Embeddings">
Embeddings map text into vectors where similar meanings stay close.

<page n=5 section="Vector Search">
Nearest-neighbor search compares a query vector against stored vectors.

<page n=6>
Use cosine distance when direction matters more than magnitude.
```

Prepare a query:

```text
How do embeddings help search?
```

Filtered query example:

```text
<search page=5 section="vector_search">

How do embeddings help search?
```

Set your API key:

```bash
export DEEPINFRA_API_KEY=...
```

Ingest:

```bash
./chunkvec_ingest notes.txt notes.sqlite
```

Search:

```bash
./chunkvec_search query.txt notes.sqlite
```

`chunkvec_search` accepts either:

- a plain query file containing only the semantic query text
- or an optional leading `<search ...>` header followed by a blank line and the
  query text

Search filter rules:

- `page` is an exact single-page filter
- `section` is a substring filter after `strutils.normalize` on both sides
- `strutils.normalize` lowercases ASCII and removes `_`
- if both filters are present, both must match
- query text is still required even when filters are present

Typical output:

```text
1. distance=0.123456 source=notes.txt ordinal=1 page=4 section="Embeddings"
Embeddings map text into vectors where similar meanings stay close.

2. distance=0.187654 source=notes.txt ordinal=2 page=5 section="Vector Search"
Nearest-neighbor search compares a query vector against stored vectors.
```

## Exit codes

- `0`: all requested work succeeded
- `2`: ingest completed with permanent chunk failures; successful rows were
  still committed
- `3`: fatal startup or runtime failure

## Requirements

- DeepInfra API key via `DEEPINFRA_API_KEY` or `config.json`
- one marked-up input text file for ingest
- one query text file for search
- `vector.so`, `vector.dylib`, or `vector.dll` beside the executables
- if building from source: Nim `>= 2.2.8`, Atlas, `libcurl`, and SQLite

## Verification

```bash
nim test tests/ci.nims
```

The test suite covers:

- page-marker parsing
- search-input parsing
- request-id packing
- SQLite plus `sqlite-vector` integration
