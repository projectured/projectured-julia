# Data-driven projections via a builder-and-walk engine

> **Status (2026-08-12): IN PROGRESS.** The engine
> (`package/kernel/main/projection/ProjectionTemplate.jl`) is done and backs
> almost every printer. Stage A (JSON) is done. Stage C has progressed well
> past the 2026-06-23 audit below: XML and Julia are now **fully** converted
> (`package/xml/main/XmlToSyntax.jl` — 8 `@projection_template` uses, 0
> `ChildrenIoMap`; `package/julia/main/JuliaToSyntax.jl` — 59 uses, 0
> `ChildrenIoMap`), Math is partial (`package/math/main/MathToSyntax.jl` — 18
> uses, but still 13 `ChildrenIoMap` / 4 hand-written `map_reference_forward`),
> and Formula/Collection are still fully open
> (`package/formula/main/FormulaToSyntax.jl`,
> `package/syntax/main/CollectionToSyntax.jl` — 0 uses each). Stage B (SQL) is
> unchanged from the 2026-06-23 audit: leaves done (now 8, not 7), nodes still
> hand-written (101 `ChildrenIoMap` uses in
> `package/sql/main/SqlToSyntax.jl`).

> **Decision (2026-08-12): this plan runs before the parameter rename.** The
> owner chose to convert first.
> [unify-projection-api-parameter-names.md](unify-projection-api-parameter-names.md)
> waits on Stage B and Stage C, because about 108 of its rename sites sit in the
> functions that this plan deletes and regenerates. Do not rename a parameter in
> a file that this plan still converts.

## Motivation

`JsonToSyntax.jl` and `SqlToSyntax.jl` (and every other `XToSyntax`) are dominated
by mechanical boilerplate. Each projection hand-writes four things that are all
consequences of one fact — the input↔output correspondence — yet are kept in sync
by hand and routinely drift:

- `projection_print` — builds the output tree, wires the deferred-iomap selection
  cell, assembles the `IoMap`.
- `map_reference_forward` / `map_reference_backward` — input-domain reference ↔
  output-domain reference.
- `projection_read` — retargets operations through the backward mapper.

The goal: write **one** thing per projection and derive the rest.

## Approach (implemented): builder + markers + reflection walk

A rule is an **ordinary builder function** `(p, doc) -> output` that constructs the
*real* output document with its *real* constructor — except that at the positions
needing special handling it drops in a **marker** value:

- `bound(:field, T, render; retype=Op)` — a value bound to `doc.field::T`; `render`
  is the real renderable value placed in the slot.
- `project(:field)` — delegate this child to its own projection (School A).
- `collection(:field[, element])` — a recursive children vector; the optional
  `element` is a per-element builder (`collection(:f) do x … end`).

Because `@document` types store every field in a `Cell` with **no type check**, a
marker can sit in a real field (e.g. a `Bound` in a leaf's value slot). The engine
**walks the built value by reflection** (`fieldnames`), records the *wiring*,
**strips the markers in place** (replacing each with its real value, wiring the
selection cell), and returns the clean output document plus a `RuleIoMap`. Reference
mapping is then **generic and data-driven** from the recorded wiring — one method
set dispatched on `RuleIoMap`, no per-type codegen.

Why this shape won out over a declarative slot-DSL (the abandoned first approach):

- **Real code, real constructors** — no bespoke template syntax, no keyword
  constructors to invent, no output-type schema for the macro to know.
- **Output reference paths fall out of the walk** — `fieldnames` give field names,
  vector positions give `[i]`; nobody hand-writes `.children[i].children[1]`.
- **Conditionals dissolve** — SQL's data-dependent child indices (the
  `body_idx = distinct ? 3 : 2` problem) need no special machinery: the builder is
  ordinary Julia, so `if`/comprehensions produce the actual children vector and the
  walk reads the actual positions.
- **No domain coupling in the engine** — fields are classified by *value*
  (marker vs not); the engine names no output type or field. Introduced/structural
  positions proj-wrap (the domain-neutral counterpart of the Syntax→Text
  flat-offset fallback, verified behavior-equivalent on the navigation gate).

