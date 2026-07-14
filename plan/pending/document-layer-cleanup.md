# Document layer cleanup — one walk, a factored macro, no leaked internals

Restructure `package/kernel/main/document/` so that each of its concerns lives in one file
and is owned by one module: merge the two copies of the reflection walk, factor the
260-line `@document` macro into a plan plus emitters, close the private-symbol leaks, move
`Clock` out of a layer it has no business being in, and split the 703-line `Document.jl`
into files at the same grain as the (already sealed) cell layer.

**Behaviour is preserved throughout.** No exported name is removed and no public signature
changes. Four names are *added* to the kernel's public surface (`unwrap_cell` and the
shadow-sync kit), which is the point of Step 3.

## ⚠️ Sealed files

Every file this plan touches in `package/kernel/main/document/` and
`package/kernel/main/cell/` is **sealed** (see the seal inventory in
[CLAUDE.md](../../CLAUDE.md)). Executing this plan requires the user's explicit permission
to modify:

- `document/DocumentModule.jl`, `document/Interface.jl`, `document/Document.jl`,
  `document/Forward.jl`, `document/Clock.jl`
- `cell/CellModule.jl`, `cell/CellStruct.jl`, `cell/CellLayer.jl`

**Do not start any step before that permission is given for the files that step touches.**
The seals hold until then. When a sealed file is restructured, re-audit it against
[architecture-requirements.md](../../documentation/architecture-requirements.md) and
re-seal it in the same commit; new files (`DocumentWalk.jl`, `DocumentPlan.jl`, …) enter
the inventory as `⬜` and are sealed on their own review.

## Scope

This plan covers items 2–5 of the document-layer review, plus the file split that falls out
of them.

**Explicitly deferred: the layer inversion (item 1).** `@document` injects
`selection::Reference` as a bare, unresolved symbol because `Reference` lives in layer 3,
above this one — a forward dependency laundered through macro hygiene. The fix is to split
the reference layer into pure path *syntax* (below documents) and *evaluation/search*
(above), which the numbers say is nearly free: of the eight files in `reference/`, only
`ReferenceEvaluation.jl` and `ReferenceSearch.jl` name `Document` at all. That is its own
plan. **Every step below is designed to survive it** — in particular Step 4's walk seam is
built so that, once the layers are reordered, the seam can collapse rather than needing
rework.

---

## Step 1 — Move `Clock` out of the document layer ✅ done

`document/Clock.jl` declares its own `ClockModule`, imports only `CellModule`, and its own
docstring says *"A clock is **not** a `Document`"*. Nothing in it is a document; its
dependency height is layer 1. It sits in layer 2 for no structural reason (AR-47: every
piece of code lives in the lowest home its dependencies allow).

- [x] `git mv package/kernel/main/document/Clock.jl package/kernel/main/cell/Clock.jl`.
- [x] `cell/CellLayer.jl`: append `include("Clock.jl")` after `include("CellModule.jl")`
      (ClockModule `using ..CellModule` is a same-layer sibling edge, which the guard
      allows).
- [x] `document/DocumentLayer.jl`: drop `include("Clock.jl")`. The file becomes a
      one-include layer table of contents.
- [x] `git mv package/kernel/test/document/ClockTest.jl package/kernel/test/cell/ClockTest.jl`,
      and update the test package's include list.
- [x] Docs: `documentation/architecture-requirements.md` AR-45 says *"a per-editor `Clock`
      **document** (`document/Clock.jl`)"* — both halves are wrong. Correct it to a
      `@cell_struct` at `cell/Clock.jl`. Check `package/kernel/doc/cell.md` too.
- [x] Seal inventory in [CLAUDE.md](../../CLAUDE.md): move the `Clock.jl` entry from the
      document layer to the cell layer, preserving its `🔒`.

**Verify:** `test_kernel_layering()` (structural, ~1s), then `test_kernel()`.
**Commit:** `refactor: move the clock to the cell layer, where its dependencies put it`

Fully independent of every other step; do it first to get a clean win and a green guard.

### Decision — the cell layer is a dependency height, not "the engine"

