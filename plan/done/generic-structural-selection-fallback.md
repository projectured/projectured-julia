# Generic structural-selection fallback (remove per-domain flat-offset readers)

## Goal

Eliminate the hand-written `projection_read` overrides in domain→syntax
projections whose only job is to fall back to a **projection-induced reference**
for projection-introduced structural glyphs (delimiters, separators, headings,
braces). Replace them with a single domain-independent mechanism so a new domain
that projects to syntax gets the structural-position fallback for free.

Concretely, delete:

- `IniToSyntax.jl` — `projection_read(::IniSectionToSyntaxNode, …)` and
  `projection_read(::IniFileToSyntaxNode, …)` (omnetpp-pred).
- `NedToSyntax.jl` — the three `projection_read(::Ned…ToSyntaxNode, …)` overrides
  (omnetpp-pred).

…by making the **generic** `RuleIoMap` reader handle every structural case.

## Background: what those readers do and why they exist

Each override is the same boilerplate (`IniToSyntax.jl:137-143` and `157-163`):

```julia
result = map_reference_backward(p, iomap, op.path)
result !== nothing && return ReplaceSelectionOperation(result)       # real content
flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
flat < 0 && return nothing
return ReplaceSelectionOperation(@reference proj(p, {flat}))          # structural glyph
```

A click on real content (a key, a value, a child entry) maps backward into the
input domain. A click on a glyph the *projection* introduced — `[Config …]`
brackets, ` = `, the `\n\n` / `\n` separators — has **no input-domain pre-image**,
so `map_reference_backward` returns `nothing`. The reader then stores a
projection-induced reference `proj(p, {flat})`: a flat character offset wrapped in
this projection's own `ProjectionReference` step, so the input document can
"remember" a cursor sitting on a glyph it does not itself contain.

A domain-neutral version of exactly this fallback **already exists** in
`ProjectionTemplate.jl` (`projection_read(p::Projection, iomap::RuleIoMap,
op::ReplaceSelectionOperation)`):

```julia
result = map_reference_backward(p, iomap, op.path)
result !== nothing && return ReplaceSelectionOperation(result)
iomap.wiring isa NodeWiring || return nothing
return ReplaceSelectionOperation(_path(ProjectionReference(p, op.path)))
```

Two things stop the Ini/Ned projections from simply deferring to it:

**Blocker A — the wiring guard.** The generic fallback fires only for
`NodeWiring`. `IniFileToSyntaxNode` is a `NodeWiring` (`collection(:children)`),
but `IniSectionToSyntaxNode` is a **`MixedNodeWiring`** (heading leaf +
`collection(:entries)`); NED adds `InlineWiring` / `SectionsWiring`. For those the
generic fallback returns `nothing`, so a custom override is required.

**Blocker B — what the fallback wraps.** The generic fallback wraps the
*output-domain syntax path* (`proj(p, op.path)`); the Ini reader pre-flattens to
`proj(p, {flat})`. They diverge only at **render time**, in `SyntaxToText`: its
`_syntax_to_flat` only knows how to render a `ProjectionReference` whose inner is
a single bare flat `{k}` — see the detailed walkthrough below.

## The fix — two small, domain-independent changes

### Change 1 (linchpin): make `SyntaxToText`'s projection-reference handling transparent

File: `package/domain/src/projection/primitive/SyntaxToText.jl`, the
`ProjectionReference` branch of `_syntax_to_flat(node::SyntaxNode, …)` (currently
lines 686-692):

```julia
# BEFORE — only a bare {k} renders
if h isa ProjectionReference
    inner = h.output_path
    inner isa ConcreteReferencePath || return -1
    idx = inner.head
    idx isa RangeReference || return -1
    return idx.start::Int
end
```

```julia
# AFTER — a ProjectionReference is transparent: strip it and keep navigating,
# except the terminal "bare flat {k}" case which means this exact offset.
if h isa ProjectionReference
    inner = h.output_path
    inner isa ConcreteReferencePath || return -1
    inner.head isa RangeReference && inner.tail isa EmptyReferencePath &&
        return inner.head.start::Int                       # this node's own flat offset
    return _syntax_to_flat(node, inner, p, depth)          # upstream proj-wrapped path
end
```

This is safe because `SyntaxToText`'s own self-produced structural selections
always carry a bare `{k}` inner (`_pos_to_selection` → `@reference proj(p, {k})`),
which still hits the fast path unchanged. The new recursion only adds the ability
to render a proj that wraps a *structured* syntax path or a *nested* proj — which
is exactly what the generic fallback produces.

### Change 2: widen the generic fallback guard

File: `package/domain/src/projection/ProjectionTemplate.jl`,
`projection_read(p::Projection, iomap::RuleIoMap, op::ReplaceSelectionOperation)`:

```julia
# BEFORE
iomap.wiring isa NodeWiring || return nothing
# AFTER
iomap.wiring isa Union{NodeWiring,MixedNodeWiring,InlineWiring,SectionsWiring,FixedNodeWiring} || return nothing
```

Atomic/leaf wirings already proj-wrap inside `_atomic_backward`, so they don't
need this outer fallback; the change only adds the remaining node-shaped wirings.

### Change 3: delete the now-redundant per-domain readers (omnetpp-pred)

- `program/src/projection/primitive/IniToSyntax.jl`: remove both `projection_read`
  methods and drop the imports they alone needed
  (`_syntax_to_flat`, `SyntaxNodeToText` from `SyntaxToTextModule`;
  `map_reference_backward` from `ProjectionApiModule`; the `@reference` import if
  unused elsewhere).
- `program/src/projection/primitive/NedToSyntax.jl`: remove all three
  `projection_read` overrides and their now-unused imports.

## Why the *count* of fallbacks does not (and should not) drop

Brackets, ` = `, and separators have **no input-domain coordinate by
construction**, so a projection-induced reference is the semantically correct
answer — you can't make `map_reference_backward` succeed there without inventing
positions that don't exist. The win is not *fewer* fallbacks but *no per-domain
fallback code*: one generic mechanism instead of N copies, and the
syntax-specific `_syntax_to_flat` knowledge confined to the syntax layer.

## Verification

- `test_json_to_syntax()`, `test_xml()`, `test_syntax_to_text()`,
  `test_syntax()` in projectured-julia — Change 1 & 2 must not regress main-repo
  domains. Pay attention to clicks on fixed-node delimiters (JSON `:`/`,`), which
  Change 2 now turns into a stored proj-selection instead of `nothing`.
- `test_text_navigation(...; check_reaches_all=true)` for an INI/NED example in
  omnetpp-pred — confirm every caret (including structural glyphs) is still
  reachable after the readers are deleted.
- A click round-trip on a structural glyph: click → stored selection → re-render
  → cursor lands on the same glyph.

## Caveats

- The stored selection shape changes: `proj(p, .children[1].open{k})` (or a nested
  `proj(p, proj(p_syntax, {flat}))`) instead of `proj(p, {flat})`. It renders
  identically after Change 1 and is *more* informative for inspection/navigation,
  but any omnetpp-pred test asserting exact reference equality on a structural
  selection will need updating.
- Change 2 affects main-repo domains' fixed/mixed/inline/sections nodes: a click
  on an introduced delimiter now stores a proj-selection. Verify this is an
  improvement (cursor lands on the glyph) and not a behavior a test relied on
  being a no-op.
- `_syntax_to_flat_range` (whole-element/tree selections) has the same proj branch
  shape; it is range-only so the cursor fallback doesn't touch it, but glance at
  it if tree-selection round-trips also begin flowing through proj-wrapped
  structural paths.

## Status

Implemented in two worktrees: `pj-structural-fallback` (projectured-julia, Changes
1+2) and `op-structural-fallback` (omnetpp-pred, Change 3).

- [x] Change 1 — `_syntax_to_flat` ProjectionReference branch transparent
- [x] Change 2 — widen generic `RuleIoMap` reader guard
- [x] Change 3 — delete Ini/Ned `projection_read` overrides + unused imports
- [x] Verify main-repo syntax tests — green in the pj worktree:
  `test_syntax_to_text` all pass (incl. flat-position round-trip 57/57),
  `test_json_to_syntax` 11/11, `test_click_roundtrips` 31/31,
  `test_syntax_tree_selection` 29/0/0. Only failure is the pre-existing
  `test_json_to_syntax_reader` line-117 array-insert quirk (47/1/0), unrelated.
- [x] Verify omnetpp-pred INI/NED navigation — against the pj worktree:
  `test_example(ini_example)` fully clean (4871/0/0); `test_example(ned_example)`
  unchanged vs. baseline — the same 34 NED type-in failures appear with **and**
  without Change 3 (identical paths), so they are a pre-existing NED type-in gap,
  not a regression. All NED printer/reader/navigation tests pass.

Commits: projectured-julia `0b72792` (Changes 1+2), omnetpp-pred `086343b`
(Change 3). Both on branch `generic-structural-selection-fallback`.

### Pre-existing NED type-in gap (out of scope, recorded for follow-up)

`test_typein(ned_example)` has 34 leaves where a `KeyPress` produces no
`StringReplaceRangeOperation` (cursor renders fine; the edit reader returns
nothing). These predate this change and are unrelated to structural selection —
they are NED leaf projections lacking type-in/retype wiring (e.g.
`.filename`, `.version`, submodule `.name`/`.type`/`.vector_size`, param/property
`.name` and literal `.text`/`.value`). INI has no such gap.
