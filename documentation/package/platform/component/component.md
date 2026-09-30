# Component

> **Kind:** design · **Status:** current · **Stands on:** [widget.md](../widget/widget.md), [document.md](../../kernel/document.md)

`ProjecturedComponent` is meant to hold components: reusable units of a user interface, such as a master-detail view, that combine widgets and behave as one. It holds one document type and no projection yet. This document says what exists, what does not, and where the plan for the rest is.

## How it works

`source/platform/component/ComponentDocument.jl` holds the abstract root `ComponentDocument` and the one concrete `@document`, `ComponentMasterDetail`:

```julia
ComponentMasterDetail(master, detail; selected_item = nothing,
                      master_title = "Master", detail_title = "Detail",
                      split_ratio = 0.3)
```

`master` is the document of the left pane, such as a tree or a list. `detail` is the document of the right pane, such as a form. `selected_item` holds the item that the master pane selected last. A caller can make `detail` a computed cell that reads `selected_item`, so the detail follows the selection. `split_ratio` is the part of the width that the master pane gets, from 0.0 to 1.0.

No projection draws a `ComponentMasterDetail`, and no reader edits it. The module docstring names a `ComponentToWidget` projection, which does not exist.

## How it fits

`ProjecturedComponent` depends only on the kernel and imports no widget type. `ComponentModule` exports only `ComponentDocument`; the concrete type is `ComponentModule.ComponentMasterDetail`. The umbrella package `Projectured` loads it, but no other package reads a component. The package registers nothing.

The planned place of a component is between a domain document and the widgets: a `ComponentToWidget` projection would draw a `ComponentMasterDetail` as a `WidgetSplitPane` of two panes.

## Design decisions

- **A component is a document.** A component can then be embedded, saved and driven by cells as any other document, and a helper function that builds widgets can do none of these. See [plan/pending/component-document.md](../../../../plan/pending/component-document.md).
- **The master-detail view is one component, not a family of types.** Two larger designs with their own resolver and a cache of detail documents were not built. See [plan/obsolete/master-detail-document.md](../../../../plan/obsolete/master-detail-document.md) and [plan/obsolete/master-detail-editable.md](../../../../plan/obsolete/master-detail-editable.md).

## Usage

```julia
using ProjecturedComponent: ComponentModule
view = ComponentModule.ComponentMasterDetail(master_document, detail_document;
                                             master_title = "Tables", split_ratio = 0.25)
```

`master_document` and `detail_document` stand for any two documents.

- Examples and tests: none. `test/component/` and `example/component/` do not exist.

## Limits

- A `ComponentMasterDetail` can not be drawn or edited, because `ComponentToWidget` does not exist.
- [plan/pending/component-document.md](../../../../plan/pending/component-document.md) holds the open work: `ComponentToWidget`, and a database catalog browser built on the master-detail view. It also names further components: a form, a tree inspector, a dashboard, a wizard and a searchable list.
