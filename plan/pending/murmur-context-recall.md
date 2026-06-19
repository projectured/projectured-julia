# Murmur — local context-following recall daemon + MCP server

## Goal

Build **Murmur**: a local, single-user program that maintains an indexed database of
this project's **code, documentation, and past LLM discussions**, and exposes
*fuzzy conceptual recall* to an assistant (Claude Code) — first as an MCP tool it
can call (**pull**), later as a daemon that watches the live context and proactively
injects one-line pointers (**push**).

It runs entirely on the developer's machine and consumes **no model tokens** for
indexing or retrieval; the only tokens spent are the chunks the assistant chooses
to read back. It complements ripgrep rather than replacing it: ripgrep wins on exact
symbols, Murmur wins on *"where do we handle the case where…"* conceptual queries
that exact-match search misses.

## Core design principles (decided)

These constraints shape every stage; do not relitigate them mid-build.

1. **Pull before push.** A working MCP `search`/`recall` server is the MVP and the
   safe path. Proactive injection is added only after retrieval precision is proven,
   because a wrong injection costs tokens *and* derails reasoning.
2. **Pointer, not payload.** Push mode injects a one-line hint
   (`path:line` + heading), never the full fragment. The assistant pulls the body
   via `recall(id)` only if it judges the hint relevant. This keeps push cheap
   (cache-friendly, ~1 line) while preserving proactive *discovery*.
3. **Honest tagging.** Injected hints are tagged as background context
   (`<system-reminder>`), never spoofed as user instructions — mirrors how Claude
   Code already tags recalled memory. Prevents the model acting on stale/wrong
   retrieved text as if commanded.
4. **Hybrid retrieval.** Vector search alone is mediocre at exact identifiers
   (function names, flags). Always combine BM25 (FTS5) ∪ vector → RRF merge →
   cross-encoder rerank. The exact-symbol case often lives in a one-line docstring.
5. **Precision over recall, conservatively gated.** A missed hint costs nothing;
   a wrong one costs tokens and trust. Tune thresholds high; loosen only with
   measurement.

## Stack (decided)

| Concern | Choice | Notes |
|---|---|---|
| Language | **Python** | Every dependency below is Python-first; hot paths are native (ONNX, SQLite C ext, tree-sitter C core), so Python is just glue |
| MCP server | **FastMCP** (`mcp` SDK) | decorator-based `search` / `recall` tools |
| Embeddings | **fastembed + a code model** (e.g. `nomic-embed-code`) | local, zero-token, offline. Behind an interface so it can swap to **Voyage `voyage-code-3`** if recall is weak |
| Store | **`sqlite-vec` + FTS5** in one `.sqlite` file | vector + keyword + source text in a single file, no daemon to run |
| Code chunking | **tree-sitter** (Julia grammar) | one chunk per module/struct/function + its docstring |
| Doc chunking | heading-split markdown | heading path kept as metadata |
| Reranking | cross-encoder (`sentence-transformers`) | local; or Voyage `rerank-2.5` |
| File watching | `watchdog` | incremental reindex on change |

The daemon's language (Python) is independent of the indexed project's language
(Julia) — tree-sitter parses Julia regardless.

## Repository layout (target)

A standalone project (not mixed into the Julia source tree):

```
murmur/
  pyproject.toml
  murmur/
    __init__.py
    chunking/      tree-sitter (code) + markdown (docs) + transcript splitters
    index/         sqlite-vec schema, writers, incremental reindex
    embed/         embedder interface + fastembed impl (+ voyage impl later)
    retrieve/      vector, bm25, RRF merge, rerank → search()
    server/        FastMCP app: search() / recall()
    watch/         watchdog daemon (murmurd)
  tests/
```

---

## Stage 0 — Scaffold & decisions locked

- [ ] Create the `murmur/` project, `pyproject.toml`, deps pinned (fastembed,
      sqlite-vec, tree-sitter + tree-sitter-julia, mcp, watchdog, pytest).
- [ ] Embedder **interface** (`embed(texts) -> vectors`, `dim`, `name`) with the
      fastembed implementation behind it. Voyage impl is a later drop-in.
- [ ] Config file: repo root, include/exclude globs (index `program/src`, `guide`,
      `example/src`; skip `Manifest.toml`, build artifacts, images).

**Verify:** `python -m murmur --version`; embedder returns a vector of the declared
`dim` for a sample string.

## Stage 1 — Indexer: chunking + store (code + docs)

The foundation. No embeddings yet — prove chunk boundaries and the store first.

- [ ] `sqlite-vec` schema: `chunks(id, path, start_line, end_line, kind, heading,
      text, content_hash)`, plus `vec_chunks` (vectors) and `fts_chunks` (FTS5) —
      created but vectors filled in Stage 2.
