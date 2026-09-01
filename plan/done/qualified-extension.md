# Qualified extension: `using ..X` + `X.f(...)`, never `import ..X: f`

## Outcome

Phases 0, 1, 2 and 4 are **done**; Phase 3 (the remaining non-projection seams) is left as the
follow-up, together with the deferred projection-generic sweep.

The rule is now **PAR-QUALIFIED-EXTENSION**, and it is machine-checked three ways: the compiler rejects an
unqualified extension after `using`, `qualified_reference_errors` keeps qualification inside the
export list (PAR-MODULE-BOUNDARY-IS-API's other half), and `relative_import_errors` holds an opt-in `qualified_files`
set to the import form. `test_export_collisions` (umbrella) guards the precondition that makes
bare `using` safe.

Seven files migrated: the reference-step seam (`ProjectionReference.jl`, `PointReference.jl`,
`TextRectangularReference.jl`) and the backend/device seam (`HeadlessBackend.jl`, `Console.jl`,
`ProjecturedSdl.jl`, `ProjecturedWeb.jl`). Verified by loading the full stack — including the
native SDL backend — not just by the guards: kernel 425/425, visual 51858 (0 fail, 1 pre-existing
`@test_broken`), ConsoleBackend 36/36, SDL 30/30, and the four layering guards green.

Two things the plan got wrong, both corrected in place below: a bare `using` of a module **alias**
binds the module's *real* name (so every backend qualifies as `BackendModule.…`, which is better
than assumed), and `ProjectionReference.jl` turned out to implement **five** reference seams, not
four (`dsl_step_subpath_args`).

## Problem

Today a module that wants to add methods to another module's generic writes:

```julia
import ..ReferenceModule: ReferenceStep, step_kind, evaluate_step, dsl_build_step, dsl_match_step
```

That single line conflates two unrelated things: `ReferenceStep` is a type this file merely
*references*, while the other four are generics this file *implements*. Nothing at the
definition site says which is which — `function step_kind(s::PointReference)` reads exactly
like a fresh local definition.

Three consequences:

1. **The new-vs-extend distinction is invisible.** A reader cannot tell, at a definition
   site, whether the file is participating in another layer's contract (PAR-FRAMEWORKS-SINK's *"multiple
   dispatch is the registration"*) or just defining a helper. The architecture's central
   registration mechanism is unmarked in the source.
2. **Silent accidental extension.** `print_document` is imported into ~200 files. A local
   helper coincidentally named `print_document` does not shadow the generic — it *adds a
   method to it*, with no diagnostic. Julia only protects against this when the name was
   brought in with `using`.
3. **Julia is deprecating the implicit path anyway.** On 1.12, extending a `using`-imported
   type's constructor without qualification already warns: *"This behavior is deprecated and
   may differ in future versions."*

The codebase already applies the fix at the `Base` boundary — there is not one `import Base:`
anywhere; it is all `function Base.show(io::IO, s::PointReference)`. Only the internal-module
case is inconsistent.

## The rule (new **PAR-QUALIFIED-EXTENSION**)

One import form, one extension form:

| Form | Meaning |
|---|---|
| `using ..X` | this file references X — bare, **never** a symbol list |
| `X.f(...) = ...` at the definition site | this file **extends** X's generic `f` |
| `import ..X: f` | **banned** |
| `import ..X` | **banned** (bare `using` already binds the module name) |

Bare `using ..X` binds the module name `X` *and* brings X's exported symbols into scope, so
one line serves both roles. No symbol lists — they are noise, and the export list is already
the module's declared API surface (PAR-MODULE-BOUNDARY-IS-API).

**Qualification is for cross-module extension only.** A file that is a *fragment of the
defining module* (`reference/ReferenceStep.jl`, `reference/ReferenceBuilder.jl`,
`reference/ReferenceCase.jl` — all included into `ReferenceModule`, none of which has an
import header at all) defines bare and is untouched. This matches PAR-MODULE-BOUNDARY-IS-API's "fragments of one
module" carve-out: same namespace by construction, so nothing is imported and nothing is
qualified.

## Semantics verified up front

Confirmed against the real Julia in this environment, not assumed:

- **Bare `using ..X` binds `X`.** `X.f(y::Int) = ...` then extends X's generic. (A symbol-list
  `using ..X: f` does *not* bind `X` — this is why the bare form is load-bearing, not just a
  taste preference.)
