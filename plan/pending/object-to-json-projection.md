# Generic `ObjectToJson` projection

A domain-agnostic, **read-only** projection that reflects *any* Julia value /
document into a `JsonDocument` tree — the JSON counterpart of the existing
generic [`ObjectToSyntax`](../../program/src/projection/primitive/ObjectToSyntax.jl).

Motivation: produce an **easy, high-prior representation of an arbitrary document
for LLM consumption**. JSON is the format LLMs understand most unambiguously
(massive training prior, self-delimiting structure, reliable round-trip when the
model emits it back), so a generic "walk the document → JSON" projection is the
natural feed for LLM document-data understanding and tool/function-calling use.

**File (new):** `program/src/projection/primitive/ObjectToJson.jl`

---

## Why generic reflection (and why this is separate from DbCatalog)

- The catalog's JSON, and any other document's JSON, falls out of this *one*
  generic projection — there is **no need for a DbCatalog-specific JSON
  projection**. (The existing
  [DbCatalogToJson.jl](../../program/src/projection/primitive/DbCatalogToJson.jl)
  is narrow, hand-written per type, and flattens each level to just `name`; it can
  be superseded by `ObjectToJson` or kept as a tailored view — not this plan's
  concern.)
- DDL is the *opposite* choice: a database-specific rendering that generic
  reflection cannot produce, so it gets its own path — see
  [plan/pending/dbcatalog-sql-document-support.md](dbcatalog-sql-document-support.md).
  Rule of thumb: **generic structural dump → `ObjectToJson`; domain-idiomatic
  rendering → a dedicated projection.**

## JSON vs the `ObjectToSyntax` tree (why JSON for LLMs)

`ObjectToSyntax` already walks any object into a readable tree, but its output is
a bespoke whitespace-delimited s-expression form the LLM has no priors for and
must reverse-engineer (where a value ends, which leaf is the type name, etc.).
JSON removes that ambiguity. Trade-off: `ObjectToSyntax` is more token-compact (no
quotes/braces/commas), so it stays the better choice when context-window-bound on
huge documents or for human/debug reading. For *LLM comprehension and round-trip*,
JSON wins. Keep both; this plan adds the JSON path.

---

## Design

Mirror `ObjectToSyntax`'s structure: a `TypeDispatchingProjection` with a
per-kind printer, assembled by an `ObjectToJson(; …)` convenience constructor.

Target types — the JSON domain ([Json.jl](../../program/src/document/Json.jl)):
`JsonNull`, `JsonBool`, `JsonNumber` (`Union{Real,Nothing}`), `JsonString`,
`JsonArray` (`CellVector` of elements), `JsonObject` (`CellVector` of
`JsonObjectEntry{key::String, value::Document}`).

Mapping rules:

- `Nothing`        → `JsonNull()`
- `Bool`           → `JsonBool(b)`  (before `Number`, since `Bool <: Number`)
- `Real`/`Number`  → `JsonNumber(n)` (non-`Real` numbers stringify into a
  `JsonString`, since `JsonNumber` only holds `Real`)
- `AbstractString` → `JsonString(string(s))`
- `Symbol` / `Char` → `JsonString(string(x))`
- `Cell`           → unwrap transparently and recurse (mirror
  [`CellToSyntax`](../../program/src/projection/primitive/ObjectToSyntax.jl#L141))
- `CellVector` / `AbstractArray` → `JsonArray` of recursively-projected elements
- struct (the `Any` fallback) → `JsonObject` whose entries are one
  `JsonObjectEntry(string(fieldname), <projected field value>)` per field

Struct → object details (carry over `ObjectToSyntax`'s hard-won behaviour):

- **Filter noise fields**: skip `:ref`, and `:selection` unless
  `include_selection=true` (matches
  [ObjectToSyntax.jl:270](../../program/src/projection/primitive/ObjectToSyntax.jl#L270)).
- **Encode the type name** so the LLM keeps the domain type it needs to reason
  about. Recommended: add a reserved entry, e.g.
  `JsonObjectEntry("type", JsonString(string(nameof(T))))` as the first entry
  (configurable key, on by default). This is the JSON equivalent of
  `ObjectToSyntax`'s type-name leaf.
- **Cycle detection** for mutable ancestors via a `:objects_seen` `IdDict` in the
  printer context, exactly like
  [ObjectToSyntax.jl:238](../../program/src/projection/primitive/ObjectToSyntax.jl#L238)
  (immutables value-equal many times legitimately; only track mutables). Render a
  cycle as e.g. `JsonString("⟨cycle: T⟩")`.
- **Undefined fields** → `JsonString("<undefined>")` (or `JsonNull`), as
  `ObjectToSyntax` handles undef mutable-struct fields.
- Optional `filter` predicate (`value -> Bool`) to drop fields/elements, like
  `ObjectToSyntax`'s `filter` kwarg.

**Read-only**: `map_reference_forward` / `map_reference_backward` /
`projection_read` all return `nothing`, exactly like
[DbCatalogToJson.jl](../../program/src/projection/primitive/DbCatalogToJson.jl).
This is a serialiser, not an editor view. (A reader could be added later if
"edit the JSON → mutate the document" is ever wanted, but it is explicitly not a
goal — the round-trip we care about is the LLM re-emitting JSON, not editing the
projection.)

---

## Convenience entry point

Mirror `print_object`: a helper that chains the projection to a string for
direct LLM-prompt use, e.g.

```julia
json_object(obj; include_selection=false, type_key="type", filter=nothing) -> String
```

assembled as
`SequentialProjection(RecursiveProjection(ObjectToJson(...)), RecursiveProjection(JsonToSyntax()), RecursiveProjection(SyntaxToText()), RecursiveProjection(TextToString()))`
— i.e. reuse the JSON rendering pipeline rather than serialising JSON text by
hand. (See `print_object` at
[ObjectToSyntax.jl:353](../../program/src/projection/primitive/ObjectToSyntax.jl#L353)
for the pattern.)

Register the new module in `program/src/Projectured.jl`.

---

## Open questions

- **Type-name encoding.** Reserved `"type"` entry (recommended, simple, explicit)
  vs a wrapper object `{ "type": …, "value"/"fields": … }`. The flat reserved-key
  form is less nested and usually easier for an LLM; pick one and make it
  configurable.
- **Map-like structs vs collections.** `JsonObject` keys are `String`; struct
  field names map cleanly. If we ever want real `Dict`/`Pair` support, decide how
  non-string keys serialise.
- **Scope of "document".** Default to the same walk `ObjectToSyntax` uses
  (fields + array/CellVector elements, Cells unwrapped). Confirm whether any
  domain wrapper types should be elided (the way `ObjectToSyntax` drops the
  `CellVector`/array wrapper's pseudo-type) — likely yes for arrays.

---

## Testing

Smallest-scope first (never `test_all`):

- A few unit examples: `json_object(42)`, `json_object([1,2,3])`,
  `json_object(SomeStruct(...))`, plus a cyclic structure to exercise cycle
  detection.
- Run the assembled pipeline on a real in-repo document (e.g. a JSON or DbCatalog
  example) and assert valid, expected JSON text.
- `test_printer(...)` on a dedicated example if one is added.

See [guide/testing.md](../../guide/testing.md) and
[CLAUDE.md](../../CLAUDE.md) "Testing a change".

---

## Out of scope

- Bidirectional editing of the JSON projection (read-only by design).
- DDL / SQL representation of the database — see
  [plan/pending/dbcatalog-sql-document-support.md](dbcatalog-sql-document-support.md).
- Replacing/retiring the existing `DbCatalogToJson` (separate decision).
