# JuliaToSyntax — bidirectional cursor navigation

**Origin:** Follow-up to the D/High finding in
[plan/done/consistency-report.md](../done/consistency-report.md). Filed 2026-06-15.

## Problem

`JuliaToSyntax`'s 30 sub-projections define `projection_print` but rely on the
generic `Projection` defaults for `map_reference_forward` / `map_reference_backward`
/ `projection_read`. As a result keyboard navigation into nested Julia is broken:
`explore_selections(julia_example)` reaches only ~3 states for an entire
`factorial` function (it never descends into the name / params / body), because the
cursor cannot rest on or traverse *through* the projection-introduced structural
tokens (`function`, `(`, `)`, `==`, `*`, `-`, `if`, `else`, `end`, …).

## What was tried (and reverted)

A full School-A mapper set (per-node `map_reference_forward`/`_backward` +
`projection_read`, with the node printers' selection cells wired via the
deferred-iomap trick, mirroring `JsonToSyntax`) was implemented and verified to
compile and print (`test_printer(julia_example)` = 1755 checks, no errors). It was
**reverted** because content mappers alone do not restore navigation: they leave
the cursor unable to traverse structural tokens, and the whole-element fallback for
the `name`-field leaves (`JuliaIdentifier`/`JuliaSymbol`) and content-less keyword
leaves nudged the reachable-state count *down* (3 → 2) rather than up. See the
commit history around `JuliaToSyntax: document deferred reference mapping`.

## The actual missing piece

`JsonToSyntax` makes structural positions navigable with a flat-offset
projection-reference mechanism (`_syntax_to_flat`, in `SyntaxToText`): a structural
output position with no input pre-image is mapped back to
`proj(p, PositionReference(flat))`, a single flattened character offset that the
`SyntaxNode` renderer/navigator understands and that round-trips. `JuliaToSyntax`
has no equivalent, so its structural tokens are dead ends for the cursor.

## Plan

- [ ] Reuse / generalise `SyntaxToTextModule._syntax_to_flat` (or factor a shared
      helper) so the Julia node readers can emit `proj(p, PositionReference(flat))`
      for structural positions, exactly as `JsonArrayToSyntaxNode.projection_read`
      does.
- [ ] Add per-node School-A `map_reference_forward`/`map_reference_backward` for
      content positions (delegating the tail through the stored child IoMaps), and
      wire each node printer's selection cell to `map_reference_forward` via the
      deferred-iomap trick.
- [ ] Resolve the leaf field-name mismatch without touching `Operation.jl`:
      `JuliaIdentifier`/`JuliaSymbol` store their text in `name` (not the SyntaxLeaf
      `value`), and `JuliaNothing`/`JuliaBreak`/`JuliaContinue` have no text field —
      so `set_selection!` must never be handed a path that descends a field these
      documents lack. (Options: translate `value` ↔ `name` in those leaf mappers, or
      keep whole-element granularity for them.)
- [ ] Verify with `test_selection(julia_example)` / `test_repl(julia_example)`:
      reachable-state count should grow well past the current 3, with zero errors,
      and stay green for `test_printer(julia_example)`.

## Notes

- During investigation a latent crash was found: `set_selection!` /
  `clear_selection!` (`common/Operation.jl`) throw a `FieldError` when a path step
  names a field the document lacks. A one-line `hasfield` guard fixes it generally,
  but `Operation.jl` is currently off-limits — revisit if that constraint lifts.
