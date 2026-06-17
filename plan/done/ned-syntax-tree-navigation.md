# NED syntax-tree (whole-element) navigation

**Status: DONE.** `test_tree_navigation(ned_example; check_reaches_all=true,
collect=collect_ned_tree_selections)` passes (32/32). NED is now navigated (no
longer skipped) by the broad `TreeNavigation` sweep (24/24) and added to
`TreeNavigationComplete` (56/56 = 24 syntax + 32 ned). No regressions:
`test_printer/reader/repl(ned_example)` = 2903/225/225,
`test_text_navigation(ned_example)` = 796, `CollapseRoundtrip` 18,
`TextNavigationComplete` 837.

**Text navigation** (`test_text_navigation(ned_example)`) passes the no-error
sweep (796/796) and NED is clean in the broad `test_text_navigations()` run. NED
is *not* added to the text-completeness (`check_reaches_all`) set — confirmed with
the user. Like `syntax`/`xml`, NedToSyntax renders each leaf as a single computed
TextString and most document string fields never become an addressable text leaf,
so "every document-field caret reachable" is the wrong invariant (navigation
covers every visible character via flat ProjectionReference offsets). Rationale
documented at the `_text_navigation_complete_examples` exclusion list in
[TextNavigationTest.jl](../../test/src/editor/TextNavigationTest.jl).

## Implementation outcome (vs. design)

- Implemented exactly as designed. `NedSectionToSyntaxNode` abstract type with
  shared `_ned_section_iomaps` / `_ned_section_forward` / `_ned_section_backward`
  / `_ned_section_print` and shared `map_reference_*` + `projection_read`; the
  five module-like types and `NedSubmodule` subtype it. Whole-section selections
  (`.params`, `.gates`, …, the `CellVector` fields) are extra reachable states —
  allowed under the subset check, not enumerated.
- **Channel rendering changed (intentional):** `NedChannel` /
  `NedChannelInterface` previously rendered params as direct children with no
  "parameters:" label; they now use the shared section grouping like every other
  module type. No projection test prints a channel (the `ned` example has none),
  so no printer/reader test changed; the new behaviour is more consistent.
- `_build_section_nodes` removed (superseded by `_ned_section_print`).

Make `test_tree_navigation(ned_example; check_reaches_all=true)` pass — i.e. the
NED example supports Ctrl+Alt+Home + Alt+arrow whole-element navigation, and
navigation reaches every navigable NED node enumerated from the document.

## Problem

Today NED has no tree navigation: `Ctrl+Alt+Home` returns `nothing`
(state_count = 0) and is silently *skipped* by `test_tree_navigations()`. Two
gaps:

1. **NedToSyntax has no whole-element (`∅`) selection mapping.** The structural
   mappers (`NedFileToSyntaxNode`, `NedConnectionGroupToSyntaxNode`) only handle
   `children[i]` paths; the module-like projections
   (`NedSimpleModuleToSyntaxNode`, …, `NedSubmoduleToSyntaxNode`) and the leaf
   projections define no `∅` case at all, so a root/child whole-element selection
   maps to `nothing`. (Contrast `JsonArrayToSyntaxNode` / `JsonObjectToSyntaxNode`,
   which carry `∅ => @reference()` everywhere and work.)

2. **Module bodies use a two-level section grouping** (`SyntaxNode("parameters:",
   children=[entries])`) that the document does not have — so syntax
   `.children[sec].children[entry]` must map to document `.params[entry]`, and the
   intermediate whole-section node (`.children[sec]∅`) must map to the field path
   (`.params`). The module projections currently use `SimpleIoMap` with no mapper.

## Design

Mirror the JSON model (`∅ => @reference()` identity for whole elements; School-A
delegation through stored child IO maps).

### Navigable node set

Exactly the nodes the projection emits as their own selectable syntax element:

- Structural `SyntaxNode` producers: `NedFile`, the five module-like types,
  `NedSubmodule`, `NedConnectionGroup`.
- `SyntaxLeaf` producers placed as entries: `NedPackage`, `NedImport`,
  `NedProperty`, `NedParam`, `NedGate`, `NedConnection`, `NedInsertion`.

Sub-parts flattened into a leaf's text (a param's `@unit` property, property keys,
literals, gate properties) are **not** independently selectable.

### NedToSyntax changes (`program/src/projection/primitive/NedToSyntax.jl`)

- Shared section infrastructure: `abstract type NedSectionToSyntaxNode`,
  `_ned_section_iomaps` (per non-empty section: `(field, label, entries)`),
  `_ned_section_forward` / `_ned_section_backward` (the `∅` / whole-section /
  entry mapping), `_ned_section_print`. The five module-like types and
  `NedSubmodule` subtype `NedSectionToSyntaxNode` and share
  `map_reference_forward` / `map_reference_backward` / `projection_read`; only
  `projection_print` (heading + section spec) differs per type.
- `NedFileToSyntaxNode` / `NedConnectionGroupToSyntaxNode`: add `∅ => @reference()`
  to forward + backward.
- Leaf projections (`Package`, `Import`, `Property`, `Param`, `Gate`,
  `Connection`, `Insertion`): add `∅ => @reference()` to forward/backward + the
  `sel` cell, and a `projection_read` for those missing one. Give `NedConnection`
  a `sel` cell (it had none).

### Test changes

- `collect_ned_tree_selections(document)` in `SelectionEnumeration.jl`: walk only
  navigable positions (file children; module/submodule sections; group
  connections), emit the whole-element path at each. Mirrors the projection so
  path strings match navigation output.
- `test_tree_navigation` gains a `collect=collect_tree_selections` keyword; NED is
  added to `test_tree_navigations_complete()` with `collect=collect_ned_tree_selections`.

## Testing

`test_tree_navigation(ned_example; check_reaches_all=true, collect=collect_ned_tree_selections)`
then the printer/reader sweep (`test_printer(ned_example)`, `test_reader(ned_example)`)
to confirm no regression.
