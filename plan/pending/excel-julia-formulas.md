# Excel-style Julia Formulas

> **Status (2026-08-12): IN PROGRESS.** Phases 1–4 (types, environment/cycle-detection,
> evaluation, projections) and Phase 7 (example) are done and re-verified live
> (`test_formula()` 42/42 pass; `formula_example` sweeps clean — see Phase 8). Phase 5
> (operations + insertion parsing) and Phase 6 (embedding in a host domain) are still
> open — `FormulaInsertion` is currently a static, non-editable label, not a live
> type-in hole. The plan sat through the "give every domain its own package" split
> (`0ed5ed2f`, `47e4a4b1`); every path below has moved from `package/formula/example/document/Formula.jl`
> to `package/formula/main/Formula.jl` (the domain types), with `package/formula/example/document/Formula.jl`
> now holding only the example-catalog factory (Phase 7). `AlternativeProjection` was
> renamed `SwitchingProjection`; `SequentialProjection` was renamed `ChainingProjection`.

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
  ([Julia.jl](../../source/julia/Julia.jl)) gives us parsing
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

**✅ DONE (verified 2026-08-12):** `FormulaModule` exists at
`package/formula/main/Formula.jl` (393 lines) with `FormulaDocument` (line 30),
`FormulaInsertion` (36-38), `FormulaReference` (44-46), `FormulaFormula` (55-60),
`FormulaEnvironment` (83-85), and is registered via `include("Formula.jl")` in
`package/formula/main/ProjecturedFormula.jl:36`. NOTE: `FormulaInsertion` holds a
`value::String` buffer but its **commit/parse-into-`FormulaFormula`** is NOT
implemented — see Phase 5. `package/formula/example/document/Formula.jl` is no
longer where the domain types live; that path now holds only the 29-line
example-catalog factory (Phase 7).

### File: `package/formula/main/Formula.jl` (`FormulaModule`)

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
[tutorial](../../documentation/tutorial-new-domain.md) Step 2).

---

## Phase 2 — Environment, dependency graph, cycle detection

**✅ DONE (verified 2026-08-12):** All query/graph functions present in
`package/formula/main/Formula.jl`: `resolve` (104-110), `column_letter` (118-128),
`cell_name` (136), `formula_references`/`_collect_references!` (143-169),
`formula_dependencies` (176-185), `would_create_cycle` (194-208),
`topological_order` (216-234). Covered by tests in
`package/formula/test/projection/FormulaToSyntaxTest.jl` (`would_create_cycle`,
`topological_order`, `cell_name`/`column_letter` boundaries). Confirmed live:
`test_formula()` passes 42/42.

### File: `package/formula/main/Formula.jl` (query/graph API, same module)

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

**✅ DONE (verified 2026-08-12):** Implemented as a section of
`package/formula/main/Formula.jl` (never split into a separate evaluator file):
`formula_to_expr`/`_to_expr` (265-324), `evaluate_formula` (334-357) with a sandbox
scratch module (`_FORMULA_SCRATCH`/`_formula_scratch_module`, 243-250) mirroring the
Mcp eval pattern, reactive wiring via `wire_result!` (388-391) setting `result` to
`Cell(() -> evaluate_formula(...))`, and the `_EVALUATING` cycle safety net
(255, 336 returning `"#CYCLE!"`). Reactive recompute and safety-net behaviour are
tested.

### File: `package/formula/main/Formula.jl` (query/graph + evaluation, same module — never split out)

- `formula_to_expr(code::JuliaDocument, env) -> Expr` — walk the Julia body to a
  native `Expr`, mapping each `FormulaReference` to a `Symbol` bound to the
  target's name. (Inverse of `juliaparse`; analogous to the `Base.show`
  source-rendering already in [Julia.jl](../../source/julia/Julia.jl), but
  producing an `Expr`.)
- `evaluate_formula(formula, env) -> result document` — evaluate in a sandbox
  module (the same `Core.eval`-in-a-scratch-module technique as
  `execute_julia_code` in [CodeExecution.jl](../../source/kernel/tool/CodeExecution.jl)),
  with each dependency name bound to its evaluated value. Wrap the value in a result
  document (`result_text`-style, like [Evaluator.jl](../../source/conversation/Evaluator.jl)).
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

