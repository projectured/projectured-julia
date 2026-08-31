# Component Document Layer

> **Status (2026-08-12): IN PROGRESS.** `ComponentMasterDetail` is a standalone
> package now, `package/component/main/Component.jl` (`ProjecturedComponent`,
> depending only on `ProjecturedKernel`) — not
> `package/visual/main/component/Component.jl` and not registered inside a
> `ProjecturedDomain.jl` include list as the draft below assumes; every
> package exports its own symbols and there is no umbrella file. The
> `ComponentToWidget` projection, the DbCatalog browser example, and every
> candidate future component (`ComponentForm`, `ComponentTreeInspector`,
> `ComponentDashboard`, `ComponentWizard`, `ComponentSearchableList`) are still
> not implemented — confirmed by an empty `grep` for each name outside this
> plan and the module docstring.

Introduce a **component** layer between widgets and the workbench. Components are higher-level, behavioral UI building blocks composed from widget primitives.

## Context

The full UI layer stack:

| Layer | What it is | Examples |
|-------|-----------|----------|
| Document | Domain data, no UI concerns | `DbCatalogRdbms`, `JsonDocument`, `TextBlock` |
| Widget | Atomic UI primitives, layout & rendering | `WidgetSplitPane`, `WidgetScrollPane`, `WidgetText` |
| Component | Composed from widgets, delivers user-facing behavior | master-detail, form, toolbar+content, etc. |
| Workbench | Application-level shell | `WorkbenchWorkbench`, `WorkbenchEditor` |

Components fill the gap between widgets and workbench: reusable, behavioral UI units that compose widgets into interactive patterns.

A component:
- **composes** from widget primitives (split panes, scroll panes, tabs, etc.)
- **delivers** user-facing interactive behavior (e.g. "select item → show detail")
- **embeds** anywhere a `Document` is accepted — inside `WorkbenchEditor.content`, inside another component, or standalone
- **projects** to a widget tree via a `ComponentToWidget` projection

## Implemented

### ComponentMasterDetail (document only)

**✅ DONE (re-verified 2026-08-12):** `ComponentMasterDetail` exists at
[package/component/main/Component.jl](../../source/component/Component.jl)
(in `ComponentModule`) with all six listed fields (`master`, `detail`,
`selected_item`, `master_title`, `detail_title`, `split_ratio`) plus the
standard `selection::Reference`. `component` is now its own package
(`ProjecturedComponent`, depending only on `ProjecturedKernel`) rather than a
file included from a `ProjecturedDomain.jl` document-slice list — that
umbrella-include pattern no longer exists anywhere in the repository.

**File**: [Component.jl](../../source/component/Component.jl)

A two-pane component: master (tree/list) on the left, detail (inspector/form) on the right. Selecting an item in the master pane reactively updates the detail pane.

Fields:
- `master::Document` — left pane content (e.g. a DbCatalog tree)
- `detail::Document` — right pane content (reactive, driven by `selected_item`)
- `selected_item::Any` — the currently selected item from the master pane
- `master_title::String` — title for the left pane
- `detail_title::String` — title for the right pane
- `split_ratio::Float64` — fraction of width for the master pane (0.0–1.0)

## TODO

### ComponentMasterDetail projection

**⏳ OPEN (re-verified 2026-08-12):** No `ComponentToWidget` projection exists. The name `ComponentToWidget` appears only in the module docstring in [package/component/main/Component.jl](../../source/component/Component.jl) ("not yet implemented, tracked in `plan/pending/component-document.md`"); there is no projection file or implementation anywhere under `package/` (grep finds zero references outside that comment). None of the described forward-projection/reader/reactive behaviors are implemented.

Create `ComponentToWidget` projection that maps `ComponentMasterDetail` to:
```
WidgetSplitPane(:horizontal)
├── LayoutConstraint(WidgetTitlePane(master_title, WidgetScrollPane(master_content)))
└── LayoutConstraint(WidgetTitlePane(detail_title, WidgetScrollPane(detail_content)))
```

Key behaviors:
- Forward-project selection onto the focused pane (left or right)
- Reader intercepts selection events from the master pane to update `selected_item`
- The `detail` cell recomputes reactively when `selected_item` changes

### DbCatalog browser example

**⏳ OPEN (re-verified 2026-08-12):** No example uses `ComponentMasterDetail` / master-detail. [package/dbcatalog/example/document/DbCatalog.jl](../../example/dbcatalog/document/DbCatalog.jl) exists but a search for `ComponentMasterDetail`/`MasterDetail`/`master.detail` across `package/*/example/` returns no matches. This depends on the (still OPEN) projection above.

Build a concrete example using `ComponentMasterDetail`:
- Master pane: `DbCatalogRdbms` → `DbCatalogToSyntax` → `SyntaxToText` → `TextToGraphics` (tree with expand/collapse)
- Detail pane: reactive, type-dispatched on `selected_item`:
  - `DbCatalogTable` → SQL query → `CellTableToTable` → `TableToGraphics` (tabular view)
  - `DbCatalogSchema` → list of tables via `SyntaxToText`
  - `DbCatalogColumn` → detail form via `WidgetComposite` with labels

### Future components

**⏳ OPEN:** None of these candidate components exist. Grep across `package/` finds no `ComponentForm`, `ComponentTreeInspector`, `ComponentDashboard`, `ComponentWizard`, or `ComponentSearchableList`. Explicitly noted as "not yet planned in detail".

Candidates for the component layer (not yet planned in detail):

- **ComponentForm** — labeled fields in a vertical/grid layout, with validation
- **ComponentTreeInspector** — specialized tree + property grid (narrower than master-detail)
- **ComponentDashboard** — grid of tiles, each hosting a different document/projection
- **ComponentWizard** — step-by-step flow with back/next navigation
- **ComponentSearchableList** — text filter field + scrollable list
