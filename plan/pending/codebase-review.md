# Codebase review — inconsistencies and improvement opportunities

Snapshot of issues found during a sweep of the Julia tree, the guides, and the
test suite as of 2026-05-28. Items are grouped by theme; each item is meant to
be actionable on its own. Some duplicate items already covered by existing
pending plans — those are cross-referenced rather than restated.

---

## 1. Dead modules and dead types

These are exported and re-exported but have no user, no projection, no test,
and no example. They look like Lisp-port leftovers that were never wired up.

### 1.1 Orphan `DocumentCoreModule` ([program/src/document/Document.jl](../../program/src/document/Document.jl))

The whole module is never `include`d from
[program/src/Projectured.jl](../../program/src/Projectured.jl) — only
[api/Document.jl](../../program/src/api/Document.jl) and
[common/Document.jl](../../program/src/common/Document.jl) are. It defines
`DocumentBase`, `DocumentNothing`, `DocumentInsertion`, `DocumentReference`,
`LoadDocumentOperation`, `SaveDocumentOperation`, `ExportDocumentOperation`,
and references undefined functions `call_loader`, `call_saver`,
`print_document`. None of these symbols are reachable from `using Projectured`.

**Action:** Delete `program/src/document/Document.jl` entirely.

### 1.2 Unused `Syntax` wrapper types ([program/src/document/Syntax.jl:60-213](../../program/src/document/Syntax.jl#L60-L213))

`SyntaxDelimitation`, `SyntaxIndentation`, `SyntaxCollapsible`,
`SyntaxNavigation`, `SyntaxConcatenation`, `SyntaxSeparation` are defined,
documented, exported, and re-exported through `Projectured.jl` — but no
projection, printer, reader, IO map, example, test, or other domain mentions
them. Grep returns matches only inside `Syntax.jl` itself plus mentions in
[architecture.md](../../guide/architecture.md) and the
[syntax-tree-selection](syntax-tree-selection.md) plan.

`SyntaxCollapsible` is particularly redundant: `SyntaxLeaf` and `SyntaxNode`
already carry a `collapsed::Bool` field.

