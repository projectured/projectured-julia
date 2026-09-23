# Every icon is a Lucide glyph

**Status (2026-09-22): DONE.** The owner reviewed the result and approved
landing (Step 7). Landed on `main` in both repositories. Nothing is pushed.

**Goal:** every icon that the user interface draws comes from one icon font,
Lucide, and is drawn as a glyph through the text renderer. So each icon has
smooth edges, all icons have one style, and each icon takes the color of the
theme.

**Repositories:** projectured-julia, then omnet-julia (Step 5). No sealed file:
every file this plan touches is outside `source/kernel/`.

## 1. Why

- **The owner found the toolbar icons rough** (a screenshot of the live window,
  2026-09-22), and asked for a nice free icon set that fits the style.
- **The cause is the SDL backend.** It draws a `GraphicsPolyline` and a
  `GraphicsPolygon` as triangles with `SDL_RenderGeometry`, which has no
  anti-aliasing. It draws text through SDL_ttf, which has. The offscreen
  `write_image` draws at double resolution and scales down, so a picture from
  it hides the fault.
- **An SVG icon set does not help by itself.** Its paths become the same
  triangles. A glyph of an icon font goes through the text renderer.
- **The owner asked if every other icon can come from the same set.** It can;
  §2 lists them.

## 2. What exists

### The chosen set

- **Lucide** (`lucide-static` 1.47.0), the icon set of shadcn/ui. The widget
  theme follows shadcn: it has slate themes, and the button printer says
  "matching the shadcn default button". ISC licence.
- `font/lucide.ttf`: 902,460 bytes, 2,112 glyphs, one code point each in the
  private use area. `font/lucide.css` names them
  (`.icon-folder:before { content: "\e0d7"; }`).
- 1000 units per em, ascent 1000, descent 0: a glyph fills the em square above
  the baseline, so a glyph drawn at the size of a box fills the box.
- The name table holds no copyright and no licence text. The ISC licence asks
  for its notice "in all copies", so the notice must travel as a file.
- A comparison of Lucide, Tabler (MIT), Phosphor (MIT) and Material Icons
  Outlined (Apache 2.0), drawn as real toolbars, showed all four smooth at the
  real size. The choice of Lucide is for the style.

### The machinery

- `ICON_REGISTRY` and `register_icon!` in
  [WidgetToGraphics.jl](../../source/widget/WidgetToGraphics.jl): a name
  answers a renderer `(elements, x, y, size, color)`.
- `make_glyph_icon(font, codepoint)` exists, and nothing uses it outside a
  test. **It draws the glyph at the size of `font`, not at `size`**: in the
  comparison, a glyph larger than the line overlapped its neighbours.
- The backends: SDL draws a `GraphicsText` with SDL_ttf. The web client loads
  every `.ttf` and `.otf` of the font folder, with the file name as the family.
  The PDF backend embeds the TrueType file of each font it draws with
  (`load_truetype_font`), so it needs a `.ttf`; Lucide is one.
- **A build copies only `.ttf` and `.otf` files** (`bundle_fonts!`), so a
  licence text beside a font never reaches a binary. `NotoEmoji-OFL.txt` has
  the same gap now.

### The icons in use

1. **The registry**: 25 built-in names, and 4 that omnet-julia registers
   (`run`, `fast`, `express`, `until`, in
   `source/presentation/page/SimulationEmbedToWidget.jl`). Their users: the
   toolbar, the tab strip "+" and close, the spin box, buttons, menu items,
   tree nodes that name an icon, and the simulation controls of omnet-julia.
2. **Pictures drawn as lines**: `_push_chevron!` (the fold of a card, a select,
   an accordion row, a tree row) and the tick of a checkbox.
3. **Unicode characters drawn as icons**: the file kinds of the navigator
   (`FileSystemToWidget.jl`), the role marks of the conversation
   (`ConversationToWidget.jl`, `_role_glyph`), the fault mark "⚠" in front of
   a fault title (`FaultToWidget.jl`), and the status marks of a run in
   omnet-julia (`ExecutionStatusView.jl`).
4. **Characters inside a text document**: the fold marks ▸ ▾ of printed code,
   and the row mark ▸ and caret ▏ of the command palette.
5. **Not icons**: the bullets of documents, key names such as ←, the → of the
   parameter form, the math symbols, and the module pictures of omnet-julia
   network diagrams.

## 3. Decisions

### D1. Lucide

