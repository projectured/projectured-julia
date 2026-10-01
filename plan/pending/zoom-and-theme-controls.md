# A person sets the zoom, the scales and the theme of an editor

> **Status:** pending, not started. Written on 2026-09-30 at the owner's
> request. On 2026-10-01 the owner decided D1 to D16, confirmed my readings in
> D7 and D13, and approved the unseal of `Display.jl` (N1) and of the four cell
> and struct files of step C1. Three mechanisms of section 5 (6, 8 and 9) wait
> for the owner's approval.

## 1. The request

The owner asked on 2026-09-30:

> In projectured-julia, I would like to gather all information about UI scale,
> font scale behaviour and operation. I want to add icon scale, and spacing
> scale. I would like to create a plan for controlling these from the user
> interface using widgets and also using keyboard shortcuts with immediate
> effect. I think a complete invalidation is ok, the output doesn't have to
> depend on it. Then I would also like to be able to control fonts and colors
> and actual sizes in the widget theme.

So the plan has two parts:

- **Part A.** Seven factors for each editor: the zoom of the interface, and six
  scales: of the fonts, of the icons, of the spacing, of the parts of controls
  that are not text, of the corner radii and of the line widths. A person
  changes each one in a tab, and four of them also with a key. The change shows
  at the next frame.
- **Part B.** The widget theme of each editor: its fonts, its colors and its
  sizes, with fewer spacing values than now. A person changes them in the same
  tab, with the same immediate effect, and saves and loads them with two
  buttons.

On 2026-10-01 the owner gave the design of D4 and D9: a projection reads a
value of the theme with no dependency edge, and one wrapper projection depends
on the theme and the scales and prints the whole view again when one of them
changes.

## 2. The words (D1, decided 2026-10-01)

The owner asked: ignoring backward compatibility, zoom or scale or what, and
which one is which? The owner chose this proposal, with "density" for the
hardware.

**The rule.**

- A **zoom** magnifies a view after the layout. The layout rules do not change;
  the layout only gets less room. A person chooses it. Examples: the zoom of the
  interface, the zoom of a `WidgetTransformPane`, the zoom of a chart.
- A **scale** multiplies one kind of length before the layout, so the layout
  changes. A person chooses it. Examples: the font scale, the icon scale, the
  spacing scale, the control scale, the radius scale, the line scale.
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
| the size of the parts of controls that are not text | the person | in layout | nothing | control scale (D15) |
| the radius of every corner | the person | in layout | nothing | radius scale |
| the width of every line | the person | in layout | nothing | line scale |
| device pixels for each logical pixel of an image or a video | the caller | by the backend | `write_image(; scale)`, `record_video(; scale)` | `density` |
| the function from the share of a slider to its value | the author | — | `WidgetSlider.scale` | `mapping` |

**Why not "scale" for the hardware.** The hardware factor acts after layout, as
a zoom does. With "scale" for it, the word means two kinds of factor. "Density"
is the word of Android (`DisplayMetrics.density`), and CSS measures it in
`dppx`. Material Design uses "density" for the compactness of the spacing, but
this plan calls that the spacing scale, so the code has no collision.

**Rejected.** "Display scale" for the hardware, although the settings of the
operating system show "Scale 200%". Then "scale" would name two kinds: the one
of the display, which acts after layout, and the six that act before it.

**What the proposal renames** (step N1). All the uses are in this repository;
omnet-julia and inet-julia have none (2026-10-01).

- `Display.scale` → `Display.density`. The owner unsealed `Display.jl` for this
  rename on 2026-10-01.
- `PROJECTURED_DISPLAY_SCALE` → `PROJECTURED_DISPLAY_DENSITY`, and
  `_PROBED_DISPLAY_SCALE` → `_PROBED_DISPLAY_DENSITY`.
- The `scale` of `write_image`, `record_video`, `make_video` and
  `VideoBackend` → `density`.
- `step_zoom` → `step_factor`, because it steps the zoom and the six scales
  through one table.
- `WidgetSlider.scale` → `mapping`.
- "font zoom" → "font scale", and "uniform zoom" → "zoom", in the guides.
- `AdjustFontZoomOperation` goes in step A2: D16 replaces it.
- These stay: `AdjustZoomOperation`, `get_device_pixel_ratio`,
  `font_logical_size`, `font_device_size`.

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
  editor. D3 chose its option (A).

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

- `plan/pending/font-zoom-per-editor.md`: this plan absorbs it. When step A2 is
  done, that plan moves to `plan/done/` with a note.
