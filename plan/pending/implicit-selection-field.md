# Implicit selection field

> **Status: pending.** Make `@document` inject `selection::Reference = nothing`
> instead of every document struct declaring it by hand (278 repetitions today).

## Goal

`selection::Reference = nothing` is written out in **278** of the 293
`@document struct`s in the repo. Julia has no field inheritance, so the field
must be materialised per struct — but nothing says the *programmer* has to be the
one to write it. Move the obligation into the macro that already owns the
document contract.

After this plan, a document is declared as:

```julia
@document struct JsonBool <: JsonDocument
    value::Bool
end
```

and `selection::Reference = nothing` is appended by the macro as the last field.

## Decisions

Settled with the user before writing this plan — these are not open questions:

1. **Every document has a `selection`, defaulted to `nothing`.** The 99 structs
   that declare `selection::Reference` *without* a default are **bugs**, not a
   deliberate "required selection" design. They get the default.
2. **`Action` gains a selection field.** It is a document; it was an oversight,
   not an exception.
3. **`Clock` and the reference types move to `@cell_struct`.** They are not
   `Document`s and only ever wanted the transparent-cell codegen. This is what
   removes the need for any opt-out flag on `@document`.

## Facts established (audit, 2026-07-13)

- 293 `@document struct`s. **278** declare `selection`; **15** do not.
- The 15 are not a ragged exception list — they are exactly the three groups the
  decisions above address:
  - **10 reference types** — `RangeReference`, `FieldReference`, `TypeReference`,
    `EmptyReferencePath`, `ConcreteReferencePath` (`kernel/main/reference/Reference.jl`),
    `ProjectionReference` (`kernel/main/projection/ProjectionReference.jl`),
    `PointReference` (`visual/main/graphics/PointReference.jl`),
    `TextRectangularReference` (`visual/main/text/TextRectangularReference.jl`).
    They subtype `ReferenceStep` / `ReferencePath`, which are **standalone
    abstract types — not `<: Document`**. They use `@document` purely for cell
    codegen.
  - **`Clock`** (`kernel/main/document/Clock.jl:43`) — bare `@document struct`,
    so the macro defaults it to `<: Document`, which it never needed to be.
  - **`Action`** (`visual/main/widget/Widget.jl:1709`) — a genuine bug (decision 2).
- Of the 278: **179** declare `= nothing`, **99** declare `selection::Reference`
  bare (decision 1 — bugs).
- `selection` is the **last** field in 271 of 278. The 7 exceptions are all in
  `visual/main/widget/Widget.jl`: `WidgetCheckbox`, `WidgetButton`,
  `WidgetMenuItem`, `WidgetSplitPane`, `WidgetSwitch`, `WidgetTable`,
  `WidgetTree` — each has transient fields (`hovered`, `pressed`, `gestures`,
  `collapsed`, `active_splitter`, `drag_anchor`, `pinned`) declared *after*
  `selection`.
- **Nothing** in the repo uses the `R`/`I`/`M` kind aliases, or the parametric
  (`Foo{C1,…}`) form, of `Clock`, `Action` or any reference type. So dropping
  `@document`'s kind aliases / `_declared_value_types` / Rule Y / Rule C codegen
  for them (which `@cell_struct` does not emit) breaks nothing.

### Two constraints that shape the design

**Layering.** `Reference = Union{Nothing, ReferencePath}` is defined at
`kernel/main/reference/Reference.jl:161` — **layer 3**. `@document` lives in
`DocumentModule` — **layer 2**, which imports only from `CellModule`. So the
macro **cannot splice the `Reference` type object** the way `@domain` does
(base sits above kernel, so `@domain` may). It must emit the **bare symbol**
`Reference` into the escaped expansion, resolving in the *caller's* module.
This works because every calling module already has `Reference` in scope (they
all write `selection::Reference` today), and the static layering guard
(`test_kernel_layering`, `check_private_imports = true`) scans **imports**, not
symbols — so an escaped bare symbol keeps it green.