**✅ MOSTLY DONE (verified 2026-08-12):** `FormulaToSyntaxModule` exists at
`package/formula/main/FormulaToSyntax.jl` (291 lines), registered via
`include("FormulaToSyntax.jl")` in `package/formula/main/ProjecturedFormula.jl:37`.
Implements `FormulaInsertionToSyntaxLeaf` (62-70), `FormulaReferenceToSyntaxLeaf`
(renders `target.name` reactively, 79-90), `FormulaFormulaToSyntaxNode` with the
three `:code`/`:result`/`:both` layouts selected by `display_mode` (struct 105-110,
`print_document` 121-162, School-A `map_reference_forward`/`backward` 173-208),
`FormulaEnvironmentToSyntaxNode` (one-per-line list, 214-239), and the
`FormulaToSyntax()` constructor merging the Julia dispatch table (281-289).
**⏳ OPEN sub-item, confirmed still open:** the mode branch is a raw `if`/`elseif`
inside a `ComputedCellVector` (146-157), not `SwitchingProjection` (the renamed
`AlternativeProjection`), and the **global default via `ProjectionConfiguringProjection`**
(now at `package/widget/main/ProjectionConfiguring.jl`) is still NOT wired — `grep
-rn "SwitchingProjection\|ProjectionConfiguringProjection" package/formula/` finds
nothing. Only the per-formula toggle exists.

### File: `package/formula/main/FormulaToSyntax.jl`

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
peel-and-delegate pattern from the [tutorial](../../documentation/tutorial-new-domain.md) Step 3,
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

**⏳ OPEN (verified absent 2026-08-12):** No `SetFormulaDisplayModeOperation`,
`RenameFormulaOperation`, or `InsertFormulaReferenceOperation` exist anywhere
(grep across `package/` finds these names only in this plan file). `FormulaToSyntax`
defines no custom reader (`read_intent`, the renamed `projection_read`).
`FormulaInsertion` commit/parse is also not implemented (Phase 1) — and it goes
further than "not implemented": comparing `FormulaInsertionToSyntaxLeaf`
(`FormulaToSyntax.jl:62-70`) against the real pattern in
`package/julia/main/JuliaInsertionToSyntax.jl` (which wires `@gestures`, a commit
callback calling `juliaparse`, and cursor mapping), Formula's version has none of
that — it is a static, non-editable "insert formula" label, not yet a live type-in
hole. Cycle-checked reference insertion is therefore not wired, even though the
underlying `would_create_cycle` check exists (Phase 2).

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

**⏳ OPEN (verified absent 2026-08-12):** No Formula type is used in any other
domain or projection (`grep -rl "Formula" package/*/main package/*/example
package/*/document package/*/test | grep -v "^package/formula/"` finds only
incidental precedent-comments in `package/fsm/main/FsmToSyntax.jl` and umbrella
wiring files — no actual embedding). No example or test embeds a `FormulaFormula`
in a table cell or in `TextBlock` prose. The claim "no host domain needs changes"
is plausible but unexercised. Also newly true: there is no `table`/`tabular`
package in this codebase at all today (only `RstTableCell`, in
`package/rst/main/Rst.jl:328`) — the "TableCell" concept this phase's design
assumes has no current reusable type to embed into; picking one is a
prerequisite for this phase, not just an implementation detail.

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

**✅ DONE (verified 2026-08-12):** `package/formula/example/document/Formula.jl:1-23`
defines `make_formula_document_example()` (A1/B1/A2=A1+B1 plus a free-standing `tax`
formula, `:both` view). `package/formula/example/projection/Formula.jl:1-7` defines
`make_formula_projection_example()` as the
`ChainingProjection(RecursiveProjection(FormulaToSyntax()), …)` pipeline (the
renamed `SequentialProjection`). Registration is now per-package, not one
`ProjecturedExample.jl`/`Examples.jl` pair: both files are included in
`package/formula/example/ProjecturedFormulaExample.jl:69-70`;
`package/projectured/example/DomainExamples.jl:114` defines
`const formula_example = Example("formula", make_formula_document_example,
make_formula_projection_example)` and adds it to `domain_examples` (line 184);
`package/projectured/example/Examples.jl:34` adds it to the umbrella `examples`
list `run_example` searches (`run_example(name="json"; kwargs...)` at line 48).
NOTE: the example does not embed a formula in text (Phase 6).

- `package/formula/example/document/Formula.jl` — `make_formula_document_example()`: a small
  `FormulaEnvironment` (or a `TableTable` of formula cells) with `A1`, `B1`,
  `A2 = A1 + B1`, showing cross-references and a `:both` view; plus one
  free-standing named formula embedded in text.
- `package/formula/example/projection/Formula.jl` — `make_formula_projection_example()`:
  `ChainingProjection(RecursiveProjection(FormulaToSyntax()),
  RecursiveProjection(SyntaxToText()), TextToGraphics())`.
- Register the example in its per-package `ProjecturedFormulaExample.jl` and the
  umbrella `DomainExamples.jl`/`Examples.jl`, so `run_example("formula")` opens it
  (tutorial Step 5).