- [ ] **Code chunker** (tree-sitter Julia): one chunk per top-level construct
      carrying its docstring + signature. Validate on `program/src/reference/Reference.jl`
      → expect a `module-doc` chunk, a `RangeReference` struct chunk, the
      `RangeReference(::Int,::Int)` constructor chunk, etc.
- [ ] **Markdown chunker**: split on headings, keep heading path as metadata.
      Validate on `guide/selection-deep-dive.md` → one chunk per `##` section with
      `heading` populated.
- [ ] `murmur index` command: full walk → populate `chunks` + `fts_chunks`.

**Verify:** index the repo; assert chunk counts per file are sane; spot-check that
`Reference.jl:50-58` is a single `struct` chunk and section boundaries in the guide
land on headings. FTS5 query for `RangeReference` returns the right chunk.

## Stage 2 — Embeddings + vector search

- [ ] On index, embed each chunk's text → write `vec_chunks`.
- [ ] `vector_search(query, k)` → embed query, cosine top-k from sqlite-vec.
- [ ] Content-hash guard so re-running index only re-embeds changed chunks.

**Verify:** `vector_search("how is a selection stored recursively in child documents", 6)`
returns the `set_selection!` section of `selection-deep-dive.md` in the top results.

## Stage 3 — MCP server: `search` / `recall` (PULL — MVP, usable here)

This is the first genuinely useful milestone: registerable in Claude Code.

- [ ] FastMCP app exposing:
      - `search(query, k=8)` → (at this stage) vector-only retrieve, returns
        `[{id, path, lines, kind, heading, snippet, score}]` with clickable `path:line`.
      - `recall(id)` → full chunk body for one id (the "fat content" pull).
- [ ] Register in Claude Code MCP config; document the one-line setup.

**Verify:** from a Claude Code session, call `search(...)` and get back pointers;
`recall(id)` returns the full `ReferenceModule` docstring. **Stop and dogfood here**
before adding complexity — confirm it beats ripgrep on a few conceptual queries.

## Stage 4 — Hybrid retrieval (BM25 ∪ vector → RRF)

- [ ] `bm25_search(query, k)` over FTS5.
- [ ] Reciprocal Rank Fusion merge of vector + BM25 candidate lists.
- [ ] `search()` now returns the fused ranking.

**Verify:** a query with exact identifiers (*"are RangeReference boundaries 0-based?"*)
surfaces the one-line `RangeReference` docstring chunk that vector-only ranked low.

## Stage 5 — Reranking

- [ ] Cross-encoder rerank of top ~50 fused candidates → top k.
- [ ] Make reranker swappable (local cross-encoder now; Voyage `rerank-2.5` later).

**Verify:** on the worked query *"how is a whole-element / no-marker selection
represented as a path?"*, the "Selection path conventions by domain" section
(which states the empty-path convention) ranks #1 even though a different section
was vector-closest.

## Stage 6 — Incremental reindex daemon (`murmurd`)

- [ ] `watchdog` watcher: on file change, re-chunk only that file, diff by
      `content_hash`, re-embed only changed chunks, update the three tables.
- [ ] Debounce; handle delete/rename; keep `path:line` accurate against the live tree.

**Verify:** edit `Reference.jl`, confirm only affected chunks re-embed within a
second or two and `search` reflects the change; stale line numbers do not appear.

## Stage 7 — Push mode (PostToolUse hook, pointer-only)

Add proactive discovery **only after** Stages 4–5 prove precision.

- [ ] A `PostToolUse` hook (fires after the assistant `Read`s a file) calls
      `search()` scoped to that file's topic and emits **one** `<system-reminder>`
      line: `Related: <path> §<heading>. Call recall if relevant.`
- [ ] Conservative score gate; anti-repeat (don't re-inject the same chunk);
      inject only at turn boundaries (cache-friendly).

**Verify:** reading `Reference.jl` surfaces a single-line pointer to the selection
convention section; measure injection precision on a handful of sessions before
loosening the gate. No mid-turn injection; no full-body dumps.

## Stage 8 — Past-discussion / transcript indexing

- [ ] Index prior Claude Code transcripts (JSONL) as timestamped, topic-split
      chunks (`kind=discussion`), so `search`/push can surface
      *"there was a related discussion on <date>: …"*.
- [ ] Recency-aware scoring; redact obvious secrets before indexing.

**Verify:** a query related to an earlier session returns the relevant discussion
chunk with its date.

---

## Later / optional (not scheduled)

- Voyage embeddings + rerank swap (decision point: local recall too weak).
- Eval harness: a fixed set of (query → expected chunk) pairs to measure
  precision/recall as the pipeline changes; gate Stage 7 loosening on it.
- Cache pre-warming / batching for push injections.
- Multi-project support (one index per repo).

## Open decision (the only one left)

**Local embedder vs Voyage.** Stage 0–6 assume local (`fastembed`), matching the
zero-token / offline goal. It's a dependency swap behind the embedder interface,
not a structural change — defer until local recall is measured (Stage 5 verify).
