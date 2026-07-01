# Julia type-in — operations & gestures to build a factorial from `JuliaInsertion`

**Filed:** 2026-07-01. **Goal:** starting from a single empty `JuliaInsertion`,
let a user *type in* the `factorial` function (the `julia_example` tree) through a
sequence of keystrokes, driven by reified `@gestures`/operations — not by pasting a
finished tree.

Target result (== `make_julia_document_example`):

```julia
function factorial(n)
    if n == 0
        1
    else
        n * factorial(n - 1)
    end
end
```

## Architecture: `@gestures` wherever possible (steer, 2026-07-02)

All Julia type-in behaviour is reified as **document-level `@gestures`**, the way
[`@gestures PrimitiveString`](../../package/domain/src/projection/primitive/PrimitiveToText.jl#L162)
reifies string char-editing — *not* as bespoke projection readers or a commit callback.
`JuliaInsertion` becomes a proper gesture-driven editable hole:

- **`@gestures JuliaInsertion`** (char insert / Backspace / Delete / commit / navigate)
  is the single source of truth. Both its projection and any other reach it through the
  generic `document_read` fallback (a leaf projection with no bespoke key reader delegates
  raw input to `document_read(iomap.input, …)`).
- **`JuliaInsertionToSyntaxLeaf` is reimplemented as a printer-only leaf** (mirroring
  [`PrimitiveStringToSyntaxLeaf`](../../package/domain/src/projection/primitive/PrimitiveToSyntax.jl#L91)):
  renders the buffer + a pale-green completion continuation, maps `value{k}` selection,
  and has **no key-capturing reader** — so `@gestures JuliaInsertion` fires instead of the
  old `InsertionToSyntaxLeaf.projection_gestures`.

**Conflict-avoidance with the in-flight `@projection_template` refactor:** everything lands
in **`DocumentInsertionToSyntax.jl`** (not in the refactor's edit set) + the kernel
(`Operation.jl`, `Projection.jl`). The refactored `JuliaToSyntax.jl` still says
`JuliaInsertion => JuliaInsertionToSyntaxLeaf()` — the **name is unchanged**, only its
implementation (in `DocumentInsertionToSyntax.jl`) changes. Zero edits to
`Julia.jl` / `JuliaToSyntax.jl` / `Document.jl`.

Existing `DocumentInsertionTest.jl` (Julia commit) keeps passing: its direct
`projection_read(jproj, jiom, KeyDown(:return))` now falls through the generic
`projection_read(::Projection,…)` → `document_read` → the `@gestures JuliaInsertion`
commit rule, still returning the commit `CompoundOperation`.

## Chosen design (from the two design forks)

1. **Hybrid `JuliaInsertion`.** `JuliaInsertion` stays a **text buffer** (char-by-char
   editing via the `InsertionToSyntaxLeaf`-style leaf). It is *both* the raw-source
   entry point *and* the structural **hole** placeholder. Structural behaviour is added
   at **commit time** and via **hole navigation**, not by stripping the buffer.
2. **Keyword completion hint (green pale continuation).** As the buffer prefix matches a
   Julia keyword-introduced construct (`function`, `if`, `for`, `while`, `begin`, `try`,
   `return`), a **pale-green completion suffix** is rendered after the typed text to
   signal "this is committable as `<keyword>`". Committing expands the keyword into a
   **scaffold with holes** (nested `JuliaInsertion`s) rather than parsing raw text. This
   is exactly the "live completion hint + green/red commitability colouring" that
   [DocumentInsertionToSyntax.jl:23-24](../../package/domain/src/projection/primitive/DocumentInsertionToSyntax.jl#L23-L24)
   flagged as "not yet ported" — we port it, specialized for Julia keywords.

So a single `JuliaInsertion` buffer commits one of two ways:

- **prefix matches a scaffold keyword** → expand to that construct's scaffold (holes +
  cursor on the first hole);
- **otherwise** → `juliaparse(value)` the buffer into a complete `JuliaDocument`
  (the existing path — handles whole sub-expressions like `n == 0`, `n * factorial(n - 1)`).

## Dependency (in flight) — do not duplicate

Gestures on a *nested* Julia node only fire and map back if the Julia→Syntax projection
provides **bidirectional reference mapping + reader routing**. That is
[plan/pending/julia-syntax-navigation.md](julia-syntax-navigation.md), being delivered by
the **`@projection_template` refactor** of `JuliaToSyntax` (School-A `bound`/`project`/
`collection` give the mappers + `_syntax_to_flat` structural navigation *for free*, the
way `JsonToSyntax` already has them). **This plan assumes that lands first** and builds
purely the *operations/gestures* on top. Concretely we rely on the refactor for:

- `replace_document(∅, …)` / `ReplaceSelectionOperation` emitted at a nested hole being
  **rerooted** up the chain to `editor.document` (the composite `projection_read`).
- `bound(:name, String, …)` on `JuliaIdentifier` and `bound(:value, Int, …)` on
  `JuliaInteger` giving char-by-char editing + a `value{k}` char cursor (so a committed
  identifier/integer is itself editable, and the `_replace_*` seeds can place a caret).

## The building blocks (all precedented in JSON)

Operation primitives already exist ([common/Operation.jl](../../package/kernel/src/common/Operation.jl)):
`replace_document(path, doc)`, `insert_elements(path, i, items, sel)`,
`ReplaceSelectionOperation(path)`, `with_selection(doc, path)`. The JSON authoring set
([document/Json.jl:196-246](../../package/domain/src/document/Json.jl#L196-L246)) is the
template: `_replace(doc, with_selection(newdoc, cursor))`, `,`-insert, Tab-advance.

New pieces this plan adds:

### A. Julia keyword scaffold + completion table (`document/Julia.jl` or a new helper)

```
const _JULIA_SCAFFOLDS = [
  "function" => () -> with_selection(
        JuliaFunction(JuliaInsertion(), [JuliaInsertion()], JuliaBlock([JuliaInsertion()])),
        @reference name),
  "if"       => () -> with_selection(
        JuliaIf(JuliaInsertion(), JuliaBlock([JuliaInsertion()]), JuliaBlock([JuliaInsertion()])),
        @reference condition),
  "for"/"while"/"begin"/"try"/"return" => …   # same shape
]
```

- `julia_scaffold(prefix)` → the scaffold builder if `prefix` *exactly* names a keyword,
  else `nothing`.
- `julia_completion(prefix)` → the pale-green suffix for a *partial* keyword
  (`"fun"` → `"ction"`), else `""`. Mirrors
  [`default_completion`](../../package/domain/src/projection/primitive/DocumentInsertionToSyntax.jl#L216).

### B. Commit logic (extend `_julia_commit`)

`_julia_commit(value)` becomes: exact keyword → its scaffold (with holes + inner cursor);
else non-empty → `juliaparse(value)`; else `nothing`. `replace_document(∅, doc)` reads
`doc.selection`, so the scaffold's `with_selection` lands the cursor on the first hole.

### C. Hole navigation — Tab / Enter across holes (new operation)

Committing a *leaf* hole (identifier/integer) must advance to the next unfilled hole.
Add an editor-level operation:

```
struct SelectNextInsertionOperation <: Operation end   # (and SelectPreviousInsertionOperation)
evaluate_operation(editor, ::SelectNextInsertionOperation) =
    update_selection!(editor.document, next_insertion_path(editor.document, current_sel))
```

`next_insertion_path` walks `editor.document` in print order from the current selection to
the next `JuliaInsertion` (an empty hole) and returns its whole-element path. This is
editor-global (it needs the whole tree), like the Text cursor motions but across the AST.

**Tab = commit-then-advance:** a `JuliaInsertion` Tab gesture emits a `CompoundOperation`
of `_julia_commit`'s replace + `SelectNextInsertionOperation`. If the buffer is empty, Tab
is just `SelectNextInsertionOperation` (skip an untouched hole).

### D. Completion-hint rendering (Julia insertion leaf)

Give the Julia insertion leaf a `completion` thunk so it renders `typed·⟨pale-green
completion⟩`. Reuse `hinted_text`/`StyleText(green)` the way `JsonStringToSyntaxLeaf`
renders its placeholder. Either extend `InsertionToSyntaxLeaf` with an optional
`completion::Function` field, or make a `JuliaInsertionToSyntaxLeaf` variant. Prefer
extending the shared leaf so SQL/Document insertions can opt in later.

### E. (Optional, later phase) Structural operator/call gestures

Not required for factorial (the buffer+`juliaparse` commit already builds `n == 0` and
`n * factorial(n - 1)`), but the natural next step for pure projectional editing:
`@gestures` on filled expressions that **wrap** the current node — type an operator →
`JuliaBinaryOp(op, current, ⟨hole⟩)`; `(` → `JuliaCall(current, [⟨hole⟩])`; `[` →
`JuliaIndex`; `.` → `JuliaFieldAccess`; `,` in a params/args/block list → insert a sibling
hole. Deferred behind the core flow.

## Factorial keystroke walkthrough (acceptance script)

Cursor on a hole shown as `‹›`. `⇥` = Tab (commit + next hole).

| # | Selection | Keys | Result |
|---|-----------|------|--------|
| 1 | root `‹›` | `function` ⇥ | `function ‹name›(‹p›)  ‹body›  end`, cursor→`‹name›` |
| 2 | `‹name›` | `factorial` ⇥ | name=`factorial`, cursor→`‹p›` |
| 3 | `‹p›` | `n` ⇥ | param=`n`, cursor→`‹body›` |
| 4 | `‹body›` | `if` ⇥ | `if ‹cond›  ‹then›  else ‹else›  end`, cursor→`‹cond›` |
| 5 | `‹cond›` | `n == 0` ⇥ | `JuliaBinaryOp(:(==), n, 0)`, cursor→`‹then›` |
| 6 | `‹then›` | `1` ⇥ | `JuliaInteger(1)`, cursor→`‹else›` |
| 7 | `‹else›` | `n * factorial(n - 1)` ⏎ | parsed nested op/call; tree complete |

Steps 5 & 7 exercise the `juliaparse` commit; 1 & 4 the keyword-scaffold commit; 2,3,6 the
identifier/integer commit; the `⇥` after each drives `SelectNextInsertionOperation`.

## Steps

- [ ] **0. Gate on the dependency.** Confirm the `@projection_template` `JuliaToSyntax`
      refactor lands: `test_printer(julia_example)` green **and**
      `test_text_navigation(julia_example)` reaches nested name/param/cond states (the
      `explore_selections` count grows past 3). Until then a nested-hole commit cannot
      reroot and this plan cannot be verified end-to-end.
- [ ] **A. Scaffold + completion table** in `document/Julia.jl`: `_JULIA_SCAFFOLDS`,
      `julia_scaffold`, `julia_completion`. Unit-test scaffold shapes + cursor refs.
- [ ] **B. Smarter commit**: extend `_julia_commit` (keyword-scaffold vs parse). Test:
      `_julia_commit("function")` returns a `JuliaFunction` with 3 holes & name-cursor;
      `_julia_commit("n == 0")` returns the `JuliaBinaryOp`.
- [ ] **C. Hole navigation**: `SelectNextInsertionOperation` (+ previous) and
      `next_insertion_path` tree walk; Tab gesture = commit+advance. Test on a
      hand-built partial factorial that Tab visits holes in print order.
- [ ] **D. Completion-hint leaf**: render the pale-green suffix; wire `julia_completion`.
      `test_printer(julia_example)` stays green; a print of a partial buffer shows the hint.
- [ ] **E. End-to-end**: a `walk`-style test that replays the keystroke script from a root
      `JuliaInsertion` and asserts the final tree `==` `make_julia_document_example()`
      (ignoring selection). Add as `test_julia_typein` alongside the JSON/XML typein tests.
- [ ] **F. (optional) Structural operator/call/list gestures** (block E above) as a
      follow-up once the parse-commit flow is solid.

## Risks / open items

- **Reroot correctness at depth.** The whole plan hinges on step 0: a `replace_document`
  emitted at, say, the `else`-block hole must reroot to the full document path. This is
  the School-A + flat-offset machinery from `julia-syntax-navigation.md`; if the refactor
  delivers mappers but not structural traversal, hole *commit* may work while Tab
  *navigation through* keyword tokens does not — verify both.
- **Tab precedence (hybrid model).** `InsertionToSyntaxLeaf.projection_gestures` currently
  owns every key. Tab must be added there (or a Julia leaf subtype) so it beats any
  ancestor Tab; audit that no enclosing projection already claims Tab on a Julia pipeline.
- **`SelectNextInsertionOperation` is editor-global.** It reads `editor.document`, unlike
  the doc-relative authoring ops. Confirm that fits `evaluate_operation` and does not need
  rerooting (it sets an absolute selection, so it should pass through readers unchanged —
  mirror `ReplaceSelectionOperation`).
- **Empty-list holes.** Scaffolds seed one hole per list (`[JuliaInsertion()]` params,
  single-statement blocks) so Tab has somewhere to land; committing a hole to empty +
  Tab should *remove* the stray hole (a later refinement; not needed for factorial).
```