- `plan/pending/line-spacing-from-the-theme.md`: a theme value for the line
  spacing. The theme of Part B is a place for it. This plan does not do it.
- `plan/pending/sdl-per-editor-state.md`, Part 2: the SDL session is shared.
  This plan does not need it.
- `plan/pending/configuration-overlay-widget.md` and
  `plan/pending/key-chords-from-bindings.md`: this plan does not use them.

## 4. The decisions

### D1. The words — decided 2026-10-01

The words of section 2, with "density" for the hardware. The owner approved on
2026-10-01 that `Display.jl` is unsealed for the rename of `Display.scale` to
`Display.density` (step N1).

### D2. Where the zoom, the scales and the theme live — decided 2026-10-01

One document for each editor, held by the `Editor`: the zoom and the six scales
as cells, and the theme in one cell. The editor copies the zoom into
`display.zoom`, and the backends read the `Display` as now. The kernel can not
name `WidgetTheme`, so the theme cell has no type in the kernel, and the widget
package reads it. The name of the document is open: `Appearance` or
`EditorAppearance`, in the editor layer of the kernel.

### D3. How a layout deep in the tree finds it — decided 2026-10-01

The editor binds its appearance in a scoped value for each frame, as it binds
the performance counters. `font_logical_size`, `_sc`, the icon box and the
widget projections read it. Outside a frame the default appearance applies:
each factor is 1.0, and the theme is the theme of the factory. This is option
(A) of `font-zoom-per-editor.md`.

The scoped value only finds the appearance of the editor. A reader reads a value
of the appearance with no edge. Only the wrapper of D4 reads them with edges.

### D4. One wrapper holds the edges — decided 2026-10-01

The owner's design:

1. A projection reads a value of the appearance, a value of the theme or a
   scale, with no dependency edge (`peek`). A theme that thousands of cells read
   adds no edges.
2. One wrapper projection wraps the whole view of the editor. Its cell reads the
   theme and the six scales with ordinary edges, and prints the inner
   projection. When one of them changes, the cell computes again and prints the
   inner projection again from the start. This is the complete invalidation that
   the owner allowed, done by a projection.
3. The zoom has no edge in the wrapper. Layout does not read it, and the backend
   applies it. A value label that shows the zoom reads its cell with an ordinary
   edge.

So no operation sets `editor.iomap = nothing`, and nothing compares snapshots.

**Where the wrapper sits.** It is a wrapper of `build_editor` in the `:screen`
layer, on by default, so it wraps the whole view, the window manager included.
`make_editor` applies no wrapper, so a test that wants it applies it.

**The one difference from other wrappers.** The owner asked what the difficulty
is, because this is a wrapper like the others, plus the read of the theme. It
is, with one difference:

- Every other wrapper prints its inner projection once, in the body of its
  print. The fault barrier does so at `Catching.jl:121`.
- This wrapper must print its inner projection a second time, when the
  appearance changes. The cell layer runs no function on a change. The only code
  that runs again after a change is the computation of a cell, when something
  reads it. So the second print runs inside the cell of the wrapper.
- A cell records each read that its computation makes, and a print makes reads.
  So the cell of the wrapper records the reads of the inner print too, not only
  the appearance. These are the reads in the bodies of the prints at the top of
  the chain, down to the first container that prints its children in cells of
  their own (3.9). Nothing records them today.
- If one of those reads changes during ordinary editing, such as the list of
  windows or the selection, each such edit prints the whole view again.

**D4.1. How to handle those reads — decided 2026-10-01: (c).**

- (a) Build a plain wrapper. Count the prints of its inner projection, and test
  that ordinary edits do not print it again: type, move the caret, open and
  close a tab, open a popup, resize the window. If the test passes, nothing
  more is needed.
- (b) If the test fails, change the print that reads too much, so that it reads
  inside a cell of its own.
- (c) The wrapper reads the appearance with edges, then runs the inner print
  with `run_untracked` (D9.1). Its cell then records the 7 edges of the
  appearance and nothing else. The reads at the top of the chain stay
  unrecorded, as they are now.

The owner chose (c) from the start, because D9.1 brings `run_untracked`
anyway. The test of (a) stays, as a check.

**What else follows from the design.**

- A cell that reads a value of the appearance with no edge, and that the new
  print does not make again, keeps an old value with no error. Examples: a
  computed cell in a document, or a cache keyed by a font that stores a scaled
  size. Step A2 lists them. A test compares an editor that changes a value while
  it runs with an editor that starts with that value, pixel for pixel.
