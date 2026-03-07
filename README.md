# chunkvec

Store embeddings for pre-chunked text in SQLite and search them locally with
`sqlite-vector`.

`chunkvec` is a two-command CLI for workflows where chunking already happened
upstream. You feed it a text file split with markers like `<bk>`, it embeds each
chunk through DeepInfra's OpenAI-compatible embeddings API, stores the rows in a
SQLite database, and later answers similarity queries locally from that
database.

## Core guarantees

- chunking stays under your control; `chunkvec` does not invent chunk boundaries
- ingest preserves chunk order with explicit `ordinal` values
- optional per-chunk metadata headers (`page`, `section`) are stored alongside
  the text
- the database stores embedding model and dimension metadata and rejects
  mismatched searches
- search computes one query embedding remotely, then runs nearest-neighbor
  lookup locally through `sqlite-vector`
- ingest retries transient embedding failures with bounded in-flight requests

## Design

`chunkvec` follows the same split runtime model as `chunktts`:

1. `chunkvec_ingest` main thread:
- parses CLI and config
- reads one input text source and splits it on a marker string
- submits embedding requests with retry handling
- inserts successful chunks into SQLite in original chunk order
- initializes and quantizes the `sqlite-vector` column

2. Relay transport thread:
- executes HTTP requests through `libcurl` multi
- keeps up to `max_inflight` embedding requests active
- returns completions to the main thread

3. `chunkvec_search`:
- embeds one query through the same model
- validates model and vector dimension against the database metadata
- prints top matches from the local SQLite database

The contract stays intentionally small: one marked-up text input in, one SQLite
database out, then local search over that database.

## Installation

### Build from source

<details>
<summary>Linux x86_64</summary>

```bash
sudo apt-get update
sudo apt-get install -y libcurl4-openssl-dev sqlite3 libsqlite3-dev
atlas install
nim c -d:release -o:chunkvec_ingest src/chunkvec_ingest.nim
nim c -d:release -o:chunkvec_search src/chunkvec_search.nim
```

</details>

<details>
<summary>macOS arm64</summary>

```bash
brew install curl sqlite
atlas install
nim c -d:release -o:chunkvec_ingest src/chunkvec_ingest.nim
nim c -d:release -o:chunkvec_search src/chunkvec_search.nim
```

</details>

<details>
<summary>Windows x86_64 (PowerShell)</summary>

```powershell
atlas install
nim c -d:release -o:chunkvec_ingest.exe src/chunkvec_ingest.nim
nim c -d:release -o:chunkvec_search.exe src/chunkvec_search.nim
```

</details>

### sqlite-vector extension

`chunkvec` loads the `sqlite-vector` extension at runtime.

- Linux: this repo currently includes `third_party/sqlite/vector.so`
- macOS: provide `third_party/sqlite/vector.dylib` or point
  `vector_extension_path` at your copy
- Windows: provide `third_party/sqlite/vector.dll` or point
  `vector_extension_path` at your copy

The default config value may omit the platform extension suffix. `chunkvec`
normalizes `third_party/sqlite/vector` to the right filename for the current
OS.

## Runtime configuration

Optional `config.json` next to the executable overrides built-in defaults. If
`DEEPINFRA_API_KEY` is set, it overrides `api_key` from `config.json`.

Supported keys:

- `api_key`
- `api_url`
- `model`
- `break_marker`
- `max_inflight`
- `max_retries`
- `total_timeout_ms`
- `vector_extension_path`
- `top_k`

Example:

```json
{
  "api_url": "https://api.deepinfra.com/v1/openai/embeddings",
  "model": "Qwen/Qwen3-Embedding-0.6B",
  "break_marker": "<bk>",
  "max_inflight": 32,
  "max_retries": 5,
  "total_timeout_ms": 120000,
  "vector_extension_path": "third_party/sqlite/vector",
  "top_k": 8
}
```

Built-in defaults:

- endpoint: `https://api.deepinfra.com/v1/openai/embeddings`
- model: `Qwen/Qwen3-Embedding-0.6B`
- marker: `<bk>`
- max inflight: `32`
- max retries: `5`
- total timeout: `120000 ms`
- vector extension path: `third_party/sqlite/vector`
- top-k search results: `8`

## CLI

```bash
./chunkvec_ingest INPUT.txt DB.sqlite
./chunkvec_ingest - DB.sqlite

./chunkvec_search DB.sqlite "your query here"
printf 'your query here' | ./chunkvec_search DB.sqlite -
```

- `chunkvec_ingest` reads from a file, or from `stdin` when `INPUT` is `-`
- `chunkvec_search` reads the query from CLI arguments, or from `stdin` when
  the query argument is exactly `-`
- normal search results go to `stdout`
- logs and fatal errors go to `stderr`

## Input format

`chunkvec_ingest` splits the input text on a marker string. The default marker
is `<bk>`.

Plain-text chunks:

```text
First chunk.<bk>
Second chunk.<bk>
Third chunk.
```

Optional metadata header per chunk:

```text
{"page":12,"section":"Backpropagation"}

Gradient descent updates weights using the negative gradient.<bk>
{"page":13,"section":"Regularization"}

Dropout disables random activations during training.
```

Rules:

- whitespace around each chunk is trimmed
- empty chunks are dropped
- if a chunk starts with a JSON object, followed by a blank line, that object is
  stored as metadata
- today the parsed metadata fields are `page` and `section`

## Quick start

Prepare an input file:

```text
{"page":4,"section":"Embeddings"}

Embeddings map text into vectors where similar meanings stay close.<bk>
{"page":5,"section":"Vector Search"}

Nearest-neighbor search compares a query vector against stored vectors.<bk>
Use cosine distance when direction matters more than magnitude.
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
./chunkvec_search notes.sqlite "How do embeddings help search?"
```

Typical output:

```text
1. distance=0.123456 source=notes.txt ordinal=1 page=4 section=Embeddings
Embeddings map text into vectors where similar meanings stay close.

2. distance=0.187654 source=notes.txt ordinal=2 page=5 section=Vector Search
Nearest-neighbor search compares a query vector against stored vectors.
```

## Exit codes

- `0`: all requested work succeeded
- `2`: ingest completed with permanent chunk failures; successful rows were still
  committed
- `3`: fatal startup or runtime failure

## Requirements

- DeepInfra API key via `DEEPINFRA_API_KEY` or `config.json`
- one pre-chunked text input for ingest
- `sqlite-vector` extension available at `vector_extension_path`
- if building from source: Nim `>= 2.2.8`, Atlas, `libcurl`, and SQLite

## Verification

```bash
nim test tests/ci.nims
```

The test suite covers:

- chunk splitting and metadata parsing
- request-id packing
- vector blob packing
- SQLite plus `sqlite-vector` integration
