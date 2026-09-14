# Divide the graph and text slices

> **Kind:** plan · **Status:** pending · **Stands on:**
> [division-terminology.md](../../documentation/rule/division-terminology.md),
> [naming-rules.md](../../documentation/rule/naming-rules.md),
> [one-module-per-slice.md](../done/one-module-per-slice.md) §4.2

## 0. Where this stands

**Both slices are folded, and this plan is done.** `text` was read and folded on
2026-09-14; `graph` was measured, the division case did not survive the
measurement, and the user chose to fold it the same day. Every slice of the tree
declares one module.

## 1. Why this plan existed

[one-module-per-slice.md](../done/one-module-per-slice.md) folded sixty of the
sixty-two slices into one module each. It left `graph` and `text` alone, because
each holds more than one unit of architecture. To fold either one would flatten
a structure that is doing real work.

That plan is done, so the reading it asks for has no owner. This plan owns it.

Nothing here is urgent. Both slices work, and both pass their suites. The cost
of leaving them is that two slices break the law the rest of the tree follows,
and a reader who derives `GraphModule` from the folder finds seventeen modules.

## 2. What the two held

| slice | modules before | modules now | files | lines |
| --- | --- | --- | --- | --- |
| `graph` | 17 | 1 | 16 | 4831 |
| `text` | 14 | 1 | 14 | 5123 |

Every slice declares one module.

## 2. `graph` is one slice — MEASURED AND FOLDED 2026-09-14

This section argued for a division and rested on a claim that measurement did
not support.

**The claim.** "`source/graph/omnetpp/` is a self-contained port of a C++
force-directed layout engine … **It knows no document type.** The only edge from
the top level into it is `GraphLayoutChoice`."

**The measurement.** Three of the ten files name a document type and two import
it:

    BasicSpringEmbedderLayout.jl:32   import ..GraphModule: GraphGraph, GraphEdge
    ForceDirectedGraphLayouter.jl:33  import ..GraphModule: GraphGraph, GraphEdge

Both also import the engine contract. So the edges run both ways: one file of the
top level reaches into `omnetpp/`, and two files of `omnetpp/` reach back up.

**The shape is three layers, not two halves.** The include order says so: the
document and the engine contract, then the ten engines, then the registry that
picks one, then the projections. The engines sit *between* two parts of the rest,
so a straight lift makes a cycle.

**To divide would have cost two moves and a package.** The document types the
engines use and the engine contract would form a base package; the built-in
choice would move down into the engines and register itself, the way
`ProjecturedAdaptagrams` already registers a native engine from its `__init__`.
That is the edge that inverts. This codebase maps one slice to one package, so
the engines would need a `Project.toml`, `[sources]` in every environment and a
row in the package-graph table.

**The user decided on 2026-09-14 to fold instead.** Sixteen modules became
`GraphModule`. The three-layer structure survives as the include order of the
fragments, which is where it was already written.

The fold needed no reconciliation. Twenty-one names are defined in more than one
fragment and every one of them is a contract with its implementations —
`layout_graph`, `layout_engine_name` and `get_supported_constraint_kinds`
declared in `GraphLayoutEngine.jl` and implemented by the two layouters,
`apply_forces!` and the `get_body_*` family declared in
`ForceDirectedParametersBase.jl` and specialised in `ForceDirectedParameters.jl`.
`duplicate_definition_violations` reports none of them, because none shares a
signature.

## 3. `text` is one slice — READ AND FOLDED 2026-09-14

The reading the plan asked for is done, and the answer is one module.

**The import headers settle it.** Across its eleven modules `text` extends eight
names — `print_document`, `read_intent`, `map_reference_forward`,
`map_reference_backward`, `evaluate_operation`, `reroot_operation`,
`set_cell_function!` and `splice_value!`. Four seams, the same set an ordinary
slice implements. Its 363 idle imported names were eleven headers repeating each
other, not a sign of two units of architecture.

`text` is one module now, and its header imports those eight names.

**The fold exposed what the module boundary was hiding: nine helpers copied into
up to six files each.** Five were copied verbatim, and four had been copied and
then diverged:

| helper | copies | what they were |
| --- | --- | --- |
| `_text_elem_path`, `_parse_text_elem_range`, `_text_range_caret` | 5 each | one body, copied |
| `_flat_caret`, `_is_structural_ref` | 4 each | one body; `_is_structural_ref`'s fourth differed only by a `ref = ref` line |
| `_parse_text_elem_path` | 6 | five identical; `TextLineNumbering`'s returned `(nothing, nothing)` where the others return `nothing` |
| `_effective_pattern` | 2 | one body, copied |
| `_forward_map` | 4 | `TextFiltering`'s takes a typed argument and is a real second method; two share a body; `WordWrapping`'s returns the caret unchanged where the others return nothing |
| `_make_span` | 3 | two take two arguments and one takes three — a real second method |

Twenty-four duplicate definitions went. Two diverged copies took a name of their
own inside their own file, `_wrap_forward_map` and `_line_number_elem_path`,
which keeps their behaviour exactly. Nothing was reconciled: to merge a variant
into its family would change what the code does, and that is separate work.

The guard caught the one family the plan missed. `_text_range_caret` survived in
two files, and `duplicate_definition_violations` named both.

### 3.1 What the old section asked

Fourteen modules across 25 internal edges:

    TextModule, TextToStringModule, TextToGraphicsModule, PrimitiveToTextModule,
    ReferenceToTextModule, WordWrappingModule, TextFilteringModule,
    TextHighlightingModule, TextLineNumberingModule, TextFirstLineModule,
    SelectionInvertingModule, TextColumnReferenceStepModule,
    TextRangeReferenceStepModule, TextSpanReferenceStepModule

The names suggest three groups — the document and its reference steps, the
projections out of text, and the decorating projections over text — but nobody
has read the edges. Do that first. The answer may be one module, two slices, or
a slice and a package, and the reading decides which.

## 4. Order of the work

1. **Read `text`'s 25 edges** the way §2 read `graph`'s 39. Write the result
   here before touching a file.
2. **Divide `graph`.** Move `omnetpp/` out, fold what remains into
   `GraphModule`, and retarget the module names.
3. **Divide or fold `text`** by what step 1 found.

Use `workspace/bin/collapse_slice.py` for a fold and
`workspace/bin/julia-rename.jl` for the module renames. Both learned the traps
during the collapse: a docstring that declares a module, a self-import in three
shapes, an import that continues onto a second line, and an include line with a
trailing comment.

After each step, run the naming guard, the slice's own suite,
`test_domain_examples()` and `test_package_graph()`, and compare each against
the same run on the commit before the step. The collapse found that a suite
matching the baseline exactly is the only claim worth making.