- `run_frame!` reads up to 32 events in one frame. After an operation that
  changes the appearance, it must end that loop, as it does now when the IO map
  is gone. Else the next events of the frame are read against the old output
  with the new theme.
- A theme for one part of the view does not work, because a cell that computes
  later can not know which wrapper holds it. One theme for each editor is what
  the owner decided (D12, answer 4).
- A new print makes again the widgets that a printer made. A drag in such a
  widget loses its state (D8).

### D5. What each scale multiplies — decided 2026-10-01

| Length | Examples now | Factor |
| --- | --- | --- |
| text | all fonts | font scale |
| named icons, the icon column of a tree, chevrons | the box from the caller, 20, `chevron` 4 | icon scale |
| paddings and margins | `pad_x` 14, `pad_y` 9, card 16, alert 14, badge 3/10, menu 4, tab 4 | spacing scale |
| gaps between items | `gap` 4, title gap 6, icon to label 6/8, radio rows 12, accordion 4/10 | spacing scale |
| indents | tree indent 22, tree row padding 4 | spacing scale |
| parts of controls that are not text | checkbox 18, radio 18/5, switch 44×24, slider 24/4/9, progress 8, scroll bar 12/8 | control scale |
| corner radii | `radius` 8, 6, row radius 4 | radius scale |
| line widths | `border_width` 1, `stroke` 2, ring 2, separators, splitters, table rules | line scale |
| a size that a document gives | the height of a viewport, a split size, a spin box width | none: only the zoom |

- A length above 0 stays at least 1 logical pixel after its scale.
- A scale multiplies a theme value where the value is read (D9). So most lengths
  take their scale in the theme (D10, D14), and `_sc` covers only the numbers
  that stay outside it.
- The owner decided on 2026-10-01 that the parts of controls get a scale of
  their own, and that the corner radii and the line widths get one each. Before,
  I had proposed the icon scale for the parts of controls, and no scale for the
  radii and the lines.

### D6. The icon scale — decided 2026-10-01

The box of a named icon is the box that the caller gives, times the icon scale.
A row that holds an icon grows to the larger of the icon and the text line. The
icon column of a tree, an icon written as text with `find_icon_character`, and
the chevrons follow. The parts of a checkbox, a radio, a switch and a slider
follow the control scale (D5).

### D7. The keys — decided 2026-10-01

- Zoom: Ctrl+`=`/`-`/`0`, as now.
- Font scale: Ctrl+Alt+`=`/`-`/`0`, as now.
- Icon scale: Ctrl+Alt+`.` larger, Ctrl+Alt+`,` smaller.
- Spacing scale: Ctrl+Alt+`]` larger, Ctrl+Alt+`[` smaller.
- Control scale, radius scale and line scale: no key. They are rows of the tab
  and commands of the palette only. The owner wrote on 2026-10-01: "Not all
  needs a keyboard binding". The icon scale and the spacing scale keep their
  keys; the owner confirmed this reading on 2026-10-01.
- The other resets and "Reset all" are commands of the palette and buttons of
  the tab, with no key.
- Ctrl+, opens the appearance tab.
- The keys move into a `@gestures` table of the window, so F1 and the palette
  show them, if the order of the gesture tables gives "after the content" with
  no new syntax. Else they stay in `read!`, and the window gets commands with no
  key. Step A5 checks the order first.

Ctrl+Alt is AltGr on some layouts, and a bracket needs AltGr on a Hungarian or a
German layout. The owner tries the keys on the owner's keyboard in step A5.

### D8. The appearance tab — decided 2026-10-01

A tool tab, as the fault log is: a toolbar item, a View menu item, a command of
the palette and Ctrl+,. It shows the appearance of its own editor.

- One row for the zoom and one for each of the six scales: the name, a −
  button, the value in percent, a + button and a reset button. Under the rows:
  "Reset all", "Save" and "Load" (D13).
- The theme sections (D11).
- The buttons run the same operations as the keys, through their `Action`.
- No slider. A change prints the whole view again (D4), with the controls of
  the tab, and a control that a printer made loses the state of a drag. A press
  is one event and needs no state across frames.
- One table of steps for all seven rows: 50% to 300%, as the zoom uses now.

### D9. How a widget reads the theme — decided 2026-10-01

The owner's design:

- Each widget printer reads the style fields of its projection, as now.
- A style field that no keyword of the constructor set reads a field of the
  theme each time something reads it. That read records no edge, and no read
  inside it records an edge.
