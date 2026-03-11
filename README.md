# chunkvec

Embedding ingest and local search for marked-up text files.

`chunkvec` reads text that already contains chunk boundaries via `<chunk ...>`
markers, sends those chunks to DeepInfra's OpenAI-compatible embeddings API,
stores the results in SQLite with `sqlite-vector`, and later answers semantic
queries locally from that database.

## Core guarantees

- input is one marked-up text file, output is one SQLite database
- `cvstore` applies one `doc` and one `kind` to the whole ingest run
- each chunk still carries its own optional `page` and `label`
- ingest does bounded in-flight embedding work with retry handling
- search embeds one raw `QUERY` string, then does nearest-neighbor lookup
  locally through `sqlite-vector`

## Design

`chunkvec` uses a small two-command shape:

1. `cvstore`:
- reads one input text file
- parses required leading `<chunk ...>` markers
- requires `--doc` and `--kind` and stores those values on every inserted row
- sends embedding requests with bounded in-flight work and retries
- inserts successful chunks into SQLite
- initializes and quantizes the `sqlite-vector` column

2. `cvquery`:
- takes one raw `QUERY` positional argument
- optionally applies CLI filter flags such as `--doc` and `--kind`
- embeds that query through the same built-in model
- prints top matches from the local SQLite database

The public contract is intentionally small: one marked-up text file in, one
SQLite database out, then local search from one query string.

## Installation

### Prebuilt binaries

Download a release asset for your platform from:

- <https://github.com/planetis-m/chunkvec/releases/latest>

Runtime dependencies:

- Linux: `libcurl` and `sqlite3`
- macOS: `curl` and `sqlite`
- Windows: no extra runtime install if the archive bundles the required DLLs

Keep `cvstore`, `cvquery`, `config.json`, and the platform
`vector` runtime library in the same directory.

### Build from source

<details>
<summary>Linux x86_64</summary>

```bash
sudo apt-get update
sudo apt-get install -y libcurl4-openssl-dev sqlite3
nimble install -y "https://github.com/nim-lang/atlas@#head"
atlas install
export SQLITE_VECTOR_VERSION=0.9.92
curl -fL \
  "https://github.com/sqliteai/sqlite-vector/releases/download/${SQLITE_VECTOR_VERSION}/vector-linux-x86_64-${SQLITE_VECTOR_VERSION}.tar.gz" \
  -o vector-linux-x86_64.tar.gz
mkdir -p sqlite-vector-download
tar -xf vector-linux-x86_64.tar.gz -C sqlite-vector-download
cp "$(find sqlite-vector-download -type f -name 'vector.so' | head -n 1)" vector.so
nim c -d:release -o:cvstore src/cvstore.nim
nim c -d:release -o:cvquery src/cvquery.nim
```

</details>

<details>
<summary>macOS arm64</summary>

```bash
brew install curl sqlite
nimble install -y "https://github.com/nim-lang/atlas@#head"
atlas install
export SQLITE_VECTOR_VERSION=0.9.92
curl -fL \
  "https://github.com/sqliteai/sqlite-vector/releases/download/${SQLITE_VECTOR_VERSION}/vector-macos-${SQLITE_VECTOR_VERSION}.tar.gz" \
  -o vector-macos.tar.gz
mkdir -p sqlite-vector-download
tar -xf vector-macos.tar.gz -C sqlite-vector-download
cp "$(find sqlite-vector-download -type f -name 'vector.dylib' | head -n 1)" vector.dylib
nim c -d:release -o:cvstore src/cvstore.nim
nim c -d:release -o:cvquery src/cvquery.nim
```

</details>

<details>
<summary>Windows x86_64 (PowerShell)</summary>

