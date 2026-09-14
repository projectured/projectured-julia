# Finish the qualified-extension sweep

> **Kind:** plan · **Status:** pending · **Stands on:**
> [architecture-invariants.md](../../documentation/rule/architecture-invariants.md)
> (`PAR-QUALIFIED-EXTENSION`, `PAR-MODULE-BOUNDARY-IS-API`),
> [naming-rules.md](../../documentation/rule/naming-rules.md)

## 0. The rule is decided; the sweep is not finished

`PAR-QUALIFIED-EXTENSION` states the form:

- **`import ..XxxModule: f, g`** — exactly the names this code extends.
- **`using ..XxxModule`, bare** — every other module, whose names this code only
  calls.
- A definition may qualify instead of import: `XxxModule.f(…) = …`.

**The compiler does not check it.** Measured on Julia 1.13: after a bare
`using ..XxxModule`, a plain `f(…) = …` for a name that module exports raises no
error and no warning. It defines a new `f`, the owner keeps its methods, and
every call through the owner reaches the fallback. So the header is not a
convenience: it is what makes an extension reach its generic.

`relative_import_errors` enforces it over an opt-in set in
[KernelSuite.jl](../../test/kernel/KernelSuite.jl). Five files are in that set,
all in the kernel. The comment says it grows as the sweep proceeds, and when it
covers every file the parameter goes. This plan is that sweep.

## 1. The scale, measured 2026-09-13

| | |
| --- | --- |
| `import ..X: names` lines | 1397 — 4 in the kernel, 1393 in the slices |
| files that carry them | 74 — 3 in the kernel, 71 in the slices |
| method definitions to qualify | 902 |
| distinct names extended | 27 |
| modules with an import header | 75 |
| of those, extending nothing they import | 14 |

**The 902 are concentrated.** Four names are 761 of them: `read_intent` 295,
`print_document` 254, `map_reference_forward` 111, `map_reference_backward` 101.
That is the projection interface, which every projection implements. Then
`evaluate_operation` 40 and `set_cell_function!` 37. The other 21 names account
for 64 sites.

The heaviest modules are `WidgetModule` 143, `SqlModule` 102,
`ProjectionAlgebraModule` 83, `SyntaxModule` 59, `MathModule` 43 and
`DbCatalogModule` 40.

**The slice collapse helped.** A fragment carries no import header, so the 254
intra-slice import lines are gone and what remains is one header per module.
That is why 1397 lines sit in only 74 files.

## 2. The blocker is cleared — DONE 2026-09-14

A bare `using` brings only what a module exports, so a file that imported a name
its owner did not export could not migrate. There were 25 such names across six
modules.

The user's decision: **export them, and fix the name where it needs fixing.**
Fourteen of the seventeen distinct names broke `PAR-NAMING-LAW` and were renamed
first. Three were already right and were exported as they stood.

| module | exported as it was | renamed, then exported |
| --- | --- | --- |
| `StyleModule` | `TrueTypeFont` | `_load_ttf` → `load_truetype_font`, `glyph_id` → `get_glyph_id`, `advance_1000` → `get_glyph_advance_1000`, `ascent_px` → `get_ascent_pixels`, `text_width` → `measure_text_width` |
| `TextModule` | `SpanPath` | `_flat_base` → `get_flat_base`, `_flat_caret_ref` → `make_flat_caret_reference`, `_flat_cursor_coord` → `get_flat_cursor_coordinate`, `_is_structural_selection` → `is_structural_selection` |
| `ProjectionTemplateModule` | — | `rule_print` → `print_template_rule`, `template_read_intent` → `read_template_intent` |
| `LayoutModule` | — | `_forward_descend` → `descend_reference_forward`, `_shift_child_image` → `shift_child_image` |
| `GraphicsModule` | — | `_canvas_content_bounds` → `get_canvas_content_bounds` |
| `DocumentModule` | `DOCUMENT_SHOW_MAX_DEPTH` | — |

Each renamed name gained the verb the law asks for and lost an abbreviation the
law bans: `px` is pixels, `ref` is a reference, `coord` is a coordinate, and
`ttf` is a TrueType font.

`text_width` needed `--calls-only`: eleven of its references are local variables
in `WidgetToGraphics.jl` that happen to share the name. `rule_print` and
`template_read_intent` needed the opposite, because three references each are
`$(rule_print)` interpolations inside a macro, which are the function and must
move.

## 2.1 The sweep is done except for graph — 2026-09-14

**Every one of the 349 source files follows the rule, except the sixteen of
`graph`.** Measured by running the checker over every file of every slice: 50
rejections, all of them in `graph`.

The guard is no longer opt-in. It checks every file of every package, and what
is not migrated is named in that package's `unmigrated_files`. Only `graph` has
one. A file named there and since migrated is reported, so the set cannot go
stale, and the per-suite ledgers are gone — twenty-six registrations and the
assertion that guarded them.