`cell.md` carried an explicit rationale for the old placement: *"the animation clock lives
in the document layer — a time value belongs with the document model, not the reactive
engine (it is a use of `Cell`, not part of the engine)."* That argument does not survive
its own neighbours. `CellStruct.jl` is codegen *over* `Cell` — a use of it, not the engine —
and `PerformanceCounter.jl` is a store the engine merely calls; both already sit in the cell
layer. So the layer is **everything at cell dependency height**, not the engine narrowly,
and `Clock` (a `@cell_struct` importing `CellModule` and nothing else) belongs in it. The
old rationale is replaced in `cell.md` rather than left to contradict the code.

Two stale doc claims fixed in passing, both of which named things that do not exist:
`cell.md` listed `WALL_CLOCK` and `start_wall_clock_heartbeat!` as API (they are the private
`_WALL_CLOCK` / `_start_wall_clock_heartbeat!`; the export is `get_wall_clock()`), and AR-45
called the clock a *document*. Fixed to AR-61 (documentation must be honest). The cell-layer
diagram in `cell.md` was also missing `CellStruct.jl`; it is now listed, since it is
load-bearing for the rationale above.

---

## Step 2 — Split `Document.jl` into one-concern files (pure motion) ✅ done

`Document.jl` is 703 lines holding five unrelated jobs. Split it *before* changing anything
in it, so the substantive steps that follow each land in one small file and review as one
idea. This mirrors the already-completed
[reference-layer-file-split](../done/reference-layer-file-split.md), and lands the document
layer at the cell layer's grain (7 files, ~90 lines each).

**Pure code motion.** Every line moves unchanged apart from section banners and the
per-file header docstring that AR-66 requires. No name added or removed.

Target layout:

| File | Content moved from | ~lines |
|---|---|---|
| `DocumentModule.jl` | aggregator: `using` / `export` / `include` list | 40 |
| `Document.jl` | `abstract type Document` + the selection contract (was `Interface.jl`) | 30 |
| `DocumentMacro.jl` | the `@document` macro | 260 |
| `DocumentKind.jl` | `_cell_kind_of`, `_same_cell`, `_declared_value_types`, `_kinded_value_type` | 50 |
| `DocumentCopy.jl` | `copy_document`, both arities | 90 |
| `DocumentSync.jl` | `sync_document!`, `_same_wrapper`, `_shadow_elem`, `_document_cell_kind` | 70 |
| `DocumentTrait.jl` | `is_element_collection`, `is_opaque` | 30 |
| `DocumentSearch.jl` | `search_documents` + `_search_documents!`, `_is_search_leaf`, `_search_text`, `_text_query`, `_deref_cell` | 110 |
| `DocumentShow.jl` | `Base.show(::Document)`, `DOCUMENT_SHOW_MAX_DEPTH` | 35 |
| `Forward.jl` | unchanged | 120 |

Notes:

