# Excel-style Julia Formulas

> **AUDIT (2026-06-23):** Phases 1–3, most of 4, and 7 are implemented and
> registered. Phase 5 (operations + insertion parsing) and Phase 6 (embedding in
> Table/Text) are still OPEN; the global-default view switch in Phase 4 and the
> `test_printer`/`test_reader`/`test_text_navigation` sweep in Phase 8 are OPEN.
> Source: `package/domain/src/document/Formula.jl`,
> `package/domain/src/projection/primitive/FormulaToSyntax.jl`,
> `package/example/src/{document,projection}/Formula.jl`,
> `package/test/src/projection/FormulaToSyntaxTest.jl`. Tests could not be
> executed (no Julia in audit environment); status is from static code evidence.

A domain for **named, cross-referencing, evaluated formulas** whose code is a
Julia expression. A formula renders either as its *code*, as its *evaluated
result*, or as *both*; formulas reference each other by name; the reference graph
is kept circle-free; and because a formula is an ordinary `Document`, it can be
embedded in a table cell, in prose, or in any other domain that recurses its
children to syntax.

This is the spreadsheet idea generalised: instead of a fixed 2-D grid of cells,
a formula is a first-class document you can drop anywhere, and its name (the
spreadsheet's `A1`) is just one naming convention among others.

## Goals (from the request)

1. **Embeddable anywhere.** A formula can live in a `TableCell`, inside `TextBlock`
   prose, or nested in any domain — not just a grid.
2. **Code / result / both.** A formula is displayed as its source code, as its
   evaluated value, or as both. The user can switch.
3. **Circle-free.** The reference graph between formulas must be acyclic; an edit
   that would introduce a cycle is rejected.
4. **Named, mutually referencing.** Each formula has a name; other formulas refer
   to it by holding a reference, and that reference is *displayed as the target's
   current name*.
5. **`A1`-style names.** A formula sitting in a table cell takes the combined
   column-letter + row-number name (`A1`, `B2`); free-standing formulas carry an
   explicit name.

## Design decisions

- **Formula code is the existing `Julia` domain.** Reusing `JuliaDocument`
  ([Julia.jl](../../program/src/document/Julia.jl)) gives us parsing
  (`juliaparse`), `JuliaToSyntax` rendering, and character-level editing for free.
  A formula body is a `JuliaDocument` tree; the only new leaf inside it is the
  cross-formula **reference**.

- **A reference points by identity, displays by name.** `FormulaReference` holds
  a *live reference to the target `FormulaFormula`* (not a copy of its name). The
  projection renders `target.name`, so renaming a formula updates every reference
  reactively — no rewrite pass. This is what "the reference is displayed with its
  name" means in a reactive, identity-based model. (Excel stores cell identity and
  re-derives the display string; we do the same.)

- **Names: explicit cell or derived thunk.** `FormulaFormula.name` is a `Cell`.
  A free-standing formula holds a literal name. A table cell sets the name to a
  *thunk* computing `column_letter(col) * string(row)` from its grid position, so
  `A1` tracks the cell's coordinates without storing redundant data. (Same
  derived-view trick `TabularGrid` uses for columns — see
  [tabular.md](../done/tabular.md).)

- **An environment is the evaluation + resolution scope.** `FormulaEnvironment`
  holds the set of named formulas and provides name→formula lookup, dependency
  extraction, and cycle detection. It is the analogue of a spreadsheet *sheet*.
  We scope to an explicit environment document rather than a process-global
  registry (unlike [document-link-feature.md](document-link-feature.md)) so that
  multiple independent formula sets can coexist and so the scope is itself a
  projectable, testable document.

- **Reactivity does the recompute; an explicit guard breaks runaway cycles.**
  Each formula's `result` is a computed `Cell` that reads its dependencies'
  `result` cells, so editing one formula incrementally re-evaluates exactly its
  transitive dependents. A genuine cycle would make a thunk force itself, so two
  defences apply: (a) the *editor rejects* any edit that would create a cycle
  (static DFS over the reference graph), and (b) the evaluator keeps a
  currently-evaluating set as a safety net, returning an error value on re-entry
  rather than looping.