- The factory, which builds the projections from a theme, sets this up.
- Only the wrapper of D4 depends on the theme and the scales.
- The benefit is fewer edges. Now each printer cell that reads a style field has
  an edge to that field; after the change it has none. The cost is one small
  function call for each read of a style field while a printer runs. The memory
  must not grow, and the other reactive cells must not pay anything.

A keyword of a constructor still sets a plain value, which never reads the
theme. A size value of the theme multiplies by its scale (D5) in the same small
function, so `_sc` covers only the numbers that stay outside the theme (D10,
D14).

**D9.1. The cell kind `UntrackedCell` — decided 2026-10-01.**

A new kind of cell, in a new file `source/kernel/cell/UntrackedCell.jl`:

```julia
"""
    UntrackedCell{T}

A cell that runs its computation at each read, with `run_untracked`. It keeps no
value and records no reader, and no read inside its computation records one.
"""
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

The helper, in `ReactiveCell.jl` beside `_get_computing_stack`, because the stack
and its key belong there. It swaps the task-local computing stack for an empty
one, so no read inside `f` finds a reader; a cell that computes inside `f` puts
itself on the new stack and still records its own dependencies:

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

- **The struct layer.** A `@projection` field finds its kind by name
  (`_find_cell_kind`, `struct/CellStructPlan.jl`). The name `UntrackedCell`
  joins the list. `@projection UntrackedCell struct …` then sets the kind of
  every field of a widget projection with one word, as `@document ImmutableCell`
  does. The constructor that `@projection` generates keeps an
  `UntrackedCell{T}` that it gets, and wraps a plain value as a constant.
  `@document UntrackedCell` also becomes possible; no coded prefix such as
  `UCFoo` is added for it.
- **The factory.** One cell for each theme value and each derived value, such as
  `UntrackedCell{StyleStroke}(@computation StyleStroke(get_theme().ring, 2))`.
  The kind is an immutable struct with one pointer, so each projection that
  holds it keeps the pointer to the same function inline, with no cell object.
- **The cost.** Other reactive cells: none, `getindex` of `ReactiveCell` does not
  change. A read of an untracked cell with a reader: one lookup and two writes
  in the task storage, a small empty vector, and one call through the abstract
  type `Function`. With no reader: one lookup and the call. A spare empty vector
  for each task can remove the allocation, if B1 shows that it matters.
- **What a person loses.** A style field can not be written after the factory
  built the projection: a write is a `MethodError`. Nothing writes one now
  (checked 2026-10-01).
- **The name.** "Untracked" is the word of the kernel for a read that records no
  dependency: `cell.md` calls `peek` "the untracked read".

**Rejected, with the reason:**

- A form of `ReactiveCell` that computes at each read: each read of each
  reactive cell would pay one more load and type test.
- `MutableCell`s in the theme, shared by the style fields: each derived value
  would become a theme value, and a write of the theme that does not also write
  a reactive revision cell would be lost with no error.
- `peek` inside the function: an ordinary read inside it, or inside a function
  that it calls, still records an edge to the printer cell, and each field read
  of a cell struct is an ordinary read.
- Let the reads register and cut the edges back afterwards: an edge is kept in
  the `Set` of the reader and in one vector for each cell that was read, and a
  registration can move entries in that vector. So an undo must find the new
  edges and remove each one, and its cost grows with the reads.
- `DerivedCell`, `VolatileCell`, `UncachedCell`, `FunctionCell`: "derived" means
  a kept and tracked value in reactive systems and has 85 other uses in the
  code; the other names do not say that the cell records no edge.

### D10. Which sizes the theme holds — decided 2026-10-01

The theme gets a value for each size that a person can want to change, with
fewer spacing values than now (D14). Step B0 makes the list. Each size value
takes its scale where it is read (D5, D9).

**The order of the steps.** B0, B1 and B2 come before A3 and A4. So each number
gets its scale once, in the theme, and A4 routes only the numbers that stay
outside the theme through `_sc`.

### D11. The theme sections of the tab — decided 2026-10-01

- The preset: a `WidgetSelect` of the four presets. A preset replaces the whole
  theme.
- A color: a swatch and a text field that takes `#rrggbb` or `#rrggbbaa`. A
  picker widget, with a hue strip and a shade area, can come later.
- A font: a `WidgetSelect` of the families in `asset/font`, one for the style,
  and a `WidgetSpinBox` for the size.
