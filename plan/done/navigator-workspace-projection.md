# Navigator Workspace Projection

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

Introduce a `Workspace` document layer between `WorkbenchNavigator` and the filesystem. The navigator holds a `Workspace` containing `WorkspaceFolder` elements. A new `WorkspaceFolderToFileSystemDirectory` projection expands each folder into a `FileSystemDirectory`, which then flows through the existing `FileSystemToSyntax → SyntaxToText → TextToGraphics` pipeline. This removes the hard-coded `WidgetLabel` creation in the navigator projection and naturally supports multi-root workspaces.

## New Documents

### 1. `program/src/document/Workspace.jl`

```julia
@document struct WorkspaceFolder <: Document
    name::String
    pathname::String
    selection::Reference
end

WorkspaceFolder(name::AbstractString, pathname::AbstractString) =
    WorkspaceFolder(String(name), String(pathname), Cell(nothing))

@document struct Workspace <: Document
    folders::CellVector
    selection::Reference
end

Workspace(folders::Vector{WorkspaceFolder}) =
    Workspace(CellVector(Cell[Cell(f) for f in folders]), Cell(nothing))
```

- `WorkspaceFolder` — a named root path (e.g. `"projectured-julia"` → `/home/user/workspace/projectured-julia`). Carries workspace-level metadata in the future (excludes, color labels, etc.).
- `Workspace` — ordered collection of folders. Lives inside `WorkbenchNavigator`.

## Core Changes

### 2. `program/src/document/Workbench.jl`

Change `WorkbenchNavigator` to hold a single `Workspace` instead of a raw `CellVector` of folders:

```julia
@document struct WorkbenchNavigator <: WorkbenchDocument
    workspace::Workspace
    selection::Reference
end

WorkbenchNavigator(workspace::Workspace) =
    WorkbenchNavigator(workspace, Cell(nothing))
```

### 3. `program/src/projection/primitive/WorkbenchToWidget.jl`

**Navigator projection**: Replace the manual `WidgetLabel` loop. Store `nav.workspace` directly as the scroll pane content. The downstream recursion handles rendering.

```julia
function projection_print(::WorkbenchNavigatorToWidgetScrollPane,
                           nav::WorkbenchNavigator, recursion, ctx)
    scroll = WidgetScrollPane(nav.workspace;
                              size=Point2D(224, 655),
                              padding=_PAD5, padding_color=_WHITE)
    WorkbenchNavigatorToWidgetScrollPaneIoMap(nothing, nav, scroll, Any[])
end
```

### 4. `program/src/projection/primitive/WorkspaceFolderToFileSystemDirectory.jl`

New projection that expands a `WorkspaceFolder` into a (shallow, one-level) `FileSystemDirectory`:

```julia
struct WorkspaceFolderToFileSystemDirectory <: Projection end

function projection_print(::WorkspaceFolderToFileSystemDirectory,
                           folder::WorkspaceFolder, recursion, ctx)
    dir = make_filesystem_pathname_shallow(folder.pathname)
    SimpleIoMap(nothing, folder, dir)
end
```

A `Workspace` projection dispatches to each `WorkspaceFolder` child via recursion.

### 5. `program/src/projection/primitive/WidgetToGraphics.jl`

**No change needed** — the scroll pane projection already uses `content isa Document` (line 843), which accepts any `Document` subtype including `Workspace`.

## Example Change

### 6. `example/src/projection/Workbench.jl`

Add workspace and filesystem types to the type dispatch:

```julia
function make_workbench_projection_example(; char_width=9, line_height=20)
    SequentialProjection(
        WorkbenchToWidget(),
        RecursiveProjection(TypeDispatchingProjection(
            # standard widget types...
            WidgetLabel      => WidgetLabelToGraphicsCanvas(...),
            WidgetScrollPane => WidgetScrollPaneToGraphicsCanvas(line_height),
            # ... etc
            # workspace types
            Workspace       => WorkspaceToFileSystem(),
            WorkspaceFolder => SequentialProjection(
                WorkspaceFolderToFileSystemDirectory(),
                FileSystemToSyntax(),
                SyntaxToText(),
                TextToGraphics(),
            ),
            # filesystem types (for recursive children)
            FileSystemDirectory => SequentialProjection(FileSystemToSyntax(), SyntaxToText(), TextToGraphics()),
            FileSystemFile      => SequentialProjection(FileSystemToSyntax(), SyntaxToText(), TextToGraphics()),
        )),
    )
end
```

### 7. `example/src/document/Workbench.jl`

```julia
workspace = Workspace([
    WorkspaceFolder("projectured-julia", root),
])
nav_page = WorkbenchPage([
    WorkbenchNavigator(workspace),
])
```

## Data Flow

```
WorkbenchNavigator
  → WorkbenchToWidget: WidgetScrollPane(content=Workspace)
  → WidgetToGraphics:  scroll pane projects content via recursion
      → Workspace dispatch → projects each WorkspaceFolder via recursion
          → WorkspaceFolderToFileSystemDirectory → FileSystemDirectory
          → FileSystemToSyntax → SyntaxToText → TextToGraphics
      → GraphicsCanvas embedded in viewport
```

## Notes

- Multi-root workspaces work naturally: add more `WorkspaceFolder` entries to the `Workspace`.
- `WorkspaceFolderToFileSystemDirectory` should scan lazily (one level), not eagerly read the entire tree. Subdirectory expansion happens when the user expands a node, triggering recursive projection of child `FileSystemDirectory` documents.
- The `_recurse` helper is not used by the navigator in the new code; other panels still use it unchanged.
- Reference forwarding for the navigator (`map_reference_forward`) returns `nothing` for now.