- **View switching = `AlternativeProjection` + a per-formula mode cell.** The
  three views (code / result / both) are three branches selected by a mode. Both
  a per-formula toggle (Excel's "show formulas", but per cell) and a global
  default are supported (the global one via the existing
  `ProjectionConfiguringProjection` control bar).

- **Embedding = the standard `RecursiveProjection(TypeDispatchingProjection(...))`
  dispatch.** Because every `…ToSyntax` printer recurses children through the
  shared `recursion` projection, adding `FormulaFormula`/`FormulaReference` to the
  type dispatch makes formulas render wherever they appear in a tree — in a
  `TableCell.content::Document`, inside a Julia AST, etc. No host domain changes.

---

## Phase 1 — Formula domain types

**✅ DONE (verified):** `FormulaModule` exists at
`package/domain/src/document/Formula.jl` with `FormulaDocument`,
`FormulaInsertion`, `FormulaReference`, `FormulaFormula`, `FormulaEnvironment`
(lines 51–143), and is registered via `include("document/Formula.jl")` in
`package/domain/src/ProjecturedDomain.jl:91`. NOTE: `FormulaInsertion` holds a
`value::String` buffer but its **commit/parse-into-`FormulaFormula`** is NOT
implemented — see Phase 5.

### File: `program/src/document/Formula.jl` (`FormulaModule`)

```
FormulaDocument (abstract)
├── FormulaInsertion   — type-in entry point (parse buffer → formula)
├── FormulaReference   — a citation of another formula; displays target.name
├── FormulaFormula     — a named formula: name + code + cached result + view mode
└── FormulaEnvironment — the resolution/evaluation scope: a set of named formulas
```

- `FormulaFormula <: FormulaDocument`
  - `name::String` — display name; literal, or a thunk derived from grid coords.
  - `code::Document` — the body, a `JuliaDocument` (may contain `FormulaReference`s).
  - `result::Document` — *computed* result document (a `TextBlock`, or a Julia
    literal node for richer display). Wired as a `Cell(() -> evaluate(...))`.
  - `display_mode::Symbol` — `:code` | `:result` | `:both`.
  - `selection::Reference`

- `FormulaReference <: FormulaDocument`
  - `target::Document` — the referenced `FormulaFormula` (held by identity).
  - `selection::Reference`
  - Rendered name is `target.name`, read reactively. Resolving a *typed* name to
    a target uses the enclosing `FormulaEnvironment` (Phase 2).

- `FormulaEnvironment <: FormulaDocument`
  - `formulas::CellVector` — the `FormulaFormula`s in scope.
  - `selection::Reference`
  - Field names (`name`, `code`, `result`, `target`, `formulas`) are the public
    reference vocabulary — chosen deliberately per the `Document` contract.

- `FormulaInsertion <: FormulaDocument` — `value::String` + `selection`; the
  per-domain type-in placeholder. Commit parses `value` (an Excel-style
  `=expr` or bare `name = expr`) into a `FormulaFormula`.

Register in `Projectured.jl`: `include`, `using`, `export` (mirroring the
[tutorial](../tutorial-new-domain.md) Step 2).

---

## Phase 2 — Environment, dependency graph, cycle detection

**✅ DONE (verified):** All query/graph functions present in `Formula.jl`:
`resolve` (155), `column_letter` (169), `cell_name` (187),
`formula_references`/`formula_dependencies` (194, 227),
`would_create_cycle` (245), `topological_order` (267). Covered by tests in
`package/test/src/projection/FormulaToSyntaxTest.jl` (`would_create_cycle`,
`topological_order`, `cell_name`/`column_letter` boundaries).

### File: `program/src/document/Formula.jl` (query/graph API, same module)

- `resolve(env, name) -> FormulaFormula | nothing` — name lookup (built over a
  reactive name→formula index recomputed from `env.formulas`).
- `column_letter(col::Int) -> String` and `cell_name(col, row) -> String` —
  `1→"A"`, `27→"AA"`, `cell_name(1,1) == "A1"`.
- `formula_dependencies(formula) -> Vector{FormulaFormula}` — walk `code`,
  collect every `FormulaReference.target`. (One `collect_references`-style tree
  walk over the Julia body.)
- `would_create_cycle(env, from, to) -> Bool` — DFS from `to` over
  `formula_dependencies`; true if it can reach `from`. Used by the reader to veto
  cycle-introducing edits.
- `topological_order(env)` — optional, for batch/whole-sheet evaluation and tests.

The acyclicity invariant is enforced at the *operation* boundary (Phase 5), so the
document is never allowed to enter a cyclic state.

---

## Phase 3 — Evaluation

**✅ DONE (verified):** Implemented as a section of `Formula.jl`:
`formula_to_expr`/`_to_expr` (316–375), `evaluate_formula` (385) with a sandbox
scratch module (`_FORMULA_SCRATCH`, 294) mirroring the Mcp eval pattern,
reactive wiring via `wire_result!` (439) setting `result` to
`Cell(() -> evaluate_formula(...))`, and the `_EVALUATING` cycle safety net
(306, 386 returning `#CYCLE!`). Reactive recompute and safety-net behaviour are
tested.

### File: `program/src/document/FormulaEvaluator.jl` (or a section of `Formula.jl`)

- `formula_to_expr(code::JuliaDocument, env) -> Expr` — walk the Julia body to a
  native `Expr`, mapping each `FormulaReference` to a `Symbol` bound to the
  target's name. (Inverse of `juliaparse`; analogous to the `Base.show`
  source-rendering already in [Julia.jl](../../program/src/document/Julia.jl), but
  producing an `Expr`.)
