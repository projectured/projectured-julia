# A person sets the zoom, the scales and the themes of an editor

> **Status:** pending, not started. Written on 2026-09-30 at the owner's
> request. The owner decided the design on 2026-10-01; section 5 logs each
> decision. The owner approved the unseal of `device/Display.jl` (step N1) and
> of `cell/CellModule.jl`, `cell/ReactiveCell.jl`, `struct/CellStructPlan.jl`
> and `struct/CellStruct.jl` (step C1). On 2026-10-01 the owner also allowed a
> change of the docstrings only in `cell/CellComputation.jl`,
> `cell/CellInterface.jl`, `cell/CellDefaults.jl` and
> `struct/CellStructModule.jl`, where they say that only a reactive cell
> computes or that there are three kinds.
>
> **In progress** on the branch `appearance`, in the worktree
> `.claude/worktrees/appearance`. Section 9 holds what the work found.

## 1. The request

The owner asked on 2026-09-30:

> In projectured-julia, I would like to gather all information about UI scale,
> font scale behaviour and operation. I want to add icon scale, and spacing
> scale. I would like to create a plan for controlling these from the user
> interface using widgets and also using keyboard shortcuts with immediate
> effect. I think a complete invalidation is ok, the output doesn't have to
> depend on it. Then I would also like to be able to control fonts and colors
> and actual sizes in the widget theme.

During the design the owner widened the request: each domain gets a theme, not
only the widgets. So the plan has two parts:

- **The zoom and the scales.** Seven factors for each editor: the zoom of the
  interface, and six scales: of the fonts, of the icons, of the spacing, of the
  parts of controls that are not text, of the corner radii and of the line
  widths. A person changes each one in a tab, and four of them also with a key.
  The change shows at the next frame.
- **The themes.** Each domain that draws gets a theme: its fonts, its colors and
  its sizes, with fewer spacing values than now. A person changes them in the
  same tab, with the same immediate effect, and saves and loads them with two
  buttons.

## 2. The words

The rule, decided on 2026-10-01 (D1):

- A **zoom** magnifies a view after the layout. The layout rules do not change;
  the layout only gets less room. A person chooses it. Examples: the zoom of the
  interface, the zoom of a `WidgetTransformPane`, the zoom of a chart.
- A **scale** multiplies one kind of length before the layout, so the layout
  changes. A person chooses it. The six scales are the font scale, the icon
  scale, the spacing scale, the control scale, the radius scale and the line
  scale.
- The **density** of a display is a fact of the hardware: the number of device
  pixels for each logical pixel. The system gives it. A person does not choose
  it in the editor.
- The **device pixel ratio** is the density times the zoom. The backend
  multiplies with it.

| Concept | Chosen by | Applied | Name now | Name in this plan |
| --- | --- | --- | --- | --- |
| device pixels for each logical pixel of the display | the system | by the backend, after layout | `Display.scale` | `Display.density` |
| magnification of the whole editor | the person | by the backend, after layout | `Display.zoom`, "uniform zoom" | zoom |
| the product of the two | — | by the backend | device pixel ratio | device pixel ratio |
| the size of every font | the person | in layout | `_FONT_ZOOM`, "font zoom" | font scale |
| the size of every icon | the person | in layout | nothing | icon scale |
| the size of every space | the person | in layout | nothing | spacing scale |
| the size of the parts of controls that are not text | the person | in layout | nothing | control scale |
| the radius of every corner | the person | in layout | nothing | radius scale |
| the width of every line | the person | in layout | nothing | line scale |
| device pixels for each logical pixel of an image or a video | the caller | by the backend | `write_image(; scale)`, `record_video(; scale)` | `density` |
| the function from the share of a slider to its value | the author | — | `WidgetSlider.scale` | `mapping` |

**What step N1 renames.** All the uses are in this repository; omnet-julia and
inet-julia have none (2026-10-01).

- `Display.scale` → `Display.density`.
- `PROJECTURED_DISPLAY_SCALE` → `PROJECTURED_DISPLAY_DENSITY`, and
  `_PROBED_DISPLAY_SCALE` → `_PROBED_DISPLAY_DENSITY`.
- The `scale` of `write_image`, `record_video`, `make_video` and
  `VideoBackend` → `density`.
- `step_zoom` → `step_factor`, because it steps the zoom and the six scales
  through one table.
- `WidgetSlider.scale` → `mapping`.
- "font zoom" → "font scale", and "uniform zoom" → "zoom", in the guides.

Other steps remove `_FONT_ZOOM`, `adjust_font_zoom!`, `AdjustFontZoomOperation`
and the kernel form of `AdjustZoomOperation` (section 4.6).
`get_device_pixel_ratio` and `font_device_size` stay.

## 3. What exists

### 3.1 The zoom of the interface

- `Display` (`source/kernel/device/Display.jl`, sealed 🔒) has `scale`, the
  hardware, and `zoom`, the choice of the person.
  `get_device_pixel_ratio(display)` is `scale * zoom`.
- `step_zoom(zoom, delta)` (`source/style/Font.jl:83`) steps through
  `_ZOOM_STEPS`: 0.5, 0.67, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0.
  A `delta` of 0 gives 1.0.
- `_zoom_operation` (`source/kernel/editor/ReadEvaluatePrint.jl:136`) turns
  Ctrl+`=`, Ctrl+`-` and Ctrl+`0` into `AdjustZoomOperation(delta)`. Shift is
  allowed, so Ctrl++ works. `read!` calls it only when no reader takes the key,
  so `WidgetTransformPane` keeps its own Ctrl+=.
- Only the SDL backend evaluates the operation (`source/sdl/Sdl.jl:4131`). It
  steps `display.zoom`, scales the logical size of each window so that its
  device size stays, and repaints every window in full. It does not project
  again, because layout does not read the zoom.
- PDF, video and `write_image` have their own `scale` and do not read the
  `Display`.
- The hardware scale comes from `PROJECTURED_DISPLAY_SCALE`, then from
  `Xft.dpi`, then from SDL (`Sdl.jl:660-757`).

### 3.2 The zoom in the web backend

- The client (`asset/web/client.js`) sizes its canvas by
  `window.devicePixelRatio`. It reports `innerWidth` and `innerHeight` as the
  logical size of the window. So the zoom of the browser already acts as the
  zoom of the interface: the device pixel ratio grows and the logical size
  shrinks.
- The client calls `preventDefault` for each key with Ctrl (`client.js:638`), so
  Ctrl+= never reaches the zoom of the browser. The server gets the key, and no
  method evaluates `AdjustZoomOperation` there. So Ctrl+= does nothing in a web
  editor now. Only the menu of the browser zooms.
- The server decodes a key by its character (`Web.jl:125-150`). `.` is
  `:period`, `=` and `+` are `:equals`, but `,`, `[` and `]` are `:char`.

### 3.3 The font zoom

- `_FONT_ZOOM` is one `Cell(1.0)` for the process (`source/style/Font.jl:50`).
  This breaks PAR-PER-EDITOR-STATE.
- `font_logical_size(font)` and `font_device_size(font, ratio)` multiply
  `font.size` by it. They have 11 calls in 5 files: `TextMeasure.jl` (3),
  `TrueType.jl` (2), `Sdl.jl` (4), `Pdf.jl` (1), `Web.jl` (1). No caller has a
  printer context.
- Ctrl+Alt+`=`/`-`/`0` gives `AdjustFontZoomOperation(delta)`. Only SDL
  evaluates it: `adjust_font_zoom!`, then `editor.iomap = nothing`, then a full
  repaint. 3.9 says why it must drop the IO map.
- With the web backend alone, Ctrl+Alt+= does nothing. With the SDL package
  loaded, it changes the font zoom of every editor in the process.
- `plan/pending/font-zoom-per-editor.md` gives three options to make it per
  editor. This plan chose none of them: the font scale lives in the themes
  (D18, D20).

### 3.4 Icons

- Every built-in icon is a Lucide glyph (`LUCIDE_ICON_GLYPHS`,
  `WidgetToGraphics.jl:6871`), drawn at the size of a square box.
  `icon_width(name, size)` is `size` (`:6841`).
- The caller gives the box. The button gives its content height (`:1863`), the
  menu item its line height (`:2371`), the toolbar item the height of "M"
  (`:2478`), the tab its title height (`:4028`), the card its title height
  (`:6665`). The tree has an icon column of 20 (`:8946`).
- A label can write an icon as text with `find_icon_character` in
  `font_lucide_icons_20` (`ConversationToWidget.jl:92`). That icon follows the
  font zoom.
- So an icon follows the text around it. No setting changes an icon alone.

### 3.5 Spacing

- `_sc(px) = Int(px)` (`WidgetToGraphics.jl:230`) is an identity. 106 lines of
  `WidgetToGraphics.jl` and 6 lines of `WidgetTableParts.jl` call it. Its
  comment says that the projection never scales.
- The theme holds the shared spacing: `radius` 8, `pad_x` 14, `pad_y` 9,
  `gap` 4, `border_width` 1, `stroke` 2, `chevron` 4.
- The factory gives about 40 more numbers to single widgets. Examples: the
  checkbox box 18, the switch track 44×24, the slider 24/4/9, the radio
  18/10/12/5, the tree 22/18/20/4, the card padding 16, the alert padding 14,
  the badge padding 3/10, the scroll bar 12 and 8, the progress bar 8, the gap
  between an icon and its label 6 (8 in a card), and the ring width 2 in 17
  places. Step B0 writes the full list into this plan.
- Outside the widgets: the tooltip (offset, minimum and maximum size), the
  command palette (padding 10, radius 6, and Solarized colors of its own), the
  gesture help window, the charts and the sequence charts (`_PAD`, `_TICK` and
  more).

### 3.6 The widget theme

- `WidgetTheme` (`WidgetToGraphics.jl:46`) is a plain immutable struct with 40
  fields: 20 palette colors, 6 decorations, `radius`, 3 fonts, `pad_x`, `pad_y`,
  `gap`, `border_width`, `stroke`, `chevron`, and 4 text styles. Each field has
  a reader.
- Four presets exist: `make_light_theme`, `make_dark_theme`,
  `make_slate_light_theme` (the default) and `make_slate_dark_theme`. They share
  `_widget_theme`, which sets the spacing and derives the decorations. For
  example, `hover_layer` is `primary` at 12%.
- `WidgetToGraphics(font; measure, theme)` reads the theme once. Each of the 42
  widget projections copies the values that it needs into its style fields.
  `@projection` keeps each field in a cell, and `p.field` reads the cell. No
  projection reads a theme at print time, and no printer context carries one.
- Five call sites in this repository make a `WidgetToGraphics`, and none of them
  passes a theme: `NaturalProjection.jl:112`, `WindowWrap.jl:162`,
  `WindowShell.jl:66`, `FileSystemToSyntax.jl:229` and
  `DataFrameViewToWidget.jl:153`. omnet-julia makes a theme of its own with
  keywords (`build_qtenv_widget_theme`).
- A font is `StyleFont(filename, size::Int)`. The font directory holds Ubuntu,
  Ubuntu Mono, DejaVu Sans, DejaVu Sans Mono, Liberation Sans, Liberation Serif,
  Inconsolata and Lucide.
- Other domains have no theme. The syntax colors are Solarized constants in each
  projection. The charts use module constants behind a `ChartStyle` whose
  `nothing` means the default. `plan/done/widget-color-design.md` decided that
  the colors of a domain belong to the projection of that domain, not to the
  widget theme.