## Architecture decisions (recorded)

- **Mutable documents.** `@document` now emits a `mutable struct` for the
  Cell-based variant (the I-prefixed snapshot stays immutable). Fields were always
  `Cell`s (so contents were mutable via `setproperty!`); mutability additionally
  lets the walk swap a field's Cell object (`setfield!`) — needed to share the
  document's selection cell into the output and to strip markers in place rather
  than reconstructing. Verified safe suite-wide (documents are handled by identity,
  so value→identity equality on the mutable variant is a non-issue).
- **`RuleIoMap`** carries `(projection, input, output, wiring, child_iomaps)`.
  `AtomicWiring` (no recursive children) records the optional bound field; any
  other output field is introduced. `NodeWiring` records the input collection
  field and the output children field; per-child correspondence lives in the
  stored `child_iomaps` (School A).
- **Authoring readers stay hand-written** — `_json_read_command` (type-to-replace),
  `,`/Tab inserts, etc. fabricate *new* documents from keystrokes; they are not a
  structural correspondence and are not derivable from the builder. They dispatch
  on `RuleIoMap`.
- **Escaping deferred** — the value lens is identity at character-offset
  granularity (`json_escape` round-trip is not yet inverted).

## Status

> **Audit (2026-06-23, re-verified 2026-08-12 against the current `package/` layout):**
> the three "Done" items below are confirmed landed in the current tree, though
> the exact file paths in the original audit have moved again.
> - `@document` emits a **mutable** struct for the Cell-based (`M`-prefixed)
>   variant: the macro now lives at
>   `package/kernel/main/document/DocumentMacro.jl` (not `package/kernel/src/common/Document.jl`,
>   which no longer exists) and has grown into a richer kind system
>   (immutable / mutable `M` / boxed `MC`, see that file's own docs) than the
>   single mutable-vs-immutable decision this plan recorded — re-verify the
>   mutability rationale against the current file if this plan is picked back up.
> - The builder/marker/walk engine lives at
>   `package/kernel/main/projection/ProjectionTemplate.jl` (this path was already
>   correct) and is included via `package/domain/main/ProjecturedDomain.jl` (not
>   `package/domain/src/...`). It implements `Bound`/`Project`/
>   `Collection`/`Tokens`/`Sections` markers, the reflection walk
>   (`rule_print`, `_atomic_print`, `_node_print`, `_fixed_print`, `_mixed_print`,
>   `_inline_print`, `_sections_print`), `AtomicWiring`/`NodeWiring`/
>   `FixedNodeWiring`/`MixedNodeWiring`/`InlineWiring`/`SectionsWiring`/`RuleIoMap`,
>   the generic `map_reference_forward`/`backward`, and the readers — Syntax-type-free.
> - All seven JSON value types are builders in
>   `package/json/main/JsonToSyntax.jl` (this path was already correct). Hand-written
>   kept: authoring readers + the structural flat-offset fallback.

### Done (branch `projection-rule-macro`, rebased onto `main` @ `cf0482c`)

The branch was reconstructed on top of `main` after `main` landed the
*layered-packaging* split (`program/` → `kernel/` + `domain/`) and the
*merge-style-text* change (projections now carry `StyleText` style fields instead
of loose `(font, color)` pairs). The original four commits collapse to three
clean ones on the new layout:

- `@document`: Cell-based struct variant is mutable — at the time, in
  `kernel/src/common/Document.jl`; as of 2026-08-12 that logic lives in
  `package/kernel/main/document/DocumentMacro.jl`, see the Status section above.
  — commit `3b95c3f`
- `ProjectionTemplate.jl`: the builder/marker/walk engine — markers, the reflection
  walk with in-place marker stripping, `AtomicWiring`/`NodeWiring`/`FixedNodeWiring`/
  `RuleIoMap`, the generic data-driven `map_reference_forward`/`backward`, and the
  readers (value-edit retype + the proj-wrap structural fallback). Output-domain-
  independent (no Syntax type or field name). At the time, in `domain/src/projection/`;
  as of 2026-08-12 it is `package/kernel/main/projection/ProjectionTemplate.jl`. All
  its imports are kernel modules reachable through the `ProjecturedDomain` const
  aliases, so **no import changes** were needed for the relocation. — commit `5a5ddc1`
- `JsonToSyntax.jl` (at the time `domain/src/projection/primitive/`, as of
  2026-08-12 `package/json/main/JsonToSyntax.jl`): **all seven** JSON
  value types as builders — `JsonNull`/`JsonInsertion` opaque leaves; `JsonBool`/
  `JsonNumber`/`JsonString` `bound(:value, …)` leaves; `JsonArray` a
  `collection(:elements)` node; `JsonObject` a `collection(:entries) do e … end`
  templated node whose per-entry pair is `[key_leaf (bound :key), project(:value)]`,
  walked into a `FixedNodeWiring` (`KeySlot`/`ProjectSlot`/`IntroSlot`). Builders
  **ported to the StyleText API** (`StyleText` struct fields, the
  `TextString(str/thunk, style)` bridge, `_hinted_text(…, style::StyleText)`).
  Hand-written kept: JSON authoring readers (type-to-replace, `,` insert, Tab) and
  the Syntax-specific flat-offset structural fallback, both dispatching on
  `RuleIoMap`. Two navigation behaviours preserved from the original Stage A —
  **structural fallback** (brackets/braces/commas/colons → flat char offset via
  `_syntax_to_flat`, keeping them navigable in the text layer) and **clean input
  paths** (the collection mapper strips `TypeReference` checkpoints from a delegated
  child tail, so the JSON boundary emits the checkpoint-free paths the canonical
  walk / clicks expect). — commit `f152d90`

- **Gates (on the rebased branch, full kernel→domain→example→test build):**
  `test_json_to_syntax` 11/11; **`test_text_navigation(json_example;
  check_reaches_all=true)` 543/543** — full reach, up from the hand-written
  object's 384/159; `test_json` 29/29, `test_syntax` 10/10, `test_text` 19/19,
  `test_syntax_to_text` 124/124, `test_copying_projection` 31/31 all green.
  `test_json_to_syntax_reader` is **44/1/3** — but this is **pre-existing on
  `main`**: the clean `main` checkout (`cf0482c`) produces the identical 44/1/3 at
  the identical lines (`JsonToSyntaxTest.jl` 85/115/117/126). `cf0482c` removed
  `length(::JsonArray)`/`length(::JsonObject)` but did not update that test, which
  still calls `length(ed.document)`/`length(arr)`/`length(obj)`. Not introduced by
  this work; flagged for a separate one-line test fix.

## Remaining

### Stage B — SQL domain (`SqlToSyntax.jl`) ⏳ PARTIAL (leaves done; nodes open)

**Audit:** in `package/sql/main/SqlToSyntax.jl` only the
seven leaves use `@projection_template` (lines 92, 104, 118, 128, 138, 236, 890).
Every node projection (Comparison, BooleanBinary, Not, the clauses, the
statements, Insert/Update/DDL) is **still hand-written** with `ChildrenIoMap` and
hand-coded `map_reference_forward`/`backward` (e.g. `SqlComparisonToSyntaxNode`
line 913, `SqlInsertStatementToSyntaxNode` line 1273, `SqlSelectClauseToSyntaxNode`
line 320 with the `body_idx = distinct ? 3 : 2` arithmetic at line 362 the plan
aimed to delete). So the fixed/conditional-node sub-steps below are OPEN.

Convert the 27 SQL projections to builders. The builder/walk model fits SQL's
shapes directly, and crucially its *conditional* structure needs no new machinery:

- **Leaves** (`SqlAllColumns`, `SqlColumnReference`, `SqlTableName`,
  `SqlTableExpression`, `SqlJoinType`, `SqlScalarValue`, `SqlColumnName`) — **DONE**.
  All seven are opaque display leaves (no marker): `SyntaxLeaf(TextString(() ->
  display(doc), p.style))` (keyword-constructor form, open/close default empty). The
  engine's opaque path derives the ∅↔∅ selection mapping; a shared
  `projection_read = nothing` preserves the original "non-editable" contract (a
  computed multi-field display has no editable interior). ~−100 lines, no engine
  change. Re-ported onto `main`'s keyword `SyntaxLeaf` constructor and the
  separate-optional-packages layout (the second rebase of this branch).
  - **Gate (no regression vs. the pre-existing SQL baseline on `main`@2d16b33):**
    `test_sql_to_syntax` 18/1 (the 1 error is line 15, a pre-existing
    `iterate(::TextBlock)` orphan in the *test*); `test_sql_insert_update_selection`
    13/1 (line 113, a pre-existing `::SqlSelectItem` checkpoint in the WHERE node);
    `test_sql_ddl` 3/3, `test_sql_ddl_selection` 7/7 green. NB
    `test_sql_to_syntax_selection` throws `UndefVarError: test_selection` — that
    helper is genuinely undefined on `main`; the test is dead until it's supplied.
- **⏳ OPEN (verified):** **Fixed nodes** (`Comparison`, `BooleanBinary`, `Not`, clauses, …) — interleaved
  keyword leaves are just plain `TextString` children (introduced); bound children
  use `project(:field)`; layout wrappers (`_comma_body`, paren lists) are ordinary
  nested `SyntaxNode`s in the builder.
- **⏳ OPEN (verified):** **Conditional/statement nodes** (`SelectClause` DISTINCT, `InsertStatement`
  columns-paren, `Update`/`SelectStatement` optional WHERE) — the builder uses
  ordinary `if`/`push!`/comprehensions to assemble the children; the walk reads the
  actual positions, so the dynamic-index arithmetic that dominated the hand-written
  mappers disappears.
- Authoring readers (`,` insert, Tab key→value, type-to-replace) stay hand-written.
- **Gate:** `test_sql_to_syntax`, `test_sql_to_syntax_selection`.

### Stage C — sweep other `XToSyntax` projections ⏳ IN PROGRESS (re-verified 2026-08-12)

**2026-06-23 audit (superseded):** none of `XmlToSyntax.jl`, `MathToSyntax.jl`,
`JuliaToSyntax.jl`, `FormulaToSyntax.jl`, `CollectionToSyntax.jl` referenced
`@projection_template`. That is no longer true for three of the five.

**2026-08-12 re-audit** (each domain now has its own `main/` package; `CollectionToSyntax.jl`
moved to `package/syntax/main/`):

| file | `@projection_template` uses | `ChildrenIoMap` uses | verdict |
|---|---:|---:|---|
| `package/xml/main/XmlToSyntax.jl` | 8 | 0 | **DONE** |
| `package/julia/main/JuliaToSyntax.jl` | 59 | 0 | **DONE** |
| `package/math/main/MathToSyntax.jl` | 18 | 13 | PARTIAL — nodes still mixed |
| `package/formula/main/FormulaToSyntax.jl` | 0 | — | OPEN |
| `package/syntax/main/CollectionToSyntax.jl` | 0 | — | OPEN |

`FormulaToSyntax`, `CollectionToSyntax` — same playbook once Math's remaining
nodes and Stage B's SQL nodes prove out the conditional cases further.

## Out of scope

- Authoring readers (keystroke→new-document), kept hand-written.
- Escape-aware character mapping for strings.
- Output domains other than Syntax — the engine is already neutral, so they need
  only builders, but none are targeted here.

## Done criteria

> **NOT MET (re-verified 2026-08-12):** the engine, JSON, XML, and Julia are
> done; Math is partial; SQL nodes, Formula, and Collection remain hand-written
> (see the Stage B/C audits above). Plan stays in `pending`.

- Every structural `*ToSyntax*` projection expressed as a builder; only authoring
  readers + display/utility functions remain hand-written.
- All domain gates green, unchanged from baseline.
- Large net line reduction (JSON already ~−230 lines; SQL is ~2260 lines, mostly
  mechanical).
