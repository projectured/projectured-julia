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
- **Most of the kernel already works this way.** `DocumentModule` owns nine
  fragments, and 11 of the 17 layers have exactly one module. Six do not:
  `projection` has 7, `cell` has 3, and `agent`, `editor`, `event` and
  `operation` have 2 each. So the kernel is evidence for the pattern, not proof
  of it, and its own `projection` layer is the sharpest counter-example in the
  repository.
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

1. **`database`, `plot`, `primitive`** — 3 slices, 0 internal edges. Nothing is
   lost. Prove the shape here.
2. **The 15 slices with 1 to 3 internal edges.**
3. **The 16 slices with 4 to 9.**
4. **The 11 slices with 10 or more**, hardest last: `graph` 39, `text` 25,
   `process` 15, `syntax` 13, `pane` 12, `projection` 10.
5. **The kernel is a separate step, and it is not free.** 11 of its 17 layers
   already hold one module and need nothing. Six hold more: `projection` 7,
   `cell` 3, and `agent`, `editor`, `event` and `operation` 2 each. Decide each
   of those six on its own. The `projection` layer is the hard one, and §5.1
   ties it to the slice of the same name.

**Treat a high edge count as a list of slices to divide, not as a reason to keep
file modules.** `graph` carries 39 internal edges across 17 modules and `text`
25 across 14. Read that as those two slices doing too much. Consider dividing
them into more slices before or instead of collapsing them.

## 5. Open questions this plan must answer

1. **A slice whose name is also a kernel layer.** `source/projection/` would
   want `ProjectionModule`, and
   [Projection.jl](../../source/kernel/projection/Projection.jl) already
   declares that name for the kernel's projection layer. Two units of
   architecture want one word. Pick the rule for this case before step 4, and
   note that the kernel's projection layer is also the one layer with seven
   modules, so both halves of this collision are unsettled.
2. **The projections table loses a row.**
   [naming-rules.md](../../documentation/rule/naming-rules.md) derives four
   names from one stem, and one of them is `<Stem>ProjectionModule`. A
   projection stops having a module of its own under this rule. Decide what the
   table says instead.
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