**Action:** Same shape as [remove-foreign-types.md](remove-foreign-types.md) —
delete the six structs and the `I*` immutables, scrub the export list and the
re-export in `Projectured.jl`, scrub the docstring at the top of `Syntax.jl`,
and update [architecture.md](../../guide/architecture.md#layer-1--domain-modules-document)
and [syntax-tree-selection.md](syntax-tree-selection.md) to stop listing them.

### 1.3 Unused `Clipboard` types ([program/src/document/Clipboard.jl](../../program/src/document/Clipboard.jl))

`ClipboardSlice`, `ClipboardCollection`, `ClipboardInsertion`,
`ClipboardForeign` are exported but no projection, operation, test, or
example mentions them. The clipboard appears in
[roadmap.md](../../guide/roadmap.md#5-clipboard) under "what's next" with
references to `ClipboardCopyOperation` / `ClipboardPasteOperation` that don't
exist either.

**Action:** Decide between (a) deleting the file and removing the
roadmap/CONTRIBUTING mentions, or (b) keeping it but converting the docstrings
to clearly say "stub for future work". Option (a) is cheaper and consistent
with the foreign-types cleanup.

### 1.4 Enormous unused `Color` palette ([program/src/document/Color.jl](../../program/src/document/Color.jl))

The file is 1206 lines defining ~1040 named colours. A grep across
`program/src`, `example/src`, and `test/src` excluding `Color.jl` itself
shows **1028 of those constants are never referenced anywhere else** — they
also aren't exported through `Projectured.jl`, so external code can't reach
them either. The actually-used set is the solarized scheme, a handful of
pastels, the basics (`color_black`, `color_white`, `color_red`,
`color_blue`), and `color_default`.

**Action:** Trim Color.jl to the ~30 constants actually referenced.
Cross-check what `Projectured.jl` actually re-exports
([Projectured.jl:225,425](../../program/src/Projectured.jl#L225)) so the public
API stays consistent. Keep the `_color(r,g,b)` constructor in case more are
re-added later.

---

## 2. Code duplication

### 2.1 `@document` / `@projection` / `@iomap` macros are nearly identical

Bodies in [common/Document.jl:39-117](../../program/src/common/Document.jl#L39-L117),
[common/Projection.jl:83-149](../../program/src/common/Projection.jl#L83-L149),
and [common/IoMap.jl:65-136](../../program/src/common/IoMap.jl#L65-L136) all
share the same logic: collect declared fields, rewrite them to `::Cell`, emit
an auto-wrapping inner constructor, emit transparent `getproperty` /
`setproperty!`. The only meaningful diff is:

- `@document` additionally emits an `I` immutable struct and the
  snapshot/hydrate constructors,
- `@iomap` additionally injects `<: IoMap` if the user didn't write one.

The triplicated code drifts (e.g. small differences in how each handles the
`<: Super` case). The macro guide
[macros.md](../../guide/macros.md) already states they share a "core pattern".

**Action:** Factor the common rewrite into a single helper function (in
`common/Document.jl` or a new `common/CellStruct.jl`) and have all three
macros call it, layering on their extras. Keep the public macro names intact.

### 2.2 `entries_iomap`, `projection_read` boilerplate per type

`projection_read` for `JsonArrayToSyntaxNode` and `JsonObjectToSyntaxNode`
([JsonToSyntax.jl:244-250](../../program/src/projection/primitive/JsonToSyntax.jl#L244-L250) and
[JsonToSyntax.jl:338-344](../../program/src/projection/primitive/JsonToSyntax.jl#L338-L344))
share an identical 4-line body: try the domain-specific translation, fall back
to `_syntax_to_flat` and wrap in a `ProjectionReference`. The same pattern
will appear in `CollectionCellVectorToSyntax.projection_read` once
[fix-selection-tests.md](fix-selection-tests.md) lands.

**Action:** Extract a tiny helper (e.g. `_node_read(p, iomap, op, translate)`)
in a shared spot inside `JsonToSyntaxModule` or a new
`projection/primitive/_NodeUtil.jl`. Saves a copy each time a new compound
projection is added.

### 2.3 Foreign-type cleanup already planned

See [remove-foreign-types.md](remove-foreign-types.md). The plan in §1.2 above
is the same shape of work and could share a checklist with it.

---

## 3. Doc / code drift

### 3.1 `AlternativeProjection` description disagrees with code

[architecture.md:93](../../guide/architecture.md#L93) says:

> AlternativeProjection — Tries each sub-projection; uses the first that succeeds

The actual code in
[Alternative.jl:23-64](../../program/src/projection/higherorder/Alternative.jl#L23-L64)
is "index-based — read `index::Cell{Int}` and dispatch to that branch." There
is no "try each in turn" behaviour at all.

**Action:** Rewrite that row in `architecture.md` to match the code, e.g.
"Selects one sub-projection by reactive `index::Cell{Int}`".

### 3.2 `Reference.jl` exports `RangeReference` but architecture lists also-removed names

[architecture.md:67](../../guide/architecture.md#L67) lists
`ElementReference`, `PositionReference`, `FieldReference`, `ProjectionReference`,
`RangeReference`, `TypeReference`, `FunctionReference` as **step types**. The
code preserves `ElementReference` and `PositionReference` only as
constructor *aliases* for `RangeReference`
([Reference.jl:62-77](../../program/src/reference/Reference.jl#L62-L77)) — they
are not types you can dispatch on. The doc reads as if they were.

**Action:** Reword the row to make clear that `RangeReference` is the only
step type and the other two are constructor sugar.

### 3.3 `Syntax.jl` selection docstring documents removed `.value` semantics

The docstring at the top of [Syntax.jl:14-19](../../program/src/document/Syntax.jl#L14-L19)
describes leaf cursors as `.open[k]`, `.value[k]`, `.close[k]` — fine. But
[concepts.md:114](../../guide/concepts.md#L114) and
[concepts.md:144-150](../../guide/concepts.md#L144) describe `{k}` as
"0-based" and `[i]` as "1-based" without mentioning that internally they're
both `RangeReference` with `start` 0-based.

The internal API for `set_selection!` and `clear_selection!`
([Operation.jl:69-77](../../program/src/common/Operation.jl#L69-L77))
explicitly converts `start + 1` to 1-based — this knowledge is implicit in
several call sites
([JsonToSyntax.jl:222-225](../../program/src/projection/primitive/JsonToSyntax.jl#L222),
[JsonToSyntax.jl:425-432](../../program/src/projection/primitive/JsonToSyntax.jl#L425),
etc.). The reference guide [editor/reference.md](../../guide/editor/reference.md)
should call out this convention prominently.

**Action:** Add a short "0-based positions vs. 1-based indices" callout to
[reference.md](../../guide/editor/reference.md) (or to
[concepts.md §4](../../guide/concepts.md#4-selection)) describing the
`RangeReference(start, stop)` invariants and explicitly noting that all
indexing code does `start + 1` to convert.

### 3.4 `roadmap.md` references nonexistent `ClipboardCopyOperation`

[roadmap.md:48-50](../../guide/roadmap.md#L48-L50) says "Wire `Ctrl+C/X/V` to
`ClipboardCopyOperation` / `ClipboardPasteOperation`." Neither type exists
in the codebase (see §1.3).

**Action:** Either define the operations as stubs or rewrite the bullet to
not name specific symbols.

---

## 4. Latent error-swallowing and missing methods

### 4.1 Silent `try`/`catch` blocks in `Reference.jl`

[Reference.jl:344-352](../../program/src/reference/Reference.jl#L344-L352) wraps
`is_valid_reference(::ConcreteReferencePath)` in `try ... catch return false`,
which hides genuine bugs (e.g. type errors in step types). Same pattern in
`collect_references` / `_search_document`
([Reference.jl:404-468](../../program/src/reference/Reference.jl#L404-L468))
has three nested empty `catch`es.

**Action:** Remove the bare `catch` blocks. If `is_valid_reference` is used
defensively against arbitrary user input, narrow the catch to the specific
exception types and rethrow others. Same for `collect_references`.

### 4.2 `evaluate_reference` does not handle all step types

[Reference.jl:368-387](../../program/src/reference/Reference.jl#L368-L387)
errors on anything other than `RangeReference`, `FieldReference`,
`FunctionReference`. There are no cases for `ProjectionReference`,
`TypeReference`, or `PointReference`. Selection code routinely produces
`ProjectionReference` paths (the JSON string quote delimiter test is the
canonical case), so `evaluate_reference` cannot be called on a real selection
from a domain that uses projection-introduced delimiters.

**Action:** Decide whether `evaluate_reference` should (a) `return nothing`
on unsupported steps (signalling "no document position") or (b) gain a
`ProjectionReference` branch that calls back into `map_reference_forward`. (a)
is the simpler fix and matches the `nothing` convention used elsewhere in the
reference API.

### 4.3 `CollectionCellVectorToSyntax` missing `projection_read`

Already documented and fixed by
[fix-selection-tests.md](fix-selection-tests.md). Cross-reference here.

### 4.4 `TableToGraphics` missing `projection_read`

Same source as the above. Both should be landed in one go.

### 4.5 `_longest_prefix_of_type` swallows errors

[Focusing.jl:117-126](../../program/src/projection/generic/Focusing.jl#L117-L126)
has `node = try evaluate_reference(document, path) catch; break end`. If
`evaluate_reference` legitimately fails partway, the loop bails and reports
the previous best — silent and untraceable.

**Action:** Use the fix from §4.2 — when `evaluate_reference` returns
`nothing` to signal a missing step, the loop here breaks naturally without
a `try`.

---

## 5. API surface

### 5.1 `Projectured.jl` is 528 lines, mostly export plumbing

The root module repeats every export across an unstructured `using` block
(lines 127-324) and a parallel `export` block (lines 326-527). A typo or
omission in either silently drops a symbol from the public API.

**Action:** No structural change suggested — but two cheap wins exist:

1. Generate the export list programmatically from `names(M)` per sub-module
   for the modules whose exports are intentionally identical to their
   sub-module exports. Most projection modules are in this category.
2. Add a CI script that warns when a symbol is `using`'d but not `export`'d
   (or vice versa) at the top level.

### 5.2 Tests rely on un-exported colour symbols

[ProjecturedTest.jl:6](../../test/src/ProjecturedTest.jl#L6) imports
`color_red`, `color_blue`, `color_white` from `Projectured` by name, but
they're not in the `export` list of `Projectured.jl`. The import works
because `using Projectured: color_red` can pull non-exported symbols, but
this is a maintenance hazard — a future rename or delete in `Color.jl`
breaks the tests with a misleading error.

**Action:** Either add the basic palette to the `Projectured.jl` export list,
or have the test import directly from `Projectured.ColorModule`.

### 5.3 Selection tests have known coverage gaps

[ProjecturedTest.jl:71-72](../../test/src/ProjecturedTest.jl#L71-L72) keeps
`test_mouse_clicks` commented out with a `TODO`. The
[fix-selection-tests.md](fix-selection-tests.md) plan also documents
selection failures on collection, table, math_table, reversing, filtering,
sorting, widget_tabbed_pane.

**Action:** Land the existing pending fix plan, then re-enable mouse-click
tests as a follow-up.

---

## 6. Minor consistency / hygiene

### 6.1 `take_first_n` uses `result = []` (Vector{Any})

[Collection.jl:203,222](../../program/src/document/Collection.jl#L203) builds
results with `[]`, leading to `Vector{Any}` allocations and lost type info.

**Action:** Use `Any[]` only if heterogeneity is intentional; otherwise
infer the element type from the call site.

### 6.2 Useless `i` loop variables

Same file, `for i in 1:n` with `i` unused — minor but pervasive in
`take_first_n` and parts of `_search_document`.

**Action:** Rename to `_` for clarity.

### 6.3 `editor/Editor.jl` operation logging

[Editor.jl:83](../../program/src/editor/Editor.jl#L83) does
`editor.operation !== nothing && println("\r\e[K[operation] $(editor.operation)")`
on every applied op. Useful when developing but noisy when running the
editor for screenshots or in tests. Same for `perf!`
([Editor.jl:114-118](../../program/src/editor/Editor.jl#L114-L118)).

**Action:** Gate behind an `Editor.verbose::Bool` field, or behind a
`Logging` debug level so test output stays clean.

### 6.4 Two definitions of `head`/`tail` for paths shadowing iteration helpers

[Reference.jl:213-214](../../program/src/reference/Reference.jl#L213-L214)
defines `head(p)` and `tail(p)` as module-internal accessors but not
exported, and there are also `Base.iterate` methods that use them
implicitly. Code that does `using ..ReferenceModule: head, tail` would
conflict with Julia's standard `Base.head` / `Base.tail` (the latter being
useful and well-known). Fortunately nothing imports them — but they're a
foot-gun if someone later does.

**Action:** Rename internal helpers to `_head` / `_tail`, or just inline
them — they're one-line accessors used in two places.

### 6.5 Inconsistent module naming convention

Most modules follow `<Name>Module`, but:

- `SdlBackendModule` (in `backend/Sdl.jl`)
- `TextLineNumberingModule` (in `projection/primitive/LineNumbering.jl`,
  but the file is `LineNumbering.jl`)
- `TextWordWrappingModule` (same — file is `WordWrapping.jl`)
- `GenericCompoundModule`, `HigherOrderCompoundModule` (in compound/)

The mismatch between file name (`LineNumbering.jl`) and module name
(`TextLineNumberingModule`) is unusual and makes greps harder.

**Action:** Either rename the modules to drop the `Text` prefix
(`LineNumberingModule`, `WordWrappingModule`) or rename the files
(`TextLineNumbering.jl`, `TextWordWrapping.jl`). Renaming the modules is
cheaper because consumer code uses the file name only in the `include`.

---

## 7. Architecture-level opportunities

These are larger and could each spawn their own plan.

### 7.1 A common helper for "translate domain path → output path" with `ProjectionReference` fallback

`_translate_json_path` /
`_forward_json_path` ([JsonToSyntax.jl:406-541](../../program/src/projection/primitive/JsonToSyntax.jl#L406-L541))
already do this for the JSON domain. The same logic is going to be needed
for every compound printer that introduces delimiters (XML, Math, Julia,
Book, FileSystem, Collection). Generalising it would shrink the per-domain
projection code substantially and would interact well with the
[syntax-tree-selection](syntax-tree-selection.md) plan.

### 7.2 Macro for the IoMap-with-children pattern

`ChildrenIoMap` already exists, but the `Cell` plumbing in every node
projection (capture the children, expose a `child_iomaps::Cell`, derive a
`sel` cell from `selection`, build a `SyntaxNode` whose children are
`Cell[... .output for ...]`) is duplicated for `JsonArray`, `JsonObject`,
`XmlElement`, `JuliaBlock`, `BookList`, `CollectionCellVectorToSyntax`, …

A `@compound_projection` macro could collapse the 30-line boilerplate to a
handful of declarations.

### 7.3 Distinguish "navigation" projections from "transformation" projections

The reader chain currently dispatches purely on `projection_read` returning
`nothing` to "skip" a step. A more structured design would split projections
into ones that contribute readers (the ones with delimiters / cursor logic)
and ones that don't (`Sorting`, `Filtering`, `Reversing`). The current design
works but causes the `SequentialProjection` reader to do redundant work
walking through projections that always return `nothing`.

Out of scope for an immediate plan; flag as a future direction.

---

## Suggested first-cut ordering

1. **§1.1** — delete orphan `DocumentCoreModule` (one file, zero risk).
2. **§1.2** — delete unused Syntax wrapper types (mirrors the foreign-types
   plan).
3. **§3.1, §3.2, §3.3, §3.4** — doc fixes; cheap and clear.
4. **§4.1, §4.2** — fix `Reference.jl` error-swallowing and missing step
   handling.
5. **§4.3 + §4.4** — land [fix-selection-tests.md](fix-selection-tests.md).
6. **§1.4** — colour-palette trim (decide policy: trim or expose).
7. **§2.1** — macro factoring after the type cleanup so the change-set is
   smaller.
8. **§1.3** — clipboard decision.
9. **§5.x, §6.x** — hygiene items as they happen to come up.

Larger items (§7.x) deserve their own plan documents once the above ground
is cleared.
