# Navigator Filesystem Projection

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

Make the workbench navigator use the filesystem projection pipeline (`FileSystemToSyntax → SyntaxToText → TextToGraphics`) for its content, removing hard-coded `isa` guards that prevent the projection system from working generically.

## Core Changes

### 1. `program/src/projection/primitive/WorkbenchToWidget.jl`

**Navigator projection** (lines 125–139): Replace the manual WidgetLabel creation loop with storing the first folder document directly as the scroll pane content.

Before:
```julia
folder_iomaps = Any[]
for i in eachindex(nav.folders)
    folder = nav.folders[i]
    name   = hasproperty(folder, :pathname) ? basename(folder.pathname) : string(folder)
    label  = WidgetLabel(Point2D(0, 0), name)
    push!(folder_iomaps, SimpleIoMap(nothing, folder, label))
end
composite = WidgetComposite(Point2D(0, 0), WidgetDocument[fm.output for fm in folder_iomaps])
scroll = WidgetScrollPane(composite; ...)
```

After: Store `nav.folders[1]` (the root filesystem doc) directly as scroll pane content. The downstream `WidgetToGraphics` recursion handles rendering. The `folder_iomaps` vector becomes empty (or is removed from the IoMap struct).

### 2. `program/src/projection/primitive/WidgetToGraphics.jl`

**Scroll pane projection** (line 711): Change `content isa WidgetDocument` → `content !== nothing`

```julia
# Before
if content isa WidgetDocument
# After
if content !== nothing
```

This lets the scroll pane project any content through `recursion`, not just widgets.

## Example Change

### 3. `example/src/projection/Workbench.jl`

Build a custom `WidgetToGraphics` type dispatch that includes filesystem entries alongside the standard widget types:

```julia
function make_workbench_projection_example(; char_width=9, line_height=20)
    SequentialProjection(
        WorkbenchToWidget(),
        RecursiveProjection(TypeDispatchingProjection(
            # standard widget types...
            WidgetLabel      => WidgetLabelToGraphicsCanvas(...),
            WidgetScrollPane => WidgetScrollPaneToGraphicsCanvas(line_height),
            # ... etc
            # filesystem types (full pipeline to graphics)
            FileSystemDirectory => SequentialProjection(FileSystemToSyntax(), SyntaxToText(), TextToGraphics()),
            FileSystemFile      => SequentialProjection(FileSystemToSyntax(), SyntaxToText(), TextToGraphics()),
        )),
    )
end
```

## Data Flow

```
WorkbenchNavigator
  → WorkbenchToWidget: WidgetScrollPane(content=FileSystemDirectory)
  → WidgetToGraphics:  scroll pane projects content via recursion
      → FileSystemDirectory dispatch → FileSystemToSyntax → SyntaxToText → TextToGraphics
      → GraphicsCanvas embedded in viewport
```

## Notes

- The `_recurse` helper is not used by the navigator in the new code; other panels (console, editor) still use it unchanged (their content is `nothing` in the scroll pane, so removing the `isa WidgetDocument` guard doesn't affect them).
- Reference forwarding for the navigator (`map_reference_forward`) returns `nothing` for now (same as most other panels).
- Only single-root navigator (like the example's `WorkbenchNavigator([fs_root])`) is handled. Multi-root support can be added later with a container projection.