### 3.7 Keys, commands and tools

- A `@gestures` table binds keys for one document type. A binding with no key
  (`nothing => "description" => rhs`) is a command of the palette only. F1
  lists the bindings on the route, and Ctrl+Shift+P runs one by name.
- The zoom keys are in no table. `read!` finds them after the pipeline, so F1
  and the palette do not show them.
- A tool tab opens with `_reach_tool!` (`source/shell/WindowChrome.jl:313`) from
  a toolbar item or a menu item. The toolbar has Explorer, Evaluator, Message
  log, Gesture log, Fault log, Statistics, Frame plot and Selection. The View
  menu has the splits and the gesture log.
- Ctrl+, and Ctrl+. are "Focus out" and "Focus in" of `FocusingProjection`, but
  only where that projection is on the route.
- No settings tab, window or document exists.

### 3.8 Controls that edit a value

- A number: `WidgetSpinBox` steps by a fixed `step`. `WidgetSlider` sets a share
  from 0 to 1, and it has `scale`, `target` and `field`. `WidgetText` takes a
  number as text.
- A choice: `WidgetSelect`, `WidgetToggleGroup`, `WidgetRadioGroup`,
  `WidgetList`.
- A flag: `WidgetCheckbox`, `WidgetSwitch`, `WidgetToggle`.
- A color: nothing. `ObjectToWidget` shows no `StyleColor`, `StyleFont` or
  `Point2D`.
- A button runs an `Action`. The callback of the action gets the editor.

### 3.9 What a print records

- A computed cell records each cell that it reads, and it computes again when
  one of them changes. The cell layer is sealed (🔒).
- A container prints a child through `reconcile_child_iomap` or
  `reconcile_child_iomaps` (`source/kernel/iomap/IoMapReconcile.jl`, ⬜). The
  print of the child (`make_iomap`) runs inside the computation of that cell.
  So the cell records each cell that the print of the child reads outside the
  cells of the child.
- But the cell keeps the old IO map of the child while the child document is
  the same object (`cached_id[] != id`). So when a read of the print changes,
  the cell computes again and gives back the old child. The sizes that the print
  measured stay. The widgets measure their text while they print and keep the
  sizes as constants (`plan/done/font-zoom-widget-resize.md`). That is why the
  font zoom drops the whole IO map.
- The root print (`print!`, `ReadEvaluatePrint.jl:184`) runs in no cell, so
  nothing records its reads.
- A wrapper prints its inner projection once, in the body of its print. The
  fault barrier does so at `source/fault/Catching.jl:121`.
- The cell layer runs no function when a cell changes. A write marks the
  dependent cells invalid, and a cell computes again when something reads it.
  `peek(c)` reads one cell and records no edge. No function runs a block of code
  with no recording. The stack of the running computations is task-local, in
  `source/kernel/cell/ReactiveCell.jl` (🔒).
- `print!` puts `:root`, `:fault_store` and `:fault_policy` into the printer
  context. `run_frame!` binds the performance counters in a scoped value
  (`EditorLoop.jl:206`).

### 3.10 Other plans

- `plan/pending/font-zoom-per-editor.md`: this plan replaces it. When step W2
  is done, that plan moves to `plan/done/` with a note.
- `plan/pending/line-spacing-from-the-theme.md`: a theme value for the line
  spacing. The themes of this plan are the place for it. This plan does not do
  it.
- `plan/pending/sdl-per-editor-state.md`, Part 2: the SDL session is shared.
  This plan does not need it.
- `plan/pending/configuration-overlay-widget.md` and
  `plan/pending/key-chords-from-bindings.md`: this plan does not use them.

## 4. The design

### 4.1 The appearance of an editor

An `Appearance` holds everything that a person sets about the look of one
editor:

- the zoom;
- the six scales: font, icon, spacing, control, radius and line;
- for each domain, its theme and its scaled theme, found by the type of the
  theme.

The main builder of an editor creates the `Appearance`, builds the projection
with it, and returns it. The `appearance` wrapper of `build_editor` wraps the
root document in an `AppearanceDocument`, with the fields `appearance` and
`content`, and wraps the projection in an `AppearanceManagingProjection` (4.5).
The collection reaches that wrapper as the setting of its keyword:
`build_editor(document, projection; appearance = collection)`. The kernel only
passes the setting on, as it does for `window`. On the path with no projection,
`build_editor(document)`, a seam of the build makes the `Appearance` before the
projection is built (4.13).

**The editor knows nothing about themes.** It gets a document and a projection,
as now. It holds no appearance, binds no value for a frame, and evaluates no
zoom and no scale.

### 4.2 A theme and a scaled theme

A domain declares its theme with the macro `@theme`. The type of each field
says which scale applies to it:

| Type of the field | Scale |
| --- | --- |
| `StyleFont` | font scale |
| `StyleText` | font scale on its font; the color stays |
| `StyleStroke` | line scale on its width |
| `StyleColor` | none |
| `Spacing` (a number or an `Inset`) | spacing scale |
| `Radius` | radius scale |
| `LineWidth` | line scale |
| `ControlSize` | control scale |
| `IconSize` | icon scale |

```julia
@theme struct JsonTheme
    key_text::StyleText = StyleText(font_ubuntu_monospace_regular_20, color_solarized_blue)
    indent::Spacing     = Spacing(16)
    border::LineWidth   = LineWidth(1)
end
# The macro generates two structs:
# - JsonTheme: one cell for each field; the tab edits these cells.
# - ScaledJsonTheme: one computed cell for each field, the base value times the
#   scale of its kind, for example
#     key_text = StyleText(scale_font(theme.key_text.font, scales.font), theme.key_text.color)
#     indent   = round(Int, theme.indent.value * scales.spacing)
#     border   = max(1, round(Int, theme.border.value * scales.line))
```

- A length above 0 stays at least 1 logical pixel after its scale.
- The computed cells of a scaled theme keep their edges to their base value and
  to their scale. These edges stay inside the theme.
- A font of a scaled theme has its final size. So the measure, the drawing and
  the export use `font.size` as it is. `_FONT_ZOOM` goes, and
  `font_logical_size` reads no scale.
- A size that a document gives, such as the height of a viewport, a split size
  or `WidgetSpinBox(width = 80)`, takes no scale. Only the zoom changes it.

**What each kind covers in the widgets:**

| Length | Examples now | Kind |
| --- | --- | --- |
| text | all fonts | font |
| named icons, the icon column of a tree, chevrons | the box from the caller, 20, `chevron` 4 | icon |
| paddings and margins | `pad_x` 14, `pad_y` 9, card 16, alert 14, badge 3/10, menu 4, tab 4 | spacing |
| gaps between items | `gap` 4, title gap 6, icon to label 6/8, radio rows 12, accordion 4/10 | spacing |
| indents | tree indent 22, tree row padding 4 | spacing |
| parts of controls that are not text | checkbox 18, radio 18/5, switch 44×24, slider 24/4/9, progress 8, scroll bar 12/8 | control |
| corner radii | `radius` 8, 6, row radius 4 | radius |
| line widths | `border_width` 1, `stroke` 2, ring 2, separators, splitters, table rules | line |

The box of a named icon is the box that the caller gives, times the icon scale.
A row that holds an icon grows to the larger of the icon and the text line. An
icon written as text with `find_icon_character` follows the icon scale too.

**Sizes in the theme, and fewer of them.** The widget theme gets a value for
each size that a person can want to change. The spacing values become about 8
named values, one for each use: the padding of a control (x and y), the padding
of a container, the gap between items, the gap under a title, the gap between
an icon and its label, the indent and the padding of a row. The radii become
`radius` and `radius_small`, and the lines `border_width`, `stroke` and
`ring_width`. Each named value is one row of the tab. This changes the default
look a little, for example 9 becomes 8, so step B0 shows images before and
after, and the owner accepts the new baseline.

### 4.3 How the projections get and read their themes

- **A constructor takes its theme as a keyword, with a default.** A default is a
  new theme object for each projection, never one object for the process. A
  projection that uses its default is outside the `Appearance`: the tab does not
  edit it and the scales do not change it. The defaults serve tests, examples
  and projections built on their own; the main builder passes a theme for each
  domain that it shows.
- **A composite builder passes the themes down.** A builder that names its parts,
  such as the window chrome, takes their themes as separate keywords.
  `NaturalToGraphics`, whose domains register themselves, passes the
  `Appearance` to each registered factory, and a factory takes its own scaled
  theme from it, or its default. This is the path that `measure` takes now. A
  row that a domain registers as one ready-made projection becomes a factory,
  because a projection now holds the scaled themes of one editor.
- **A style field reads the scaled theme with no edge.** A projection is declared
  `@projection UntrackedCell struct …`. The factory builds one `UntrackedCell`
  for each theme value and each derived value, such as the ring stroke at the
  ring width, and each projection that uses it holds the same cell. A keyword
  of a constructor sets a plain value, which never reads the theme. The
  printers do not change: they read `p.content_color` as now.
- **A font in a document is as its author set it.** An author can copy a font
  from a theme or from a scaled theme, or give a document a reactive font that
  follows the scaled theme. A scale does not change a font of a document by
  itself.

### 4.4 `UntrackedCell`

A new kind of cell, in `source/kernel/cell/UntrackedCell.jl`. It runs its
computation at each read, keeps no value and records no edge, and no read
inside its computation records one:

```julia
struct UntrackedCell{T} <: AbstractCell{T}
    computation::Function
    UntrackedCell{T}(marker::Computation) where {T} = new{T}(marker.computation)
    UntrackedCell{T}(value) where {T} = new{T}(Returns(convert(T, value)))
end

# There is no `setindex!`: a write is a `MethodError`, as for `ImmutableCell`.
Base.getindex(c::UntrackedCell{T}) where {T} = run_untracked(c.computation)::T
Base.peek(c::UntrackedCell) = c[]
is_cell_up_to_date(::UntrackedCell) = true
is_computed_cell(c::UntrackedCell) = !(c.computation isa Returns)
copy_cell_as(c::UntrackedCell{T}, v) where {T} = UntrackedCell{T}(v)
```

`run_untracked` lives in `ReactiveCell.jl`, beside `_get_computing_stack`, and is
not exported. It swaps the task-local computing stack for an empty one, so no
read inside `f` finds a reader. A cell that computes inside `f` puts itself on
the new stack and still records its own dependencies:

```julia
function run_untracked(f)
    stack = _get_computing_stack()
    isempty(stack) && return f()                 # no reader: nothing to stop
    storage = task_local_storage()
    storage[:projectured_reactive_computing] = ReactiveCell[]
    try
        return f()
    finally
        storage[:projectured_reactive_computing] = stack
    end
end
```

- The struct layer finds a kind by name, so `UntrackedCell` joins
  `_find_cell_kind`. `@projection UntrackedCell struct …` then sets the kind of
  every field with one word. `@document UntrackedCell` also becomes possible; no
  coded prefix such as `UCFoo` is added.
- The kind is an immutable struct with one pointer, so a projection keeps the
  pointer to the shared function inline, with no cell object. A view uses less
  memory than now.
- Other reactive cells pay nothing: `getindex` of `ReactiveCell` does not change.
  A read of an untracked cell costs a lookup and two writes in the task storage,
  a small empty vector, and one call through the abstract type `Function`. A
  spare empty vector for each task can remove the allocation, if the frame times
  show that it matters.
