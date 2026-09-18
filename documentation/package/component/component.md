# Component

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

A component composes widget primitives into a reusable, behavioral UI unit —
a layer meant to sit between a document and a widget tree, the way a form or
a master-detail view combines several widgets into one interactive pattern.
Today the slice defines one such composite, `ComponentMasterDetail`, as a
document; no projection renders it yet.

## What is in the slice

| File | What it holds |
| --- | --- |
| `source/component/ComponentModule.jl` | the module, and what it exports |
| `source/component/ComponentDocument.jl` | the abstract `ComponentDocument`, and `ComponentMasterDetail` |

## The document

```julia
ComponentMasterDetail(master, detail; selected_item = nothing,
                       master_title = "Master", detail_title = "Detail",
                       split_ratio = 0.3)
```

`ComponentMasterDetail` is a two-pane layout: `master` is the document shown
in the left pane, typically a tree or a list; `detail` is the document shown
in the right pane, typically an inspector or a form. `selected_item` holds
the item the master pane last selected; a caller drives `detail` from it,
for example by making `detail` a reactive cell that recomputes whenever
`selected_item` changes. `master_title` and `detail_title` label the two
panes, and `split_ratio` is the fraction of the width the master pane gets,
from 0.0 to 1.0.

## What a reader must know before changing this

`ComponentModule` exports only `ComponentDocument`; `ComponentMasterDetail`
is reached through the `ProjecturedComponent` package, not re-exported at
the top level. No `ComponentToWidget` projection exists, so a
`ComponentMasterDetail` cannot yet be rendered or edited in the running
editor — it is a document type with no view. There is no `test/component/`
and no `example/component/`. `plan/pending/component-document.md` tracks the
projection and the further components (a form, a tree inspector, a
dashboard, a wizard, a searchable list) that this slice does not have yet.

## How it fits

`ProjecturedComponent` depends only on `ProjecturedKernel`; it imports no
widget type. The intended position is between the document layer and the
widget layer that [widget.md](../widget/widget.md) describes: a component
would compose widgets the way `WorkbenchEditor` composes panes, without
being a domain of its own.