The owner left the choice of a free set that fits the style. Lucide is the set
of the design system the theme follows, and it has a picture for every icon of
§2.

### D2. The whole font, not a subset

A subset of the 50 glyphs in use would be about 20 KB, but every new icon would
need the subset built again. The whole font is 0.9 MB, and a new icon is one
line of the table.

### D3. A glyph icon is drawn at the size of its box

`make_glyph_icon` draws with the font of the file at `size` pixels. Because the
ascent of Lucide is its em, the glyph fills the box. A glyph font whose
metrics differ is not in scope.

### D4. The names stay, and one table maps them

Each registry name keeps its name and gets a Lucide code point, in one table
beside the registry. A name still says what the picture shows. New names for
the icons of §2 groups 2 and 3, each named after its Lucide picture:

| Name | Lucide | Where |
| --- | --- | --- |
| `:chevron_down`, `:chevron_right`, `:check`, `:x`/`:close`, `:plus`, `:minus`, `:menu` | same names; `x` | built-in |
| `:file`, `:folder`, `:save`, `:pencil`/`:edit`, `:trash`/`:delete`, `:search` | same; `trash-2` | built-in |
| `:play`, `:pause`, `:stop`, `:step_forward`/`:step`, `:finish` | same; `square`, `step-forward`, `flag` | built-in |
| `:chat`, `:terminal`, `:list`, `:keyboard`, `:warning`, `:chart`, `:crosshair` | `message-square`, `square-terminal`, `logs`, `keyboard`, `triangle-alert`, `chart-column`, `crosshair` | the toolbar |
| `:fast_forward`, `:chevrons_right`, `:skip_forward` | same | omnet-julia controls |
| `:lambda`, `:braces`, `:pilcrow`, `:diamond`, `:hexagon`, `:file_sliders`, `:sigma` | same | file kinds |
| `:user`, `:bot`, `:dot` | same | conversation roles |
| `:loader`, `:circle_pause`, `:circle_check`, `:circle` | `loader-circle`, same | run status |

### D5. The vector renderers go

`_icon_path!`, `_icon_fill!` and every `_icon_*` renderer have no user once the
table exists, so they are deleted. `make_image_icon` stays: it is for a raster
picture, not for this set.

### D6. omnet-julia uses the shared names

Its controls name `:play`, `:fast_forward`, `:chevrons_right` and
`:skip_forward`, and it deletes its own four vector icons and their
registration. Then no repository draws an icon of its own.

### D7. Group 4 stays text, group 5 is not icons

An icon inside a text document needs a span in a second font in the text
renderer. That is a change of the text domain, and not in this plan.

### D8. The licence travels with the font

`asset/font/Lucide-ISC.txt` holds the ISC notice, and `bundle_fonts!` copies
the licence texts of the font folder with the fonts. That also brings
`NotoEmoji-OFL.txt` into a binary.

## 4. Steps

### Step 0: baselines

