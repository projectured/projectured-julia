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

### Step 1 — Move the non-documents to `@cell_struct`

`@cell_struct` (`kernel/main/cell/CellStruct.jl:178`) already emits exactly what
these types need: `::Cell` fields, the auto-wrapping inner ctor, transparent
accessors, and a keyword ctor when defaults are present. It does **not** inject a
supertype, kind aliases, or Rule Y/C ctors — none of which these types use.

- [ ] `Clock` (`kernel/main/document/Clock.jl:43`) → `@cell_struct`. It stops
      being `<: Document`. Bonus: `clock::Clock` in `Editor.jl:54` and
      `PrinterContext.jl:53` becomes a **concrete** field type (today it is the
      `Clock{…}` UnionAll, i.e. abstract).
- [ ] The 10 reference types → `@cell_struct`. They keep their declared
      `<: ReferenceStep` / `<: ReferencePath` supertypes.
- [ ] `@cell_struct` does **not** export the struct name (`@document` does).
      Add explicit `export`s where these names were relying on the macro.
- [ ] Verify by loading, and run `test_kernel()` (includes `test_kernel_layering()`).

### Step 2 — `@document` injects the field

- [ ] In `@document` (`kernel/main/document/Document.jl:94`), after the field
      walk, append `selection::Reference = nothing` **when the body does not
      already declare `selection`**.
      - Emit the **bare symbol** `Reference` (see *Layering* above), not the
        spliced type object.
      - Append it **last** — this matches 271/278 structs and is what makes it
        land in Rule Y's trailing-defaults run.
      - The "explicit declaration wins" escape hatch is what makes the migration
        incremental: steps 3–6 can then delete declarations file by file, each
        commit loading green.
- [ ] Verify by loading. At this point *nothing* has changed semantically — every
      struct still declares its own field — so the whole suite must stay green.

### Step 3 — The 99 bare `selection::Reference` → `= nothing`

The risky step. Do it in small batches (by file), loading after each.

- [ ] Add `= nothing` to the 99 bare declarations.
- [ ] Delete the hand-written ctors the macro now generates (the exact-signature
      collisions **and** the merely-redundant `Foo(a, b) = Foo(a, b, nothing)`
      forms). See the audit table appended below.
- [ ] Watch for the three newly-triggered codegen paths per struct: the
      `Foo`/`IFoo`/`MFoo` **keyword** ctors (keyword-only, zero positional — so
      they collide with a hand-written `Foo(; …)`, but *not* with a
      `Foo(x; …)`), **Rule Y**, and — for a struct that is a single `CellVector`
      plus `selection` — **Rule C**'s variadic `Foo(items::Document...)`.

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

### Step 7 — `@domain` stops hand-writing the field

- [ ] `@domain` (`base/main/document/DomainSupport.jl:371`) hand-builds the
      `XNothing` / `XInsertion` struct defs *including* a `selection` field
      (lines 407-418) and feeds them to `@document`. Drop `selection` from both
      `ndef` and `idef` — otherwise the generated types get a **duplicate field**.
- [ ] `XInsertion` currently needs a hand-written `XInsertion(value::AbstractString)`
      because "a fully-defaulted `@document` struct gets no positional
      constructors" (Rule Y's `req ≥ 1` guard). That stays true — `value` and
      `selection` both default — so keep it.

### Step 8 — Enforce and document

- [ ] Flip the step-2 escape hatch into an **error**: `@document` should reject a
      body that declares `selection` explicitly ("`selection` is injected
      automatically; remove the explicit field"). Decision 1 says a hand-written
      selection field is a bug — make it unrepresentable rather than merely
      discouraged.
- [ ] Update `@document`'s docstring (it enumerates what the macro generates) and
      `package/kernel/doc/macros.md`.
- [ ] Update `documentation/architecture-requirements.md` if it states the
      selection-field obligation as a rule the *author* must follow.

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