- A size: a `WidgetSpinBox`.
- The derived values follow the base values. `hover_layer`, `pressed_layer` and
  the four text styles are computed from the palette and the fonts, so a change
  of `primary` changes the hover layer.
- A write from the tab is a change of the view, as a zoom is, so Ctrl+Z does not
  take it back.

### D12. The four answers — decided 2026-10-01

1. **The appearance survives a restart.** D13 says how.
2. **A web editor shows the zoom.** The owner asked why the row would hide.
   There is no good reason: the web backend does not read `Display.zoom` now, so
   the row would do nothing there. The fix is small. The server sends the zoom
   of the editor to the client. The client draws with `devicePixelRatio` times
   the zoom, reports `innerWidth / zoom` and `innerHeight / zoom` as its logical
   size, and divides the pointer position by the zoom. The SDL backend does the
   same. The zoom of the browser menu multiplies it, as the density of the
   display does in SDL. Step A7.
3. **An export of the view of an editor uses the appearance of that editor.**
   `write_image` and the PDF export bind the appearance of the editor, so the
   scales and the theme apply. An export with no editor uses the default
   appearance. The zoom does not multiply the density of the image, because the
   zoom belongs to a view on a screen; the caller gives the density (agreed
   2026-10-01). Step A8.
4. **One appearance for each editor**, not for each window.

### D13. Where the appearance is saved — decided 2026-10-01

- A TOML file, `appearance.toml`, in the configuration folder of the platform:
  on Linux `$XDG_CONFIG_HOME/projectured/`, by default `~/.config/projectured/`.
  A keyword of `build_editor` names another file, so an application can keep its
  own.
- The tab has a "Save" button and a "Load" button. Save writes the appearance of
  this editor: the zoom, the six scales and the theme. Load reads the file and
  replaces the appearance of this editor.
- An editor reads the file when it starts, so a saved appearance survives a
  restart (D12, answer 1).
- A key that is missing takes its default, and a key that is not known is
  ignored. A color is `#rrggbbaa`, and a font is a file name and a size.
- The editor saves only when the person presses Save, and it never saves on
  its own; the owner confirmed this reading on 2026-10-01. So the save needs no
  check at each frame and no new hook in the editor loop.
- Two editors that use one file each write when their person presses Save. The
  last save wins at the next start.
- The save and the load live in the package that knows the theme, because the
  kernel can not name it.

### D14. Fewer spacing values — decided 2026-10-01: (a)

The owner wrote on 2026-10-01: "maybe we should also consolidate the so many
spacings a bit". Now the widgets use about 12 different numbers for space: 2, 3,
4, 6, 8, 9, 10, 12, 14, 16, 22 and more (3.5). Most of them are fixed in one
widget.

- (a) A short list of named values in the theme, one for each use: the padding
  of a control (x and y), the padding of a container, the gap between items, the
  gap under a title, the gap between an icon and its label, the indent, and the
  padding of a row. About 8 values. Each widget takes its space from one of
  them.
- (b) A ramp of sizes, such as 2, 4, 8, 12, 16 and 24. Each widget takes one
  step of it, as Tailwind does.
- (c) Both: named values, each set to a step of the ramp.

The same holds for the radii (8, 6 and 4 become `radius` and `radius_small`)
and for the lines (1, 2, and the ring width 2 in 17 places become
`border_width`, `stroke` and `ring_width`).

A consolidation changes the default look a little: for example 9 becomes 8, and
14 becomes 12 or 16. So step B0 shows images before and after, and the steps of
Part B compare against the new baseline that the owner accepts.

The owner chose (a). A person changes "the padding of controls" in the tab,
not "step 3 of a ramp", and each named value is one row of the tab.

### D15. The name of the scale for the parts of controls — decided 2026-10-01: (a)

- (a) "control scale". `widget.md` calls the interactive widgets "controls", and
  the scale is for their parts that are not text.
- (b) "indicator scale". Qt uses the word, and `WidgetCheckboxToGraphicsCanvas`
  has `indicator_*` fields. But a slider, a progress bar and a scroll bar are
  not indicators.

The owner chose (a): the control scale.

### D16. One operation for the scales — decided 2026-10-01: (a)

- (a) One operation with the name of the scale beside `AdjustZoomOperation`:
  `AdjustScaleOperation(scale::Symbol, delta)`, such as
  `AdjustScaleOperation(:font, 1)`. It replaces `AdjustFontZoomOperation`.
- (b) One operation type for each scale: `AdjustFontScaleOperation`,
  `AdjustIconScaleOperation` and four more.

