# Every icon is a Lucide glyph

**Status (2026-09-22): IN PROGRESS.** Branch `every-icon-is-a-lucide-glyph`, in
the worktree `workspace/projectured-julia-lucide-icons`. **Nothing lands on
`main` before the owner has seen the result** (the owner's condition,
2026-09-22). Step 7 is that review.

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

- [ ] The file kinds, the conversation roles and the fault mark use registry
      names.

### Step 5: omnet-julia

- [ ] The controls use the shared names (D6), the status marks use registry
      names, and the four vector icons go. Tested with a scratch environment
      whose projectured-julia paths point at this worktree, because the
      `[sources]` of omnet-julia reach only the main checkout.

### Step 6: pictures for the owner

- [ ] Offscreen pictures of the toolbar, the tab strip, the navigator, the
      card, the select, the accordion, the tree, the checkbox, the
      conversation, and the simulation controls of omnet-julia.
- [ ] A PDF of a toolbar, to see the glyph embed.
- [ ] The gallery pictures of the widget guide that show an icon, drawn again.

### Step 7: the owner's review

- [ ] The owner sees the pictures, and can run
      `~/workspace/projectured-julia-lucide-icons/bin/projectured`.
- [ ] Only after the owner agrees: land projectured-julia, then omnet-julia.

### Step 8: close

- [ ] The guides, the memory, and the move of this plan to `plan/done/`.

## 5. What this plan does not do

- It gives the SDL backend no anti-aliasing for lines and shapes. Charts and
  graph edges stay as they are.
- It changes no character inside a text document (D7).
