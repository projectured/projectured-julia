# One module per unit of architecture

> **Kind:** plan · **Status:** pending · **Stands on:**
> [division-terminology.md](../../documentation/rule/division-terminology.md),
> [naming-rules.md](../../documentation/rule/naming-rules.md),
> [architecture-invariants.md](../../documentation/rule/architecture-invariants.md)
> (`PAR-NAMING-LAW`, `PAR-MODULE-BOUNDARY-IS-API`)

## 1. The decision

The user decided on 2026-09-12: **a module is one unit of architecture, never one
file.** A layer in the kernel is one module. A slice in a domain or in the
substrate is one module. The files under it are fragments, exactly as a kernel
layer's files are fragments today.

The rule that a module is the file name plus `Module` goes away. It is replaced
by: **the module is the slice, and a file name is free to describe what the file
holds.**

This came out of the naming collection, which found 30 files named
`<Slice>Document.jl` that declare `<Slice>Module`. Under the old rule all 30 were
wrong. Under this rule all 30 are right, and 717 references stay as they are.

## 2. Why

- **A file split stops being an API change.** Today the module name tracks the
  file name, so a split means a new module, a new name, and an edit at every
  importer. That is a tax on the refactor you most want to be cheap, and it is
  paid silently: files stay too big because a split costs too much.
- **Part of the kernel already works this way.** `DocumentModule` owns nine
  fragments, and 11 of the 17 layers have exactly one module. Six do not:
  `projection` has 7, `cell` has 3, and `agent`, `editor`, `event` and
  `operation` have 2 each. The kernel is evidence for the pattern, not proof of
  it. **The user decided on 2026-09-12 that the kernel keeps its modules exactly
  as they are today.** This plan changes slices only.
- **The encapsulation it removes is soft.** Julia has no package-private. The
  346 symbols that only their own slice imports are internal by politeness, and
  any file can write `JsonParserModule.anything` today. The change gives up a
  convention, not a guarantee.
- **The naming law gets shorter.** It removes the `<Slice>Document.jl` problem,
  most of the module class of
  [naming-rule-violations.md](naming-rule-violations.md) §4.2, and the questions
  about a `Backend` qualifier and a collision prefix.

## 3. What it costs, measured

| cost | size |
| --- | --- |
| intra-slice `import ..XModule` lines deleted | 254 |
| cross-slice import lines, unaffected | 1626 |
| exported symbols that only their own slice imports, which become visible to the whole package graph | 346 |
| multi-module slices | 45 of 62 |
| multi-module slices with no internal edge, where the collapse is free | 3 |

**The real loss is the import header as local documentation, not the guard.**
The first 25 lines of [JsonToSyntax.jl](../../source/json/JsonToSyntax.jl) say
exactly what that file uses. The intra-slice part of that disappears and a grep
replaces it.

The guard loses less than 254 suggests. Julia tolerates a logical cycle inside a
module, because method definitions are order-independent unless they run at load
time. So those edges catch a design cycle, not a load failure, and inside one
feature a document type and its projection that refer to each other are normal.
Cycle discipline earns its keep between layers and between packages, and every
one of the 1626 cross-slice edges survives.

## 4. Order of the work

Take the slices in order of what they cost, so the pattern is proven before it
meets a hard case.

1. **`database`, `plot`, `primitive`** — 3 slices, 0 internal edges. **DONE
   2026-09-13.** Seven modules became three and nothing declared was lost.

   What the three taught:

   - **The fragment's imports do not always move up.** `plot` had to lift
     `PlotStyle.jl`'s `import ..ColorModule` into the module header; `primitive`
     did not, because `PrimitiveModule` already imported every name
     `ObjectField.jl` used.
   - **A qualified call is the bulk of the work.** 85 of `plot`'s 93 retargeted
     references are `PlotGeometryModule.to_pixel` and its siblings in one test
     file.
   - **A module no grep finds can still be live.** `DatabaseDocumentModule` was
     named nowhere, because each test package walks `names(pkg; all = true)` and
     re-exports whatever submodules it finds. Deleting it as dead would have
     removed `DatabaseTable` from every test silently. Its exports moved into
     `DatabaseModule` and the suite still passes.
   - **A slice whose module already carries the slice name is nearly free.**
     `PrimitiveModule` was already right, so its 49 references never moved.
2. **The 15 slices with 1 to 3 internal edges.**
3. **The 16 slices with 4 to 9.**
4. **The 11 slices with 10 or more.** Read each one before collapsing it. Two
   of them should not be collapsed at all — see §4.2.