- A style field can not be written after the factory built the projection.
  Nothing writes one now (checked 2026-10-01).

### 4.5 The wrapper

`AppearanceManagingProjection` wraps the whole view: it is a wrapper of
`build_editor` in the `:screen` layer, on by default, so it also wraps the window
manager. `make_editor` applies no wrapper, so a test that wants it applies it.
It is the one place that handles a change of the appearance and makes the view
print again. It holds no cell and no edge.

```julia
function read_intent(p::AppearanceManagingProjection, recursion, intent, iomap)
    answer = <the answer of the content>
    answer === nothing && (answer = <the answer of the wrapper's own key bindings>)
    changes_appearance(p, answer) ?
        CompoundOperation(Any[answer, InvalidateProjectionOperation()]) : answer
end
```

- The content gets each event first. The wrapper's key bindings (4.7) run only
  when the content declines the key, so `WidgetTransformPane` keeps its Ctrl+=.
- An answer changes the appearance when it holds one of the wrapper's own zoom
  and scale operations, or a write whose root object is the `Appearance` or one
  of its themes, such as a theme value from the tab, or Load.
- `InvalidateProjectionOperation` is a kernel operation, beside
  `DoNothingOperation`. Its evaluation calls `invalidate_projection!(editor)`,
  which exists. The existing code then stops the read loop
  (`EditorLoop.jl:93`), leaves the remaining input for the next frame, and
  prints the whole view again from the start, in the print phase. Its inverse
  is `DoNothingOperation`.

So a print happens at most once in a frame, and the events after a change wait
for the new view.

### 4.6 The zoom

- The zoom lives in the `Appearance`, beside the scales. The tab shows it, and
  Save and Load keep it.
- `AdjustZoomOperation` and `AdjustScaleOperation(scale, delta)` belong to the
  package of the wrapper and carry the `Appearance`. The scale operation writes
  the scale. The zoom operation writes the zoom and copies it into the `Display`
  of the editor, because the backends read it there. A Load copies it the same
  way, and a start step of the wrapper copies the saved zoom when the editor
  starts.
- **SDL** finds a new pixel ratio when it draws. It then keeps the device size of
  each window and repaints in full: `_reflow_for_scale!` moves from its zoom
  operation into its drawing, and its two `evaluate_operation` methods go.
- **The web backend.** The server reads the zoom from the `Display` in the
  devices that `write_to_devices` gets, and sends it as a field of the update
  message. The client applies it: it draws with the ratio
  `devicePixelRatio × zoom`, reports `innerWidth / zoom` and
  `innerHeight / zoom` as the logical size, and divides each pointer position by
  the zoom. The server stays in logical pixels. After a zoom step, the client
  reports its new logical size and the server lays the view out for it. The zoom
  of the browser menu multiplies with it.
- **The kernel has no zoom.** `_zoom_operation` in `read!`, the kernel forms of
  `AdjustZoomOperation` and `AdjustFontZoomOperation`, and their lines in
  `Operations.jl`, `Description.jl`, `Inversion.jl`, `Rerooting.jl` and
  `OperationModule.jl` go. The keys work only in an editor with the wrapper.

### 4.7 The keys

| Factor | Larger | Smaller | Reset |
| --- | --- | --- | --- |
| zoom | Ctrl+`=` | Ctrl+`-` | Ctrl+`0` |
| font scale | Ctrl+Alt+`=` | Ctrl+Alt+`-` | Ctrl+Alt+`0` |
| icon scale | Ctrl+Alt+`.` | Ctrl+Alt+`,` | palette, tab |
| spacing scale | Ctrl+Alt+`]` | Ctrl+Alt+`[` | palette, tab |
| control, radius and line scale | palette, tab | palette, tab | palette, tab |

- "Reset all" is a command of the palette and a button of the tab.
- Ctrl+, opens the appearance tab.
- The keys are bindings of the wrapper, so F1 and the palette list them.
- Ctrl+Alt is AltGr on some layouts, and a bracket needs AltGr on a Hungarian or
  a German layout. The owner tries the keys on the owner's keyboard.
- The web server decodes `,`, `[` and `]`, which are `:char` now.

### 4.8 The appearance tab

A tool tab, as the fault log is: a toolbar item, a View menu item, a command of
the palette and Ctrl+,. Its projection is `AppearanceToWidget`, and it shows the
`Appearance` of its own editor.

- One row for the zoom and one for each of the six scales: the name, a −
  button, the value in percent, a + button and a reset button. Under the rows:
  "Reset all", "Save" and "Load". One table of steps for all seven: 50% to 300%.
- No slider. A change prints the whole view again, with the controls of the
  tab, and a control that a printer made loses the state of a drag. A press is
  one event and needs no state across frames.
- The theme sections, one for each theme in the `Appearance`:
  - the preset: a `WidgetSelect` that replaces the whole theme;
  - a color: a swatch and a text field that takes `#rrggbb` or `#rrggbbaa`;
  - a font: a `WidgetSelect` of the families in `asset/font`, one for the
    style, and a `WidgetSpinBox` for the size;
  - a size: a `WidgetSpinBox`.
- The derived values follow the base values. For example, `hover_layer`,
  `pressed_layer` and the four text styles of the widget theme are computed from
  its palette and its fonts.
- A write from the tab is a change of the view, as a zoom is, so Ctrl+Z does not
  take it back.

### 4.9 Save and load

- A TOML file, `appearance.toml`, in the configuration folder of the platform:
  on Linux `$XDG_CONFIG_HOME/projectured/`, by default `~/.config/projectured/`.
  An application can name another file.
- The file holds the zoom, the six scales and the base values of each theme. A
  color is `#rrggbbaa`, and a font is a file name and a size. A key that is
  missing takes its default, and a key that is not known is ignored.
- The main builder fills the `Appearance` from the file before it builds the
  projection, so a saved appearance survives a restart.
- "Save" writes the `Appearance` of this editor. "Load" reads the file and
  writes its values into the `Appearance`. The editor never saves on its own.
- Two editors that use one file each write when their person presses Save. The
  last save wins at the next start.

### 4.10 Exports

An export of the view of an editor, with `write_image` or to PDF, uses the
projections of that editor, so it has the same themes and scales. The zoom does
not multiply the density of the image: the zoom belongs to a view on a screen,
and the caller gives the density. An export with no editor uses the default
themes.

### 4.11 The packages

| Part | Package |
| --- | --- |
| `@theme`, `Spacing`, `Radius`, `LineWidth`, `ControlSize`, `IconSize`, `Appearance`, the lookup of a scaled theme | the style slice of `ProjecturedPlatform`, beside `StyleFont` |
| `UntrackedCell`, `run_untracked` | the kernel, cell layer |
| `InvalidateProjectionOperation` | the kernel, `operation/Operations.jl` |
| `AppearanceDocument`, `AppearanceManagingProjection`, the `appearance` wrapper, `AdjustZoomOperation`, `AdjustScaleOperation`, the keys, Save and Load, `AppearanceToWidget` | a new slice `source/platform/appearance/` of `ProjecturedPlatform`, above the widget slice (section 9, finding 1) |
| the toolbar item and the View menu item | the shell slice (`WindowChrome.jl`), above the appearance slice |
| the theme of a domain | the slice or package of that domain; `WidgetTheme` stays in the widget slice |

`plan/pending/fold-the-internal-packages.md` is a draft that moves code between
packages only through `Project.toml` and the entry files, so the new slice is
one more slice for it to place.

### 4.12 The new mechanisms

The rule PAR-NO-NEW-SYNTHETIC-EVENT and the word of the owner on 2026-09-23 need
each new mechanism named and approved before it is added. The owner approved
each of these on 2026-10-01:

1. `Appearance` and `AppearanceDocument`, and the `appearance` wrapper of
   `build_editor`.
2. `@theme`, the five types of length, and the scaled theme.
3. The cell kind `UntrackedCell` and the helper `run_untracked`, with the unseal
   of the four cell and struct files.
4. Style fields of projections that are `UntrackedCell`s over a scaled theme.
5. `AppearanceManagingProjection`, whose reader adds
   `InvalidateProjectionOperation` to each answer that changes the appearance.
6. `InvalidateProjectionOperation`.
7. `AdjustZoomOperation` and `AdjustScaleOperation` in the new package, and the
   copy of the zoom into the `Display`.
8. A field for the zoom in the message from the web server to the client.
9. Save and Load to a TOML file.
10. The seam of the build that makes the value of a wrapper setting before the
    projection is built (4.13), and the settings passed on to
    `make_document_projection`.

The plan adds no `SyntheticEvent`, no reader payload and no `read_intent` method
for a new type.

### 4.13 The path with no projection

`build_editor(document)` and `run_editor!(document)` build the projection with
the kernel seam `make_document_projection(document)`
(`EditorBuild.jl:130-136`, `EditorLoop.jl:354-357`). The kernel can not make an
`Appearance`. So on this path the projection would use its default themes and
the `appearance` wrapper would make a default of its own: the tab and the scales
would not reach the projection.

- (a) Before it builds the default projection, `build_editor` asks each wrapper
  for the value of its setting, through a new seam of the build, such as
  `make_wrapper_setting(Val(keyword), setting)`, whose default answers the
  setting as it is. The package of the wrapper answers a new `Appearance` for
  the setting `true`. `build_editor` then passes the settings to
  `make_document_projection(document; settings...)` and to the wrappers, so the
  projection and the wrapper share one `Appearance`. The kernel passes the
  values on and never reads them.
- (b) This path gets no appearance that the tab and the scales reach. A caller
  that wants them builds the projection with an `Appearance` and passes both to
  `build_editor`. The guide says so. The zoom still works on this path.

The owner chose (a) on 2026-10-01 (D29). The seam lives in `EditorBuild.jl`
(⬜), beside the other seams of the wrappers, and the `appearance` package adds
its method in step W1.

## 5. The decision log

All decisions are of 2026-10-01, by the owner, unless the entry says otherwise.
Each entry says what was decided and what was rejected, with the reason.

- **D1. The words.** Zoom, scale, density and device pixel ratio as in section 2.
  Rejected: "display scale" for the hardware, which gives "scale" two kinds.
- **D2, D3. An appearance on the editor, bound for each frame.** Replaced by
  D20.
- **D4. The wrapper handles every change of the appearance** (4.5). The design
  took five forms. The first compared the appearance with the printed one before
  each print. The second gave the wrapper a cell with edges that printed the
  inner projection again; that cell also recorded the reads of the inner print.
  The third let the editor ask its root IO map whether it was still current, and
  the fourth gave the editor a cell that watched the appearance. The owner
  rejected the third, a new mechanism for what an operation can already do, and
  the fourth, which makes the editor know the theme. The fifth is the decision:
  the wrapper adds `InvalidateProjectionOperation`, a new operation whose
  evaluation calls the existing `invalidate_projection!`.
- **D5. What each scale multiplies** (the table in 4.2). The owner gave the
  parts of controls, the radii and the line widths scales of their own; I had
  proposed the icon scale for the parts of controls and no scale for the radii
  and the lines.
- **D6. The icon scale** (4.2).
- **D7. The keys** (4.7). The control, radius and line scales have no key: "Not
  all needs a keyboard binding". The icon and spacing scales keep theirs (the
  owner confirmed this reading).
- **D8. The tab** (4.8). Rejected: a slider, which loses its drag when the view
  prints again; a `WidgetSelect` of the steps in place of − and +.