---

## Phase 8 — Tests

**✅ DONE (verified 2026-08-12, more complete than the earlier audit found):**
`package/formula/test/projection/FormulaToSyntaxTest.jl:10-130` defines
`test_formula_to_syntax()` covering: column_letter/cell_name boundaries (12-25),
reference renders+tracks renames (27-40), view modes (42-59), evaluation
`A2=A1+B1` with reactive recompute (61-78), cycle rejection (80-94), cycle
safety-net error (96-106), environment one-per-line (108-118), and
`topological_order` (120-128). Registered in `package/formula/test/ProjecturedFormulaTest.jl:92-97`
and called from `package/projectured/test/ProjecturedTest.jl:250`. Confirmed live:
`test_formula()` passes 42/42. **The "no test_printer/test_reader/test_text_navigation
sweep" sub-item is now DONE, not open:** `formula_example` is in the umbrella
`examples` list, so the sweep drivers in `package/projectured/test/editor/ExampleSweeps.jl`
cover it automatically, with none of them marking it broken. Run directly:
`test_printer(formula_example)` → 1416/1416 pass; `test_reader("formula", …)` →
225/225 pass; `test_repl("formula", …)` → 225/225 pass;
`test_position_navigation("formula", …)` → 55/55 pass. Two genuinely open gaps
remain, both consequences of Phase 5 being unimplemented: `click_broken` in
`ExampleSweeps.jl:339` marks formula's click round-trip as failing (12 clicks
inside the formula grid produce no selection operation — no text-cursor reader
yet), and `NAV_LEFT_WALK_STALLS`/`NAV_RIGHT_WALK_MISSES_END` mark its keyboard
caret walk as not reaching start/end. `test_typeins()` excludes formula entirely
(only `"json","text","xml","book","syntax"` are covered), consistent with there
being no live insertion buffer to type into (Phase 5).

Per the testing conventions ([testing.md](../../documentation/testing.md), CLAUDE.md), add targeted
helpers — do not lean on `test_all`:

- ✅ DONE — `test_formula_to_syntax()` — printer output for each view mode; reference renders
  the target name; renaming the target updates the rendered reference.
- ✅ DONE — Evaluation unit tests — `A2 = A1 + B1` evaluates correctly; editing `A1`
  invalidates and recomputes `A2` (reactive propagation).
- ✅ DONE — Cycle tests — `would_create_cycle` rejects `A1 → A2 → A1`; the insert operation
  is a no-op when it would close a loop; the evaluator safety net returns an error
  result rather than hanging.
- ✅ DONE — `cell_name` / `column_letter` boundary tests (`A`, `Z`, `AA`).
- ✅ DONE (2026-08-12) — `test_printer` / `test_reader` / `test_text_navigation` on
  `formula_example` — covered by the umbrella `ExampleSweeps.jl` drivers, all
  clean (see Phase 8 above); `test_position_navigation` also clean, only click
  round-trip and the keyboard caret walk remain broken (Phase 5 dependent).

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
7. **✅ DONE (2026-08-12) — formula_example printer/reader/navigation sweep now
   passes clean too** — Phases 7-8 example + tests.

## Dependencies / prerequisites

- `Julia` domain + `juliaparse` (present, `package/julia/main/Julia.jl` +
  `JuliaParser.jl`).
- `Evaluator` result-document conventions (present, `package/conversation/main/Evaluator.jl`),
  `execute_julia_code` sandbox-eval pattern (present, but no longer inside the mcp
  package — now `package/kernel/main/tool/CodeExecution.jl:88`).
- `SwitchingProjection` (renamed `AlternativeProjection`), `TypeDispatchingProjection`,
  `RecursiveProjection`, `ProjectionConfiguringProjection` (present; the last two
  unchanged in name, now at `package/projection/main/higherorder/TypeDispatching.jl`
  and `package/widget/main/ProjectionConfiguring.jl`).
- `Table` / inline-text embedding for Phase 6 — **not present**: no `table`/`tabular`
  package exists in this codebase today (see Phase 6 above).
- A `formula_to_expr` unparser (present, `package/formula/main/Formula.jl:265-324`
  — small, mirrors the Julia `Base.show` logic, as planned).

## Future work

- Navigate into a reference to jump to its target (follow the link).
- Spill ranges / array formulas (`A1:A3`).
- Named ranges and multiple sheets (multiple `FormulaEnvironment`s).
- Richer result documents (tables, charts) instead of `TextBlock`.
- Auto-recalc ordering surfaced in the UI; error display for `#REF!`-style states.
</content>
</invoke>
