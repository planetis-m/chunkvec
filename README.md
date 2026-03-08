# chunkvec

Store embeddings for pre-chunked text in SQLite and search them locally with
`sqlite-vector`.

`chunkvec` is a small two-command CLI for workflows where chunking already
happened upstream. You give it one marked-up text file, it embeds each chunk
through DeepInfra's OpenAI-compatible embeddings API, stores the rows in SQLite,
and later answers similarity queries locally from that database.

## Why try it?

- chunk boundaries stay under your control; `chunkvec` never re-chunks text
- ingest preserves the original order with explicit `ordinal` values
- optional per-chunk metadata headers (`page`, `section`) stay attached to rows
- search does one remote embedding call, then runs nearest-neighbor lookup
  locally through `sqlite-vector`

## Design

`chunkvec` follows the same small runtime shape as `chunktts`:

1. `chunkvec_ingest`:
- reads one input text file
- splits it on the built-in `<bk>` marker
- sends embedding requests with bounded in-flight work and retries
- inserts successful chunks into SQLite in original order
- initializes and quantizes the `sqlite-vector` column

2. `chunkvec_search`:
- reads query text from `stdin`
- embeds that query through the same built-in model
- prints top matches from the local SQLite database

The public contract is intentionally small: one marked-up text file in, one
SQLite database out, then local search from one query on `stdin`.

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
- `max_inflight`
- `max_retries`
- `total_timeout_ms`
- `top_k`

Example:

```json
{
  "api_url": "https://api.deepinfra.com/v1/openai/embeddings",
  "max_inflight": 32,
  "max_retries": 5,
  "total_timeout_ms": 120000,
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
- top-k search results: `8`
- sqlite-vector runtime path: the app directory, using the platform filename

## CLI

```bash
./chunkvec_ingest INPUT.txt DB.sqlite
./chunkvec_search DB.sqlite < QUERY.txt
./chunkvec_ingest --help
./chunkvec_search --help
```

- `INPUT.txt` and `DB.sqlite` are required positional paths
- `chunkvec_search` reads the query text from `stdin`
- `stdout` is used only for search results
- logs and fatal errors go to `stderr`

## Input format

`chunkvec_ingest` splits the input file on the built-in `<bk>` marker.

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
- if a chunk starts with a JSON object followed by a blank line, that object is
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

Prepare a query:

```text
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
printf '%s\n' 'How do embeddings help search?' | ./chunkvec_search notes.sqlite
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
- `2`: ingest completed with permanent chunk failures; successful rows were
  still committed
- `3`: fatal startup or runtime failure

## Requirements

- DeepInfra API key via `DEEPINFRA_API_KEY` or `config.json`
- one marked-up input text file for ingest
- query text on `stdin` for search
- `vector.so`, `vector.dylib`, or `vector.dll` beside the executables
- if building from source: Nim `>= 2.2.8`, Atlas, `libcurl`, and SQLite

## Verification

```bash
nim test tests/ci.nims
```

The test suite covers:

- chunk splitting and metadata parsing
- request-id packing
- SQLite plus `sqlite-vector` integration