- The old `Interface.jl` becomes `Document.jl` (the abstract type is the interface; a file
  named `Document.jl` that is *not* the module's namesake is the current confusion). The
  old 703-line `Document.jl` ceases to exist.
- Include order in `DocumentModule.jl`: `Document.jl` first (everything refers to the
  supertype), then `DocumentTrait.jl`, `DocumentKind.jl`, `DocumentCopy.jl`,
  `DocumentSync.jl`, `DocumentMacro.jl`, `DocumentSearch.jl`, `DocumentShow.jl`,
  `Forward.jl`.
- All fragments keep sharing `DocumentModule`'s namespace, so nothing is imported between
  them and the private helpers stay reachable exactly as today.

- [x] Create the files, move the code, add the header docstrings.
- [x] Rewrite `DocumentModule.jl`'s docstring: it currently names its "three fragments"
      explicitly and must now describe the new set.

**Verify:** `test_kernel_layering()`, `test_kernel()`.
**Commit:** `refactor: split the document layer into one-concern fragments`

### Deviation — no empty `DocumentWalk.jl` placeholder

The original table listed an empty `DocumentWalk.jl` for Step 4 to fill. Dropped: AR-50 says
*"a file nothing imports gets wired in or deleted before it gets a home — no orphan shapes
the structure"*, and an empty placeholder is exactly that orphan. Step 4 creates the file
when it has content to put in it.

Motion was verified mechanically, not by eye: the sorted set of top-level definitions across
the eight new fragments is identical to that of the two files they replace.

---

## Step 3 — Close the private-symbol leaks ✅ done

Two separate leaks, both AR-48 violations (imports name only exported symbols — the module
boundary *is* the API boundary).

### 3a. `unwrap_cell` — ten copies of one expression

`x isa AbstractCell ? x[] : x` is written out, by hand, in at least ten places:

| Where | As |
|---|---|
| `kernel/document/DocumentSearch.jl` (after Step 2) | `_deref_cell` |
| `kernel/reference/ReferenceStep.jl:23` | `_deref_cell` |
| `base/document/collection/CellVector.jl:71` | `_slotval` |
| `kernel/projection/Projection.jl:58` | `_force_output` |
| `kernel/operation/Operations.jl:400`, `kernel/selection/Selection.jl:218`, `base/projection/Searching.jl` (×2), `base/projection/higherorder/Chaining.jl:122`, `projectured/example/Catalog.jl:27` | inline |

The comment in `ReferenceSearch.jl` defends the duplication as cheaper than exporting an
internal. It isn't: unwrapping a cell-or-value is a *cell-layer concept* with exactly one
owning module (AR-65: every exported name has one owning module).

- [x] `cell/AbstractCell.jl`: define `unwrap_cell(x) = x isa AbstractCell ? x[] : x`,
      exported from `CellModule`, with a docstring saying it is the cell-or-value accessor
      (an untracked passthrough for a non-cell, a *tracked* read for a cell — worth stating,
      since it registers a dependency).
- [x] Replace all ten call sites; delete `_deref_cell` (×2), `_slotval`, `_force_output`,
      `_unwrap` (Catalog), and the inline copies.
- [x] Delete the comments that rationalized the duplication.

**Deliberate exclusion — `Copying.jl`'s `_unwrap`.** `base/projection/Copying.jl:43-44`
looks like an eleventh copy but is **not** the same function: it dispatches on `Cell`
(= `ReactiveCell{Any}`), not `AbstractCell`, so it leaves a `MutableCell` / `ImmutableCell`
field *wrapped* and hands the raw cell to `print_child`. Swapping in `unwrap_cell` would
silently change `CopyingProjection`'s behaviour for non-reactive-kind documents. Whether the
narrow dispatch is intentional or a latent bug is a real question — but it is a *different*
question, and this commit does not answer it by accident. Left alone; flagged here.

### 3b. The shadow-sync kit is a real protocol, not four internals

`base/document/Collection.jl:27` imports `_same_cell`, `_same_wrapper`, `_shadow_elem`, and
`_document_cell_kind` — four **non-exported** names — from `DocumentModule`, across a
package boundary, to implement `sync_document!(::CellVector, ::CellVector)`. That import is
the smell; the fix is not to hide it better but to admit that `CellVector`'s sync is a
legitimate consumer and the kit is therefore public.

- [x] Rename them to the naming law (AR-65: full words, `get_*` for getters) and export
      them from `DocumentModule`:
  - `_same_wrapper(a, b)` → `is_same_document_type(a, b)`
  - `_document_cell_kind(doc)` → `get_document_cell_kind(doc)`
  - `_shadow_elem(K, x)` → `copy_shadow_element(K, x)`
  - `_same_cell(c, v)` → `copy_cell_as(c, v)` (a fresh cell of `c`'s kind holding `v`)
- [x] `base/document/Collection.jl`: import the exported names.
- [x] `DocumentSync.jl` header: state that these four are the shadow-sync seam a
      collection type implements `sync_document!` against — the contract, not an internal.
      Each of the four gained a docstring; they are public API now.
- [x] Delete `_value_type` — **dead**: defined, never called anywhere.

**Verify:** `test_kernel()` 338/338, `test_base()` 82/82, `test_visual()` 51856/0 fail.
**Commit:** `refactor: give the cell-unwrap and shadow-sync helpers their owning module`

### Baseline correction — `test_domain()` is not green on `main`

`test_domain()` reports **125962 pass / 93 fail / 1 error / 15 broken**. That is **not** a
regression from this work: a worktree at pre-plan `main` (`d66fd442`) reports the *identical*
numbers, pass count included. Any future step in this plan must compare against
`125962/93/1/15`, not against zero, and must not "fix" those 93 by accident. (A stored note
claiming a "~13 failed" baseline was stale and has been corrected.)

---

## Step 4 — One walk, not two

`search_documents` (kernel `document/`) and `search_references` (kernel `reference/`) are
the same traversal, and the code says so out loud: *"The two walks are structurally
parallel; keep them in sync"* (`ReferenceSearch.jl:7`) and *"a fix to one branch here
should be mirrored there"* (`Document.jl:592`). A maintenance contract enforced by a
comment is a bug factory. Both duplicate the four-branch dispatch (element-collection /
dict / array / struct-fields), the `:ref`/`:selection` skip, the `maxdepth` bound, the
`try predicate catch` guard, the `reported` dedup, the `raw` folding, and — verbatim — the
`_is_search_leaf` / `_search_text` / `_text_query` helpers.

**They are not identical, and the difference is deliberate.** This is the trap a naive
merge falls into:

| | `search_documents` | `search_references` |
|---|---|---|
| Location of a node | the object itself | a `ReferencePath` |
| Cycle policy | one **global** `seen` → each object visited **once** (shared subtrees not re-walked) | **per-path** `seen`, copied per level, mutables only → **every distinct path** reported; only ancestor-loops dropped |
| Dict branch | iterates `values(obj)` | iterates pairs, uses the key as a `FieldReference` |
| Post-pass | none | `annotate_reference_types` |

So the walk must be parameterized by **both** the location type and the visit policy.

### Design

`DocumentWalk.jl` (document layer) declares the walk and its seam:

```julia
abstract type DocumentWalk end

# The location of `child`, reached from `location` by struct field / dict key `name`.
function child_field_location end     # (walk, location, name, child) -> location
# The location of `child`, reached from `location` at 1-based index `i`.
function child_element_location end   # (walk, location, i, child) -> location
# :once_per_object (shared subtrees walked once) | :once_per_path (every distinct path)
function visit_policy end             # (walk) -> Symbol

walk_document(walk::DocumentWalk, root, predicate;
              include_selection=false, maxdepth=64, raw=false) -> Vector
```

`walk_document` owns the entire traversal: the four-branch dispatch, the leaf test, the
depth bound, the enclosing-document tracking, the `reported` dedup, and the `raw` fold. It
calls the three seam functions and nothing else.

Two strategies implement it:

- `ValueWalk <: DocumentWalk` — **document layer**, in `DocumentSearch.jl`.
  `child_*_location` returns the child; `visit_policy` is `:once_per_object`.
  `search_documents(obj, pred; …) = walk_document(ValueWalk(), obj, pred; …)`.
- `PathWalk <: DocumentWalk` — **reference layer**, in `ReferenceSearch.jl`.
  `child_field_location` returns `append_reference(location, FieldReference(string(name)))`,
  `child_element_location` returns `append_reference(location, ElementReference(i))`;
  `visit_policy` is `:once_per_path`. `search_references` calls `walk_document(PathWalk(),
  …)` and then maps `annotate_reference_types` over the result, exactly as today.

The seam is what lets the walk live *below* the reference layer without naming
`FieldReference` / `ElementReference` (which it cannot — they are layer 3). This is the
standard AR-49 shape: the lower layer declares open generics, the higher layer adds
methods, and dispatch is the registration. **And it is the shape that survives item 1**:
once path syntax sinks below documents, `PathWalk` can move down beside `ValueWalk` and the
seam either collapses or stays as a two-strategy dispatch — no rework either way.

- [ ] `DocumentWalk.jl`: `DocumentWalk`, the three seam generics, `walk_document`, and the
      shared helpers `is_search_leaf` / `search_text` / `text_query` moved here from
      `DocumentSearch.jl` (they are walk vocabulary, not search vocabulary). Export the
      seam; keep the helpers module-internal — `PathWalk` needs only the seam.
- [ ] `DocumentTrait.jl` header: note that `is_element_collection` / `is_opaque` exist to
      let `walk_document` avoid naming concrete collection types. They are walk traits, and
      after Step 2 they finally sit next to the walk instead of in the middle of the copy
      code.
- [ ] `DocumentSearch.jl`: `ValueWalk` + `search_documents` over `walk_document`. Delete
      `_search_documents!`.
- [ ] `reference/ReferenceSearch.jl`: `PathWalk` + `search_references` over
      `walk_document`. Delete `_search_references!` and the duplicated helpers.
- [ ] Delete both "keep them in sync" comments — the obligation is gone, and a comment
      describing a contract the code no longer needs is exactly the noise AR-71 forbids.

**Verify:** the semantic difference in the table above is where a regression will hide.
Beyond `test_kernel()` and `test_base()`, hand-check in the REPL against a document with a
**shared subtree** (one node reachable by two paths) and against a **cyclic** graph (a
`ListNode` `prev`/`next` pair): `search_documents` must return the shared node **once**,
`search_references` must return **both** paths to it, and neither may hang. If no existing
test covers this, add one (AR-54) — the fact that the merge could silently break it is
itself the argument that it should have been tested all along.
**Commit:** `refactor: one document walk, two strategies — value and path`

---

## Step 5 — Factor `@document` into a plan and emitters

`@document` is one 260-line function that parses fields, injects `selection`, and then
inline-emits the parametric stem, the auto-wrapping inner constructor, the accessors, the
kind aliases, the typed kind constructors, the keyword constructors, Rule Y, Rule C, and
the exports. Nothing in it is independently testable: the only way to exercise Rule C is to
declare a struct and construct one.

Note what it shares with the cell layer, which already exports a codegen kit
(`cell_struct_exprs` / `cell_struct_kw_params` / `cell_struct_kwctor` /
`cell_struct_autowrap_ctor` / `cell_struct_property_accessors`):

- **The field-form parser is written twice, verbatim.** `cell_struct_exprs`
  (`CellStruct.jl:104-120`) and `@document` (`Document.jl:135-161`) both walk the struct
  body handling bare `f`, typed `f::T`, and defaulted `f[::T] = v`, and both strip the
  default into a `Pair` list.
- **Rule Y is not document-specific.** "Positional constructors that omit a trailing run of
  defaulted fields" is a rule about any cell struct with defaults.

### Design

- [ ] **Cell layer, new `cell/StructPlan.jl`** (fragment of `CellModule`): a `StructPlan`
      capturing what both macros need from a struct definition —

  ```julia
  struct StructPlan
      name          :: Symbol
      supertype     :: Any                  # expr, or nothing
      field_names   :: Vector{Symbol}
      field_types   :: Vector{Any}          # declared type expr, or :Any
      defaults      :: Dict{Symbol,Any}     # field => default expr
      order         :: Vector{Symbol}       # declaration order (defaults included)
  end
  struct_plan(structdef) -> StructPlan       # the one parser
  ```

  plus `required_count(plan)` / `trailing_default_count(plan)` (the `req` / `trailing`
  split Rule Y needs), and the generic Rule Y emitter
  `cell_struct_positional_ctors(plan, target_name)` moved down beside
  `cell_struct_kwctor`. Export the lot — `@document` is an out-of-module consumer, so they
  are public by AR-48.
- [ ] `cell_struct_exprs` consumes `struct_plan` instead of its own inline parser.
      **`@cell_struct` gains Rule Y for free** — it has no principled reason not to have
      it, and today it doesn't only because the rule was written on the document side.
      *(If this turns out to change an existing `@cell_struct` call site's dispatch, stop
      and reconsider: it may need to be opt-in. Check `Clock`, and every other
      `@cell_struct` in the repo, before committing.)*
- [ ] **Document layer, `DocumentMacro.jl`**: `@document` becomes
      `plan = struct_plan(structdef)` → append the `selection` field to the plan → call
      named emitters, each a pure function of the plan and each independently testable:

  | Emitter | Emits |
  |---|---|
  | `emit_document_stem(plan)` | the kind-parameterized immutable struct `Foo{C1<:AbstractCell,…}` |
  | `emit_autowrap_ctor(plan)` | the single inner constructor, with its two constant-parameter fast paths |
  | `emit_kind_aliases(plan)` | `RFoo` / `IFoo` / `MFoo` + the typed `IFoo`/`MFoo` ctors + `_declared_value_types` |
  | `emit_keyword_ctors(plan)` | the `Foo(;…)` / `IFoo(;…)` / `MFoo(;…)` trio, gated on `programmer_defaults > 0 \|\| declared_fields == 0` |
  | `emit_collection_ctors(plan)` | Rule C |
  | `emit_document_exports(plan)` | the four-name `export` |

  Rule Y is now `cell_struct_positional_ctors(plan, name)` from the cell layer.
- [ ] Keep the `@document` docstring exactly where it is (on the macro) — it is the single
      best explanation of the codegen in the repo and must not be scattered across the
      emitters. Each emitter gets a one-line docstring stating what it emits, no more.
- [ ] **Add unit tests for the emitters** in `package/kernel/test/document/` — the whole
      point of the refactor. `struct_plan` on each field form; `required_count` /
      `trailing_default_count` on a mixed struct; each emitter's output shape. Today none
      of this can be tested without declaring a struct.

### Known wart, recorded not fixed

Rule C detects its `CellVector` field by **matching the declared type's symbol**
(`ftype === :CellVector`, `Document.jl:327`) — a kernel-layer macro string-matching the
name of a type defined in the **base package**, one package up. It works only because the
name is unique, and it silently does nothing if a domain aliases the type. The honest fix
is a trait (`is_element_collection` already exists and means almost exactly the right
thing) resolved at expansion time — but a macro cannot call a runtime trait on a type that
does not exist yet, so this needs its own think. **Preserve the current behaviour, and
carry the wart into `emit_collection_ctors`'s docstring so the next reader knows it is
known.**

**Verify:** `test_cell()`, `test_kernel()`, then `test_base()` and `test_domain()` — every
domain document in the repo goes through this macro, so a codegen regression is broad and
loud. This is the step most likely to break something; run the wider sweep here even though
the plan otherwise says not to.
**Commit:** `refactor: factor @document into a struct plan and named emitters`

---

## Step 6 — Documentation and seals

- [ ] `package/kernel/doc/` — update any guide describing the document layer's file layout,
      the `@document` codegen, or the two searches.
      `package/kernel/doc/finding-and-selecting.md` is the one that documents
      `search_documents` / `search_references` as a pair; it should now be able to say
      *one walk, two strategies* instead of describing two parallel implementations.
- [ ] `documentation/architecture-requirements.md` — AR-45's Clock reference (Step 1); check
      whether any AR names a symbol renamed in Step 3.
- [ ] Seal inventory in [CLAUDE.md](../../CLAUDE.md) — the document layer's entry list is
      replaced wholesale by the Step 2 layout; `cell/StructPlan.jl` and `cell/Clock.jl`
      join the cell layer. Re-audit and re-seal each restructured file against
      [architecture-requirements.md](../../documentation/architecture-requirements.md).
- [ ] Move this plan to `plan/done/`.

**Commit:** `doc: document the restructured document layer; re-seal`

---

## Execution notes

- Work in a **dedicated git worktree**, not the main checkout — the user commits in the
  main checkout concurrently. `git add` explicit paths; never a pathless commit.
- One commit per step, in order. Steps 1 and 2 are risk-free (motion only); 3 is
  mechanical; 4 and 5 carry the real risk and each has a named regression to watch for.
- Mark each `[ ]` as you land it, and record any design decision that departs from the
  above **in this file** — the wart in Step 5 is the template.

## Not in scope

- **The layer inversion (item 1)** — reference-path syntax below documents. Its own plan;
  Step 4 is built to survive it.
- **Rule C's `:CellVector` symbol match** — recorded in Step 5, deliberately not fixed.
- `Forward.jl` — self-contained, correctly sized, correct where it is. Leave it alone.
