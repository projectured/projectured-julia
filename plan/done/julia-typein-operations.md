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

- [x] **0. Gate on the dependency.** ✅ The `@projection_template` `JuliaToSyntax` refactor
      landed on `main` (`a764d51`…`f400ef0`) mid-implementation; this worktree was rebased
      onto it. Leaf/collection/templated nodes route + map; **compound nodes
      (`JuliaFunction`/`JuliaIf`/`JuliaCall`) are still hand-written** and do NOT route
      nested char input — see the interactive gate under Results.
- [x] **A. Scaffold + completion table** — `_JULIA_KEYWORD_SCAFFOLDS`, `julia_scaffold`,
      `julia_completion` in `DocumentInsertionToSyntax.jl` (NOT `document/Julia.jl`, to avoid
      the refactor's edit set). Verified: `julia_scaffold("function")` → `JuliaFunction` with
      3 holes, cursor `name.value{0}`; `julia_completion("fun")` → `"ction"`.
- [x] **B. Smarter commit** — `_julia_commit`: keyword prefix → scaffold, else `juliaparse`.
      Verified: `_julia_commit("if")`→`JuliaIf`, `("n == 0")`→`JuliaBinaryOp`, `("1")`→
      `JuliaInteger`, `("")`→`nothing`.
- [x] **C. Hole navigation** — `SelectNextInsertionOperation(predicate, cursor)` (kernel
      `Operation.jl`) + pass-through arm in `Projection.jl`; `@gestures JuliaInsertion` Tab
      (`_julia_ins_tab`) = commit-and-advance. Verified: pre-order walk visits
      name → params[1] → body.statements[1], cursor `value{0}`, clamps at last.
- [x] **D. Completion-hint leaf** — `JuliaInsertionToSyntaxLeaf` reimplemented printer-only
      (mirrors `PrimitiveStringToSyntaxLeaf`): buffer + pale-green completion `close` span,
      `value{k}` mapping, no key reader. `test_document_insertion` stays 18/18.
- [x] **E. End-to-end** — `test_julia_typein` (`editor/JuliaTypeinTest.jl`): (1) navigation
      unit test; (2) the gesture operations (rerooted) build **exactly**
      `make_julia_document_example()`; (3) **interactive** — replaying the full keystroke
      script as real key events through `RecursiveProjection(JuliaToSyntax())` builds the
      same factorial tree. Result **8 pass / 0 broken**. Wired into `test_all`.
- [ ] **F. (optional) Structural operator/call/list gestures** — deferred; not needed for
      factorial (the buffer+`juliaparse` commit builds `n == 0`, `n * factorial(n - 1)`).
- [x] **@gestures-first** — all `JuliaInsertion` editing reified as `@gestures JuliaInsertion`
      (char insert/delete/commit/Tab), reached via the generic `document_read` fallback.

## Results (2026-07-02) — complete, interactive path live

**Operations layer + interactive end-to-end verified.** Starting from an empty
`JuliaInsertion`, the reified gesture operations compose into the exact `factorial` tree,
both applied directly (rerooted) and — the acceptance — driven as **real key events**
through `RecursiveProjection(JuliaToSyntax())`:
`function⇥ factorial⇥ n⇥ if⇥ n == 0⇥ 1⇥ n * factorial(n - 1)⏎` →
`make_julia_document_example()`. `test_julia_typein` = **8 pass / 0 broken**. Regression:
`test_document_insertion` 18/18, `test_repl(json_example)` 225/225,
`test_repl(julia_example)` 225/225.

**Interactive gate: lifted.** The gate was the compound-node projection routing of
`julia-syntax-navigation.md`. It closed when the `@projection_template` refactor **finished
JuliaToSyntax** (`bf8de12` "finish JuliaToSyntax" / `2d098c9` "Julia 32/32" — nested
sub-node F1 + conditional-children F2 markers): every node now routes nested-hole input and
reroots the resulting edits, so the interactive build works with no changes to this plan's
operations layer. (An earlier `@test_broken` mis-checked for a committed identifier after
typing without a commit; it was replaced by the full interactive-build assertion.)

## Notes on the risks that materialised

- **Tab precedence** was resolved cleanly by making `JuliaInsertionToSyntaxLeaf` printer-only
  (no `projection_gestures`), so `@gestures JuliaInsertion` owns every key via `document_read`.
  The shared `InsertionToSyntaxLeaf` (DocumentInsertion/SQL) is untouched.
- **`SelectNextInsertionOperation` is editor-global** — carries no reference, added a
  pass-through arm to the default `projection_read` (like `ToggleCollapseOperation`); the
  `else`-branch of `prepend_steps_to_op` already forwards it. Confirmed non-regressing.
- **Empty-list holes**: scaffolds seed one hole per list so Tab lands; deleting a hole to
  empty + removing the stray hole is a later refinement (not needed for factorial).