This is consistent with what layer 2 already asserts: `DocumentModule`'s own
docstring calls `Interface.jl` "the `Document` type + **selection-field
obligation**", and both `Base.show` and `search_documents` in
`document/Document.jl` already special-case the field *by name*. The layer
already knows `selection` exists; now it also creates it.

**The cell object is load-bearing.** `selection` cannot become a side table
(`IdDict{Document,Cell}`) or a computed property: projections wire the *cell
object* itself — `getfield(doc, :selection)` is passed into `set_function!` and
shared into child documents (e.g. `PrimitiveToSyntax.jl:48`,
`WidgetToGraphics.jl:2497`). It must stay a real field cell. (Side tables are
also unsound here: `@document` structs are **immutable**, so identity is
content-based, and construction-time cell sharing is a deliberate feature —
two documents sharing all their cells would be `===` and collide.)

## Risk: the 99 bare-`selection` structs newly trigger constructor codegen

This is the one hazard that makes this a refactor rather than a macro tweak.

`@document`'s keyword ctors, **Rule Y** (positional ctors that omit a trailing
run of defaulted fields) and **Rule C** (single-`CellVector` ctors) are emitted
**only when the struct declares ≥1 default**. The 99 bare-`selection` structs
have *zero* defaults today, so they get **none** of that codegen — which is
precisely why they carry hand-written outer constructors whose whole job is to
pass `nothing` for selection, e.g. `visual/main/syntax/Syntax.jl:203`:

```julia
SyntaxSeparation(children::Vector{<:SyntaxDocument}, separator::TextString) =
    SyntaxSeparation(CellVector(Cell[Cell(c) for c in children]), separator, nothing)
```

Giving `selection` a default flips all three rules on for those 99 structs.
Julia treats **method overwriting during precompilation as a fatal error**, so
any generated ctor whose signature is *exactly* a hand-written one is a hard
failure. (A *more specific* hand-written ctor — like the one above, whose
`::Vector{<:SyntaxDocument}` beats the generated untyped `Foo(a, b)` — merely
coexists, and is fine.) See the `document-macro-ruleY-guard-req1` memory: this
class of collision has already bitten once.

Two things follow:

- The colliding / now-redundant hand-written ctors must be **deleted**, not
  worked around. They are the same boilerplate one level down — the macro is
  taking over their job. This is a net cleanup, and it is the bulk of the diff.
- **A structural guard is not a load check** (memory: `guards-are-not-a-load-check`).
  Every step must be verified with a real `using`, not just `Pkg.precompile`
  exit codes.

## Steps

Work in a dedicated git worktree. Commit per step; each step must load green.

### Step 1 — Move the non-documents to `@cell_struct` — ✅ DONE

`@cell_struct` (`kernel/main/cell/CellStruct.jl:178`) already emits exactly what
these types need: `::Cell` fields, the auto-wrapping inner ctor, transparent
accessors, and a keyword ctor when defaults are present. It does **not** inject a
supertype, kind aliases, or Rule Y/C ctors — none of which these types use.

- [x] `Clock` (`kernel/main/document/Clock.jl:43`) → `@cell_struct`. It stops
      being `<: Document`. Bonus: `clock::Clock` in `Editor.jl:54` and
      `PrinterContext.jl:53` becomes a **concrete** field type (today it is the
      `Clock{…}` UnionAll, i.e. abstract).
- [x] The 8 reference types → `@cell_struct` (5 in `reference/Reference.jl`,
      plus `ProjectionReference`, `PointReference`, `TextRectangularReference`).
      They keep their declared `<: ReferenceStep` / `<: ReferencePath` supertypes.
- [x] Exports: **no change needed** — `ReferenceModule.jl:45-54` and
      `ClockModule` (`Clock.jl:32`) already export their type names explicitly,
      so losing `@document`'s auto-export costs nothing.
