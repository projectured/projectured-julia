# Purge the bespoke `DbCatalogToJson` projection

Remove the domain-specific `DbCatalog → JsonDocument` projection
(`DbCatalogToJson` and its five per-level sub-projections) and the example /
test wiring that depends on it. **Plan only — do not implement yet.**

## Context / motivation

This came out of a discussion about the *best representation of a database
catalog* for two different consumers:

1. **Feeding an LLM with database structure.** The community/best-practice
   answer is **SQL DDL (`CREATE TABLE …`) + a few sample rows + comments**, not
   JSON: LLMs are saturated with DDL from pretraining, DDL is far more
   token-efficient, and foreign keys / constraints sit inline where the model
   needs them (this is the consensus from text-to-SQL benchmarks; see also the
   "M-Schema" format from XiYan-SQL). JSON catalog dumps are ~2–4× the tokens
   for the same information and are an idiosyncratic shape the model has seen
   little of. For the LLM use case the **DbCatalog → SQL DDL** projection
   (already planned/started — see commit `4315cd0` and
   `plan/pending/dbcatalog-sql-document-support.md`) is the one to invest in.

2. **In-project use (machine interchange, bidirectional projectional editing).**
   JSON is genuinely useful *as a domain* here — but that value is delivered by
   the **generic** `ObjectToJson` projection
   (`program/src/projection/primitive/ObjectToJson.jl`), which reflects any
   `@document` tree into JSON and is reusable across all domains. The
   **bespoke** `DbCatalogToJson` is a hand-written duplicate of what
   `ObjectToJson` already produces generically, differing only cosmetically
   (no `"type"` key, hand-picked field set).

### Why purge the bespoke one specifically

- **It is read-only.** `DbCatalogToJson` defines `projection_read`,
  `map_reference_forward`, and `map_reference_backward` all returning `nothing`
  (`DbCatalogToJson.jl:64-66`, etc.). So it does **not** deliver the one thing
  that would justify a JSON projection in a *projectional editor* —
  bidirectional editing. It is a one-way dump.
- **It is redundant with `ObjectToJson`.** The generic reflective path produces
  the same nested `databases → schemas → tables → columns` JSON tree and is
  already wired up as `dvdrental_object_json_example`. The only delta is the
  absence of `"type"`/noise keys, which `ObjectToJson`'s `filter` / `type_key`
  options can already approximate if a cleaner dump is ever wanted.
- **Maintenance cost.** It is ~145 lines that must track every change to the
  `DbCatalog*` struct fields (it already had to be renamed Connection→Rdbms in
  the `database-instance-catalog-sql` refactor) for no capability the generic
  path or the DDL path doesn't cover better.

### What this plan deliberately does NOT do

- Does **not** remove the generic `ObjectToJson` projection — that stays and is
  the supported JSON view of any domain, including the catalog
  (`dvdrental_object_json_example`).
- Does **not** touch the `DbCatalog → Syntax` / widget / text pipelines.
- Does **not** implement the DDL projection — that is its own plan
  (`plan/pending/dbcatalog-sql-document-support.md`). This plan only notes that
  DDL supersedes JSON for the LLM use case.

---

## Removal steps

### 1. Delete the projection module

- Delete `program/src/projection/primitive/DbCatalogToJson.jl`.

### 2. `program/src/Projectured.jl`

- Remove the include at line ~183:
  `include("projection/primitive/DbCatalogToJson.jl")`.
- Remove the `using .DbCatalogToJsonModule: …` import block (lines ~278-280).
- Remove `DbCatalogToJson` (and the five `DbCatalog*ToJson` symbols) from the
  export list (line ~592 and the block it sits in).
- Leave the `ObjectToJson.jl` include / imports / exports (lines ~139, ~362,
  ~729) untouched.

### 3. Example wiring — `example/src/projection/DbCatalog.jl`

- Delete `make_dvdrental_catalog_json_projection_example` (the
  `DbCatalogToJson → JsonToSyntax → …` pipeline, lines ~75-96) and its banner
  comment.
- Keep `make_dvdrental_object_json_projection_example` (the generic
  `ObjectToJson` JSON view) — that is the replacement.

### 4. Example registry — `example/src/Examples.jl`

- Delete the `dvdrental_catalog_json_example` const and its comment block
  (lines ~120-126).
- Keep `dvdrental_object_json_example` (the generic JSON view).
- Grep for `dvdrental_catalog_json_example` elsewhere (registry lists, docs) and
  remove any remaining references.

### 5. Tests

- Delete `test/src/external/DbCatalogJsonTest.jl`.
- Remove its include from `test/src/ProjecturedTest.jl` (line ~86:
  `include("external/DbCatalogJsonTest.jl")`).
- Remove the corresponding `test_db_catalog_json()` call from any aggregate
  (e.g. wherever `test_all` / external suite wiring invokes it — grep
  `test_db_catalog_json`).

### 6. Docs / guides

- `guide/architecture.md` references `DbCatalogToJson` — update the module
  inventory to drop it (and, if useful, note that the catalog's JSON view is the
  generic `ObjectToJson`).
- Check `plan/pending/object-to-json-projection.md`,
  `plan/pending/dbcatalog-sql-document-support.md`,
  `plan/pending/syntax-to-widget.md`, `plan/pending/component-document.md` for
  mentions; these are planning docs, so update only if a mention is now
  misleading (no code impact).

---

## Verify (after implementation)

- Package loads / precompiles (`Projectured` builds with the include + exports
  removed).
- The remaining JSON view still works: `run_example(dvdrental_object_json_example)`
  renders the catalog as JSON via `ObjectToJson`.
- The non-JSON catalog pipelines are unaffected:
  `test_db_catalog()`, `test_db_catalog_syntax()` still pass.
- No dangling references: grep for `DbCatalogToJson`, `dvdrental_catalog_json`,
  `DbCatalogJsonTest`, `test_db_catalog_json` returns nothing in `program/`,
  `example/`, `test/`.

## Out of scope

- Implementing or extending the `DbCatalog → SQL DDL` projection (sample rows,
  column comments) — tracked separately.
- Any change to `ObjectToJson` behaviour or its options.
- Removing the JSON *domain* or any other JSON projection.