- **The compiler enforces the rule for us.** After `using ..X`, a bare `f(y::Int) = ...` is a
  hard error: `invalid method definition in User: function X.f must be explicitly imported to
  be extended`. This makes the migration mechanical — flip a header to `using`, and the
  compiler enumerates every extension site that needs qualifying. It also makes consequence
  (2) above structurally impossible afterwards.
- **Export collisions fail loudly.** Two bare-`using`'d modules exporting the same name give
  `UndefVarError` **on use**, not a silent pick. Detectable at load/test time, not a lurking
  hazard. (This is the main new risk the bare form introduces — see Risks.)
- ~~**Module aliases work.** Files may qualify through whatever alias they already name.~~
  **Wrong — corrected during Phase 2.** A bare `using` of an alias binds the module's *real*
  name, not the alias: `using ..BackendApiModule` (a `const` alias for
  `ProjecturedKernel.BackendModule`) binds `BackendModule`. The original claim holds for
  `import ..Alias: syms` but not for the bare form, and `Console.jl` failed to load until its
  extension sites named `BackendModule`. The outcome is *better* than assumed: every backend in
  the repo now registers under one canonical `BackendModule.initialize_backend!`, whichever
  alias path its package uses to reach the contract.
- **Macros get strictly cleaner.** A macro can emit an extension by interpolating the *Module
  object* — `:(function $(ReferenceModule).step_kind(...) end)` — so the call site needs no
  import of the generic at all. Verified working with the caller importing nothing. This
  removes a hidden coupling from `@document`/`@projection`/`@iomap` rather than adding one.

## The one real cost: PAR-MODULE-BOUNDARY-IS-API loses coverage unless the guard is extended

`check_private_imports` in [package/kernel/test/layering/CheckLayering.jl](../../test/kernel/layering/CheckLayering.jl)
collects imported symbols only from the `import X: a, b` form (the `:(:)` head, ~L85).

Qualification **bypasses exports entirely** — verified: `X.internal_helper()` reaches a
non-exported name with no error. So the moment we encourage qualification, PAR-MODULE-BOUNDARY-IS-API ("imports name
only exported symbols — the module boundary *is* the API boundary") stops being enforced
precisely at the sites that matter most.

**This must be closed in the same change, before the sweep, not after.** The guard needs a new
pass that scans qualified references `X.sym` in package source and asserts `sym ∈ exports(X)`.

Good news on layering: the guard's module-path extraction (~L68,
`path = (arg isa Expr && arg.head === :(:)) ? arg.args[1] : arg`) already handles the bare
non-colon form, so bare `using ..X` still records the dependency edge. The layer DAG check
survives untouched.

## Scope: what this plan does NOT do

**The four projection generics are explicitly out of scope for now.**

| generic | extension sites |
|---|---|
| `read_intent` | 253 |
| `print_document` | 206 |
| `map_reference_forward` | 169 |
| `map_reference_backward` | 165 |
| **total** | **~793** |

That is ~40% of the 2078 top-level method definitions in the repo, and it is entangled with
`@projection` / `@projection_template` / `@iomap` codegen. It gets its own follow-up plan once
the rule and the guard have proven themselves on a small surface.

## Blast radius of bare `using` — measured, not guessed

The obvious objection to dropping symbol lists is that bare `using` dumps every export of every
used module into scope, so same-named exports collide. Measured against the real loaded stack
(`ProjecturedKernel` + `Base` + `Visual` + `Domain`, 190 modules):

- **14** names are exported by more than one module.
- **13 of those 14 are re-exports** — the *same binding object* reached through several module
  names (`evaluate_operation` is one function visible through `OperationModule`,
  `OperationApiModule`, `OperationRerootingModule` and `WidgetModule`; `set_function!` through
  8 modules; the whole `Inset`/`Point2D`/`inset_*` family through `GeometryModule` and
  `WidgetModule`). Verified: Julia raises an ambiguity error only when the bindings **differ** —
  `using A, B` where both export the *same* binding resolves cleanly. These are not collisions.
- **1 real collision** exists in the entire codebase.

### The one real collision: `NothingToSyntaxLeaf`

Two genuinely different projections share one exported name:

| | |
|---|---|
| [package/visual/main/syntax/ObjectToSyntax.jl:37](../../package/visual/main/syntax/ObjectToSyntax.jl#L37) | `@projection struct NothingToSyntaxLeaf` — renders a Julia `nothing` value (regular font, magenta) |
| [package/domain/main/insertion/InsertionToSyntax.jl:493](../../package/domain/main/insertion/InsertionToSyntax.jl#L493) | `struct NothingToSyntaxLeaf <: Projection` — renders the `*Nothing` **insertion placeholder** (italic, gray) |

It is **latent, not active**: no file currently names both modules (checked — none of
`JsonToSyntax` / `XmlToSyntax` / `YamlToSyntax` / `SqlToSyntax`, which import the insertion one,
mentions `ObjectToSyntaxModule`). Under bare `using` it stays harmless *until* some file needs
both, at which point it fails loudly with `UndefVarError` on use.

This is an PAR-MODULE-BOUNDARY-IS-API smell independent of this plan — two modules publishing the same name for
different concepts — and the insertion module's own export list already shows the fix: every
sibling is prefixed (`DocumentInsertionToSyntaxLeaf`, `DomainInsertionToSyntaxLeaf`,
`JuliaInsertionToSyntaxLeaf`, `SqlInsertionToSyntaxLeaf`); `NothingToSyntaxLeaf` is the lone
unprefixed odd-one-out. The more-specific concept takes the qualifier.

**Verdict: the risk that motivated this check is not real. Proceed.**

## Phase 0 — clear the one collision (prerequisite)

- [x] Rename the insertion placeholder to `InsertionNothingToSyntaxLeaf`, matching its four
      prefixed siblings in the same export list. ~8 sites: the declaration + inner constructor +
      `print_document` method in `InsertionToSyntax.jl`, its export line, and the
      `import ..DocumentInsertionToSyntaxModule: …, NothingToSyntaxLeaf` header plus one use site
      in each of `JsonToSyntax.jl`, `XmlToSyntax.jl`, `YamlToSyntax.jl`, `SqlToSyntax.jl`.
      (Alternative, rejected: rename the visual one — it holds the generic name legitimately.)
- [x] Verify with `test_json()` / `test_xml()`; commit. **Done** — 12 sites (not 8); `test_json`
      24/24, `test_json_to_syntax` 11/11, `test_xml_to_syntax` 7/7, `test_sql_to_syntax` 19/19.
      The collision sweep then reported **0** real collisions across the stack.

## Phase 1 — teach the guard (do this first)

- [x] Add `qualified_reference_errors` to `CheckLayering.jl`: walk each file's AST for
      `Expr(:., X, QuoteNode(sym))` where `X` resolves to a sibling/lower module, and assert
      `sym ∈ exports(X)`. Restores PAR-MODULE-BOUNDARY-IS-API at qualification sites.
- [x] Add a lint forbidding the `import ..X: f` and bare `import ..X` forms — `relative_import_errors`. Stage it: allow a
      grandfathered file list initially, shrink it to empty as the sweep proceeds. Without the
      grandfather list the guard goes red on ~1400 existing lines on day one.
- [x] Confirm bare `using ..X` still produces the correct layer edge (expected — L68 handles it —
      but assert it with a test rather than trusting the read).
- [x] Commit.

## Phase 2 — pilot: the two small PAR-INTERFACE-DECLARES-ONLY interface seams

Both are declared in interface files (PAR-INTERFACE-DECLARES-ONLY), both cross package boundaries, and together they
are ~26 sites across **7 files**. This is the "small blast".

### Reference-step seam — declared in `kernel/main/reference/Interface.jl`

Generics: `step_kind`, `evaluate_step`, `dsl_build_step`, `dsl_match_step` (18 sites).

Files to convert (cross-module only):

- [x] [package/kernel/main/projection/ProjectionReference.jl](../../package/kernel/main/projection/ProjectionReference.jl) — `import ..ReferenceModule: step_kind, evaluate_step, …`
- [x] [package/visual/main/graphics/PointReference.jl](../../package/visual/main/graphics/PointReference.jl) — the exemplar line that conflates `ReferenceStep` (referenced) with four generics (implemented)
- [x] [package/visual/main/text/TextRectangularReference.jl](../../package/visual/main/text/TextRectangularReference.jl)

Untouched (same-module fragments of `ReferenceModule`, no import header): `ReferenceStep.jl`,
`ReferenceBuilder.jl`, `ReferenceCase.jl`.

### Backend seam — declared in `kernel/main/backend/BackendInterface.jl`

Generics: `initialize_backend!`, `quit_backend!` (8 sites). Note these files also import
`measure_text` / `write_image` on the same line — same treatment.

- [x] [package/kernel/main/backend/HeadlessBackend.jl](../../package/kernel/main/backend/HeadlessBackend.jl) — via `..BackendModule`
- [x] [package/visual/main/backend/Console.jl](../../package/visual/main/backend/Console.jl) — via `..BackendApiModule` (alias)
- [x] [package/sdl/main/ProjecturedSdl.jl](../../package/ProjecturedSdl/src/ProjecturedSdl.jl) — via `ProjecturedDomain.BackendApiModule`
- [x] [package/web/main/ProjecturedWeb.jl](../../package/ProjecturedWeb/src/ProjecturedWeb.jl) — via `ProjecturedDomain.BackendApiModule`

### Method

For each file: flip the header to bare `using`, let the compiler enumerate the extension sites
(`function X.f must be explicitly imported to be extended`), qualify each one, reload. Commit
per seam.

Verification: `test_kernel()` and `test_visual()` for the reference seam; a real load of the SDL
stack for the backend seam (per the *guards-are-not-a-load-check* lesson — a green guard plus a
clean `Pkg.precompile` exit code does **not** prove `using` works).

## Phase 3 — the remaining non-projection seams (NOT DONE — the follow-up)

Deliberately left. Phase 2 proved the rule and exercised the guards on 7 files; the rest is a
mechanical sweep that should ride on its own plan, together with the deferred projection
generics. `evaluate_operation` is the natural next one — and note SDL already imports it, so
SDL's header is only *partly* migrated today (its backend/device contracts are bare-`using`,
its `print_document` / `evaluate_operation` imports are untouched by design).

- [ ] `evaluate_operation` — 46 sites / 14 files, declared in `operation/Interface.jl`. The
      largest non-projection seam; likely deserves its own commit.
- [ ] `write_to_devices` — 6 sites, declared in `device/Device.jl`.
- [ ] `copy_document` (10), `sync_document!` (2), `collect_gesture_bindings` (9),
      `get_projection_gesture_bindings` (7).
- [ ] Sweep the remaining `import ..X: …` headers that import *only* types/values (no
      extension) — these are pure `using` conversions with no qualification needed, so they are
      mechanical and can be delegated.
- [ ] Shrink the guard's grandfather list to empty for every layer reached.

## Phase 4 — write the rule down

- [x] Add **PAR-QUALIFIED-EXTENSION** to [documentation/architecture-requirements.md](../../documentation/rule/architecture-invariants.md)
      (72 is the current highest), stating the table above, the same-module-fragment carve-out,
      and the reason: the compiler can only distinguish "new function" from "extension of
      another layer's contract" if the name arrives via `using`. Cross-reference PAR-MODULE-BOUNDARY-IS-API
      (imports name only exported symbols — now also enforced at qualification sites), PAR-FRAMEWORKS-SINK
      (multiple dispatch is the registration — now visible at every site), and PAR-INTERFACE-DECLARES-ONLY (interface
      files declare the generics being extended).
- [x] Note the deferred projection-generic migration as a known remaining instance, in the style
      of PAR-MODULE-BOUNDARY-IS-API's `PlaybackModule` note. PAR-MODULE-BOUNDARY-IS-API also gained a cross-reference: an import header is
      only half the boundary, and `qualified_reference_errors` closes the other half.

## Risks

- ~~**Export collisions from bare `using`.**~~ **Measured and cleared** — see *Blast radius*
  above. Exactly one real collision exists in the whole stack, it is latent, and Phase 0 removes
  it. Re-exports (13 of the 14 candidates) are not collisions. Should a *new* collision ever
  arise, it fails loudly (`UndefVarError` on use, never a silent pick); the fix is to rename the
  more-specific concept, not to reintroduce a symbol list.
- **Signature length.** `function ReferenceModule.step_kind(s::PointReference)` is ~18 chars
  longer. Accepted: the explicitness is the point.
- **Guard grandfather list rots.** If Phase 3 stalls, the list becomes a permanent exemption.
  Mitigate by keeping it a literal file list in the guard, not a pattern.
- **New modules can silently reintroduce a collision.** The `check_qualified_references` pass of
  Phase 1 should also assert that no two modules export the same name with *different* bindings —
  cheap to compute, and it turns the property just measured into a standing guarantee.