- **D9. Style fields read the theme with no edge** (4.3). **D9.1:** the cell
  kind `UntrackedCell` (4.4), and the name. Rejected:
  - a form of `ReactiveCell` that computes at each read: each read of each
    reactive cell would pay a type test;
  - `MutableCell`s in the theme shared by the style fields: each derived value
    would become a theme value, and a write that does not also write a reactive
    revision cell would be lost with no error;
  - `peek` inside the function: an ordinary read inside it, or inside a
    function that it calls, still records an edge to the printer cell;
  - letting the reads register and cutting the edges back: an edge is kept in
    the `Set` of the reader and in one vector for each cell read, and a
    registration can move entries, so an undo costs as much as the reads;
  - the names `DerivedCell`, `VolatileCell`, `UncachedCell` and `FunctionCell`.
- **D10. Sizes in the theme** (4.2), and the order of the steps: the themes
  before the scales that act on their values.
- **D11. The theme sections of the tab** (4.8).
- **D12. Four answers.** The appearance survives a restart (4.9). A web editor
  shows the zoom (4.6). An export of an editor uses its appearance (4.10). One
  appearance for each editor, not for each window.
- **D13. Save and load** (4.9): TOML, two buttons, and no save on its own (the
  owner confirmed this reading). Rejected: the binary document file `.pdoc`.
- **D14. Fewer spacing values:** named values, one for each use (4.2). Rejected:
  a ramp of sizes, and named values on a ramp.
- **D15. The name "control scale".** Rejected: "indicator scale", because a
  slider, a progress bar and a scroll bar are not indicators.
- **D16. One `AdjustScaleOperation` with the name of the scale.** Rejected: one
  operation type for each scale.
- **D17. A theme for each domain** that draws, not only for the widgets.
- **D18. A theme and a scaled theme are two structs.** An author can copy a font
  from either.
- **D19. A font in a document is as its author set it** (4.3). Rejected: a span
  with no font, which takes the font of the theme; scaling every font where text
  is drawn, which scales a theme font twice when a widget passes it into a text
  view.
- **D20. The editor holds nothing for the appearance** (4.1). Rejected: an
  opaque field on the editor that the editor binds for each frame; a font scale
  on the editor.
- **D21. How the themes reach the projections** (4.3). Rejected: one keyword
  for each theme on `NaturalToGraphics`, whose domains register themselves.
- **D22. The collection lives in `AppearanceDocument`** and reaches the wrapper
  through its keyword (4.1). Rejected: a field of the root document of the
  application, which the wrapper must search for.
- **D23. `@theme` makes the scaled theme** from the types of the fields (4.2).
  Rejected: a scaled struct and a scaling function by hand for each domain, where
  a forgotten field does not scale and nothing reports it; one generic
  `Scaled{T}` with a dictionary of cells, where each read is a lookup with no
  fixed type.
- **D24. The zoom lives in the `Appearance`** and is copied into the `Display`
  (4.6). Rejected: the zoom only on the `Display`, which the tab can not show
  unless the kernel gives the printers the `Display`.
- **D25. The kernel fallback for the zoom keys goes** (4.6). Rejected: a small
  zoom in the kernel for an editor with no wrapper, which gives the zoom two
  homes.
- **D26. The web client applies the zoom** (4.6). Rejected: the server converts
  the sizes and the positions while the client still scales its drawing.
- **D27. The names** `Appearance`, `AppearanceDocument`,
  `AppearanceManagingProjection`, `AppearanceToWidget` and the keyword
  `appearance`. Rejected: `ThemeCollection` and `ThemingProjection`, because the
  collection and the wrapper also hold and handle the zoom and the scales.
- **D28. The packages** (4.11). Rejected: no new package, with the wrapper in
  the screen package and the tab in the shell package.
- **D29. The path with no projection** (4.13): a seam of the build makes the
  value of each wrapper setting first, so the default projection and the wrapper
  share one `Appearance`. Rejected: no appearance on this path, where the tab and
  the scale keys would do nothing visible.
- **Also rejected:** a cell of its own for each child print in the IO map
  reconcile, so that a changed read prints the child again. The wrapper of D4
  made it unnecessary.
- **D30. One widget theme for each editor** (B2, 2026-10-01). Before this
  work an editor drew its widgets in two fonts: the window frame (`WindowWrap`,
  `WindowShell`) in Ubuntu Regular 20, and the tabs, the natural renderer,
  `FileSystemToSyntax`, the application and the data frame view in Ubuntu Mono
  20. Every widget of an editor now draws with the one `WidgetTheme` of its
  `Appearance`, so the widgets inside documents and the tabs take the fonts of
  the theme. The fonts of code and of text come from their own domain themes in
  part P. Rejected: a widget theme for each role, a frame theme and a content
  theme, which would key a theme by its type and a role and show two widget
  sections in the tab.
- **D31. The wrapper and the tab before the domain themes** (2026-10-01). The
  branch lands on `main` after B2, and the work goes on with W1–W6, then P1–P4,
  then G1, so the owner can use the zoom, the keys and the tab early, and the
  settings plan, which waits for W1, can start. The order of D10 put every
  domain theme first, so that the font scale reached all text from the first
  day; until P is done, a scale reaches the widgets only.
- **D32. Every wrapper sees the settings of the others** (W1, 2026-10-01). The
  content, the tab strip of the `tabs` wrapper and the `AppearanceDocument` of
  the `appearance` wrapper must draw from one `Appearance`, but a wrapper gets only
  its own setting. `EditorParts` holds the setting of each wrapper that is on, as
  `make_wrapper_setting` made it, and the `tabs` wrapper takes the appearance from
  there when its own setting names none. The kernel holds the settings and never
  reads them. Rejected: a caller that passes the appearance twice, which the path
  with no projection can not do; a seam that resolves one setting with the others,
  which needs an order of the settings.
- **D33. A color of a theme is edited as text** (W3, 2026-10-01). A text field
  needs a caret, and the caret is a part of the one selection, which lives in
  the input: a `StyleColor`, not a string. A small text projection of
  `StyleColor` prints `#rrggbbaa` and reads an edit back into the color, and the
  tab shows each color field through the renderer, so the selection maps through
  to the caret. The other controls of the tab need no caret: a preset is a radio
  group that writes every field of the preset into the theme in place, a size is
  a spin box with steppers (four for an inset, two for a point), and a font is a
  pair of buttons that step through the font files and a spin box for its size.
  A select is not used, because it writes from the window of its popup, where
  the reader of the tab sees nothing. Rejected: three spin boxes for a color,
  and a chooser of the named colors.

## 6. Steps

Each step is a commit in a worktree. With the default themes and every factor at
1.0, each step before B0 gives the pixels of the baseline of A0, and each step
from B0 on gives the pixels of the baseline that the owner accepts in B0.

**The order of the work:** A0, N1, C1, T1, T2, B0, B1, B2, then a landing on
`main`, then W1, W2, W3, W4, W5, W6, then P1, P2, P3, P4, then G1 (D31). The
wrapper, the keys and the tab come before the domain themes, so that the owner
can use them early. Until P is done, a scale reaches the widgets and the text of
a domain keeps its size. `plan/pending/editor-settings.md` starts its work after
W1 lands on `main`, so W1 lands as soon as it is done (my reading of that plan,
2026-10-01).

- [x] **A0. The baseline on main.** Done on 2026-10-01 at `3d0d25ae0`, in
  `environment/all` of the worktree, offscreen. No fail and no error:
  `test_kernel()` 4058 pass and 2 broken; `test_platform()` 97486 pass and 8
  broken; `test_sdl()` 803 pass; `test_web_backend()` 103 pass;
  `test_write_pdf()` 43 pass. The pixel script `/var/tmp/appearance-a0/pixels.jl`
  writes `widget_example`, `widget_table_example`, `json_example` and
  `markdown_example` with `supersample = 1`; their hashes are in
  `/var/tmp/appearance-a0/pixels/hashes.txt`. The web and PDF tests are in the
  umbrella `ProjecturedTest`.
  - `test_kernel()`, `test_sdl()`, `test_web_backend()`, the PDF test, and the
    widget tests of `test/substrate/projection/`, one file at a time.
  - Pixel hashes of four examples: the live-window check of the device audit,
    and `write_image` with `supersample = 1`.
  - Frame times of the same four examples during a scripted edit, and the count
    of the edges and of the memory of one view: later, before B1, at the owner's
    word on an idle machine (section 9, finding 2).

### Part N: the names

- [x] **N1. The renames of section 2**, with `workspace/bin/julia-rename.jl` and
  a second pass for the prose. `SEALING.md` records the unseal of `Display.jl`.
  Done on 2026-10-01 in 22 files: `test_kernel()` 4100 pass and 2 broken,
  `test_platform()` 97486 pass and 8 broken, `test_sdl()` 803, `test_web_backend()`
  103 and `test_write_pdf()` 43 pass, as before; the pixels equal A0. Also renamed,
  because they carry the same value: `_detect_display_scale!`, the constant
  `SCREENSHOT_SCALE` of the examples, and the constant `SCALE` of two video tools.
  omnet-julia and inet-julia use none of the old names.

### Part C: the cell layer

- [x] **C1. `UntrackedCell` and `run_untracked`** (4.4). Done on 2026-10-01:
  `test_untracked_cell()` 42 pass, `test_kernel()` 4100 pass and 2 broken (the
  baseline plus the new tests). The eight sealed files that it changed are ⬜ in
  `SEALING.md` until they are audited again, and `UntrackedCell.jl` is listed
  after `ImmutableCell.jl`. The error text of `_reject_computation` in
  `CellDefaults.jl` still says "only a ReactiveCell computes": it is code, not a
  docstring, so the owner's permission did not cover it. `SEALING.md` records
  the unseal of the four files.
  - `run_untracked` in `ReactiveCell.jl`, not exported. The new file
    `UntrackedCell.jl`, its `include` and `export` in `CellModule.jl`, the name
    in `_find_cell_kind`, and the list of kinds in the error text of
    `CellStruct.jl`.
  - Tests: a read of an untracked cell inside a computation records no edge,
    also for a cell that its function reads with `[]`. A cell that computes
    inside `run_untracked` records its own dependencies. The real stack comes
    back after an error. A nested use works. `@projection UntrackedCell struct`
    keeps a cell that it gets and makes a constant of a plain value. A write is
    a `MethodError`. `is_computed_cell` and `copy_cell_as`.
  - The guide `documentation/package/kernel/cell.md`: the fourth kind, and the
    docstrings of the four other sealed files that the owner allowed.

### Part T: the theme machinery

- [x] **T1. The style package** (4.2). `@theme`, the five types of length and
  their rule of at least 1, `Appearance` with the zoom, the six scales and the
  themes found by type, and the lookup of a scaled theme, which makes a default
  theme for a domain that the `Appearance` does not hold yet, while a projection
  is built and never while it prints.
  - Tests: each kind takes its scale. A change of a base value or of a scale
    changes the scaled cell. A read of a scaled cell through an `UntrackedCell`
    records no edge. Two `Appearance` objects are independent.
  - Done on 2026-10-01 in `source/platform/style/Theme.jl` and `Appearance.jl`:
    `test_theme()` 44 pass, `test_platform()` 97530 pass and 8 broken (the
    baseline plus the new tests). The lookup is `get_scaled_theme!`, with a `!`
    because it stores a default; `set_theme!` puts a preset in place, and
    `get_theme` answers the theme that a person edits. Section 9, finding 5.