The owner chose (a). The keys, the tab and the palette name the scale, and
`describe_operation` says "font scale larger". Six types would be six copies of
the same code.

## 5. The new mechanisms

The rule PAR-NO-NEW-SYNTHETIC-EVENT and the word of the owner on 2026-09-23 need
each new mechanism named before it is added:

1. A kernel document type for the appearance, and a field `appearance` on the
   `Editor`. Approved with D2.
2. A scoped value that holds the appearance of the editor during a frame.
   Approved with D3.
3. The appearance wrapper: a wrapper of `build_editor` whose cell reads the theme
   and the six scales with edges, and runs the inner print with
   `run_untracked`. Approved with D4 and D4.1.
4. A read of an appearance value with no edge, and style fields that read the
   theme (D9). Approved with D4 and D9.
5. The cell kind `UntrackedCell` and the helper `run_untracked` (D9.1).
   Approved, with the unseal of `cell/CellModule.jl`, `cell/ReactiveCell.jl`,
   `struct/CellStructPlan.jl` and `struct/CellStruct.jl` on 2026-10-01.
6. The end of the read loop of `run_frame!` after an operation that changes the
   appearance (D4). Needs approval.
7. `AdjustScaleOperation` (D16). Approved with D16.
8. The kernel evaluates the operations of the zoom and the scales for every
   backend. The SDL backend keeps the reflow of its windows and the full
   repaint, and finds a new ratio when it writes. Needs approval.
9. A field for the zoom in the message from the web server to the client (D12).
   Needs approval.
10. The save and the load of the appearance: a TOML file, two buttons, and a
    read when the editor starts, and a keyword of `build_editor` that names the
    file (D13). Approved with D13.

The plan adds no `SyntheticEvent`, no reader payload and no `read_intent` method
for a new type.

## 6. Steps

Each step is a commit in a worktree. The steps follow the decisions and the
recommendations. A different choice changes the step that names it. At a zoom
and scales of 1.0 and the default theme, each step before B0 must give the
pixels of the baseline of A0, and each step after B0 the pixels of the baseline
that the owner accepts in B0.

**The order of the work:** A0, N1, C1, A1, A2, B0, B1, B2, A3, A4, A5, A6, A7,
A8, A9, A10, B3, B4, B5. Parts A and B interleave, because the scales of D5
apply to the size values of the theme (D10).

- [ ] **A0. The baseline on main.**
  - `test_kernel()`, `test_sdl()`, `test_web_backend()`, the PDF test, and the
    widget tests of `test/substrate/projection/`, one file at a time.
  - Pixel hashes of four examples: the live-window check of the device audit,
    and `write_image` with `supersample = 1`.
  - Frame times of the same four examples during a scripted edit.

### Part N: the names

- [ ] **N1. The renames of D1**, with `workspace/bin/julia-rename.jl` and a
  second pass for the prose. The owner unsealed `Display.jl` for the rename of
  `Display.scale` on 2026-10-01; `SEALING.md` records it in this step.

### Part C: the cell layer

- [ ] **C1. `run_untracked` and `UntrackedCell`** (D9.1). The owner unsealed
  the four files for this step on 2026-10-01; `SEALING.md` records it in this
  step.
  - `run_untracked` in `ReactiveCell.jl`, exported. The new file
    `UntrackedCell.jl`, its `include` and `export` in `CellModule.jl`, the name
    in `_find_cell_kind`, and the list of kinds in the error text of
    `CellStruct.jl`.
  - Tests: a read of an untracked cell inside a computation records no edge,
    also for a cell that its function reads with `[]`. A cell that computes
    inside `run_untracked` records its own dependencies. The real stack comes
    back after an error. A nested use works. `@projection UntrackedCell struct`
    keeps a cell that it gets and makes a constant of a plain value. A write is
    a `MethodError`. `is_computed_cell` and `copy_cell_as`.
  - The guide `documentation/package/kernel/cell.md`: the fourth kind.

### Part A: the zoom and the scales