```powershell
nimble install -y "https://github.com/nim-lang/atlas@#head"
atlas install
$env:SQLITE_VECTOR_VERSION = "0.9.92"
curl.exe -fL `
  "https://github.com/sqliteai/sqlite-vector/releases/download/$env:SQLITE_VECTOR_VERSION/vector-windows-x86_64-$env:SQLITE_VECTOR_VERSION.zip" `
  -o vector-windows-x86_64.zip
Expand-Archive -Path vector-windows-x86_64.zip -DestinationPath sqlite-vector-download -Force
$candidate = Get-ChildItem -Path sqlite-vector-download -Recurse -Filter vector.dll |
  Select-Object -First 1
if ($null -eq $candidate) { throw "vector.dll not found in archive" }
Copy-Item $candidate.FullName (Join-Path $pwd "vector.dll") -Force
# Install curl/sqlite3 as in CI, for example via vcpkg:
#   vcpkg install curl[http2,ssl,c-ares] sqlite3 --triplet x64-windows-release
#   $env:VCPKG_ROOT = "$pwd\vcpkg\installed\x64-windows-release"
nim c -d:release -o:cvstore.exe src/cvstore.nim
nim c -d:release -o:cvquery.exe src/cvquery.nim
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
./cvstore --doc=DOC --kind=source|derived [--source=RELATIVEPATH] INPUT.txt
./cvquery [--doc=DOC] [--kind=source|derived] [--page=N] [--label=TEXT] QUERY
./cvstore --help
./cvquery --help
```

- `cvstore` requires `--doc` and `--kind` for the whole ingest run
- `cvquery` takes a raw `QUERY` string, not a query file
- `cvquery --page` requires `--doc`
- `stdout` is used only for search results
- logs and fatal errors go to `stderr`

## Input format

`cvstore` requires every chunk to start with a `<chunk ...>` marker.
Chunk headers now carry only per-chunk metadata. `doc` and `kind` no longer
belong in the input file; pass them on the `cvstore` command line instead.
Older `<chunk ... pos=...>` and `<chunk doc=... kind=... position=...>` files
must be regenerated for this format.

Minimal example:

```text
<chunk page=1>
First chunk.

<chunk page=2>
Second chunk.

<chunk page=3>
Third chunk.
```

Input with label metadata:

```text
<chunk page=12 label="Backpropagation">
Gradient descent updates weights using the negative gradient.

<chunk page=13 label="Regularization">
Dropout disables random activations during training.
```

Rules:

- leading file whitespace before the first marker is ignored
- every chunk must start with `<chunk ...>`
- `page` is optional and must be an integer when present
- `label` is optional and must be double-quoted when present
- `doc`, `kind`, and legacy `pos`/`position` attributes are rejected
- unknown marker attributes are rejected
- surrounding whitespace around each chunk body is trimmed
- empty chunk bodies are rejected

## Quick start

Prepare an input file:

```text
<chunk page=4 label="Embeddings">
Embeddings map text into vectors where similar meanings stay close.

<chunk page=5 label="Vector Search">
Nearest-neighbor search compares a query vector against stored vectors.

<chunk>
Use cosine distance when direction matters more than magnitude.
```

Set the ingest metadata on `cvstore`:

- `--doc=notes-course`
- `--kind=source`

Set your API key:

```bash
export DEEPINFRA_API_KEY=...
```

Ingest:

```bash
./cvstore --doc=notes-course --kind=source --source=course/notes.md notes.txt
```

Search:

```bash
./cvquery --doc=notes-course --kind=source --page=5 --label=vector_search "How do embeddings help search?"
```

Search filter rules:

- `doc` is an exact match filter on the logical document id
- `kind` is an exact match filter on `source` or `derived`
- `page` is an exact integer filter and requires `doc`
- `label` is a substring filter after `strutils.normalize` on both sides
- `strutils.normalize` lowercases ASCII and removes `_`
- if multiple CLI filters are present, all must match
- `QUERY` is still required even when filters are present

Typical output:

```text
1. distance=0.123456 source=course/notes.md doc="notes-course" kind=source page=4 label="Embeddings"
Embeddings map text into vectors where similar meanings stay close.

2. distance=0.187654 source=course/notes.md doc="notes-course" kind=source page=5 label="Vector Search"
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
- one raw query string for search
- `vector.so`, `vector.dylib`, or `vector.dll` beside the executables
- if building from source: Nim `>= 2.2.8`, Atlas, `libcurl`, and SQLite

## Verification

```bash
nim test tests/ci.nims
```

The test suite covers:

- chunk-marker parsing
- search-input parsing
- request-id packing
- SQLite plus `sqlite-vector` integration