5. **The kernel does not change at all.** Its 31 modules across 17 layers stay
   as they are, including the seven of the `projection` layer. This is the
   user's decision, not a deferral, so nothing in the kernel is on this plan's
   list.

**Treat a high edge count as a list of slices to divide, not as a reason to keep
file modules.** `graph` carries 39 internal edges across 17 modules and `text`
25 across 14. Read that as those two slices doing too much.

### 4.2 `graph` is a division candidate, not a collapse candidate

Reading it settles the question. Its 39 edges are not flat: they form a
dependency graph four to five levels deep.

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

And the two halves barely touch. `source/graph/omnetpp/` is a self-contained
port of a C++ force-directed layout engine — geometry, a random generator, a
component, the parameter families and two embeddings. It knows no document type.
The only edge from the top level into it is `GraphLayoutChoice`, which picks a
layouter.

Collapsing the slice would merge a layout algorithm library with a document and
its projections, and flatten a structure that is doing real work. **Divide it
instead:** `source/graph/` keeps the documents and the projections, and
`omnetpp/` becomes its own slice, plausibly its own package, since it depends on
nothing above it.

`text` at 25 edges across 14 modules wants the same reading before anything is
done to it.

Neither is on this plan's collapse list.

### 4.1 One file split waits for this plan

[ClipboardToAny.jl](../../source/clipboard/ClipboardToAny.jl) holds two
projection stems, `ClipboardSliceToAnyProjection` and
`ClipboardCollectionToAnyProjection`, under one module named for neither.
[naming-rule-violations.md](naming-rule-violations.md) §7.1 asks for two files.

The split waits for this plan, because today it would also split the module, and
the file does not divide:

- the two projection types and their two IO maps sit together, and
  `print_document`, `map_reference_forward` and `map_reference_backward`
  alternate between the stems through all 631 lines;
- **16 private helpers serve both stems** — `_clipboard_copy`, `_clipboard_cut`,
  `_clipboard_paste`, `_os_paste_document`, `_prefix_op`, `_prepend` and more;
- `WriteOsClipboardOperation` belongs to neither stem.

Splitting the module today means duplicating those 16 helpers or inventing a
third module to hold them. Once the clipboard slice is one module, the two stems
become two fragment files that share the helpers, and the split costs nothing.

Do it as part of the clipboard slice's step.

## 5. Open questions this plan must answer

1. **A slice whose name is also a kernel layer — ANSWERED.**
   `source/projection/` would want `ProjectionModule`, which
   [Projection.jl](../../source/kernel/projection/Projection.jl) already
   declares for the kernel's projection layer. The user decided on 2026-09-12:
   **the kernel keeps `ProjectionModule`, and the concrete projections take a
   different module name.** The slice holds eighteen domain-free projections —
   eight generic, eight higher-order and two compound — so it takes
   **`ProjectionAlgebraModule`**, which collides with nothing.

   The name is the package's own. The docstring of
   [ProjecturedProjection.jl](../../package/ProjecturedProjection/src/ProjecturedProjection.jl)
   already reads "the domain-free projection *algebra*: the generic and
   higher-order combinators, the compound aggregates … None of these owns a
   document." `Concrete` was the wrong axis, because `Identity` and `Constant`
   are as abstract as a projection gets, and `Generic` was unusable because it
   already names one of the three categories inside the slice.

   This is the one place where the module name is not the slice name. State it
   in the rules as a named exception with its reason, so a reader who derives
   `ProjectionModule` from the folder finds the exception rather than a
   contradiction. The alternative, a rename of the slice and its package to
   `projections` and `ProjecturedProjections`, costs more and buys the same
   thing.
2. **The projections table loses a row — FOLLOWS FROM THE DECISION.**
   [naming-rules.md](../../documentation/rule/naming-rules.md) derives four
   names from one stem, and one is `<Stem>ProjectionModule`. A projection no
   longer has a module of its own: it belongs to its slice's module, so
   `JsonToSyntax` lives in `JsonModule` and `Copying` in
   `ProjectionAlgebraModule`. Drop the module row and say the projection
   belongs to its slice. The remaining three names — file, type and IO map —
   still come from one stem.
3. **What replaces the intra-slice guard.** Either accept the loss, or assert
   something cheaper, such as that the slice module's `include` order is a valid
   order for the code that runs at load time.
4. **The namespace gets bigger.** `text` would hold 14 files of names in one
   module. Check what that does to `names(TextModule)` and to the model-facing
   tool surface before step 4.

## 6. What this cancels in the naming plan

[naming-rule-violations.md](naming-rule-violations.md) §4.1 and §14.1 — the 30
document module renames — are cancelled, not deferred. Several other rows lose
their module half and keep only their file half. §6 of that plan records which.