- [ ] **A1. The appearance and its wrapper** (D2, D3, D4).
  - The appearance document: the zoom, the six scales and the theme cell. The
    `Editor` field, and a keyword `appearance` of `Editor`, `make_editor` and
    `build_editor`.
  - The scoped value. `run_frame!` and the first print of `make_editor` bind it.
    Check `run_on_editor_task!` and the feeds.
  - A getter for each scale, such as `get_font_scale()`, reads the bound
    appearance with no edge, else 1.0.
  - The appearance wrapper, a wrapper of `build_editor` in the `:screen` layer.
    Its cell reads the theme and the six scales with edges and runs the inner
    print with `run_untracked` (D4.1). A count of the prints of its inner
    projection.
  - `run_frame!` ends its read loop after an operation that changes the
    appearance.
  - The editor copies the zoom into `display.zoom`.
  - Tests: an ordinary edit does not print the inner projection again: type,
    move the caret, open and close a tab, open a popup, resize the window. A
    write of a scale prints it once. Two editors in one process: a write in one
    leaves the other.
  - If the first test fails, stop and give the numbers to the owner.
- [ ] **A2. The font scale** on the appearance (D16).
  - `AdjustScaleOperation`. The kernel evaluates it and `AdjustZoomOperation`:
    it writes the cells. `AdjustFontZoomOperation` and the two SDL methods go.
    SDL finds a new ratio at its next write, reflows its windows and repaints in
    full. It also repaints in full after a new output of the wrapper.
  - `font_logical_size` and `font_device_size` read `get_font_scale()`.
    `_FONT_ZOOM` and `adjust_font_zoom!` go, and no operation drops the IO map.
    The PDF test sets the font scale of an appearance.
  - The list of D4: each cell outside the output of the wrapper that reads a
    font size with no edge.
  - Tests: two editors in one process, a font scale in one, and the other keeps
    its layout and its pixels. The same with two web backends, where the font
    scale now works. An export outside an editor has no scale. An editor that
    changes its font scale while it runs draws the same pixels as an editor that
    starts at that scale.
  - Move `font-zoom-per-editor.md` to `plan/done/` with a note that this plan
    did its option (A).
- [ ] **A3. The icon scale** (D6), after B2.
  - The icon box multiplies by `get_icon_scale()`. The five callers and the tree
    column grow the row to the larger of the icon and the text.
  - A label that writes an icon as text scales its icon style.
  - Tests: at 1.5, the icon box of a button, a menu item, a toolbar item, a tab,
    a card title and a tree row is 1.5 times its size at 1.0. A press on the
    drawn icon hits its control. A change while the editor runs gives the pixels
    of an editor that starts at 1.5.
- [ ] **A4. The spacing, control, radius and line scales** (D5), after B2.
  - Each size value of the theme multiplies by its scale in the function of its
    `UntrackedCell` (B1).
  - The numbers that stay outside the theme go through one function for each
    kind of length: `_sc` for space, and one each for the parts of controls, the
    radii and the lines. Each multiplies by its scale and rounds, and a length
    above 0 stays at least 1.
  - The gaps of `GridLayout` in the layout package take the spacing scale.
  - Tests: at 1.5 for each scale alone, only the lengths of its kind change. A
    press at the drawn place of each control hits it, so the reader and the
    printer agree. A change while the editor runs gives the pixels of an editor
    that starts at 1.5.
- [ ] **A5. The keys** (D7).
  - The owner tries the keys on the owner's keyboard.
  - Find how a binding of the window document orders against a reader of the
    content. Then put the keys in the window table or in `read!`.
  - The keys of the zoom, the font scale, the icon scale and the spacing scale.
    The commands of the palette for all seven factors and "Reset all". Ctrl+,
    for the tab. The web server decodes `,`, `[` and `]`.
  - `describe_operation` for `AdjustScaleOperation`. Its inverse is
    `DoNothingOperation`, as for `AdjustZoomOperation`.
  - Tests: each key gives its operation when the content declines it.
    `WidgetTransformPane` keeps Ctrl+=. F1 and the palette list the commands.
- [ ] **A6. The appearance tab** (D8).
  - The projection of the appearance to widgets: seven rows, "Reset all",
    "Save" and "Load". The toolbar item, the View menu item, and a Lucide glyph
    for them.
  - Tests: a press on + changes the value label and the layout at the next
    frame. The tab keeps its focus and its place after the new print. The
    pixels, offscreen.
- [ ] **A7. The zoom in the web backend** (D12, answer 2).
  - The server sends the zoom. The client multiplies its ratio, divides the
    size that it reports and the pointer position.
  - Tests: `test_web_backend()` with a zoom of 1.5: the logical size that the
    server gets, and a press at a drawn control.
- [ ] **A8. An export uses the appearance of its editor** (D12, answer 3).
  - `write_image` and the PDF export of the view of an editor bind its
    appearance.
  - Tests: the export of an editor at a font scale of 1.5 equals the export of
    an editor that starts at 1.5.