- `evaluate_formula(formula, env) -> result document` — evaluate in a sandbox
  module (the same `Core.eval`-in-a-scratch-module technique as
  `execute_julia_code` in [Mcp.jl](../../program/src/editor/Mcp.jl)), with each
  dependency name bound to its evaluated value. Wrap the value in a result
  document (`result_text`-style, like [Evaluator.jl](../../program/src/document/Evaluator.jl)).
- `FormulaFormula.result` is `Cell(() -> evaluate_formula(self, env))`: reading a
  dependency's value inside the thunk registers the reactive dependency, so a
  change to any upstream formula invalidates exactly the downstream results.
- **Cycle safety net:** a task-local "evaluating" `Set` guards re-entry; revisiting
  a formula mid-evaluation yields an explicit error result instead of looping.
  (Static rejection in Phase 5 means this should never trigger in normal use.)

The `Evaluator` domain already pairs a *form* with a *result*; `FormulaFormula` is
the named, reactive, cross-referencing evolution of that idea — reuse
`result_text` and the result-document conventions where possible.

---

## Phase 4 — Projections

**✅ MOSTLY DONE (verified):** `FormulaToSyntaxModule` exists at
`package/domain/src/projection/primitive/FormulaToSyntax.jl`, registered in
`ProjecturedDomain.jl:140`. Implements `FormulaReferenceToSyntaxLeaf` (renders
`target.name` reactively, 77–88), `FormulaFormulaToSyntaxNode` with the three
`:code`/`:result`/`:both` layouts selected by `display_mode` (103–206, including
School-A `map_reference_forward`/`backward`), `FormulaEnvironmentToSyntaxNode`
(one-per-line list, 212–267), and the `FormulaToSyntax()` constructor merging the
Julia dispatch table (279–287). **⏳ OPEN sub-item:** the AlternativeProjection
mode cell is realised directly via a `display_mode`-driven `CellVector` rather
than `AlternativeProjection`, and the **global default via
`ProjectionConfiguringProjection`** is NOT wired (no reference anywhere). Only the
per-formula toggle exists.

### File: `program/src/projection/primitive/FormulaToSyntax.jl`

`FormulaToSyntax = RecursiveProjection(TypeDispatchingProjection(Dict(...)))`
dispatching:

- **`FormulaReference` → `SyntaxLeaf`** — value is `() -> reference.target.name`,
  coloured as an identifier/link. Reactive, so it tracks renames. (Future:
  navigating into the leaf follows a `ProjectionReference`/link to the target.)

