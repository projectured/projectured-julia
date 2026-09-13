# Divide the graph and text slices

> **Kind:** plan · **Status:** pending · **Stands on:**
> [division-terminology.md](../../documentation/rule/division-terminology.md),
> [naming-rules.md](../../documentation/rule/naming-rules.md),
> [one-module-per-slice.md](../done/one-module-per-slice.md) §4.2

## 0. Why this plan exists

[one-module-per-slice.md](../done/one-module-per-slice.md) folded sixty of the
sixty-two slices into one module each. It left `graph` and `text` alone, because
each holds more than one unit of architecture. To fold either one would flatten
a structure that is doing real work.

That plan is done, so the reading it asks for has no owner. This plan owns it.

Nothing here is urgent. Both slices work, and both pass their suites. The cost
of leaving them is that two slices break the law the rest of the tree follows,
and a reader who derives `GraphModule` from the folder finds seventeen modules.

## 1. What the two hold

| slice | modules | files | lines |
| --- | --- | --- | --- |
| `graph` | 17 | 16 | 4831 |
| `text` | 14 | 14 | 5123 |

Every other slice declares one module.

## 2. `graph` — the case is read and the answer is known

Its 39 internal edges are not flat. They form a dependency graph four to five
levels deep:

    LayoutGeometry  <-  GraphComponent, ForceDirectedParametersBase,
                        ForceDirectedParameters, HeapEmbedding, StarTreeEmbedding
    GraphComponent  <-  HeapEmbedding, StarTreeEmbedding
    ForceDirectedParametersBase <- ForceDirectedParameters
    StarTreeEmbedding <- ForceDirectedGraphLayouter

    GraphModule     <-  GraphLayoutEngine, GraphLayoutChoice,
                        GraphToGraphLayout, GraphLayoutToGraphics
    GraphLayout     <-  GraphLayoutEngine, GraphToGraphLayout, GraphLayoutToGraphics
    GraphLayoutEngine <- GraphLayoutChoice, GraphToGraphLayout
    GraphToGraphLayout <- GraphLayoutToGraphics

**The two halves barely touch.** `source/graph/omnetpp/` is a self-contained
port of a C++ force-directed layout engine: geometry, a random generator, a
component, the parameter families and two embeddings. It knows no document type.
The only edge from the top level into it is `GraphLayoutChoice`, which picks a
layouter.

**The division:** `source/graph/` keeps the documents and the projections and
becomes one module. `omnetpp/` becomes its own slice, plausibly its own package,
because it depends on nothing above it.

## 3. `text` — the reading is not done

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