- [ ] **A9. Save and load the appearance** (D13).
  - The TOML form of the appearance, the Save and Load buttons, the read when
    the editor starts, and the keyword of `build_editor` that names the file.
  - Tests: Save writes the file. Load gives the pixels of an editor that starts
    with that file. A new editor reads it. A missing key takes the default. A
    file with an unknown key loads.
- [ ] **A10. The guides.** `style.md`, `widget.md`, `sdl.md`, `web.md`,
  `editor.md`, the page of the kernel on the build wrappers, and "See more of
  it, or less" in `keyboard-and-mouse-guide.md`.

### Part B: the theme

- [ ] **B0. The list of sizes and fewer spacing values** (D10, D14), after A2.
  Each number of 3.5, what it sizes, and the theme value that takes it. Images
  of the examples before and after. The owner accepts the new baseline.
- [ ] **B1. Style fields that read the theme** (D9). The widget projections
  are declared `@projection UntrackedCell struct`. The factory builds one
  `UntrackedCell` for each theme value and each derived value, and each
  projection that uses it holds the same cell. The function of the cell reads
  the theme of the bound appearance with no edge, else the theme of the
  factory. At the default theme, the pixels of the baseline of B0. A count of
  the edges and of the memory of a view, before and after: both must not grow.
  The theme of omnet-julia still builds.
- [ ] **B2. The size values** of D10 and D14 in `WidgetTheme` and
  `_widget_theme`. `build_qtenv_widget_theme` of omnet-julia follows.
- [ ] **B3. A theme change while the editor runs.** A test that changes the
  slate light theme to the slate dark theme in a live editor, and gets the
  pixels of an editor that starts dark.
- [ ] **B4. The theme sections of the tab** (D11): the preset, the palette, the
  fonts, the sizes, the color control, the font control, and the derived values.
  The Save and Load buttons of A9 cover the theme.
- [ ] **B5. The guides:** `widget.md` (the theme while the editor runs) and
  `style.md`.

## 7. Risks

- The scoped value must cover each place where the cells of an editor compute. A
  cell that computes outside the frame gets the default appearance.
  PAR-STORE-THEN-DRAIN keeps the cells of an editor on its task, but step A1
  must list the places: `run_frame!`, the first print, `run_on_editor_task!`,
  and each feed.
- The wrapper runs its inner print untracked, so the reads at the top of the
  print chain stay unrecorded, as they are now. The test of A1 checks that an
  ordinary edit does not print the whole view again.
- A cell outside the output of the wrapper that reads an appearance value with
  no edge keeps an old value with no error (D4). The pixel test of each step
  finds such a cell only where the example draws it.
- Each change of the theme or of a scale prints the whole view again. A held key
  repeats the change, and each step prints once, because the read loop ends.
- The SDL text textures are keyed by size, so each step of the font scale adds
  textures. The cache is bounded.
- The fewer spacing values of D14 change the default look. The screenshots of
  the examples (`asset/image/example/`), the videos and the look of omnet-julia
  change with it.
- The sweeps of B1 and A4 touch most of `WidgetToGraphics.jl`, which has about
  9,400 lines. A branch that changes that file conflicts. Each sweep needs a
  pixel diff against a clean main.
- A press must hit what is drawn at each factor. A test must press at the drawn
  pixels, not at a computed coordinate.
- Ctrl+Alt is AltGr on some keyboards (D7).
- Sealed files: the rename of `Display.scale` (N1) changes `Display.jl` (🔒),
  unsealed by the owner. Step C1 changes `cell/CellModule.jl`,
  `cell/ReactiveCell.jl`, `struct/CellStructPlan.jl` and `struct/CellStruct.jl`
  (🔒), unsealed by the owner on 2026-10-01. The other kernel files that the
  plan changes are ⬜ on 2026-10-01: `Editor.jl`, `EditorLoop.jl`,
  `ReadEvaluatePrint.jl`, `EditorBuild.jl`, `Operations.jl`,
  `OperationDefaults.jl`, `GestureBinding.jl`. Read `SEALING.md` again before
  each edit.

## 8. Not in this plan

- The colors of the syntax, the charts, the sequence charts, the fault log, the
  gesture log, the command palette and the inspector. They are not widgets
  (`widget-color-design.md`, D5). A later plan can give each domain a theme of
  its own.
- The line spacing of a theme (`line-spacing-from-the-theme.md`).
- A theme that follows the dark mode of the operating system.
- A different appearance for each window.
