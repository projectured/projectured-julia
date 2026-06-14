# Fixed sizes & positions in the Widget layer — audit report

**Date:** 2026-06-13
**Scope:** Widget *documents* ([program/src/document/Widget.jl](../program/src/document/Widget.jl)),
widget *examples* ([example/src/document/Widget.jl](../example/src/document/Widget.jl)),
and the widget *projections*
([WidgetToGraphics.jl](../program/src/projection/primitive/WidgetToGraphics.jl),
[WorkbenchToWidget.jl](../program/src/projection/primitive/WorkbenchToWidget.jl),
[ConversationToWidget.jl](../program/src/projection/primitive/ConversationToWidget.jl),
[ObjectToWidget.jl](../program/src/projection/generic/ObjectToWidget.jl)).

**Goal (per request):** every size/position should come from one of three
sources, never a hand-tuned literal:

1. **Content-aware automatic sizing** — measure the content, size to fit.
2. **Automatic layout** — parent allocates space (`available_width/height`,
   `LayoutConstraint`, `allocate_axis`) instead of children carrying absolute
   `position`/`size`.
3. **Theme / style tokens** — all insets, paddings, margins, spacing, gaps,
   radii, and control dimensions resolved from a `WidgetTheme`/style document.

This report enumerates **every** place a size or position is a precalculated
fixed number instead.

> **Status (updated 2026-06-14).** Steps 1–2 of the original plan (§7) are
> implemented and committed (`f421ea0`): `WidgetTheme` was expanded with
> spacing/sizing tokens and the width-bearing widgets became content-aware.
> The plan has since been **revised** to a *hybrid* style architecture — see
> **§8 "Revised architecture & conventions"**, which supersedes §7 steps 3–4
> and re-factors the Step-1 theme. Read §8 before implementing further; §1–§6
> remain the authoritative inventory of fixed values.

---

## 0. What infrastructure already exists (so we know the target)

The pieces needed to do this *right* are already in the codebase but are used
inconsistently:

- **Content measurement** — `_text_size(measure, font, text)` /
  `p.measure(text, font)` is used widely and correctly for text extents.
- **Automatic layout** — `PrinterContext.available_width/height` (reactive
  cells), `with_available_size`, `LayoutConstraint`, and `allocate_axis`
  ([Layout.jl](../program/src/document/Layout.jl)) implement a real
  min/preferred/max/weight allocator. Only `WidgetSplitPane`, `WidgetShell`,
  `WidgetTabbedPane`, and `WidgetScrollPane` consult it.