- [x] Verified: `test_kernel()` 338/338 (incl. `test_kernel_layering()`),
      `test_base()` 82/82, `test_visual()` 51850 pass / 1 broken,
      `test_domain()` 132976 pass / 1 error / 15 broken — the single domain
      error (`TableNavigationTest`, "individual moves (3×3 with headers)",
      a `SelectionMismatch` on `RWidgetTable`) **reproduces identically on clean
      `main`**: it is the known pre-existing "table Alt+arrow" failure, not a
      regression.

**Discovered during implementation.** `@cell_struct` emits `Cell` as a **bare
symbol** resolved in the caller's scope (it does *not* splice the type object the
way `@document` splices its cell types), so every module that switches to it must
also `import ..CellModule: Cell`. `ReferenceModule` already did; `ClockModule`,
`ProjectionReferenceModule`, `PointReferenceModule` and
`TextRectangularReferenceModule` each needed `Cell` added to their import. This is
the same call-site-resolution mechanism step 2 relies on for `Reference`, so it is
a useful confirmation that the approach works.

Also: `Clock`'s only uses are as a field of `Editor` (a plain `mutable struct`)
and `PrinterContext` (a plain `struct`) — **no `@document` struct holds a
`Clock`** — so `copy_document` / `sync_document!` never walked into it, and it
losing `Document` status changes nothing for them.

### Step 2 — `@document` injects the field — ✅ DONE

- [x] In `@document` (`kernel/main/document/Document.jl`), after the field walk,
      append `selection::Reference = nothing` **when the body does not already
      declare `selection`**.
      - Emits the **bare symbol** `Reference` (see *Layering* above), not the
        spliced type object. Confirmed correct by step 1: `@cell_struct` emits
        its `Cell` type the same way.
      - Appended **last** and always defaulted, so it lands in Rule Y's trailing
        run and a document's own fields keep the arity they had without it.
      - "Explicit declaration wins" is the migration escape hatch; step 8 flips it
        to an error.
- [x] The `isempty(cell_fields) && return esc(structdef)` early return is now
      **dead** (injection guarantees ≥1 field) and was removed. A zero-field
      `@document struct Foo end` is now a one-field struct holding just its
      selection — which is exactly what e.g. `JsonNull` wants.
- [x] `@document`'s docstring documents the injected field and points types that
      are *not* addressable content at `@cell_struct`.
- [x] Verified as a no-op: `test_kernel()` 338/338, `test_base()` 82/82,
      `test_visual()` 51856 pass / 1 broken, `test_domain()` 132976 pass /
      1 pre-existing error / 15 broken.

### Step 5 — `Action` gains a selection field — ✅ DONE (by step 2)

- [x] `Action` (`visual/main/widget/Widget.jl`) was the only *real* `@document`
      struct in the repo with no `selection` field, so step 2's injection gave it
      one with no edit: its fields are now
      `(:label, :icon, :enabled, :shortcut, :callback, :selection)`. This is
      visible in the suite — `test_visual()` went from 51850 to **51856** passes
      (0 fail / 0 error): six assertions that previously could not hold for a
      selection-less document now do.
- [x] Confirmed no `@document` struct anywhere is left without a selection. (A
      scan reports five more names — `JsonNothing`, `JsonInsertion`, `gets`, `T`,
      `Foo` — but these are *docstring examples* inside `DomainSupport.jl` and
      `Document.jl`, not real declarations.)

### Steps 3 + 6 — Delete all 271 remaining declarations — ✅ DONE

Steps 3 and 6 **collapsed into one**: since the injected field is appended last
*and* defaulted, deleting a `selection::Reference` line from a struct where it was
already last leaves the field layout byte-identical. So "give it a default" and
"delete the declaration" are the same edit. 271 declarations removed from 47 files;
zero remain.