- [x] **T2. `InvalidateProjectionOperation`** in the kernel (4.5): its evaluation,
  its description, its inverse `DoNothingOperation`, and its pass through every
  projection unchanged. Tests beside those of `DoNothingOperation`. Done on
  2026-10-01: `test_kernel()` 4110 pass and 2 broken; a test of the frame shows
  that the request in a `CompoundOperation` ends the frame, prints the view
  again, and lets the next event wait for the new view.

### Part B: the widget theme

- [x] **B0. The sizes of the widgets, fewer of them** (4.2). Each number of 3.5,
  what it sizes, and the named theme value that takes it. Images of the examples
  before and after. The owner accepts the new baseline.
  **The values of B0**, accepted by the owner on 2026-10-01. The named values
  of the widget theme, by kind, with the numbers that each one takes:

  | Kind | Name | Value | Takes now | Change |
  | --- | --- | --- | --- | --- |
  | spacing | `control_padding` | 9 above and below, 14 at the sides | `pad_x`, `pad_y`: text, button, tooltip, dialog, toggle, select, option, textarea, list row, table cell, toggle segment, spin box (no right side); the accordion item, 10 above and below | accordion item 10 → 9 |
  | spacing | `container_padding` | 16 | card 16, alert 14 | alert 14 → 16 |
  | spacing | `compact_padding` | 3 above and below, 10 at the sides | badge | none |
  | spacing | `item_gap` | 4 | `gap`: toolbar, shell bands, status bar, select, accordion; dropdown padding 4, tab padding 4, tree row padding 4, the offset of a submenu and of a select popup 4 | none |
  | spacing | `title_gap` | 6 | title pane 6, card 4, alert 4 | card and alert 4 → 6 |
  | spacing | `label_gap` | 6 | icon to label 6 (button, menu item, tab, tree), alert icon to title 8, radio circle to label 10 | alert 8 → 6, radio 10 → 6 |
  | spacing | `section_gap` | 10 | card footer 10, accordion sections 10, radio rows 12 | radio rows 12 → 10 |
  | spacing | `bar_gap` | 12 | menu bar items 12 | none |
  | spacing | `indent` | 22 | tree indent | none |
  | radius | `radius` | 8 | the 13 widgets that read `radius` | none |
  | radius | `radius_small` | 4 | checkbox (`radius ÷ 2`), table and tree row band 4, highlight 6, skeleton 6 | highlight and skeleton 6 → 4 |
  | line | `border_width` | 1 | borders, splitters, separators, rules, dividers | none |
  | line | `stroke` | 2 | checkmark, radio ring, knob ring | none |
  | line | `ring_width` | 2 | the focus ring and the selection ring of 16 widgets, the highlight outline | none |
  | control | `indicator_size` | 18 | checkbox box, radio circle | none |
  | control | `indicator_dot` | 5 | radio dot | none |
  | control | `switch_track` | 44 × 24 | switch | none |
  | control | `switch_knob_padding` | 3 | switch | none |
  | control | `slider_height`, `slider_track`, `slider_knob` | 24, 4, 9 | slider | none |
  | control | `progress_height` | 8 | progress bar | none |
  | control | `scroll_bar_thickness`, `scroll_thumb_minimum` | 12, 8 | scroll bar | none |
  | icon | `chevron` | 4 (half the side) | select, accordion, tree, card | none |
  | icon | `tree_chevron_column`, `tree_icon_column` | 18, 20 | tree | none |
  | text | `font`, `font_bold`, `font_small` | Ubuntu 20, Ubuntu Bold 20, Ubuntu 18 | as now | none |

  The small offsets stay numbers in the code, scaled by the spacing scale through
  `_sc`: the nudge of a card chevron 1, the shadow of a button 2, the inset of a
  toggle segment 2, the gap above an accordion body 2, and the inset of a spin
  box glyph 3. The fallback size of a dialog window, 480 × 320, is not a theme
  value. Images before and after: `/var/tmp/appearance-b0/compare/` (`all.png`
  holds the seven examples that change; `widget_title_pane_example` does not
  change).

  **The baseline from B0 on.** `/var/tmp/appearance-b0/after/hashes.txt` for the
  eight examples of `/var/tmp/appearance-b0/render.jl`, and
  `/var/tmp/appearance-b0/baseline-a0-set/hashes.txt` for the four examples of
  the A0 script, where only `widget_example` differs from A0.
- [x] **B1. `WidgetTheme` with `@theme`.**
  - [x] The theme values of B0, each with its kind of length. The four presets.
  - [x] The widget projections are declared `@projection UntrackedCell struct`.
    ~~The factory builds one `UntrackedCell` for each value of the scaled widget
    theme and each derived value, and each projection that uses it holds the same
    cell.~~ Each projection builds its own small cells with `_themed` (finding 6).
    `WidgetToGraphics(font; measure, theme)` takes a theme or a scaled theme; its
    default is a new default theme.
  - [x] The icon box multiplies by the icon scale. The button, the menu item, the
    toolbar item, the tabbed pane, the alert and the tree have a field
    `icon_scale`, and the row that holds an icon is as tall as the larger of the
    icon and the line (findings 9 and 10). `_sc` remains only for numbers that a
    document authors (finding 8).
  - Tests:
    - [x] At the default theme, the pixels of B0: the twelve examples are
      identical.
    - [x] At 1.5 for each scale alone, only the lengths of its kind change, and a
      press at the drawn place of a checkbox, a radio option and a tab hits it,
      with every scale at 1.5 (`test_widget_scales`, 23 tests).
    - [x] The edges and the memory of a view do not grow (finding 11). Before
      is `45376ce8d`, after is the branch; the edges of the reactive cells that
      a forced view reaches, and the live bytes that a second print keeps after a
      full collection:

      | example | edges before | edges after | bytes before | bytes after |
      | --- | --- | --- | --- | --- |
      | `widget_example` | 9235 | 8167 | 1816464 | 1806256 |
      | `widget_alert_example` | 141 | 120 | 20576 | 20160 |
      | `widget_accordion_example` | 74 | 56 | 16480 | 16336 |
      | `widget_card_example` | 81 | 63 | 15440 | 14992 |

      The script is `/var/tmp/appearance-b1/measure/edges4.jl`.
  - [x] omnet-julia: `build_qtenv_widget_theme` and its widget projections follow
    (omnet-julia `95c62ead` on its branch `appearance`, finding 14).
- [x] **B2. The builders pass the themes** (4.3). `NaturalToGraphics`,
  `WindowWrap`, `WindowShell`, `FileSystemToSyntax` and `DataFrameViewToWidget`
  take the `Appearance` or the themes of their parts. The registry factories get
  the `Appearance`, and a row built at registration becomes a factory.
  - [x] Every registry calls its factories with the `Appearance` of the editor:
    `factory(; appearance)` for a syntax row, `factory(; measure, appearance)`
    for a graphics row and a rung of the ladder, `factory(; measure, font, wrap,
    appearance)` for the fallback, and `make_graphics_projection(T; measure,
    appearance)`. Inside the registries the keyword is required; the entry points
    (`NaturalToGraphics`, `make_natural_projection`, the builders below) default
    to a new `Appearance`. The ready-made form of `register_natural_syntax!` is
    removed: no domain used it any more.
  - [x] Every widget of an editor draws with the one `WidgetTheme` of its
    `Appearance` (D30). `WidgetToGraphics(; measure, theme)` is the form for a
    builder; the form with a font stays for a projection built on its own. The
    `font` keyword of `make_tabs_projection`, of the `tabs` wrapper and of
    `make_window_shell_projection` is removed.
  - [x] The builders take `appearance` and pass it on: `NaturalToGraphics`,
    `make_tabs_projection` and the `tabs` wrapper (from its options),
    `make_window_shell_projection`, `make_window_wrap`,
    `make_opened_window_projections`, `make_natural_tooltip_row`, the
    conversation rows, the `:workspace` row, `make_data_frame_view_projection`,
    `make_natural_to_syntax_dispatch`, `make_natural_prose_graphics`. A main
    builder makes one `Appearance` for its window and passes the same object to
    every builder: `run_application`, the display editor, and in omnet-julia
    `run_omnet_ide` and `run_campaign_window`.
  - [x] The data frame view reads the height and the step of a row from the
    scaled theme at each print (untracked fields), so a scale reaches them.
  - Tests:
    - [x] Two renderers with two `Appearance` objects draw with their own
      widget themes, and every text that the natural renderer, the tabs, the
      window shell and an opened window draw grows with the font scale
      (`test_builder_appearance`). An icon is left out: it follows the line of
      its label and the icon scale, which `test_widget_scales` covers.
    - [x] A registered factory runs on each build with the appearance that the
      build gets (`test_natural_registry`), and every registered factory takes
      the appearance (a check that builds every row of every registry).
    - [x] The data frame view follows a change of the spacing scale and of the
      font scale of its appearance.
  - [ ] The images of the examples whose widgets change font (D30), for the
    owner's review: `/var/tmp/appearance-b2/compare/` holds the tabs, a data
    frame table and the workspace explorer, before on the left and after on the
    right. The owner had them when the branch landed, and has not answered yet.