- **Theme tokens** — `WidgetTheme`
  ([WidgetToGraphics.jl:77](../program/src/projection/primitive/WidgetToGraphics.jl#L77))
  exists but only carries **three** spacing tokens: `radius` (8), `pad_x` (14),
  `pad_y` (9). Everything else (gaps, row pitch, control sizes, card/badge/table
  paddings, indents) is a literal in the projection. **The theme is too small to
  be the single source of truth it claims to be.**
- **Box model** — `margin`/`border`/`padding` `Inset`s exist on the *original*
  widgets and are honored by `_content_offset` / `_inset_total`, but they
  default to `inset_default` (all-zero) and the **extension widgets carry no box
  model at all** — their spacing is hardcoded in the renderer.

`_sc(px)` (font-scaled logical pixel) wrapping a literal is **still a fixed
number** — scaling is orthogonal to the hardcoding problem and does not count as
"theme-driven" here.

---

## 1. Widget projection — `WidgetToGraphics.jl`

This is where the bulk of the hardcoded geometry lives. Legend for the
**Fix** column: **T** = move to theme/style token, **C** = make content-aware,
**L** = should come from automatic layout / available size.

### 1a. Core widgets

| Widget | Location | Fixed value | What it is | Fix |
|---|---|---|---|---|
| Checkbox | [:595–597](../program/src/projection/primitive/WidgetToGraphics.jl#L595) | `s=_sc(18)`, `rad=_sc(4)`, `bw=_sc(2)` | box size, corner radius, stroke | T |
| Button | [:655](../program/src/projection/primitive/WidgetToGraphics.jl#L655) | shadow offset `_sc(2)` | drop-shadow y-offset | T |
| Button | [:657](../program/src/projection/primitive/WidgetToGraphics.jl#L657) | border `max(1,_sc(1))` | border width | T |
| Menu | [:766](../program/src/projection/primitive/WidgetToGraphics.jl#L766) | `item_h = measure("M")` | row pitch uses cap-height of "M", **not** the actual item height | C |
| Shell | [:909](../program/src/projection/primitive/WidgetToGraphics.jl#L909) | `menu_h = measure("M")` | menu-bar band height is "M" height, not the menu's measured height | C |
| Shell | [:917–918](../program/src/projection/primitive/WidgetToGraphics.jl#L917) | `toolbar_h = measure("M")`, `+ 4` | toolbar band height + magic 4 px gap | C / T |
| TitlePane | [:1011](../program/src/projection/primitive/WidgetToGraphics.jl#L1011) | `_sc(6)` | gap between title and content | T |
| SplitPane | [:1061](../program/src/projection/primitive/WidgetToGraphics.jl#L1061) | `200` | per-slot fallback main-axis size when no constraint/`sizes` | L |
| SplitPane | [:1071](../program/src/projection/primitive/WidgetToGraphics.jl#L1071) | `splitter_thickness = max(1,_sc(1))` | divider thickness | T |
| TabbedPane | [:1372](../program/src/projection/primitive/WidgetToGraphics.jl#L1372), [:1481](../program/src/projection/primitive/WidgetToGraphics.jl#L1481) | `sel_pad = 4` | tab inner padding (duplicated in printer + reader) | T |
| ScrollPane | [:1600](../program/src/projection/primitive/WidgetToGraphics.jl#L1600), [:1603](../program/src/projection/primitive/WidgetToGraphics.jl#L1603) | `400`, `300` | viewport fallback w/h when neither `size` nor `available_*` given | L |
| Toolbar | [:1700](../program/src/projection/primitive/WidgetToGraphics.jl#L1700) | `item_gap = 4` | gap between toolbar items | T |
| Toolbar | [:1708](../program/src/projection/primitive/WidgetToGraphics.jl#L1708) | `measure("    ")` | 4-space fallback advance for non-content items | C |
| ScrollBar | [:1735–1736](../program/src/projection/primitive/WidgetToGraphics.jl#L1735) | `bw=200`, `bh=16` | track fallback size (printer) | T/L |
| ScrollBar | [:1749](../program/src/projection/primitive/WidgetToGraphics.jl#L1749), [:1753](../program/src/projection/primitive/WidgetToGraphics.jl#L1753) | `max(8, …)` | minimum thumb extent | T |
| ScrollBar | [:1773–1774](../program/src/projection/primitive/WidgetToGraphics.jl#L1773), [:1781](../program/src/projection/primitive/WidgetToGraphics.jl#L1781), [:1784](../program/src/projection/primitive/WidgetToGraphics.jl#L1784) | `200`/`16`, `max(8,…)` | same constants re-hardcoded in the **reader** (drift risk) | T/L |
| ScrollViewport | [:2471–2472](../program/src/projection/primitive/WidgetToGraphics.jl#L2471) | `400`, `300` | `WidgetScrollPaneToGraphicsViewport` fallback size | L |

### 1b. Extension widgets (printer-only) — spacing is **entirely** hardcoded

These widgets deliberately carry no box-model fields ("colors, radius and
spacing all come from the WidgetTheme"), yet in practice they read **none** of
their spacing from the theme — every pad/gap/dimension is a literal:

| Widget | Location | Fixed value(s) | What it is | Fix |
|---|---|---|---|---|
| Badge | [:1825](../program/src/projection/primitive/WidgetToGraphics.jl#L1825) | `pad_x,pad_y = _sc(10),_sc(3)` | pill padding (ignores `theme.pad_*`) | T |
| Card | [:1872](../program/src/projection/primitive/WidgetToGraphics.jl#L1872) | `pad = _sc(16)` | card padding | T |
| Card | [:1881](../program/src/projection/primitive/WidgetToGraphics.jl#L1881), [:1887](../program/src/projection/primitive/WidgetToGraphics.jl#L1887), [:1896](../program/src/projection/primitive/WidgetToGraphics.jl#L1896), [:1900](../program/src/projection/primitive/WidgetToGraphics.jl#L1900) | `_sc(4)`, `_sc(10)`×3 | inter-section vertical gaps | T |
| Card | [:1908](../program/src/projection/primitive/WidgetToGraphics.jl#L1908) | `max(_sc(width), mw+2pad)` | width floored at doc default **320** | C |
| Switch | [:1929](../program/src/projection/primitive/WidgetToGraphics.jl#L1929) | `h,wd = _sc(24),_sc(44)` | track size (fully fixed) | T |
| Switch | [:1934](../program/src/projection/primitive/WidgetToGraphics.jl#L1934) | `pad = _sc(3)` | knob inset | T |
| Switch | [:1931](../program/src/projection/primitive/WidgetToGraphics.jl#L1931) | `color_zinc_300` | off-track color hardcoded, not from theme | T |
| Progress | [:1954](../program/src/projection/primitive/WidgetToGraphics.jl#L1954) | `H = _sc(8)` | bar height (width from doc default 240) | T |
| Slider | [:1977](../program/src/projection/primitive/WidgetToGraphics.jl#L1977) | `H = _sc(24)` | control height | T |
| Slider | [:1979](../program/src/projection/primitive/WidgetToGraphics.jl#L1979), [:1987](../program/src/projection/primitive/WidgetToGraphics.jl#L1987) | `tk=_sc(4)`, knob `_sc(9)` | track thickness, knob radius | T |
| RadioGroup | [:2006–2008](../program/src/projection/primitive/WidgetToGraphics.jl#L2006) | `diam=_sc(18)`, `gap=_sc(10)`, `row_gap=_sc(12)` | dot size, label gap, row pitch | T |
| RadioGroup | [:2020](../program/src/projection/primitive/WidgetToGraphics.jl#L2020) | inner dot `_sc(5)` | selected indicator radius | T |
| Alert | [:2070](../program/src/projection/primitive/WidgetToGraphics.jl#L2070) | `pad = _sc(14)` | callout padding | T |
| Alert | [:2081](../program/src/projection/primitive/WidgetToGraphics.jl#L2081) | `_sc(4)` | title→description gap | T |
| Alert | [:2087](../program/src/projection/primitive/WidgetToGraphics.jl#L2087) | width floored at doc default **360** | C |
| Skeleton | [:2108](../program/src/projection/primitive/WidgetToGraphics.jl#L2108) | radius `_sc(6)` | corner radius (ignores `theme.radius`); W/H from doc 240×20 | T |
| Chevron | [:2116](../program/src/projection/primitive/WidgetToGraphics.jl#L2116) | stroke `max(1,_sc(2))` | shared chevron stroke | T |
| Toggle | [:2146](../program/src/projection/primitive/WidgetToGraphics.jl#L2146) | border `max(1,_sc(1))` | (padding correctly uses `theme.pad_*`) | T |
| ToggleGroup | [:2183–2184](../program/src/projection/primitive/WidgetToGraphics.jl#L2183) | `_sc(2)`, `_sc(4)` | selected-segment inset | T |
| Select | [:2209](../program/src/projection/primitive/WidgetToGraphics.jl#L2209) | `W = _sc(Int(w.width))` | **width is fixed (doc default 220), never content-aware** | C |
| Select | [:2218](../program/src/projection/primitive/WidgetToGraphics.jl#L2218) | chevron `_sc(4)` | trailing chevron size/offset | T |
| Textarea | [:2235](../program/src/projection/primitive/WidgetToGraphics.jl#L2235) | `W = _sc(Int(w.width))` | width fixed (doc default 320); height is row-aware ✓ | C |
| Accordion | [:2264](../program/src/projection/primitive/WidgetToGraphics.jl#L2264) | `W = _sc(Int(w.width))` | width fixed (doc default 360) | C |
| Accordion | [:2266](../program/src/projection/primitive/WidgetToGraphics.jl#L2266) | `pad_y = _sc(10)` | overrides `theme.pad_y`; body offset `_sc(2)` at [:2283](../program/src/projection/primitive/WidgetToGraphics.jl#L2283) | T |
| Table | [:2307](../program/src/projection/primitive/WidgetToGraphics.jl#L2307) | `cpx,cpy = _sc(12),_sc(8)` | cell padding (ignores `theme.pad_*`); col widths ARE content-aware ✓ | T |
| Table | [:2309](../program/src/projection/primitive/WidgetToGraphics.jl#L2309) | `row_h = lh + 2cpy` | uses cap-height `lh` of "M" for row height | C |
| Tree | [:2363](../program/src/projection/primitive/WidgetToGraphics.jl#L2363) | `indent=_sc(22)`, `chev_w=_sc(18)` | indent step, chevron column | T |
| Tree | [:2365](../program/src/projection/primitive/WidgetToGraphics.jl#L2365) | `row_h = lh + 2*_sc(4)` | row pitch (magic 4) | T |

**Pattern:** the extension widgets that take a `width` field
(Card/Alert/Select/Textarea/Accordion/Progress/Slider/Skeleton) hardcode a
*default* width in the document and then render to exactly that width regardless
of content (except Card/Alert which floor at it). None of these widths come from
the parent's `available_width`, so they cannot participate in automatic layout.

---

## 2. Widget *documents* — `Widget.jl` (default sizes baked into constructors)

Every default below is a hand-picked number that becomes the rendered size when
the caller doesn't override it. With content-aware sizing + theme defaults these
should not be needed (or should be `nothing` = "size to content / fill parent").

| Constructor | Location | Default | Field |
|---|---|---|---|
| `WidgetScrollBar` | [:717](../program/src/document/Widget.jl#L717) | `thumb_size=0.2` | thumb fraction |
| `WidgetSeparator` | [:783](../program/src/document/Widget.jl#L783) | `length=200` | rule length |
| `WidgetCard` | [:806](../program/src/document/Widget.jl#L806) | `width=320` | card width |
| `WidgetProgress` | [:842](../program/src/document/Widget.jl#L842) | `width=240` | bar width |
| `WidgetSlider` | [:860](../program/src/document/Widget.jl#L860) | `width=240` | slider width |
| `WidgetAvatar` | [:898](../program/src/document/Widget.jl#L898) | `size=64` | avatar diameter |
| `WidgetAlert` | [:920](../program/src/document/Widget.jl#L920) | `width=360` | callout width |
| `WidgetSkeleton` | [:939](../program/src/document/Widget.jl#L939) | `width=240, height=20` | placeholder size |
| `WidgetSelect` | [:995](../program/src/document/Widget.jl#L995) | `width=220` | select width |
| `WidgetTextarea` | [:1014](../program/src/document/Widget.jl#L1014) | `width=320, rows=4` | textarea size |
| `WidgetAccordion` | [:1035](../program/src/document/Widget.jl#L1035) | `width=360` | accordion width |

Note also: `inset_default` ([Geometry.jl:39](../program/src/document/Geometry.jl#L39))
is all-zero, so every original widget's margin/border/padding defaults to **0**
unless an example overrides it with a literal `Inset(…)`. There is **no theme
default** for the box model — spacing is opt-in per call site.

---

## 3. Workbench → Widget projection — `WorkbenchToWidget.jl`

This projection builds the whole IDE chrome out of fixed-size scroll panes and
fixed split constraints. These are the most impactful fixed numbers because they
define the entire workbench layout.

| Location | Fixed value | What it is | Fix |
|---|---|---|---|
| [:111](../program/src/projection/primitive/WorkbenchToWidget.jl#L111) | `_PAD5 = Inset(5,5,5,5)` | one padding constant reused everywhere | T |
| [:162](../program/src/projection/primitive/WorkbenchToWidget.jl#L162) | info pane `min_height=200, max_height=200` | pinned (non-resizable) info row | T |
| [:168](../program/src/projection/primitive/WorkbenchToWidget.jl#L168) | nav `min_width=200, max_width=200` | pinned nav column width | T |
| [:170](../program/src/projection/primitive/WorkbenchToWidget.jl#L170) | control `min_width=400, max_width=400` | pinned control column width | T |
| [:187–188](../program/src/projection/primitive/WorkbenchToWidget.jl#L187) | shell fallback `1280 × 720` | window size when run outside a window | L |
| [:224](../program/src/projection/primitive/WorkbenchToWidget.jl#L224) | navigator scroll `Point2D(224, 655)` | **fully fixed** scroll-pane size | L |
| [:233](../program/src/projection/primitive/WorkbenchToWidget.jl#L233) | console scroll `Point2D(1000, 130)` | fixed | L |
| [:245](../program/src/projection/primitive/WorkbenchToWidget.jl#L245) | descriptor scroll `Point2D(1000, 130)` | fixed | L |
| [:253](../program/src/projection/primitive/WorkbenchToWidget.jl#L253) | operator scroll `Point2D(1000, 130)` | fixed | L |
| [:261](../program/src/projection/primitive/WorkbenchToWidget.jl#L261) | searcher scroll `Point2D(1000, 130)` | fixed | L |
| [:269](../program/src/projection/primitive/WorkbenchToWidget.jl#L269) | evaluator scroll `Point2D(1000, 130)` | fixed | L |
| [:285](../program/src/projection/primitive/WorkbenchToWidget.jl#L285) | assistant conv pane `Point2D(1600, 1600)` | fixed | L |
| [:288](../program/src/projection/primitive/WorkbenchToWidget.jl#L288) | assistant input pane `Point2D(1600, 90)` | fixed | L |
| [:296](../program/src/projection/primitive/WorkbenchToWidget.jl#L296) | input `min_height=30, preferred_height=90, max_height=180` | input row band | T |
| [:305](../program/src/projection/primitive/WorkbenchToWidget.jl#L305) | editor scroll `Point2D(1000, 700)` | fixed | L |

Observation: these scroll panes are placed inside split-pane slots that *do*
allocate space via `available_width/height`, so the `size=Point2D(…)` here is
largely a **fallback that is overridden at render time** — but it is still a
required literal and a source of wrong sizes whenever the allocation path is not
taken (tests, isolated rendering). The split *constraints* (200/200/400/200) are
genuine fixed layout decisions that arguably belong in a workbench style/theme.

---

## 4. Conversation → Widget projection — `ConversationToWidget.jl`

Vertical stacking here is done by **manually assigning each child a `position`**
(`_stack_vertical!`) using an approximate row height, rather than using a
`VerticalLayout`. This is the clearest case of "manual fixed layout where an
automatic layout exists."

| Location | Fixed value | What it is | Fix |
|---|---|---|---|
| [:73](../program/src/projection/primitive/ConversationToWidget.jl#L73) | `_PAD5 = Inset(5,5,5,5)` | composite padding | T |
| [:77](../program/src/projection/primitive/ConversationToWidget.jl#L77) | `_ROW_H = 28` | approximate per-row vertical pitch | C |
| [:94–95](../program/src/projection/primitive/ConversationToWidget.jl#L94) | `_wrap_widget` size `Point2D(800, _ROW_H)` | one-row scroll viewport | C/L |
| [:101–102](../program/src/projection/primitive/ConversationToWidget.jl#L101) | `_text_widget` size `Point2D(800, _ROW_H)` | fixed 800-wide text row | C/L |
| [:107–134](../program/src/projection/primitive/ConversationToWidget.jl#L107) | `_set_position!` / `_widget_height` / `_stack_vertical!` | hand-rolled vertical stack using `_ROW_H` estimates | L |

`_widget_height` ([:116–125](../program/src/projection/primitive/ConversationToWidget.jl#L116))
*estimates* a widget's height by summing `_ROW_H`s instead of reading the
projected canvas's `h` cell — so wrapping text, multi-line code, or tall nested
messages will overlap or leave gaps. A real `VerticalLayout` (which sizes from
children's intrinsic `h`) removes all of this.

---

## 5. Object → Widget projection — `ObjectToWidget.jl`

The generic parameter-form builder also hand-places each control row.

| Location | Fixed value | What it is | Fix |
|---|---|---|---|
| [:83](../program/src/projection/generic/ObjectToWidget.jl#L83) | `_ROW_H = 28` | vertical pitch per control row | C |
| [:84](../program/src/projection/generic/ObjectToWidget.jl#L84) | `_CONTROL_X = 160` | x where the control sits after its label | C |
| [:97–98](../program/src/projection/generic/ObjectToWidget.jl#L97) | `Point2D(0, y)`, `y += _ROW_H` | manual row stacking | L |
| [:126](../program/src/projection/generic/ObjectToWidget.jl#L126), [:142](../program/src/projection/generic/ObjectToWidget.jl#L142) | `Point2D(_CONTROL_X, 0)` | control column offset (not measured from label width) | C |

A `GridLayout(columns=2)` (label | control) sizes the label column to the widest
label automatically — removing both `_CONTROL_X` and `_ROW_H`.

---

## 6. Examples — `example/src/document/Widget.jl`

Examples legitimately hardcode positions (they are hand-authored layouts), but
they are worth listing because they (a) double as the visual regression corpus
and (b) demonstrate the absence of layout containers — every example positions
children by hand.

### 6a. The composite gallery `make_widget_document_example`

| Location | Fixed value(s) |
|---|---|
| [:1](../example/src/document/Widget.jl#L1) | `width=1024, height=768, line_height=56` |
| [:3](../example/src/document/Widget.jl#L3) | `field_border = Inset(1,1,1,1)` |
| [:6–15](../example/src/document/Widget.jl#L6) | label/field columns at fixed x = `0`, `280`, `100`; rows at `k*line_height` |
| [:15](../example/src/document/Widget.jl#L15) | button `Point2D(180, line_height)` |
| [:17](../example/src/document/Widget.jl#L17), [:31](../example/src/document/Widget.jl#L31) | composite origins `Point2D(16,16)` / `Point2D(0,0)` |
| [:24–25](../example/src/document/Widget.jl#L24), [:33–35](../example/src/document/Widget.jl#L33), [:43–46](../example/src/document/Widget.jl#L43) | scroll sizes `width-2 × height-80`, `width/2-4 × height-120` |
| [:51–52](../example/src/document/Widget.jl#L51) | split `sizes=[width/2, width/2]` |
| [:55–62](../example/src/document/Widget.jl#L55) | scrollbar positions/sizes `(16,16)`, `(width-64,24)`, `(width-36,16)`, `(20,height-160)` |
| [:95–96](../example/src/document/Widget.jl#L95) | tooltip `Point2D(20, height-80)`, `Point2D(360, line_height)` |

### 6b. Per-widget examples

Pervasive `Point2D(40, 40)` origins and `_wy(...)` literal y-offsets
(`0/36/72/108`, `0/40/80`, `0/44`, `0/96`, `0/32/64`, …) used to stack siblings —
e.g. [:172–174](../example/src/document/Widget.jl#L172),
[:243–247](../example/src/document/Widget.jl#L243),
[:300–305](../example/src/document/Widget.jl#L300),
[:308–312](../example/src/document/Widget.jl#L308).
Every one of these is a manual layout that a `VerticalLayout`/`HorizontalLayout`
with a theme `gap` would replace. Sizes passed to example widgets
(`width=260/340/220`, `size=64`, `length=260`, scroll `400×300`, etc.) are also
fixed — see [:254](../example/src/document/Widget.jl#L254),
[:275](../example/src/document/Widget.jl#L275),
[:279](../example/src/document/Widget.jl#L279),
[:287](../example/src/document/Widget.jl#L287),
[:302–304](../example/src/document/Widget.jl#L302),
[:320](../example/src/document/Widget.jl#L320),
[:325](../example/src/document/Widget.jl#L325).

---

## 7. Summary of the gaps (what to change)

**A. The theme is missing most spacing tokens.** `WidgetTheme` has only
`radius`, `pad_x`, `pad_y`. To make "spacing comes from the theme" true it needs
(at least): `gap` (inter-item), `row_gap`, control sizes (`checkbox`, `switch`
track, `slider`/`progress` thickness, `radio` dot, `scrollbar` thickness/min
thumb), `border_width`, `card_pad`, `badge_pad`, `table_cell_pad`, `tree_indent`,
`title_gap`, and a default **box-model inset** so `inset_default` can be themed
rather than all-zero. Today these are ~40 literals scattered across
`WidgetToGraphics.jl`.

**B. Several widths are fixed, not content-aware.** Select, Textarea, Accordion,
Card, Alert, Progress, Slider, Skeleton render to a `width` field (with a
hardcoded default) instead of measuring content and/or filling
`available_width`. These are the `C`/`C+L` rows in §1–§2.

**C. Manual stacking instead of automatic layout.** `ConversationToWidget`
(`_stack_vertical!` + `_ROW_H`), `ObjectToWidget` (`_ROW_H` + `_CONTROL_X`), and
all examples place children with absolute `position` + estimated heights. The
`VerticalLayout`/`HorizontalLayout`/`GridLayout` documents already exist and size
from children's intrinsic `w`/`h` — switching to them removes the estimates and
the overlap/gap bugs they cause.

**D. Fixed fallback sizes that mask missing allocation.** ScrollPane `400×300`,
ScrollBar `200×16`, Shell `1280×720`, and every `WorkbenchToWidget` scroll-pane
`size=` are fallbacks used when `available_*` isn't seeded. They should resolve
through layout (parent allocation) with a themed default, not per-call literals.

**E. Duplicated constants across printer/reader.** ScrollBar's `200/16/max(8,…)`
and TabbedPane's `sel_pad=4` are written twice (print + hit-test); a shared token
avoids drift.

### Suggested order of attack

1. ✅ **Done (`f421ea0`).** Expand `WidgetTheme` into a full spacing/sizing token
   set (and a themed default box-model inset). (§7A, all `T` rows.)
2. ✅ **Done (`f421ea0`).** Route widths through content + `available_width` for
   the `width`-bearing extension widgets. (§7B, `C` rows.)
3. **Replace manual stacking with layout documents** in `ConversationToWidget`,
   `ObjectToWidget`, then the examples. (§7C, `L` rows.) — *deferred behind the
   §8 theme split; still planned.*
4. **Fold fallback sizes into the layout/allocation path** so the literals in
   `WorkbenchToWidget` and the scroll/scrollbar fallbacks disappear. (§7D.)
   — *deferred behind the §8 theme split; still planned.*

> Steps 1–2 landed with a **monolithic** `WidgetTheme` (one struct that absorbed
> ~24 single-use, widget-specific dimensions). §8 re-factors that into a hybrid
> and must be done **before** steps 3–4.

---

## 8. Revised architecture & conventions (current direction)

### 8.0 Why revise

Step 1 put **everything** in one `WidgetTheme`: ~20 palette colors, 3 fonts, and
~31 spacing/sizing tokens. But of those 31 spacing tokens only ~7 are read by
more than one widget; the other ~24 (`switch_w`, `switch_h`, `knob_radius`,
`tree_indent`, `badge_pad_x`, `card_pad`, `table_pad_x`, `progress_h`,
`accordion_pad_y`, …) are read by exactly one widget. A token used by one widget
buys no consistency and no fan-out — it is just that widget's parameter parked in
a god-object. So the monolithic theme is mis-factored.

### 8.1 The model: per-projection params fed by a small shared theme

A **hybrid** (the standard design-tokens → component-styles pipeline):

- **Each widget projection owns its style parameters** as fields — colours,
  sizes, paddings, radii — so the projection is self-contained and its interface
  states exactly what it consumes. This is also the ProjecturEd-native path:
  `ProjectionConfiguringProjection` already projects an inner projection *object*
  through `ObjectToWidget` to build an editable parameter bar, so projection
  fields that are reactive `Cell`s become **live-editable, per-widget-scoped**
  controls for free.
- **A small shared `WidgetTheme` (the style document) holds only the
  cross-cutting values** — the palette, the text styles, and the handful of
  spacing tokens read by many widgets.
- **The compound projection factory** (`WidgetToGraphics(; theme)`) reads the
  theme and **distributes / derives** each child projection's parameters at
  construction time. Different *styles* are different factory constructors.
- **Linking values:** share the same `Cell` between projections, or derive a
  projection's parameter from a theme token in the factory (e.g.
  `card.padding = scale(theme.padding, 1.5)`). A value that must track the theme
  is *derived*; a value that is genuinely independent is a plain projection
  default.

**Split rule (keep the theme small):** a value lives in the **theme** iff it is
read by **≥ 2–3 widgets and should move together**; otherwise it is a
**projection default** (optionally derived from a theme token). This keeps
`theme params ≪ Σ projection params`, which is the whole point — the theme is the
compressed, shared core; the projections carry the long tail of detail.

### 8.2 Field conventions (apply everywhere — documents, theme, projections)

These two rules are mandatory for the refactor and for new code:

1. **No abbreviations — write field names out in full.** Rename on the way
   through:
   - `pad_x` / `pad_y` → folded into a `padding` field (see compound types).
   - `radius` → `corner_radius`.
   - `stroke` → `stroke_width`; `bw` → `border_width`; `cw`/`ch` → `content_width`
     / `content_height`; `tw`/`th` → `text_width` / `text_height`; `kr` →
     `knob_radius`; `sw` → `segment_width`; etc.
   - `seg_inset` → `segment_inset`; `tab_pad` → `tab_padding`; `thumb_min` →
     `minimum_thumb_length`. (Local computation variables inside a function
     should be spelled out too, not just struct fields.)

2. **Use a compound type wherever several scalars describe one concept** —
   exactly as the codebase already does with `StyleColor`, `StyleFont`, `Inset`,
   `Point2D`:
   - **`Inset`** (`top`/`bottom`/`left`/`right`) for any padding / margin /
     border spacing — never four `*_top/*_bottom/*_left/*_right` scalars, and
     never an `_x`/`_y` pair where a box is meant. The theme's content padding
     becomes `padding::Inset`; `badge_pad_x/badge_pad_y` → `padding::Inset`; etc.
   - **`Point2D`** for any width+height size or x+y position — `switch_w` +
     `switch_h` → `track_size::Point2D`; `progress_h` alone stays scalar
     (`bar_height`) since there is no paired width.
   - **`StyleColor`**, **`StyleFont`** as today.
   - **New `StyleText { font::StyleFont, color::StyleColor }`** — a combined text
     style, since widgets repeatedly pass a `(font, color)` pair. The theme then
     exposes *semantic* text styles instead of loose fonts + colours, e.g.
     `body::StyleText`, `title::StyleText` (bold + foreground),
     `caption::StyleText` (small + muted), `label::StyleText`. A renderer takes a
     `StyleText` and draws text in one call. (`StyleText` is new; add it beside
     `StyleColor`/`StyleFont` and export it.)

   All members of these compound types are already reactive `Cell`s
   (`Inset`/`Point2D` hold `Cell`s), which is what makes per-projection params
   live-editable and linkable.

### 8.3 Shape of the shared theme (target)

Roughly (names final, types compound):

- **Palette:** `background_color`, `foreground_color`, `card_color`,
  `muted_color`, `muted_foreground_color`, `primary_color`,
  `primary_foreground_color`, `border_color`, `input_color`, `ring_color`,
  `destructive_color`, … (StyleColors).
- **Text styles:** `body_text`, `title_text`, `caption_text`, `label_text`
  (`StyleText`).
- **Shared spacing:** `corner_radius`, `padding::Inset`, `gap`, `border_width`,
  `stroke_width`, `chevron_size`. (≈ the 7 that fan out.)
- **Box model default:** `inset` (themed default margin/border/padding).

Everything else (`track_size`, `knob_radius`, `bar_height`, `indent`,
`chevron_column_width`, `card`-specific paddings/gaps, `table` cell padding,
`minimum_thumb_length`, `segment_inset`, `tab_padding`, `title_gap`, `row_gap`,
…) moves onto the **projection that uses it**, defaulted in the factory and
derived from a theme token where it should track the theme.

### 8.4 Worked example — `WidgetButton`

*Before (Step-1 state):* `WidgetButtonToGraphicsCanvas(font, measure, theme)`;
renderer reads `p.theme.pad_x`, `p.theme.radius`, `p.theme.border_width`,
`p.theme.shadow_offset`, abbreviated locals `bw`, `bh`, `tw`, `th`.

*After (hybrid):*

```julia
struct WidgetButtonToGraphicsCanvas <: Projection
    measure::Function
    label_text::StyleText      # font + foreground colour
    background_color::StyleColor
    border_color::StyleColor
    padding::Inset             # content padding (was pad_x / pad_y)
    corner_radius::Cell        # was radius
    border_width::Cell
    shadow_offset::Cell        # button-specific default, derived from theme
end
```

…built by the factory as

```julia
WidgetButtonToGraphicsCanvas(
    measure,
    theme.label_text,
    theme.background_color,
    theme.border_color,
    theme.padding,
    theme.corner_radius,
    theme.border_width,
    Cell(2))            # shadow_offset: button-only default (could derive)
```

and the renderer reads `projection.padding.left[]`, `projection.corner_radius[]`,
etc. — full names, compound types, no `p.theme.*` indirection, and the
printer/reader of the *same* projection share the one field (killing the
duplicate-constant problem from §7E).

### 8.5 Revised order of attack

3a. **Add `StyleText`** beside `StyleColor`/`StyleFont`; give the theme semantic
    text styles.
3b. **Split the theme** (§8.1 rule): shrink `WidgetTheme` to the shared core;
    move the ~24 widget-specific dimensions onto their projections (full names,
    compound types), defaulted/derived by the factory. Render code goes
    `p.theme.x → p.field`; collapse printer/reader duplicates. *Verify rendering
    is unchanged* (values preserved; the audit images are the oracle).
3c. **Then** the original §7 step 3 (layout documents) and step 4 (fold fallback
    sizes) — unchanged in intent, done on top of the hybrid.

---

### Appendix — files audited

- [program/src/document/Widget.jl](../program/src/document/Widget.jl) — widget document types & default sizes
- [program/src/document/Geometry.jl](../program/src/document/Geometry.jl) — `Inset`, `Point2D`, `inset_default`
- [program/src/document/Layout.jl](../program/src/document/Layout.jl) — layout documents + `allocate_axis` (the automatic-layout machinery)
- [program/src/context/PrinterContext.jl](../program/src/context/PrinterContext.jl) — `available_width/height` plumbing
- [program/src/projection/primitive/WidgetToGraphics.jl](../program/src/projection/primitive/WidgetToGraphics.jl) — the renderer (theme + all per-widget geometry)
- [program/src/projection/primitive/WorkbenchToWidget.jl](../program/src/projection/primitive/WorkbenchToWidget.jl)
- [program/src/projection/primitive/ConversationToWidget.jl](../program/src/projection/primitive/ConversationToWidget.jl)
- [program/src/projection/generic/ObjectToWidget.jl](../program/src/projection/generic/ObjectToWidget.jl)
- [example/src/document/Widget.jl](../example/src/document/Widget.jl) — gallery + per-widget examples