- [x] 271 declarations deleted (the 7 reordered widgets were done in step 4).
- [x] The newly-triggered constructor codegen was resolved. **The load is the
      oracle for collisions** — Julia makes method overwriting during
      precompilation a *fatal error*, so every exact-signature clash surfaced
      loudly, one per precompile. The fixes split into two shapes:
  - **A hand-written zero-arg `Foo()`** (`CellVector`, `CellMatrix`, `CellTable`,
    `GraphicsCanvas`, `ScreenDocument`, the four `XLayout(; kwargs...)` shims, the
    four `WidgetX(; kwargs...)` shims, `TextNewline`, `WindowDocument`). The honest
    fix is to **hoist the values that constructor was hard-coding into field
    defaults** and delete it — the macro's keyword constructor then *is* that
    constructor. This is a real improvement: `CellVector()` now means "elements
    default to empty", stated on the field.
  - **A redundant `Foo(a, b) = Foo(a, b, nothing)`** (`PrimitiveBool/Number/String`,
    `ImageMemory`, `ImageFile`, `WidgetAccordionItem`, `WidgetTabPage`,
    `SyntaxNavigation`, `DatabaseInstance`, `VersionProperties`). Deleted — Rule Y
    now generates exactly these.
- [x] Verified green, **identical to baseline**: `test_kernel()` 338/338,
      `test_base()` 82/82, `test_visual()` 51856 pass / 1 broken, `test_domain()`
      132976 pass / 1 pre-existing error / 15 broken.

**Two hazards found during implementation that the plan had not called out:**

1. **Rule Y can *silently shadow* a variadic** — no error, just wrong behaviour.
   With `elements` required and `selection` defaulted, `CellVector` would have had
   Rule Y emit an untyped 1-arg `CellVector(x)`, which is *more specific* than the
   hand-written variadic `CellVector(items...)` and would have silently changed
   `CellVector(doc)` from "a one-*element* vector" to "elements = doc". Defaulting
   `elements` drives `req` to 0, which suppresses Rule Y entirely and keeps the
   variadic in charge. The file's own comment already warned about this arity
   confusion.

2. **The generated keyword constructor is zero-*positional*, so it claims the
   `Foo(; …)` signature** — and would collide with any hand-written keyword
   constructor that does more than fill fields. `WorkbenchAssistant` back-links its
   draft (`draft.assistant = a`) and `DatabaseCredentials` coerces its arguments;
   neither can be expressed as field defaults. Tellingly, `WorkbenchAssistant` and
   `VersionProperties` both carried the comment *"to avoid a zero-arg ctor clash"* —
   their bare `selection` was a **workaround for exactly this**, which is why it was
   on the bug list.

   **Resolution (a macro change):** the injected `selection` no longer counts as a
   default *for keyword-constructor generation*. Keyword ctors are emitted when the
   **programmer** declared ≥1 default (or the struct declares no fields at all — see
   below). Rule Y and Rule C *do* still count it, since filling a trailing default
   positionally is precisely their job, and that is what retires the
   `Foo(a, b) = Foo(a, b, nothing)` boilerplate. So injection is non-invasive to the
   keyword surface: a struct that needs to own `Foo(; …)` simply declares no
   defaults.

   The **no-declared-fields exception** is load-bearing: `JsonNull` (and every
   `@domain` placeholder) holds nothing but its selection, so `JsonNull()` cannot
   come from Rule Y (`req == 0`) and there is no hand-written keyword constructor to
   protect. Those structs still get the generated one.

### Step 4 — The 7 widget structs: `selection` moves to last

- [ ] In `visual/main/widget/Widget.jl`, drop the explicit `selection` from
      `WidgetCheckbox`, `WidgetButton`, `WidgetMenuItem`, `WidgetSplitPane`,
      `WidgetSwitch`, `WidgetTable`, `WidgetTree`; the injected field lands after
      their transient fields.
- [ ] Reorder the positional forwards in their hand-written keyword ctors
      accordingly (e.g. `WidgetSwitch` at `Widget.jl:1224-1227` forwards all 9
      cells positionally). **No caller constructs these positionally**, so the
      change is contained to those ctor bodies.
- [ ] Field order is otherwise inert: it is only ever used for positional
      construction. `FieldReference` addresses by *name*, `copy_document` /
      `sync_document!` / `show` iterate `fieldnames`, and
      `_declared_value_types` is positional but internally consistent.

### Step 5 — `Action` gains a selection field