- **The landing after B2** (2026-10-01, at the owner's word): projectured-julia
  `main` at `3c2557b32` and omnet-julia `main` at `635f342a`, by fast-forward,
  not pushed. The owner asked to land before the broad sweep; a sub-agent runs
  `test_all()` and the omnet tests on frozen checkouts of these two commits.
  - [x] omnet-julia follows: its registered factories and its main builders
    (`run_omnet_ide`, `run_campaign_window`). The omnet tests that cover the
    change give 714 pass and 1 fail, the catalog fault of finding 14.

### Part P: the themes of the domains

Each step gives each domain of its group a theme with `@theme`, makes its
projections take the theme and read it through `UntrackedCell`s, and makes its
factory take the theme from the `Appearance`. Tests for each domain: at the
default theme, the pixels of B0; at a font scale of 1.5, its text is 1.5 times
as large. omnet-julia and inet-julia follow where they build these projections.

- [x] **P1. Text and syntax:** `text`, `syntax`, `natural`. Done with this form (finding 30):
  - `make_theme_cell(T, scaled, f)` in the style slice makes a style field of any
    scaled theme; `_themed` of the widgets calls it.
  - A projection takes `theme`. With a theme or a scaled theme, each style field
    reads the scaled theme through `make_theme_cell`. With none, the default, each
    field holds the plain value of the default theme at no scale:
    `get_theme_defaults(T)` makes the scaled default theme of `T` once and answers
    its values. So a printer that builds a projection at each print makes no
    theme, and the 25 builders of `TextToGraphics` that pass only `measure` stay
    as they are.
  - `TextTheme` (text slice): the font of a text that no document styles, the
    caret and the dormant caret, the width of the caret, the selection and the
    dormant selection, the radius of a selection, the color of a match, the text
    of a line number, the inverted background and foreground, and the texts of a
    boolean, a number and a string. `TextToGraphics`, `WordWrapping`,
    `TextLineNumbering`, `TextHighlighting`, `SelectionInverting` and the
    primitive leaves read it. `ReferenceToText` serves only the inspector, so it
    moves to P4.
  - `SyntaxTheme` (syntax slice): the texts of the leaves (a boolean, a number, a
    string and its quotes, a symbol, a nothing, a reflected boolean), of a type
    name, a field name and a note (an undefined field, a cycle, an empty
    placeholder), of a delimiter and a separator, of the parts of an insertion
    (its label, the typed text, the hint, and the colors of a wrong and of a
    found completion), of the ellipsis, the color that lights the delimiters, and
    the font of a decoration. The leaves, the reflection, the collections, the
    insertions and `SyntaxToText` read it.
  - The natural renderer passes the scaled `TextTheme` and `SyntaxTheme` of its
    `Appearance` to its text and syntax rows, to its rungs and to the fallback.
    The line of prose of a placeholder takes the font of the `TextTheme`. The gap
    between the layers of a tooltip is the `item_gap` of the widget theme.
  - Open: the caret of a widget text field, which the widgets print with their own
    `TextToGraphics`, keeps the default text theme.
- [x] **P2. The document domains:** `json`, `xml`, `yaml`, `sql`, `julia`,
  `markdown`, `rst`, `book`, `math`, `formula`. The form (finding 31):
  - Each domain declares `<Domain>Theme` with `@theme` in a fragment of its own,
    with one value for each role that its projections draw, named by meaning
    (`keyword_text`, `delimiter_text`, `heading_color`, `block_gap`, …). The
    default of each value is the literal that the code drew, so the pixels at no
    scale do not change.
  - Each projection struct is `@projection UntrackedCell struct` with
    `theme::Any = nothing` as its first field, and each style field defaults to
    `_get_<domain>_style(theme, :role)`: the generated keyword constructor reads
    the earlier keyword `theme`, as `Base.@kwdef` does. So a builder passes one
    theme to every projection, a role is named once, and a projection built with
    no theme holds the plain default values. A plain struct holds a style as a
    value or a cell in an `Any` field and reads it with `unwrap_cell`.
  - The factory of a domain takes `theme` and `syntax_theme` (the latter for the
    insertion and the empty placeholder of the syntax slice), scales each once,
    and its natural registration passes the scaled themes of the `Appearance`.
  - A module const of a style, or a helper that answers one, reads the theme.
    A literal `color_default` that pairs a style font with the default color
    stays: its font follows the theme already.
  - `draw_font_sizes` in `ProjecturedPlatformTest` draws a document with the
    natural renderer, and each domain test checks a font scale of 1.5.
  - JSON is the model (`12ebb11c2`); the other nine follow it.
- [x] **P3. The charts:** `chart`, `sequencechart`, `plot`, `graphics`. Done with this form (finding 32):
  - `graphics` holds the output primitives, whose values their callers resolve,
    and `plot` is the arithmetic and the cycles of colors and symbols that a
    chart document holds as its own defaults; neither draws a look of its own,
    so neither has a theme.
  - `ChartTheme` and `SequenceChartTheme` hold what the printer draws when the
    document says nothing: the colors of the backgrounds, the axis, the grid, the
    text, the selection and the hover, the title, axis and label fonts, and the
    paddings, gaps, tick lengths, swatches and lane spacings. A value that a
    document sets in its style keeps its priority.
  - A printer has many helpers, so it holds all values of its theme as one
    style field (`make_theme_values_field`), reads it once at each print, and
    gives the tuple to the helpers in place of the module consts.
  - `ChartStyle.legend_font` and `SequenceChartStyle.label_font` were read by
    nothing; the legend and the labels of events, arrows and bands draw with them.
- [x] **P4. The tools and the overlays:** `fault`, `gesturelog`,
  `gesturehelp` (with the command palette), `inspector`, `log`, `statistics`,
  `undo`, `process`, `fsm`, `help`, `dbcatalog`, `filesystem`. Done with this
  form (finding 33):
  - A theme for each slice, with the roles that its projections draw, in the form
    of P2. A theme reaches a projection where its builder has an `Appearance`:
    the natural registrations, the wrappers `command_palette` and `gesture_help`
    of `build_editor`, which read it from the arguments of the build, and
    `make_opened_window_projections` of the shell wrapper (the window of the
    gesture map). These also pass the syntax and the text themes to the
    chains that they build, so the palette and the F1 window scale.
  - The overlays of the fault log and of the gesture log, and the substitutes of
    a fault barrier (`FaultToSyntax`, `FaultToText`, `FaultToGraphics`), have no
    builder with an `Appearance`; they keep their literals.
  - `UndoBufferToSyntax` has no view in the application; it takes `theme` like
    the others, and a builder that has one passes it.
  - `ReferenceTheme` in the text slice holds the colors of the tokens of a
    reference (`ReferenceToText`), and `InspectorTheme` the header of the
    inspector.
  - Process, FSM and the database catalog have no view in this repository's
    application; their factories take `theme`, and process and FSM pass
    `julia_theme` and `syntax_theme` on to `JuliaToSyntax`.
  - Three agents run one after another, because the platform slices are one
    package and a second agent would compile it while the first edits it.
- [ ] **Open: the graph domain** has no step in Part P. Its look (the border,
  the fill, the radius and the padding of a box, the color and the width of an
  edge and of an arrow, the highlight) is a set of module consts in
  `GraphLayoutToGraphics.jl`, and the diagrams of process and FSM draw through
  it.

### Part W: the wrapper and its controls

- [x] **W1. The package `ProjecturedAppearance`** (4.1, 4.5, 4.6, 4.7). Done as
  the slice `source/platform/appearance/` of `ProjecturedPlatform` (finding 1),
  with `test_appearance_wrapper` (44 tests); findings 15 to 17.
  `AppearanceDocument`, `AppearanceManagingProjection`, the `appearance` wrapper
  of `build_editor` with its start step that copies the zoom into the `Display`,
  `AdjustZoomOperation`, `AdjustScaleOperation` and the key bindings. The seam
  of 4.13 in `EditorBuild.jl`, its method for `:appearance`, and the
  `Appearance` passed to `make_document_projection`; a test that
  `run_editor!(document)` gives a tab and scales that change the view.
  - Tests: an ordinary edit does not print the view again: type, move the
    caret, open and close a tab, open a popup, resize the window. A change of a
    scale prints the view once, and the events after it in the same frame wait
    for the next frame. Each key gives its operation when the content declines
    it. `WidgetTransformPane` keeps Ctrl+=. F1 and the palette list the keys.
    Two editors in one process: a change in one leaves the other. A change
    while the editor runs gives the pixels of an editor that starts with it.
- [x] **W2. The old zoom goes** (4.6). Done together with W1, because the
  kernel `AdjustZoomOperation` and the one of the slice had one name.
  - `_zoom_operation`, the kernel forms of `AdjustZoomOperation` and
    `AdjustFontZoomOperation`, and their lines in `Operations.jl`,
    `Description.jl`, `Inversion.jl`, `Rerooting.jl` and `OperationModule.jl`.
    Their kernel tests go or move to the new package.
  - `_FONT_ZOOM` and `adjust_font_zoom!` go; `font_logical_size` reads no
    scale. The PDF test sets the font scale of an `Appearance`.
  - SDL: its two `evaluate_operation` methods go, and `_reflow_for_scale!`
    moves into its drawing, which finds a new pixel ratio. Test: a zoom step
    keeps the device size of each window.
  - Move `plan/pending/font-zoom-per-editor.md` to `plan/done/` with a note that
    this plan replaced it.
- [x] **W3. The appearance tab** (4.8). Part 1 is written: the seven rows,
  "Reset all", "Save" and "Load", the presets, the sizes and the fonts. Part 2 is
  written: the color as text (D33, finding 22), with a test in an editor that a
  typed digit writes the color, that the caret stays in the text after the new
  print, and that a character that is no hex digit and a deletion leave the
  color. The pixels offscreen: `/var/tmp/appearance-w4/tab-default.png` and
  `tab-scaled.png` (finding 26). The place of the tab after the new print is in
  the `Appearance` (finding 23). `AppearanceToWidget`: the seven rows,
  "Reset all", "Save", "Load" and the theme sections. The toolbar item and the
  View menu item in `WindowChrome.jl`, a Lucide glyph, and Ctrl+,.
  - Tests: a press on + changes the value label and the layout at the next
    frame. A color typed into its field changes the drawn color. The tab keeps
    its focus and its place after the new print. The pixels, offscreen.
- [x] **W4. The zoom in the web backend** (4.6). The field of the update
  message, the client, and the keys `,`, `[` and `]`. Done (finding 24): the
  update message holds `zoom`, the zoom of the `Display` in the devices; a new
  zoom sends each window in full. The client draws at `devicePixelRatio × zoom`,
  divides each size and each pointer position that it sends by the zoom, and
  multiplies the size and the place of a window that it opens. W1 already gave
  the keys `,`, `[` and `]` their names.
  - Tests: `test_web_backend()` with a zoom of 1.5: the logical size that the
    server gets, and a press at a drawn control.
- [x] **W5. Exports** (4.10). Done with no change of code (finding 25), and
  with a test in `test_write_image`.
  - Tests: the export of an editor at a font scale of 1.5 equals the export of
    an editor that starts at 1.5, and the zoom does not change the size of the
    image.
- [x] **W6. Save and load** (4.9). The TOML form, generated by `@theme` for each
  theme, the folder, the keyword that names another file, and the fill before
  the build. Done (finding 18): `save_appearance!` and `load_appearance!` in
  the style slice encode each kind of value by the kind of the field, not by
  code that `@theme` generates; the "Save" and "Load" buttons of the tab are
  `SaveAppearanceOperation` and `LoadAppearanceOperation`; `run_application`,
  the display editor, `run_omnet_ide` and `run_campaign_window` load the file
  before they build. `test_appearance_file` covers the round trip, a theme that
  is made later, a load in place, a missing and an unknown key, and a missing
  file. Not yet: the pixels of a loaded editor against a started one.
  - Tests: Save writes the file. Load gives the pixels of an editor that starts
    with that file. A new editor reads it. A missing key takes the default. A
    file with an unknown key loads.

### Part G: the guides

- [ ] **G1.** A new design document `documentation/package/appearance/`. The
  changes in `style.md`, `widget.md`, `sdl.md`, `web.md`, `editor.md`, `cell.md`
  and the design document of each domain that has a theme. "See more of it, or
  less" in `keyboard-and-mouse-guide.md`.

## 7. Risks

- An operation that does not pass through the reader chain, such as one that a
  tool puts into the inbox of the editor, does not make the view print again
  (4.5).
- A cell outside the view that reads a value of a theme with no edge keeps an
  old value with no error. The pixel test of each step finds such a cell only
  where an example draws it.
- A projection built with its default theme ignores the tab and the scales with
  no error (4.3). The test of B2 looks for text that did not grow.
- Each change of a theme or a scale prints the whole view again. A held key
  repeats the change, and the view prints once in each frame.
- The SDL text textures are keyed by size, so each step of the font scale adds
  textures. The cache is bounded.
- Fewer spacing values change the default look. The screenshots of the examples
  (`asset/image/example/`), the videos and the look of omnet-julia change with
  it.
- Parts B and P touch most of the drawing code: about 29 packages, and most of
  `WidgetToGraphics.jl`, which has about 9,400 lines. A branch that changes
  those files conflicts, and so does the fold of the packages. Each step needs a
  pixel diff against a clean main.
- omnet-julia and inet-julia build widget projections and themes. Steps B1, B2
  and P change those constructors, so both follow in the same steps; check
  `Pkg.precompile` there.
- A press must hit what is drawn at each factor. A test must press at the drawn
  pixels, not at a computed coordinate.
- Ctrl+Alt is AltGr on some keyboards (4.7).
- Sealed files: `Display.jl` (N1) and `cell/CellModule.jl`,
  `cell/ReactiveCell.jl`, `struct/CellStructPlan.jl` and `struct/CellStruct.jl`
  (C1) are unsealed by the owner for their steps. The other kernel files that
  the plan changes are ⬜ on 2026-10-01: `Operations.jl`, `Description.jl`,
  `Inversion.jl`, `Rerooting.jl`, `OperationModule.jl`, `ReadEvaluatePrint.jl`
  and `EditorBuild.jl`. Read `SEALING.md` again before each edit.

## 8. Not in this plan

- A theme that follows the dark mode of the operating system.
- A different appearance for each window, or a theme for one part of the view.
- A color picker widget, with a hue strip and a shade area.
- The line spacing as a theme value (`plan/pending/line-spacing-from-the-theme.md`).
  The themes of this plan are the place for it.

## 9. Findings during the work

1. **The package fold landed on `main` before the work started** (2026-10-01).
   The 38 platform packages are one package, `ProjecturedPlatform`, and the
   source moved into group folders: `source/kernel/`, `source/platform/<slice>/`
   (style, widget, screen, shell, text, syntax, natural, and the tools),
   `source/domain/<slice>/` (one package each), `source/backend/<slice>/`. The
   paths of section 3 are those of before the fold: `source/style/Font.jl` is now
   `source/platform/style/Font.jl`, `source/sdl/Sdl.jl` is
   `source/backend/sdl/Sdl.jl`, and so on. So D28 becomes a slice
   `source/platform/appearance/` in `ProjecturedPlatform`, not a new package;
   the owner agreed on 2026-10-01. The style slice and the widget slice are in
   the same package, so "the lowest package" of 4.11 is now "the lowest slice".
2. **The frame times of A0 wait** until the machine is idle, at the owner's word
   on 2026-10-01; the machine was busy when B1 was due. A0 takes the suites and
   the pixel images. The "before" run takes the commit before B1, `45376ce8d`, in
   a temporary checkout, and the "after" run the branch, as one A/B on an idle
   machine with the owner's word.
3. **`test_video()` has one failure on `main`** (`3d0d25ae0`), before this work:
   "a take whose window can not paint still ends, with the fault on its frames"
   (`test/backend/video/editor/ApplicationVideoTest.jl:244`, 0 red pixels where
   more than 384 are expected). It fails the same before and after N1, so it is
   not a regression of this plan. The baseline of the video suite is 40 pass and
   1 fail.
4. **`device/DeviceModule.jl` names the "density" of a display** in its
   docstring. N1 had no permission for that sealed file. The owner allowed the
   change on 2026-10-01, and the file is ⬜ until the owner seals it again. On the
   same day the owner accepted that the files which the work changed stay ⬜,
   and seals them later.
5. **An `Appearance` keeps its themes by the declared name.** `@document` gives the
   name that a declaration writes to the cell layout of the document, so the
   concrete type of `JsonTheme()` is a variant of `JsonTheme`, not `JsonTheme`
   itself. `@theme` therefore adds `get_theme_type(theme)`, which answers the
   declared name, and `set_theme!` keeps a theme under it.
6. **Each widget projection builds its own untracked cells** (B1). The step
   planned one cell for each value of the scaled theme, shared by the
   projections. The factory makes one projection for each widget type, so a
   shared cell saves a few small cells for each value and nothing that can be
   measured. `_themed(T, theme, f)` builds a cell in place of each default, and
   each constructor stays whole.
7. **The printer walk counts an untracked cell once for each value** (B1).
   `test_printer` forces every cell that it reaches and counts one test for each.
   An `UntrackedCell` is immutable, so two of the same content have the same
   `objectid`, and the cycle guard of the walk counts them once. A `ReactiveCell`
   is mutable and counts once for each object. So `test_platform` counts 84336
   tests, with the 23 of `test_widget_scales`, where it counted 97486 before B1. Without the guard for untracked cells
   the walk of the platform examples counts 14398 more. Each different style
   field is still forced.
8. **The small offsets take the spacing scale where a projection reads its
   theme** (B1). B0 gave them to `_sc`. `_scale_space(n, theme)` scales them in
   the style field instead, so `_sc` stays an identity marker for a number that
   a document authors on a widget (`w.width`, `w.height`, a position). 86 calls of
   `_sc` on a theme value are removed, and 29 calls remain.
9. **An icon written as text follows the icon scale in step P** (B1).
   `ConversationToWidget` writes the icon of a speaker as a character of the
   Lucide font. It follows the icon scale when the conversation slice has its
   theme.
10. **A tree row grows only when the roots show an icon** (B1). The same rule
    widens the icon column, so a tree of plain labels keeps rows of one line at
    each icon scale. The row height is in the geometry cell, which the reader
    also uses.
11. **A derived inset or point is kept in a computed cell** (B1). An `Inset` and
    a `Point2D` hold reactive cells, and a printer that reads a side records an
    edge to it. A style field such as the border, the uniform inset of
    `border_width`, made a new inset at each read, so each print recorded edges
    to new cells: the alert example had 152 edges where it had 141 before B1.
    `_themed` for these two types keeps the derived value in one computed cell
    that follows the scaled theme, and the style field reads that cell with no
    edge. The value is then made once for each state of the theme, as the
    factory made it once before B1.
12. **The error of `_reject_computation` names both computing kinds** (C1). It
    said that only a `ReactiveCell` computes; it says a `ReactiveCell` and an
    `UntrackedCell`. `cell/CellDefaults.jl` was ⬜ since C1.
13. **omnet-julia follows N1 and B1** (B1). `SimulationEmbedToWidget.jl` gives
    its speed slider the keyword `mapping`, the name that N1 gives the field
    `scale` of `WidgetSlider`. `build_qtenv_widget_theme` sets the named sizes of
    the theme, so the padding of an accordion item in qtenv follows
    `control_padding` and changes from 10 to 4. The owner accepted this on
    2026-10-01.
14. **The omnet tests of B1** (2026-10-01). `test_qtenv`, `test_module_views`,
    the six workbench tests, `test_demo_catalog`,
    `test_catalog_shell_fills_the_window` and `test_inspector_disclosure` give 555
    pass, 3 fail and 1 error. All four failures are in `test_inspector_disclosure`,
    and they are older than this work. The tree answers a chevron press with
    `ReplaceViewStateOperation(ReplaceReferencedValueOperation(…))` since
    2026-09-22, and `read_intent` of `ReflectionToWidget` matches only a bare
    `ReplaceReferencedValueOperation`. So no `SetReflectedDisclosureOperation` is
    made, and a chevron of the inspector opens no node. The reflection slice had
    no change on this branch. At the owner's word the reader translates a marked
    fold and keeps the mark (`b1c58f373`, omnet-julia `9462aedd`): the window's
    inspector then opens its node, 6 of 6. Through the catalog shell one assertion
    still fails: the node opens and syncs its five children, but no new row is
    rendered (110 texts before and after). The same assertion fails on `main`
    (`3d0d25ae0`) with omnet-julia `aa33732b` and only the fix, so this fault is
    older than this work and stays open.
15. **"Reset all" is a button of the tab, and not yet a command of the palette**
    (W1). The palette lists the bindings of the gesture tables, and a binding
    needs a key. W3 gives "Reset all" its button.
16. **The `appearance` wrapper changes the root of every editor** (W1). A test
    that checks the root document after `build_editor`, or the depth of a
    selection path, turns the wrapper off with `appearance = false`, as it turns
    off `tabs`; `ApplicationTest` expects a third `content` step. A method of
    `make_document_projection` takes every keyword, because `build_editor` passes
    the settings of the wrappers.
17. **SDL finds a new zoom when it draws** (W2). It compares the zoom of the
    `Display` with the zoom of the frame before, and not the whole pixel ratio:
    the probe of the density, which the first window runs, must change no logical
    size. The test is in `DeviceConfigTest`.
18. **An appearance keeps the tables of a file until their themes are made**
    (W6). A main builder loads the file before it builds, when the appearance
    holds no theme yet. `Appearance.saved_themes` keeps the table of each theme
    by the name of its type, and `set_theme!` writes it into the theme that a
    builder makes. So no table of theme types is needed. A load into an
    appearance that holds the theme writes the fields in place, so the scaled
    theme and every view follow. `TOML` is a new dependency of
    `ProjecturedPlatform`.
19. **The main builders did not pass their appearance to `build_editor`** (W6).
    `run_application`, the display editor and the omnet campaign window built
    their projection with one `Appearance` and let the `appearance` wrapper make
    another, so a key changed an appearance that the view did not read. Each
    passes `appearance = …` now.
20. **The sweep after the landing of W1 and W2** (`03e83ba36`, 2026-10-01):
    1207033 pass, 14 fail, 4 error, 1597 broken. Sixteen are the six groups of
    `main` before the landing. Two are new: the export block of the slice did not
    follow the order of `AppearanceOperations.jl` (one statement for each
    fragment, the names in the order of their definitions), and the catalog
    coverage found no atom for `AppearanceDocument`. Both are fixed for the next
    landing: the export block follows the rule, `AppearanceDocument` is in
    `_NO_ATOM` as the root wrapper of an editor, which only its wrapper draws, and
    `Appearance` has an atom. omnet: 714 pass and the known catalog fault.
    `test_video` stops at the same fault of `test_application_video` before and
    after the landing in the offline sandbox.
    `OmnetPresentationTest.test_all()` does not end with `-t 2`:
    `test_parallel_sim_dashboard_panel` spins, as on `main`.
21. **The tests after the rebase onto `4357fa3a9`** (W3, W6, 2026-10-01). The
    appearance tests, the context menu tests, `test_build_editor`,
    `test_application`, `test_exports` and the catalog coverage give 561 pass and
    2 fail. The toolbar test of `ApplicationTest` listed the tools without
    "Appearance"; it lists it now. The catalog coverage finds no atom for
    `ContextMenuWindowState`, which the context menu commit of `main` added, so
    `main` has this failure too.
22. **The caret of a color is a path in the widgets of the tab** (W3, part 2).
    D33 needs a caret in the text of a color. The tab builds its widgets again at
    each print, and a color has no node in the `Appearance` that can hold a
    selection, because the themes are in a `Dict` and a theme is no document. So
    the `Appearance` holds the caret as a path that `AppearanceToWidget`
    introduces: a path in its widget tree, from the scroll pane. The tree has the
    same form at each print, so the path names the same color after a new print.
    The print sets the selection of the pane from that path, and the selection of
    each widget in the tree from the part of its parent's path below it, so a
    layout sends a key to the color text and the text draws its caret. A color is
    a `WidgetText` with `#rrggbbaa`; no projection of `StyleColor` is needed. The
    reader of the tab turns a text edit of that text into a write of the color:
    the text after the edit, read as `#rrggbb` or `#rrggbbaa`, or, for one hex
    digit typed with no range, the text with the digit after the caret replaced,
    so the text keeps nine characters. A text that is no color gives no
    operation. `format_style_color` and `convert_text_to_style_color` in the
    style slice write and read the text, for the tab and for the file.
23. **The tab loses its place at each write** (W3). The tab makes a new
    `WidgetScrollPane` at each print, with the scroll position `Point2D(0, 0)`,
    and each write of the appearance prints the whole view again. So a step of a
    spin box or a typed digit of a color far down the tab scrolls the tab to its
    top. The scroll position must live outside the print: in the projection, which
    is made once for each renderer, or in the `Appearance` as view state, as
    `DataFrameView.scroll_position` does for its table. The owner chose the
    document (2026-10-01): the appearance is a special case, because a change of
    it prints the whole view again, so a scroll position in a pane is lost even
    where the projection of the pane is incremental. `Appearance.scroll_position`
    holds the place, the tab gives each new pane that cell
    (`WidgetScrollPane(…; scroll_position = cell)`, which takes a cell as
    `follow_end` does), and the file does not keep it. A test in an editor scrolls
    the tab, presses a Reset button and finds the tab at the same place; without
    the cell the place falls back to the top.
24. **The client of the web backend has no test runner** (W4). The repository runs
    no JavaScript. `test_web_backend` checks the server: the zoom in each update, a
    window in full after a new zoom, and 1 with no `Display`. The client was
    checked once with `gjs` and stubs of the page (`/var/tmp/appearance-w4/harness.js`,
    not in the repository): at a ratio of 2 and a zoom of 1.5, a page of 1200×900
    reports 800×600, the canvas keeps 2400×1800 pixels, the paint scale is 3, and
    a press at (150, 300) of the page goes as (100, 200). A browser on a real
    display is the owner's check.
25. **An export already follows the appearance and not the zoom** (W5).
    `write_image(document, projection, …)`, `write_pdf(document, projection, …)`
    and `record_video(document, projection; …)` print the projection that the
    caller gives, and take the density from the caller. None reads a `Display`.
    So an export with the projection of an editor has the scales of its
    `Appearance` at the time of the export, and the zoom does not reach the
    image. The test exports a button: a projection whose appearance changes to a
    font scale of 1.5 gives the bytes of one that starts at 1.5, and a zoom of 2
    gives the same bytes.
26. **The look of the tab in an image** (W3, 2026-10-01). An image of the tab,
    written offscreen at a density of 2, showed four defects, which are fixed:
    the content touched the edge of the pane, so the pane has the
    `container_padding` of the theme on each side; a swatch of a light color did
    not show on the light page, so a swatch is a box with the `border` color of
    the theme around it; the name of a theme section looked like a field, so it
    has the bold font; and the names of the parts of a size and the name of a
    font sat at the top of their row, so these rows center their parts.
27. **The sweep after the landing of W3, part 1 and W6** (`1b44b5c3b`, omnet-julia
    `ff2ac43a`, 2026-10-01). projectured: 1214062 pass, 16 fail, 4 error, 1597
    broken, against 1206783 pass, 12 fail, 4 error and 1597 broken after the
    landing before. All failures are old ones of `main` but one group:
    `WindowShellTest` listed the menu and the toolbar without "Appearance", and
    the shell commit of `main` (`975643d8d`) lists it now. omnet-julia: 713 pass
    and 2 fail; the old one is `InspectorDisclosureTest:110`, and the new one is
    `IdeWindowWrapTest:259`, which listed the toolbar without "Appearance". The
    toolbar of every window holds the Appearance tool since W3, part 1, so the
    test lists it now.
28. **The value of a wrapper keyword is its argument** (2026-10-01, D12 of
    `plan/pending/editor-settings.md`). The settings plan gives the word
    "settings" to what a person chooses, so the kernel word of W1 changed:
    `make_wrapper_setting` is `make_wrapper_argument`, `EditorParts.settings` is
    `EditorParts.arguments`, `make_document_projection(document; settings...)` is
    `make_document_projection(document; arguments...)`, and the argument
    `setting` of `wrap_editor!` is `argument`. The decisions above keep the old
    names, as they were written; the code and the guides use the new ones.
29. **Ctrl+Z takes back a change of a setting in its tab** (2026-10-01, D14 of
    `plan/pending/editor-settings.md`). The window history of the application
    holds the pane tree, so it holds a tool tab and records its writes, and the
    owner decided to keep that for the settings tab, and that the theme tab of
    W3 takes the same answer. This changes the last point of 4.8 for W3: a write
    from the theme tab is a step of the window history. For the inverse to bring
    the view back, the step must print the view again, as the forward write does.
30. **P1: the text and the syntax have themes** (2026-10-01). `TextTheme` has
    nine values and `SyntaxTheme` eighteen; each value is one that a view of the
    platform draws now, and its default is that value, so the images of all 94
    examples that draw as one image are equal, byte for byte, to those of
    `9b5d1210a`, and the same 11 examples draw no image on both sides. Facts found:
    - The fonts and the colors of a text come from its document, so
      `TextToGraphics` themes only its caret and the band of its selection. The
      caret beside an image in a block with no font keeps the default font of a
      `TextString`, and the decoration of a syntax node keeps the font of its
      delimiter: both are defaults of a document, which a typed run takes too.
    - `TextHighlighting`, `SelectionInverting` and `TextLineNumbering` have no
      builder in the platform, so no `Appearance` can reach them; they keep their
      keywords. `ProjectionConfiguring` shows the cell fields of a projection as
      controls, which a change of the struct of `TextHighlighting` would change.
    - `@theme` refuses a field named `selection`, so the band is `highlight`.
    - Three printers build a `TextToGraphics` at each print (the phrase of the
      natural renderer, and two in the widgets). The phrase holds one now; the
      widgets keep theirs, which takes the plain default values and makes no
      theme (`get_theme_defaults`).
    - A plain struct (the insertion leaf, the compound printer, the phrase, the
      tooltip column) holds a style as a value or a cell in an `Any` field, and
      reads it with `unwrap_cell`.
    - The appearance tab shows a section for each theme of the appearance, in the
      order of the names, so the natural renderer adds the sections `SyntaxTheme`
      and `TextTheme` before `WidgetTheme`. Two tab tests looked for a field by
      name in every section; they keep to the widget theme now.
    - `test_text_and_syntax_themes`: at a font scale of 1.5 a number, a string
      and an empty placeholder draw their text 1.5 times as large; a change of the
      scale reaches the next print; the caret and the band follow the line and
      the radius scales; a projection with no theme has the default values.
31. **P2: the ten document domains have themes** (2026-10-02). Each theme has
    3 (SQL) to 21 (RST) values, one for each role; every style default of every
    projection matched a role, so the images of all 94 examples that draw as one
    image equal those of `9b5d1210a` byte for byte. The domain suites give 2841
    pass and the 2 old broken markers of YAML. Facts found:
    - A node with no delimiter of its own drew its indentation and its line
      breaks in a fixed fallback font, so at a font scale its text grew and its
      whitespace did not. The fallback is the `font` of `SyntaxTheme`, which
      `SyntaxCompoundToText` holds. This corrects P1, which kept the fallback as a
      default of the document.
    - A delimiter that a printer gives as a plain string becomes `TextString(s)`
      in the default font, which no theme reaches; the indentation of its node
      takes that font too. SQL styles its commas and parentheses with
      `plain_text`, which equals the default of `TextString`, and the reflection
      styles its separators with the font of the field names and the default
      color. A space has no ink, so its color does not show.
    - Markdown, RST and Book draw no leaf of the syntax slice, so their factories
      take no `syntax_theme`. The `font` field of `JuliaBlockToSyntaxNode` was
      read nowhere; it goes, and the block indents in the font of `SyntaxTheme`.
    - `MathConfig` is an `@cell_struct UntrackedCell struct`, so its fields hold
      a value or a theme cell and its about 20 reads stay plain; it holds the wash
      of a selection too. A keyword of a constructor whose default is a theme cell
      has no type, because Julia checks the type of a keyword against its default.
    - Book and Formula have no natural row of their own for the syntax, so their
      tests build the chain to graphics by hand.
    - The appearance tab has a section for each theme that the loaded domains
      registered, sorted by name, so the widget theme is far down in a session
      with many domains. The color test of the tab scrolls the tab through
      `Appearance.scroll_position`.
    - Not themed: `JuliaCodePieces` (the colors of a code field of a widget),
      which reads no projection.
    - `test_formula()` prints "detected a stack overflow" before its summary, as on
      `main`; all its tests pass.
32. **P3: the charts have themes** (2026-10-02). `ChartTheme` has 21 values and
    `SequenceChartTheme` 22; each default is the module const or the fallback font
    that it takes the place of, so the images of all 94 examples that draw as one
    image, the 12 charts and sequence charts among them, equal those of
    `9b5d1210a` byte for byte. The chart suite gives 361 pass and the sequence
    chart suite 290. Facts found:
    - The printers hold all values of a theme as one style field
      (`make_theme_values_field`) and read it once at each print: the helpers
      take the tuple, or the layout tuple `g` that carries it, in place of the
      module consts. The behaviour consts (the veil, the zoom and pan steps, the
      tolerance of a hit, the levels of density) stay.
    - The legend of a chart drew with the axis font and the labels of the events,
      arrows and bands of a sequence chart with the axis label font, so
      `ChartStyle.legend_font` and `SequenceChartStyle.label_font` were read by
      nothing. They draw with them now; no document of the examples or of
      omnet-julia sets them, so no image changes.
    - The title font of a sequence chart has no field in `SequenceChartStyle`; the
      theme gives it one.
    - The sequence chart has no natural registration, so only a builder that
      passes `theme` themes it; omnet-julia builds both printers with keywords and
      passes no theme yet.
33. **P4: the tools and the overlays have themes** (2026-10-02). Thirteen themes:
    `FaultTheme`, `GestureLogTheme`, `MessageLogTheme`, `FrameStatisticsTheme`,
    `UndoTheme`, `FileSystemTheme`, `GestureHelpTheme`, `HelpTheme`,
    `InspectorTheme`, `ReferenceTheme` (text slice), `ProcessTheme`, `FsmTheme`
    and `DbCatalogTheme`. Every default equals the literal of the code, so the
    images of all 94 examples that draw as one image equal those of `9b5d1210a`
    byte for byte. The tests: 377 and 211 pass in the platform parts, 208 in
    the umbrella tests of help, the palette and the inspector, 309, 159 and 72
    in the suites of process, FSM and the catalog, and 1031 in a last run of the
    umbrella tests of the tools, the application and the guards (2 old broken
    markers of the navigator). Facts found:
    - The shell slice uses the syntax and the text slices, because
      `make_opened_window_projections` passes their themes to the window of the
      gesture map. The table of the slice edges names the two new edges.
    - `main` replaced `make_window_wrap` with the wrappers of `build_editor`
      while P4 was written, so at the rebase onto `160be101d` the wrappers
      `command_palette` and `gesture_help` take the themes from the
      `Appearance` in the arguments of the build (`_get_gesture_help_themes`),
      and with no `appearance` wrapper they pass none.
    - `GestureHelpDecoratorProjection` only opens the window of a gesture map;
      the renderer of that window takes the themes, so the decorator has none.
    - A style field that holds a `NamedTuple` of values is declared
      `::NamedTuple`, because the cell struct layer makes an `Any` field an
      `UntrackedCell{Any}`, which takes no `UntrackedCell{NamedTuple}`.
    - A theme type that a module of the export rule exports can not appear in
      its export block, because only the macro defines the scaled type; `@theme`
      exports the theme as `@document` does.
    - The six log tools named their style fields by role (`count_text`, …); the
      help, palette and inspector projections kept theirs.
    - The catalog has no design document, so its theme is described only in its
      docstring.