- **`FormulaFormula` → `SyntaxNode`**, three layouts behind an
  `AlternativeProjection` whose index cell follows `formula.display_mode`:
  - `:code`   → recurse into `code` (Julia rendering, with embedded references).
  - `:result` → recurse into `result`.
  - `:both`   → `name " = " code " ⇒ " result` (a node combining the parts).

- **`FormulaEnvironment` → `SyntaxNode`** — children are the formulas (one per
  line); a plain list, like `BookmarkList` in the tutorial.

Mappers (`map_reference_forward`/`map_reference_backward`) follow the School-A
peel-and-delegate pattern from the [tutorial](../tutorial-new-domain.md) Step 3,
so cursor movement and character edits round-trip through `code`/`result`. No
custom `projection_read` is needed for plain editing; only the new operations
(Phase 5) add reader logic.

**Composition with the Julia projection.** A formula body mixes `JuliaDocument`
nodes and `FormulaReference`s. Combine the two type-dispatch tables (Julia's plus
the formula entries) into one `TypeDispatchingProjection`, wrapped in a single
`RecursiveProjection`, so the same `recursion` renders both kinds of node. This is
also exactly what lets a formula appear inside an otherwise-Julia AST.

Register the projection in `Projectured.jl` (include / using / export).

---

## Phase 5 — Operations (reader side)

**⏳ OPEN (verified absent):** No `SetFormulaDisplayModeOperation`,
`RenameFormulaOperation`, or `InsertFormulaReferenceOperation` exist anywhere
(grep across `package/` finds these names only in this plan file). `FormulaToSyntax`
defines no custom `projection_read`. `FormulaInsertion` commit/parse is also not
implemented (Phase 1). Cycle-checked reference insertion is therefore not wired,
even though the underlying `would_create_cycle` check exists (Phase 2).

- `SetFormulaDisplayModeOperation` — cycle `:code → :result → :both` on the
  selected formula (bound to a key, e.g. a toggle).
- `RenameFormulaOperation` — set `name`; references need no update (they display
  the live name).
- `InsertFormulaReferenceOperation` — given a typed name, `resolve` it in the
  environment and splice a `FormulaReference` into the code; **rejected** by
  `would_create_cycle` if it would close a loop (the reader returns no operation
  and the edit is a no-op, optionally surfacing an error result).
- Code editing reuses the Julia readers (`StringReplaceRangeOperation` on leaves);
  `FormulaInsertion` commit parses its buffer into a `FormulaFormula`.

These hang off the `FormulaToSyntax` reader / the editor's `evaluate_operation`,
consistent with how other domains add structural operations.

---

## Phase 6 — Embedding in host domains

**⏳ OPEN (verified absent):** No Formula type is used in any Table/Tabular/Text
domain or projection (grep for `Formula` across `package/domain/src/document/`
and `.../projection/` returns only `FormulaToSyntax.jl`). No example or test
embeds a `FormulaFormula` in a `TableCell` or in `TextBlock` prose. The claim
"no host domain needs changes" is plausible but unexercised.

- **Table.** A `TableCell.content` holds a `FormulaFormula`; the table's name
  thunk is set to `cell_name(col, row)`. The existing `TableToGraphics` /
  `CellTableToTable` path already recurses cell content, so once `FormulaToSyntax`
  is in the shared dispatch, formulas render in-grid. Example:
  `TableCell(FormulaFormula(code = juliaparse("A1 + B1")))` with its name derived
  from position.
- **Text / prose.** Embed a formula inline via the same inline-document mechanism
  used for [inline images](../done/inline-text-images.md) / `NestingProjection`,
  so `=A1*2` can sit in a sentence.
- **Any domain.** Because dispatch is by type through the shared `recursion`, no
  host domain needs changes — a `FormulaFormula` in any recursively-projected
  field just renders.

---

## Phase 7 — Example

**✅ DONE (verified):** `package/example/src/document/Formula.jl` defines
`make_formula_document_example()` (A1/B1/A2=A1+B1 plus a free-standing `tax`
formula, `:both` view). `package/example/src/projection/Formula.jl` defines
`make_formula_projection_example()` as the
`SequentialProjection(RecursiveProjection(FormulaToSyntax()), …)` pipeline. Both
files are included in `ProjecturedExample.jl` (lines 40, 82) and
`formula_example` is registered in `Examples.jl:147` and the examples list
(179), so `run_example("formula")` resolves. NOTE: the example does not embed a
formula in text (Phase 6).