- [ ] `Action` (`visual/main/widget/Widget.jl:1709`) — nothing to write; once
      step 2 is in and it stays on `@document`, it simply gets the field.
      Confirm it is genuinely a document (it is `@document struct Action` with no
      supertype, so `<: Document`).

### Step 6 — Delete the 278 declarations

- [ ] Remove the explicit `selection::Reference[ = nothing]` line from all 278
      structs, file by file, loading as you go.
- [ ] Remove the per-type docstring bullets that spell out
      `- selection::Reference — a ReferencePath or nothing (stored in a Cell)`
      (Syntax.jl alone has ~8). The macro's docstring documents it once.

### Step 7 — `@domain` stops hand-writing the field — ✅ DONE

- [x] `@domain` (`base/main/document/Domain.jl`) hand-built the `XNothing` /
      `XInsertion` struct defs *including* a `selection` field and fed them to
      `@document`. Dropped from both `ndef` and `idef` — otherwise the generated
      types would get a **duplicate field**. `XNothing` is now an empty struct body;
      it holds nothing but its injected selection.
- [x] `Reference` dropped from `Domain.jl`'s imports — the macro no longer splices
      the type, and nothing else in that module names it.
- [x] `XInsertion` keeps its hand-written `XInsertion(value::AbstractString)`:
      `value` and `selection` both default, so `req == 0` and Rule Y emits nothing.
- [x] Verified: `JsonNothing` has fields `(:selection,)`, `JsonInsertion` has
      `(:value, :selection)`, and `JsonNothing()` / `JsonInsertion("js")` /
      `JsonInsertion()` all work.

### Step 8 — Enforce and document — ✅ DONE

- [x] The step-2 escape hatch is now an **error**: `@document` rejects a body that
      declares `selection`, pointing at `@cell_struct` for types that should not
      carry one. Decision 1 says a hand-written selection field is a bug, so it is
      now unrepresentable rather than merely discouraged. (This also closes the
      `WorkbenchAssistant` workaround for good — a bare `selection` can no longer be
      used to suppress the keyword constructors.)
- [x] `@document`'s docstring documents the injected field, the `@cell_struct`
      alternative, and the keyword-constructor gate.
- [x] Prose docs updated: `package/kernel/doc/document.md` (contract #1 is now a
      macro *guarantee*, not an author obligation), `package/kernel/doc/macros.md`
      (the example no longer writes the field; the expansion still shows it),
      `package/kernel/doc/reference.md` (steps/paths are `@cell_struct`-backed),
      `documentation/tutorial-new-domain.md`, `documentation/concepts.md`,
      `documentation/vision.md`, `package/base/doc/collection.md`,
      `package/domain/doc/json.md`, `package/domain/doc/workbench.md`,
      `CONTRIBUTING.md`.
- [x] Per-type docstrings cleaned: the `- selection::Reference — a ReferencePath or
      nothing` bullets removed (8 of them), and the two abstract-base docstrings that
      said a concrete type "must have a `selection::Reference` field" reworded — that
      is now the macro's job, not the author's.
- [x] `documentation/architecture-requirements.md` needed no change: it never stated
      the selection field as an author obligation.

## Verification

Per the repo's testing guidance, run the narrowest test that covers each step,
not `test_all()`:

- Step 1: `test_kernel()` (bundles `test_kernel_layering()`).
- Steps 3–6, per package touched: `test_base()`, `test_visual()`, `test_domain()`.
- A real `using` after every step — a green precompile exit code is not a load
  check.
- Only once the targeted suites are green: one `test_all()` sweep, compared
  against the `test-suite-green-baseline` memory (~13 known failures, 0 errors).
  Any *new* `Fail`/`Error` is a regression from this work.

## Audit table — hand-written ctors to delete in step 3

_(To be filled in from the constructor-collision audit; see the audit agent's
report. Structure: per file — (A) structs to change, (B) exact-signature
collisions that are fatal at precompile, (C) redundant ctors to delete,
(D) structs where `selection` is not last.)_
