# Reference step cleanup

Make the reference-step system uniformly `@document`, remove dead code, add a
per-step-type extensibility seam so step types can live in the package that
owns their concept, and move `PointReference` / `TextRectangularReference` /
`ProjectionReference` out of the kernel reference layer accordingly.

## Motivations

- **Placement (AR-PACKAGE-CHAIN/47).** Three step types are named after concepts owned by
  higher packages: `TextRectangularReference` (visual/text),
  `PointReference` (visual/graphics), `ProjectionReference` (kernel/projection,
  layer 7). All three currently sit in kernel/reference (layer 3).
- **Consistency (AR-FIELDS-ARE-CELLS).** Some step types are `@document`, others are plain
  `struct`. There is no principled split; make every step type `@document`.
- **Extensibility.** `evaluate_reference`, `get_valid_reference_prefix`, and
  `annotate_reference_types` all hardcode `step isa RangeReference / … / …`
  chains. A per-step-type generic lets a step type live in its own package
  and register its behaviour by dispatch, no kernel edits needed.
- **Dead code.** `FunctionReference` is never constructed anywhere in the
  tree; only handled in dispatch branches and a text-rendering handler that
  therefore never fires.

## Design

### Step 1 — extensibility seams (kernel/reference)

Three open generics, no default:

```julia
"""
    evaluate_step(step, document) -> child_document

Navigate `document` through `step` and return the child. Structural steps
descend into a child; non-navigating checkpoint steps (like `TypeReference`)
return `document` unchanged after asserting their invariant. Terminal-only
steps that never descend (`PointReference`, `TextRectangularReference`,
`ProjectionReference`) throw a sentinel or don't implement the seam at all,
and the walker treats them as terminal.
"""
function evaluate_step end

"""
    try_evaluate_step(step, document) -> Union{Any, Nothing}

Non-throwing sibling used by the validation walk. Returns the child on
success, `nothing` on any structural failure (missing field, out-of-range,
type mismatch).
"""
function try_evaluate_step end
```

Or a single seam with a boolean `strict` — TBD when implementing.

Kernel registers methods for `RangeReference`, `FieldReference`,
`TypeReference` (checkpoint, returns document unchanged after `isa` check).

`evaluate_reference`, `get_valid_reference_prefix`,
`annotate_reference_types` all drop their `if step isa X …` chains and call
through the seam instead. Non-navigating steps get a dedicated marker or
throw a specific `TerminalStepError` the walker catches and treats as
end-of-path.

### Step 2 — delete `FunctionReference`

- Remove the type declaration.
- Remove the `evaluate_reference` / `get_valid_reference_prefix` /
  `annotate_reference_types` branches for it.
- Remove the two rendering methods in `ReferenceToText.jl`.
- Remove from `ReferenceModule.jl` exports.

### Step 3 — uniform `@document`

Convert to `@document`:
- `TypeReference(type::Any)`
- `ProjectionReference(projection::Any, output_path::ReferencePath)`
- `TextRectangularReference(start::Int, stop::Int)`
- `EmptyReferencePath(type::Any)`

`RangeReference`, `FieldReference`, `PointReference`, `ConcreteReferencePath`
are already `@document`.

### Step 4 — extension-register the DSL fragments

`ReferenceBuilder.jl`'s `.point(x, y)` / `.proj(p, sub)` and
`ReferenceCase.jl`'s `isa PointReference` / `isa ProjectionReference` today
name kernel-local types by qualified reference. Once those types move out
of the kernel, the kernel DSL can't reference them.

Approach: replace the hardcoded step-name → expansion table with a
per-step-type dispatch:

```julia
"""
    dsl_build_step(::Val{name}, ctx, args...) -> Expr

Return the expression that constructs the step type mapped to `.name(args)`
in the `@reference` DSL. Each package registers a `::Val{:name}` method
for its own step types.
"""
function dsl_build_step end

"""
    dsl_match_step(::Val{name}, ctx, ...) -> Expr

Return the case-branch that matches the step type registered as `.name` in
the `@reference_case` DSL.
"""
function dsl_match_step end
```

Kernel registers `.type` (TypeReference). Higher packages register their own
DSL entries in a slice-local fragment when the step type is defined.

The DSL macros walk their AST and for each `.name(...)` call, emit
`dsl_build_step(Val(name), args...)` — dispatched at parse time.

### Step 5 — move step types

Once (1)–(4) land, the moves are mechanical:

- `ProjectionReference` → `kernel/main/projection/` (new file
  `ProjectionReference.jl` folded into `ProjectionLayer.jl` before
  `Projection.jl`, or a fragment of an existing module). Registers its
  `evaluate_step` + `dsl_build_step(::Val{:proj})` + `dsl_match_step`.
- `PointReference` → `visual/main/graphics/` (its own file or joined onto
  `Graphics.jl`). Registers its methods.
- `TextRectangularReference` → `visual/main/text/` (new file or joined onto
  `Text.jl`).

Every consumer's `import ..ReferenceModule: PointReference, …` becomes
`import <new-home>: PointReference, …`. The `..ApiModule` aliases in
`ProjecturedVisual.jl` gain / adjust entries so the umbrella still exposes
them flat.

## Blast radius

- **Kernel**: adds three generic function declarations; `Reference.jl`
  shrinks by ~40 lines (dispatch chains → single generic call); DSL
  fragments refactored to use dispatch. `FunctionReference` gone.
- **Base**: one comment mentioning `PointReference` — leave as-is.
- **Visual**: `PointReference` and `TextRectangularReference` gain new
  homes; every `import ..ReferenceModule: …, PointReference, …` splits its
  import between ReferenceModule and the new home.
- **All packages**: `ReferenceApiModule` in visual/domain umbrellas may
  gain / need new companion aliases.

## Rollout order

1. **Extensibility seams** (Step 1). Purely additive; consumers unchanged.
2. **Delete FunctionReference** (Step 2). Trivial.
3. **Uniform `@document`** (Step 3). Storage layout change; verify tests.
4. **Extension-register the DSL** (Step 4). No moves yet; the kernel just
   dispatches through the new seam, still registers all step types itself.
5. **Move step types** (Step 5). Cross-package moves; imports adjust.
6. **Seal walk resumes**: `Reference.jl`, `Selection.jl`, `ReferenceCase.jl`,
   `ReferenceBuilder.jl`, `ReferenceModule.jl`.

Each step ends with the four-package test sweep; each is its own commit.

## Related

- Pairs with `plan/pending/reference-types-always-present.md` — once the
  types-always-present invariant is enforced, the retired `_ignoring_types`
  functions collapse. The two plans are orthogonal: this one restructures
  the *type registry*; the other tightens the *type invariant*.
- Once the moves are done, the "opaque payload" note in
  `reference/ReferenceModule.jl`'s docstring becomes obsolete —
  `ProjectionReference` will be defined at the layer that owns projections.
