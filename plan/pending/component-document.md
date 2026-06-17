# Component Document Layer

Introduce a **component** layer between widgets and the workbench. Components are higher-level, behavioral UI building blocks composed from widget primitives.

## Context

The full UI layer stack:

| Layer | What it is | Examples |
|-------|-----------|----------|
| Document | Domain data, no UI concerns | `DbCatalogRdbms`, `JsonDocument`, `TextText` |
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

**File**: [Component.jl](../../program/src/document/Component.jl)

A two-pane component: master (tree/list) on the left, detail (inspector/form) on the right. Selecting an item in the master pane reactively updates the detail pane.

Fields:
- `master::Document` — left pane content (e.g. a DbCatalog tree)
- `detail::Document` — right pane content (reactive, driven by `selected_item`)
- `selected_item::Any` — the currently selected item from the master pane
- `master_title::String` — title for the left pane
- `detail_title::String` — title for the right pane
- `split_ratio::Float64` — fraction of width for the master pane (0.0–1.0)

Registered in [ProjecturEd.jl](../../program/src/ProjecturEd.jl) after Widget/Layout and before Workbench.

## TODO

### ComponentMasterDetail projection

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

Build a concrete example using `ComponentMasterDetail`:
- Master pane: `DbCatalogRdbms` → `DbCatalogToSyntax` → `SyntaxToText` → `TextToGraphics` (tree with expand/collapse)
- Detail pane: reactive, type-dispatched on `selected_item`:
  - `DbCatalogTable` → SQL query → `CellTableToTable` → `TableToGraphics` (tabular view)
  - `DbCatalogSchema` → list of tables via `SyntaxToText`
  - `DbCatalogColumn` → detail form via `WidgetComposite` with labels

### Future components

Candidates for the component layer (not yet planned in detail):

- **ComponentForm** — labeled fields in a vertical/grid layout, with validation
- **ComponentTreeInspector** — specialized tree + property grid (narrower than master-detail)
- **ComponentDashboard** — grid of tiles, each hosting a different document/projection
- **ComponentWizard** — step-by-step flow with back/next navigation
- **ComponentSearchableList** — text filter field + scrollable list