Proven by breaking a file that was never on any list: `JsonParser.jl` gained an
`import ..CellModule: Cell` and the guard named the file, the name and the fix.

`graph` is out of the sweep, the user's decision on 2026-09-14, and
[divide-graph-and-text.md](divide-graph-and-text.md) owns it. The reason is that
the fold shape depends on the division, and the division needs a decision this
sweep should not take:

- The include order is three layers: the document and the engine contract, then
  the ten engines under `omnetpp/`, then the registry that picks one, then the
  projections.
- `GraphLayoutChoice.jl` straddles the seam. It holds the registry that
  `ProjecturedAdaptagrams` already uses from its `__init__` — a clean one-way
  seam — and it also holds the built-in choice, which names
  `SpringEmbedderLayout` and `ForceDirectedLayout` directly. That one edge is
  what makes the halves inseparable.
- To divide, the built-in choice moves down into the engines and registers
  itself, the way Adaptagrams does. The dependency direction allows nothing
  else.
- This codebase maps one slice to one package, so an engines slice means a new
  package: a `Project.toml`, `[sources]` in every environment, and a row in the
  package-graph table.

To fold `graph` as one module would finish the sweep and flatten a layering that
§4.2 of the division plan argues is real. So it waits.

## 3. Order of the work

1. **The five modules that extend nothing and sit outside `graph`** —
   `DefaultBackendModule`, `PlotModule`, `ComponentModule`, `DatabaseModule`,
   `FocusModule`. A header rewrite and a load, with no site to qualify.
   **DONE 2026-09-13.** Fourteen import lines became twelve bare `using` lines,
   five lines of symbol list went, and every package loads. No site needed
   qualification, exactly as the count predicted.

   Four are registered in a guard: `ProjecturedComponent`, `ProjecturedFocus`
   and `ProjecturedPlot` in `test/substrate/SubstrateSuite.jl`, and
   `ProjecturedDatabase` in its own suite. Regressing one line of `Focus.jl` to
   `import` was tried, and the guard named the file, the line and the rule.

   `example/projectured/DefaultBackend.jl` is migrated but not registered: the
   example package has no layering guard to register it with. Either give it
   one, or accept that the example tree is checked by loading alone.
2. **The domain slices**, whose sites are almost entirely the four projection
   functions. Take them in batches, smallest first.
3. **`SyntaxModule`, `ProjectionAlgebraModule`, `SqlModule`, `WidgetModule`**
   last, because they carry 387 of the 902 sites between them. **DONE.**
4. **The kernel.** **DONE.** Every kernel file follows the rule, the sealed ones
   included: what they import, they extend.

**`graph` waits for [divide-graph-and-text.md](divide-graph-and-text.md).** Nine
of the 14 modules that extend nothing are inside it, and the division moves
them. To migrate them now is work the division redoes.

## 4. How to migrate one module

1. **Split the import list, do not delete it.** For each
   `import ..XxxModule: a, b, c`, keep the names the module extends and move the
   rest to a bare `using ..XxxModule`. A name is extended when some file of the
   module defines a method for it under that bare name.
2. Run `shadowed_extension_violations(root)` from `test/suite/naming.jl`. It
   reports every definition left stranded — a name the module no longer imports,
   that a module it names exports.
3. Run the module's suite and compare it against the run before the step.
4. Add the module's files to `qualified_files` in the suite that guards them,
   so `relative_import_errors` holds the header to the rule from then on.

**Do not reverse steps 1 and 3.** A header rewritten ahead of the check compiles
and loads and is wrong: seven module headers were rewritten this way on
2026-09-13, six packages loaded clean, and `test_fsm()` fell from 153 passing to
93 pass and 7 error. The suite is the check, not the loader.

## 4.1 What holds the rule up

Three guards, because the compiler holds up none of it:

- `shadowed_extension_violations` (`test/suite/naming.jl`) — a definition that
  reads as an extension and is a new function. Whole tree, every suite.
- `relative_import_errors` (the layering guard) — no bare `import ..Xxx`, no
  `using ..Xxx: a, b`, and no imported name that nothing extends. Opt-in over
  `qualified_files`.
- `qualified_reference_errors` — a `XxxModule.sym` names an exported symbol.

## 5. How to check a step

Run the naming guard, the slice's own suite, `test_domain_examples()` and
`test_package_graph()`, and compare each against the same run before the step.
A suite that matches the previous numbers exactly is the only claim worth
making.

`test_export_collisions` matters more here than anywhere else: a bare `using`
puts every export of every used module in scope, so the rule's precondition is
that no two modules export one name with different bindings. It is checked
dynamically in the umbrella suite, and it passes today.