- [x] projectured-julia at `52935e90` (the branch point): `test_substrate()`
      63325 pass, 3 fail, 2 errors, 1 broken (the split pane drag tests, known
      on `main`); `test_shell()` 157; `test_fault()` 73; `test_filesystem()` 27;
      `test_conversation()` 166 pass, 1 fail (the layering guard "every file
      imports what it extends"); `test_application()` 108; `test_write_pdf()`
      all pass; `test_gallery_wrappers()` 13.

### Step 1: the font and its licence

- [x] `asset/font/lucide.ttf` and `asset/font/Lucide-ISC.txt`. The licence file
      names the font and its version, then holds Lucide's ISC text and the MIT
      text of the Feather icons Lucide grew from.
- [x] `bundle_fonts!` copies the `.txt` licence texts with the fonts. The
      builder test "a bundled font carries its licence" copies the fonts into
      the staging root (the fonts are 12 MB, and `/tmp` can be memory) and
      finds `lucide.ttf`, `Lucide-ISC.txt` and `NotoEmoji-OFL.txt`.

### Step 2: glyph icons

- [x] `make_glyph_icon` draws at the size of the box (D3), with the file of the
      font it is given.
- [x] `font_lucide_icons_20` in the style slice. `LUCIDE_ICON_GLYPHS`, the
      table of D4, is registered with `make_glyph_icon`, and every vector
      renderer is gone (D5). `find_icon_character(name)` answers the character
      of a name for a place that writes an icon as text in a label.
- [x] A tool button has 4 pixels of padding: the glyphs stood almost edge to
      edge, and the hover surface was no larger than the glyph.
- [x] `test_widget_icon()` **306**: each case asserts the glyph, not a shape; a
      glyph icon is drawn at the size of its box; every name of the table is a
      glyph the font has (a wrong code point would draw nothing). The toolbar
      and window shell tests assert that a toolbar item draws one text, the
      glyph of its icon.

### Step 3: chevrons and the tick

- [x] `_push_chevron!(elements, cx, cy, s, dir, color)` draws the chevron glyph
      in a box of `4s`: the glyph fills the middle half of its box, so its tips
      stay `s` from the center. The `stroke` keyword went from the helper and
      its four callers; the stroke width of the `chevron` and `check` styles is
      no longer read.
- [x] The checkbox draws the `:check` glyph in its box.
- [x] `test_widget_card_fold()` reads the fold direction from the glyph.
- [x] `test_substrate()` fails the same five assertions as Step 0, and passes
      353 fewer. A verbose run of both states shows why: the 307 test sets are
      the same, and three counts differ. `Icons` 69 → 306 and `WidgetToolbar
      pointer routing` 36 → 34 are the changed tests. `SubstrateExamples`
      59672 → 59084 asserts once per forced reactive cell, and a glyph is one
      text where a vector icon was several polylines. `test_shell()` 158,
      `test_application()` 108, `test_builder()` 164 → 167.
- Steps 2 and 3 are one commit: both change `WidgetToGraphics.jl`.

### Step 4: the characters that are icons, in projectured-julia

- [x] The file kinds of the navigator are icon names (`:folder`, `:lambda`,
      `:braces`, `:pilcrow`, `:diamond`, `:hexagon`, `:file_sliders`, `:sigma`,
      and `:file` for any other kind). `test_filesystem()` **28** (27 + 1: each
      kind is an icon the widget layer draws).
- [x] The role marks of the conversation are the glyphs of `:user`, `:bot` and
      `:dot`, in `font_lucide_icons_20`, through `find_icon_character`. The old
      comment said that a thin outline mark read as a smudge beside a bold word;
      a Lucide stroke is about as heavy as the stem of a letter at this size,
      and Step 6 looks at it. `test_conversation()` 166 with the 1 failure of
      Step 0 (the same message).
- [x] `WidgetAlert` has an `icon` keyword, drawn before the title, as tall as
      it and in its color. The fault alert of `FaultToWidget` has `icon =
      :warning` and loses the "⚠ " before its title. The "⚠" of
      `FaultToSyntax` is text inside a syntax document (group 4) and stays.
      `test_fault()` 73; `test_substrate()` 62988, with the failures of Step 0.

### Step 5: omnet-julia

In the worktree `omnet-julia-lucide-icons`, branch `every-icon-is-a-lucide-glyph`,
commit `70d4febf`; and one commit here, `b7a5a3c3`.

- [x] projectured-julia: a `WidgetLabel` takes a `StyleFont` alone as its
      `text_style`, and draws in that font and the theme's color. A run's
      status mark needs a label in the icon font in the color of the text
      beside it; no form of the style said that before. `test_widget_icon()`
      **309**.
- [x] The run status: `format_status_strip` answers the text alone,
      `get_status_icon(view)` the icon name (`:loader`, `:circle_pause`,
      `:warning`, `:circle_check`, `:circle`), and `make_status_line(get_view)`
      the line: a label in the icon font, then the text. The status view, the
      session card and the embed card all use it, so the three cannot differ.
- [x] The embed toolbar names `:play` (Go on, Run), `:fast_forward` (Fast) and
      `:chevrons_right` (Express). The four vector icons, their helpers, their
      registration in `__init__` and the `GraphicsPolygon` import are gone
      (D6). `:until` had no user.
- [x] Tested in scratch environments whose projectured-julia paths point at
      this worktree: `test_execution_status_view()` **12** (+ the icon and the
      two labels), `test_session_view()` 15, the three embed tests,
      `test_playback_mode()` 22; `test_ide_window_wrap()` 29,
      `test_ide_file_navigator()` 8, `test_select_and_paste()` 81 pass, 4 fail,
      1 error (the same as on `main`).
- [x] **A hang, not from this plan.** The first run seemed to take 45 minutes.
      A `SIGUSR1` sample showed three worker threads spinning in
      `try_claim_and_execute!` of the parallel engine. The tests had finished in
      minutes; the process could not exit while the threads spun, and the
      buffered results appeared only when the time limit killed it.
      `test_demo_catalog()` 357 pass, 4 fail, 4 errors: `exec_less` is not
      defined in `OmnetSimulator.ParallelModule`, a page marker names an
      unregistered `Assistant`, two capture paths name "mm1k", and the topology
      pane is empty. **omnet-julia `main` fails the same eight, on the same
      lines** (357 pass, 4 fail, 4 errors), so none is from this plan. A test
      script that must end while those threads spin ends with
      `ccall(:_exit, Cvoid, (Cint,), 0)` after it flushes its output.

### Step 6: pictures for the owner

- [x] The gallery pictures, drawn at the branch point and on the branch with
      `generate_example_screenshots`, and compared pixel for pixel: 11 of 48
      differ (`assistant`, `conversation-widget`, `filesystem-widget`,
      `widget-accordion`, `widget-checkbox`, `widget-collapsible-card`,
      `widget-disabled`, `widget-focus`, `widget-select`, `widget-tree`,
      `widget`). Those 11 replace the pictures in `asset/image/example`; the
      other 37 are the same and stay as they are.
- [x] **The pictures showed one fault, fixed here.** The tree reserved an icon
      column of 20 pixels, made for one character, and a named icon is as tall
      as a line: the file icons of the navigator touched their names. A tree
      that shows a named icon now reserves the line height and a gap of 6
      pixels (`WTreeGeometry.icon_column`); a tree of plain labels keeps the
      column of its theme, so its labels do not move. `test_widget_icon()`
      **310** (the label starts after the icon and a gap).
- What the pictures show beside that: the Lucide chevrons are a little lighter
  than the two-stroke chevrons were; the role marks of the conversation are
  outlines and lighter than the solid `☻` `✱`, and they read clearly; the tab
  strip of `widget.png` is 5 pixels lower.
- [x] The application window and a simulation page of omnet-julia, drawn
      offscreen with no supersampling, as the live window draws: the toolbar,
      the navigator, the tab strip and the bot mark are glyphs with smooth
      edges; the page shows Run, Pause and Stop with the Lucide play, pause and
      square, and the status line draws a circle before "ready — press Run".
- Step 6 did not draw a PDF: `test_write_pdf()` already embeds a TrueType font
  per drawn font, and `lucide.ttf` is one.

### Step 7: the owner's review

- [x] The owner saw a review sheet (the application window and a simulation
      page drawn as the live window draws, and before-and-after pairs of the
      gallery) and approved landing on 2026-09-22.
- [x] projectured-julia: rebased onto `eae964d2` (19 commits of `main`; one
      file in common, `WindowChrome.jl`, merged without conflict). On the
      rebased branch the suites fail only what the branch point failed:
      `test_substrate()` 62988 (the split pane drag tests), `test_shell()` 158,
      `test_fault()` 73, `test_filesystem()` 28, `test_conversation()` 166 (the
      layering guard), `test_application()` 119, `test_builder()` 167,
      `test_write_pdf()` passes. The 11 gallery pictures drawn again on the
      rebased branch are the same, pixel for pixel. Landed with a fast-forward.
- [x] projectured-julia `main` moved twice more while the tests ran. The
      second move (the other session's pointer plan) touched four files of
      this branch; the rebase was clean, and the suites ran again: the same
      known failures, `test_shell()` 178, `test_application()` 126. The third
      move touched no file of the branch. Landed at `3f48a344`.
- [x] omnet-julia: rebased onto `234d77e4` (one commit, no file in common) and
      tested in the worktree against projectured-julia `main`: the status view
      12, the session view 15, the embed tests, `test_ide_window_wrap()` 32,
      `test_ide_file_navigator()` 8. `test_select_and_paste()` and
      `test_demo_catalog()` fail what `main` fails. `test_playback_mode()` fails
      "a widget inside a pane can report its own state again": a press now
      answers a `ReplaceViewStateOperation`, which the other session's commit
      `6a5d5272` (projectured-julia) added, and that test still expects the
      bare `ReplaceReferencedValueOperation`. Not from this plan. Landed at
      `e569e027`.

### Step 8: close

- [x] The widget guide says that every built-in icon is a Lucide glyph, names
      the table and `find_icon_character`, and how a label writes an icon. The
      shell and fault guides and the README were right already.
- [x] The memory, and the move of this plan to `plan/done/`.

## 5. What this plan does not do

- It gives the SDL backend no anti-aliasing for lines and shapes. Charts and
  graph edges stay as they are.
- It changes no character inside a text document (D7).
