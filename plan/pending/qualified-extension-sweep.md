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

## 2. One blocker: fourteen names reach past an export list

A bare `using` brings only what a module exports, so a file that imports a name
its owner does not export stops compiling. There are 14, measured against the
loaded modules rather than the source:

| name | from | reached by |
| --- | --- | --- |
| `TrueTypeFont`, `_load_ttf`, `advance_1000`, `ascent_px`, `glyph_id` | `StyleModule` | `source/pdf/Pdf.jl` |
| `rule_print`, `template_read_intent` | `ProjectionTemplateModule` | `source/rst/RstDocument.jl` |
| `head`, `tail` | `ReferenceModule` | `source/text/TextToGraphics.jl`, `source/tooltip/TooltipDocument.jl` |
| `DOCUMENT_SHOW_MAX_DEPTH` | `DocumentModule` | `source/widget/WidgetDocument.jl` |
| `_forward_descend`, `_shift_child_image` | `LayoutModule` | `source/widget/WidgetDocument.jl` |

Each one is either part of the owner's API, and the owner exports it, or it is
not, and the reader stops reaching it. Three of them say which they are by their
name: `_load_ttf`, `_forward_descend` and `_shift_child_image` are private, and
reaching them already breaks `PAR-MODULE-BOUNDARY-IS-API`.

Settle these before the module that reaches them is migrated, not before the
sweep starts. They block six files, not seventy-four.

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
   last, because they carry 387 of the 902 sites between them.
4. **The kernel's remaining three files**, and then delete the `qualified_files`
   parameter, because the opt-in set covers everything.

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