- `example/src/document/Formula.jl` — `make_formula_document_example()`: a small
  `FormulaEnvironment` (or a `TableTable` of formula cells) with `A1`, `B1`,
  `A2 = A1 + B1`, showing cross-references and a `:both` view; plus one
  free-standing named formula embedded in text.
- `example/src/projection/Formula.jl` — `make_formula_projection_example()`:
  `SequentialProjection(RecursiveProjection(FormulaToSyntax()),
  RecursiveProjection(SyntaxToText()), TextToGraphics())`.
- Register in `ProjecturedExample.jl` and add `formula_example` to `Examples.jl`,
  so `run_example("formula")` opens it (tutorial Step 5).

---

## Phase 8 — Tests

**✅ MOSTLY DONE (verified):** `package/test/src/projection/FormulaToSyntaxTest.jl`
defines `test_formula_to_syntax()` covering: view modes (code/result/both),
reference renders+tracks renames, evaluation `A2=A1+B1` with reactive recompute,
`would_create_cycle` rejection, the cycle safety-net error result,
`column_letter`/`cell_name` boundaries, environment one-per-line, and
`topological_order`. Registered in `ProjecturedTest.jl` (include 48, call 128,
export 218). **⏳ OPEN sub-item:** no `test_printer`/`test_reader`/
`test_text_navigation` is run on `formula_example` (the last bullet below).

Per the testing conventions ([testing.md](../testing.md), CLAUDE.md), add targeted
helpers — do not lean on `test_all`:

- `test_formula_to_syntax()` — printer output for each view mode; reference renders
  the target name; renaming the target updates the rendered reference.
- Evaluation unit tests — `A2 = A1 + B1` evaluates correctly; editing `A1`
  invalidates and recomputes `A2` (reactive propagation).
- Cycle tests — `would_create_cycle` rejects `A1 → A2 → A1`; the insert operation
  is a no-op when it would close a loop; the evaluator safety net returns an error
  result rather than hanging.
- `cell_name` / `column_letter` boundary tests (`A`, `Z`, `AA`).
- `test_printer` / `test_reader` / `test_text_navigation` on `formula_example`.

---

## Implementation order

1. **✅ DONE** — Phase 1 domain types + registration.
2. **✅ DONE** — Phase 2 environment, naming, dependency graph, cycle detection.
3. **✅ DONE** — Phase 3 evaluation (reactive `result` cell + safety net).
4. **✅ DONE (global default ⏳ OPEN)** — Phase 4 projections (code / result / both
   + reference-by-name), composed with `JuliaToSyntax`.
5. **⏳ OPEN** — Phase 5 operations (display-mode toggle, rename, cycle-checked
   reference insert; FormulaInsertion parse).
6. **⏳ OPEN** — Phase 6 embedding (table first, then text/inline).
7. **✅ DONE (formula_example printer/reader/navigation sweep ⏳ OPEN)** —
   Phases 7–8 example + tests.

## Dependencies / prerequisites

- `Julia` domain + `juliaparse` (present).
- `Evaluator` result-document conventions, `execute_julia_code` sandbox-eval
  pattern (present, [Mcp.jl](../../program/src/editor/Mcp.jl)).
- `AlternativeProjection`, `TypeDispatchingProjection`, `RecursiveProjection`,
  `ProjectionConfiguringProjection` (present).
- `Table` / inline-text embedding (present) for Phase 6.
- A `formula_to_expr` unparser (new — small, mirrors the Julia `Base.show` logic).

## Future work

- Navigate into a reference to jump to its target (follow the link).
- Spill ranges / array formulas (`A1:A3`).
- Named ranges and multiple sheets (multiple `FormulaEnvironment`s).
- Richer result documents (tables, charts) instead of `TextBlock`.
- Auto-recalc ordering surfaced in the UI; error display for `#REF!`-style states.
</content>
</invoke>
