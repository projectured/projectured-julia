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

- [ ] projectured-julia at the branch point: `test_widget_icon()`,
      `test_widget_toolbar()`, `test_shell()`, `test_application()`, and the
      tests of the tree, the card, the select, the accordion, the checkbox, the
      spin box, the tab strip, the file system navigator, the conversation and
      the fault slice.

### Step 1: the font and its licence

- [ ] `asset/font/lucide.ttf` and `asset/font/Lucide-ISC.txt`, with the version
      in the licence file.
- [ ] `bundle_fonts!` copies the licence texts too; the builder test that
      counts the bundled fonts follows.

### Step 2: glyph icons

- [ ] `make_glyph_icon` draws at the size of the box (D3).
- [ ] The table of D4, registered with `make_glyph_icon`; the vector renderers
      go (D5).
- [ ] The icon tests assert a `GraphicsText` in the Lucide font and the right
      character, not a vector shape; a toolbar item draws one glyph and no
      word.

### Step 3: chevrons and the tick

- [ ] `_push_chevron!` and the tick of the checkbox draw a glyph.

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
