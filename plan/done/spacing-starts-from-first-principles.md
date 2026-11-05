# Spacing starts from first principles

## The goal

The user (2026-11-03) asked to step back from the plan
[the-window-has-one-system-for-space.md](the-window-has-one-system-for-space.md)
and to derive the spacing rules in this order:

1. Write the first principles of spacing in terms of what a person sees, not
   in terms of documents: what touches what, what never touches what, and
   what is closer or further.
2. Make a catalog of what other frameworks and tools do.
3. Start from a layout with no space at all, and show the examples from there.
4. Find the degrees of freedom: padding, margin, the gap between elements, and
   on which elements.
5. Find where a value comes from: the document or the theme.
6. Find how a rule of the theme decides: by the type of the current document,
   of its parent (upward, through the typed reference of the print), of its
   child (downward), or by the printer context.
7. Show how the rules follow from the principles, as text and as artifacts.

Then the user decides. This document is the text. The artifact "Spacing from
zero" shows the same steps on real screens:
https://claude.ai/artifact/LSyJQotJh7cRRhA6FAHDNC

## 1. First principles

**P0. The eye sees marks only.** A mark is text, an icon, a line or a fill.
Space is the distance between two marks. A box that draws nothing has no edge
that a person can see. Its padding is only a part of the distance between the
marks around it.

Every rule below is a rule about the distance between marks.

### What touches what

- **T1. Two areas that share a boundary meet at one line or at one change of
  fill.** No empty band lies between them. Examples: the toolbar and the tab
  row; two panes of a split; the tab row and its page; a page and the status
  bar.
- **T2. A line runs until it meets another line or the edge of the window.**
  Example: a divider ends on the line under the tab row and on the line above
  the status bar.
- **T3. A fill that marks an area reaches the edges of that area.** Examples:
  the fill of the header row of a table reaches both sides of the table. A fill
  that is a shape of its own, such as a pill, a chip or a card, stands clearly
  inside its area, never 1 or 2 px short of an edge.
- **T4. The parts of one joined control touch.** Examples: the segments of a
  toggle group, the tabs of a tab strip.

### What never touches what

- **N1. Text and icons never touch a line, or the edge of a fill, that is not a
  part of them.** Examples: the text of a button and its border; a label and a
  divider; the first line of a page and the edge of the window.
- **N2. Two lines never run side by side.** When the border of a box would lie
  on a divider or on another border, space comes between them, or one of them
  is not drawn.
- **N3. Two separate things with edges of their own never touch.** Examples:
  two buttons, two cards, two tables. Each edge must stay visible.

### What is closer and what is further

- **C1. Things that belong together are closer than things that do not.** The
  parts of one item are closer than two items of a group, and two items of a
  group are closer than two groups.
- **C2. A title is closer to what it names than to what comes before it.**
- **C3. The space between two things with edges is not smaller than the space
  inside each of them.** Otherwise two cards read as one.
- **C4. A distance is measured between marks.** So the space of an item
  includes the padding of its own box. Two icons of a toolbar are 4 + 4 + 4 =
  12 px apart, which is more than the 6 px between an icon and its label.

### Rules over all of them

- **R1. Once.** The space between content and one visible edge is given once.
  Two spaces with no mark between them add up, and the result looks like a
  mistake. This follows from P0.
- **R2. Symmetry.** The space on one side of a thing equals the space on the
  opposite side, unless the two sides mean different things. Examples: the
  same space on both sides of a divider; the same space at the top and at the
  bottom of a view.
- **R3. Alignment.** The first marks of a region start on one line, the content
  edge.
- **R4. One value for one relation.** The same relation gets the same distance
  everywhere, from one scale of roles.
- **R5. Economy.** Space costs room on the screen. Use the least space that keeps
  the rules above. A dense view, such as code, a tree, a table or a log, uses the
  smallest steps.

### What the principles do not decide

- **O1. Is the cut edge of a view that scrolls a visible edge?** If it is, N1
  holds there at every scroll position, and the content is cut 8 px inside the
  edge. If it is not, the content passes under the edge. R2 asks for the same
  answer at the top and at the bottom. The user (2026-11-03): "it should be
  symmetric". Decided (2026-11-04): it is a visible edge, S2.
- **O2. Is a table that fills a slot a box with an edge, or a part of the
  frame?** As a box, N2 and N3 give it space around its border. As a part of
  the frame, T3 lets its fills reach the edges of the slot, and it draws no
  border. The user chose a box (2026-11-03): two tables in a split must not
  touch.
- **O3. Does the band of a selected row reach the edges of its slot?** If it
  does (T3), the tree takes the space of the slot into its rows. If it does not,
  the band is a shape 8 px inside the slot, and R3 puts the first mark of a row
  on the content edge, so the rows have no space of their own at the left.
  Decided (2026-11-04): it reaches the edges of its slot.

## 2. What other frameworks do

A research pass read the documentation and the source of each tool on
2026-11-03. The full tables, with a source for each claim, are in the appendix.
"nv" marks a claim that the pass could not confirm.

Most of them agree:

- **Two layers of space.** The space inside the edge of a container, and the
  space between its children. Newer systems put the space between children on
  the parent: CSS `gap`, Compose `spacedBy`, Flutter `spacing`, Figma gap.
- **A scale.** Values come from a scale on a 4 px base (Fluent, Tailwind,
  Bootstrap), or from the platform style (Qt, SwiftUI).
- **The container owns the space at its own edge.** In Qt only the outer layout
  of a widget takes the style margin (11 for a window, 9 otherwise, spacing 6);
  a layout inside it gets 0.
- **IDE tools keep tables and lists flush, with no border.** Visual Studio Code
  lists have no padding; JetBrains: "Do not add borders between rows or
  columns". Settings screens use framed cards: libadwaita boxed lists, Flutter
  cards.

They split:

- **Margin.** Compose and Figma have none. Where it exists (CSS, Android,
  Flutter, GTK, WinUI), it causes double space, and only CSS collapses it, and
  not in flex or grid.
- **How a rule is selected.** CSS by the parents, the children (`:has()`) and
  the siblings. The toolkits by the type of the element, through a style or a
  theme. Flutter and Compose by an inherited context: the `MediaQuery` padding,
  the padding values of a `Scaffold`, insets that a child consumes.
- **Scrolling.** The padding scrolls with the content in CSS, Compose
  `contentPadding`, Flutter `SliverPadding` and SwiftUI `contentMargins`.
  Android views cut the content inside the padding by default (`clipToPadding`).
  Qt viewport margins stay fixed outside the view.

What this means for the decisions of section 8:

- **D1.** The input I4 is close to the consumed insets of Compose and the
  `MediaQuery` padding of Flutter: a parent passes an amount, and a child
  consumes it. The input I2 is close to the descendant selectors of CSS. The
  input I3 exists only as `:has()` in CSS.
- **O1.** Most of the newer toolkits let the padding scroll with the content
  (S1). Android views and Qt keep it fixed (S2).
- **O2, O3.** The IDE tools are flush; the settings screens are framed.

## 3. Step 0: no space at all

Set every padding, margin and gap to 0. Lines, borders and fills stay. Then:

- **T1 to T4 already hold.** The areas touch, the lines run to the lines, and
  the fills reach their edges, because nothing adds space. So the frame needs no
  space at all.
- **N1 breaks everywhere.** The text of a button touches its border, the text of
  a cell touches the grid line, a command touches the border of its menu, and
  the first line of a page touches the edge of the window and the divider.
- **N2 and N3 break.** Two buttons of a row touch, two cards touch, and two
  tables in a split touch, with their borders on the divider.
- **C1 and C2 break.** An icon touches its label, the rows of a form touch, and
  groups do not separate from each other.

So **each space must have a reason in an N rule or a C rule**. A space that no N
rule and no C rule asks for is a space to remove. This is the test for every
value below.

## 4. The degrees of freedom

| Element | Freedom | Which principle needs it |
|---|---|---|
| a control with an edge: a button, a field, a tab, a menu command, a badge | the space inside its edge (padding) | N1 |
| a row of a list or a tree, a cell of a table | the space inside its fill or its grid lines (padding); the indent of a level | N1, C1 |
| a box with an edge: a card, a dialog, an alert, a tooltip, a menu | the space inside its edge (padding); the gap between its parts | N1, C1, C2 |
| a layout: a row, a column, a grid | the gap between its children; the gaps of a grid by row and by column | N3, C1, C2 |
| a slot of the frame: the page of a tab, a pane of a split | the space between its edge and what it holds | N1, N2, R1 |
| a part of the frame: the shell bands, the tab group, a split, a divider | nothing: 0 everywhere; the width of a line | T1, T2 |
| a view that scrolls | how its edge treats the space: with the content, or cut inside | O1, R2 |
| a popup, a tooltip, a context menu | the distance from what it belongs to | C1 |

**Margin has no job left.** The space between two siblings is the gap of their
layout, and the space inside an edge is the padding of the box that draws the
edge. The only margin in the code today is the indent of a guide line of an
outline (`OutlineRow.jl:296`).

## 5. Where a value comes from

| Source | What it is | Good for | Weak for |
|---|---|---|---|
| **the document** | a field of a widget or a layout: `padding = Inset(4, 4, 8, 8)`, `gap = 8` | a place that is different on purpose | R4: a number in a document does not follow the theme or the scale |
| **the theme** | a role with a value: `control_padding`, `section_gap` | R4 and R5: one value for one relation, scaled, edited in the Appearance tab | a place where the role depends on where the thing is |
| **a rule** | a choice of a role by where the thing is (section 6) | R1 and N1 at the edge of a slot | it needs an input that knows the place |

Today a field that is `nothing` takes the role of its kind of widget from the
theme, and a field with a value wins.

## 6. How a rule decides

A rule picks a role for a place. It can read four inputs.

| Input | What it knows | An example rule | What it can not know |
|---|---|---|---|
| **I1. the type of the current document** | what the thing is | "a button has `control_padding`" | where the thing is |
| **I2. the type of the parent, upward** | the documents on the path from the root, by the typed reference of the print | "a page whose nearest parent with an edge is a tab gets 8; one in a card gets 0" | the direct parent is often a layout that draws nothing, so the rule must look for the nearest parent with an edge; across a projection the path names the domain document, not the widget that it became, which is to check |
| **I3. the type of the child, downward** | what the thing holds | "a tab gives 8 to its page, unless the page is a split" | the parent holds a document; it learns what the document becomes only after the child prints |
| **I4. the printer context** | what space the parents gave so far | "add what is missing to 8" | what lies in that space: a line, a fill, its colour |

Which input can decide which rule:

| Rule | I1 | I2 | I3 | I4 |
|---|---|---|---|---|
| N1 inside a control or a box | yes | — | — | — |
| C1, C2: the gap by the kind of layout | yes | — | — | — |
| N1 at the edge of a slot, once (R1) | no | yes, by the nearest parent with an edge | yes, in the frame | yes, as an amount |
| T1: no space around a split in a tab | no | yes | yes | yes, a split passes it on |
| a page in a card gets no second space | no | yes | no | yes |
| content on a tinted fill, such as an alert, needs space from the fill edge | yes, the alert pads | yes | no | no: the amount does not say that a fill is there |
| O1: the edge of a view that scrolls | yes, the scroll pane decides | — | — | yes, the amount to give |

## 7. From step 0 to the rules

Each step adds the space that one principle asks for, and names the input that
decides it. The artifact shows the screens after each step.

| Step | Principle | The space it adds | Input |
|---|---|---|---|
| 1 | N1 inside controls | `control_padding` 4, 4, 8, 8; the tab, the menu command and the table cell the same; a badge 2, 2, 6, 6; a row 2, 2, 8, 8 | I1 |
| 2 | N1 inside boxes | `container_padding` 8 for a card, a dialog and an alert; 4 inside a menu | I1 |
| 3 | N3 between separate things | `button_gap` 8; `item_gap` 4 between the items of a bar, whose own padding gives 12 between their icons (C4); `section_gap` 8 between cards | I1, by the kind of layout |
| 4 | C1, C2 | `title_gap` 2, `line_gap` 2, `form_row_gap` 6, `label_gap` 6, `form_column_gap` 8 | I1, by the kind of layout |
| 5 | N1 and N2 at the edge of a slot, R1 | `slot_padding` 8, given once, around the first box in a slot | I4 for the amount, I1 for how a box takes it: decision D1 |
| 6 | T1, T2 | nothing: the tab group, the split and the shell stay at 0, so the dividers still reach the lines | I1 |
| 7 | R2 | the same 8 on both sides of a divider, from step 5; a view that scrolls cuts its content 8 px inside every edge | I1 with I4: decision O1 |
| 8 | R3 | the first mark of each region on the content edge; the band of a selected row reaches the edges of its slot, and the rows hold the 8 px at the sides | I1 with I4: decision O3 |

## 8. What the user decided

The user accepted the three recommendations on 2026-11-04.

- **D1. The input for the space at the edge of a slot** (step 5): I4, the
  amount in the printer context, and I1, the type of the box, decides how the
  box takes it. A slot puts the space to give into the context. A split passes
  it on. The first box that has an edge takes it and passes 0.
  - Each part decides from what it gets. No part searches up the path, and no
    part looks into its child.
  - I2 must search upward for the nearest parent with an edge, because the
    direct parent is often a layout that draws nothing. Across a projection,
    the path names the domain document, not the widget that it became. The
    slot knows that it gives space, so the fact goes down with the print.
  - I3 must know what a document becomes before the document prints.
  - I4 does not know what lies in the space, such as a tinted fill. Only the
    alert needs that, and the alert pads itself by its type (I1).
  - Compose (consumed insets) and Flutter (`MediaQuery` padding) do the same.
- **O1. The edge of a view that scrolls:** S2. The view cuts its content 8 px
  inside every edge, at every scroll position, and its bar stays at its outer
  edge. It is the only option that is the same at the top, in the middle and
  at the bottom. Android does this by default (`clipToPadding`). The cost: the
  view loses 16 px of height, and text disappears 8 px before the line.
- **O3. The band of a selected row:** it reaches the edges of its slot (T3),
  as in Visual Studio Code and JetBrains. The rows keep the padding
  2, 2, 8, 8, so the first letter stays 8 px from the edge, as in every other
  slot. Two trees in a split can have bands that touch the divider from both
  sides. This is correct, because the divider is a line and a tree has no
  border. A table keeps its border and its 8 px.

**What follows from D1** (accepted by the user on 2026-11-04): a layout draws
no edge, so it is not the box that takes the space. It passes the space on by
side: a column gives the left and the right space to each child, the top space
to its first child and the bottom space to its last child, and a row does the
same across. Without this, the layout of the filter bar and the tree of the
Explorer takes the space around itself, and the bands of the tree stop 8 px
short of the edges.

## Appendix: the catalog of frameworks

Every cell is verified in a source listed under "Sources" unless it says "nv" (not verified). "n/a" means the concept does not exist or does not apply. Source-code claims were read on the main/dev branch on 2026-11-03, so numbers can differ in released versions.

### D1 Box model: which properties exist, on which elements

| Framework | Padding | Margin | Border | Gap between children |
|---|---|---|---|---|
| CSS | on every box | on every box; vertical margins of block siblings and parent/child collapse; not in flex/grid containers | on every box | `gap` on flex, grid, multicol containers; default `normal` = 0 (1em in multicol) |
| Figma auto layout | on the frame (container) | no margin property on the page read (nv that none exists) | stroke; "include strokes in layout" setting acts like border-box | gap on the frame: number, or Auto (Between/Around/Evenly) |
| Qt Widgets | none on plain widgets; layout contents margins act as padding of the container | none on widgets; QSS has margin, border, padding | QFrame/QSS | `QLayout::spacing` between items |
| GTK 4 / libadwaita | CSS padding on a widget | `margin-start/end/top/bottom` properties on any widget | CSS border | `GtkBox:spacing`, default 0 |
| SwiftUI | `.padding()` modifier | none as a concept (nv); padding only | `.border` / overlay | stack `spacing:`; nil = system default distance per pair |
| AppKit | nv (Auto Layout constraints) | n/a | n/a | n/a (stack views: nv) |
| Android Views | `padding` on any View | `layout_margin` on the child, read by the parent | background drawable | none in LinearLayout by default (nv for divider/gap props) |
| Jetpack Compose | `Modifier.padding` | no margin modifier; the docs say order of modifiers replaces it | `Modifier.border` | `Arrangement.spacedBy(dp)` on Row/Column |
| Flutter | `Padding` widget; `Container.padding` builds one | `Container.margin` (outer space); `Card.margin` | decoration | `spacing` on Row/Column/Flex (default 0.0 on Wrap, same macro for Flex) |
| WinUI / Fluent | `Padding` on Grid, StackPanel, RelativePanel, Border, controls | `Margin` on every element (nv by quote) | `BorderThickness` | `StackPanel.Spacing` (nv by quote); WrapPanel `ItemSpacing`/`LineSpacing` default 0 |
| Material 3 | per-component values (ListItem: see D2) | window margin (nv, official page unreadable) | n/a | spacer between panes (nv) |
| VS Code workbench | per CSS | per CSS | per CSS | CSS; sash is the divider |
| JetBrains | borders/insets (JBUI) nv | n/a | n/a | UI DSL gaps NONE/SMALL/MEDIUM (rows), RightGap.SMALL (cells) |
| Tailwind | `p-*` | `m-*`, negative `-m-*` | `border-*` | `gap-*`; `space-x/y-*` = margins on all but the last child |
| Bootstrap | `p-*` | `m-*` | `border` | `gap-*`, `row-gap-*`, `column-gap-*` |

### D2 Source of values

| Framework | Source | Default scale / values |
|---|---|---|
| CSS | stylesheet, element, custom properties | no default; `gap` normal = 0 (1em multicol); UA stylesheet gives margins to some elements (nv) |
| Figma | set on the frame | number the designer types; no scale (nv) |
| Qt | style (`QStyle::pixelMetric`), overridable per layout | QCommonStyle: layout margin 11 (window) / 9 (not window), spacing 6; the doc says "11 on most platforms". Non-top-level layouts: 0 |
| GTK / libadwaita | CSS theme + widget properties | `.toolbar` = 6px margin + spacing; `.rich-list > row` padding 8px 12px, min-height 32px; `.frame` border 1px |
| SwiftUI | system, per platform and presentation context | `.padding()` "platform-specific default"; numbers nv |
| AppKit | HIG | nv |
| Android Views | XML attribute per view | n/a (dp set by author) |
| Jetpack Compose | `PaddingValues`, `contentPadding`, tokens | M3 ListItem: start 16dp, end 16dp, vertical 8dp, three-line 12dp, leading/trailing gap 16dp (ListItem.kt) |
| Flutter | widget argument; theme (`CardTheme`, `ListTileTheme`) | Card margin 4.0 all sides; ListTile content padding horizontal 16.0 (start 16, end 24 in some cases) |
| WinUI / Fluent | tokens, 4px base | "base unit is four pixels" (Fluent 2); WinUI doc: 8epx between buttons, 12epx control-label and content areas, text surface to edge 16epx (page text also says 12 in a caption: inconsistent) |
| Material 3 | tokens | margins 16dp (compact) / 24dp (medium, expanded), spacer 24dp: only via SAP secondary doc, official page not readable (nv) |
| VS Code | CSS + settings | `--vscode-sash-size: 4px`; `editor.padding.top/bottom` default 0; webview default body `padding: 0 20px` |
| JetBrains | guidelines + UI DSL | no px on the pages read (nv) |
| Tailwind | theme variable `--spacing` | `--spacing: 0.25rem`; `p-4` = `calc(var(--spacing) * 4)` |
| Bootstrap | Sass `$spacers` | `$spacer: 1rem`; 0, .25, .5, 1, 1.5, 3 rem |

### D3 How a rule is selected

| Framework | Own type/class | Parent/ancestor | Children | Siblings | State | Inherited context |
|---|---|---|---|---|---|---|
| CSS | type/class selectors | descendant `a b`, child `a > b` | `:has()` selects the parent or a previous sibling | `+`, `~`, `:not(:last-child)` | pseudo-classes | custom properties inherit by default; `@property` with `inherits:false` stops it |
| Figma | per frame | n/a | n/a | n/a | variants | variables/modes (nv) |
| Qt | QSS type, class, property selectors (nv by quote); style by widget class | QLayout asks "am I top level" and the style | n/a | n/a | QSS pseudo-states (nv) | layout spacing is "inherited from the parent layout, or from the style of the parent widget" |
| GTK | CSS node/class | CSS descendant | `:has` supported (nv) | CSS sibling (nv) | CSS pseudo-classes | CSS inherited props only |
| SwiftUI | per modifier call | environment | n/a | stack decides the default distance per pair of children | n/a | `contentMargins` same placement: inner overrides outer; no spacing environment value found (nv) |
| Android | per XML attribute / style / theme | parent reads child margins (LayoutParams) | n/a | n/a | state-list drawables | theme attributes |
| Compose | per modifier | `Scaffold` passes `PaddingValues` / window insets down | n/a | n/a | n/a | composition locals (nv for spacing) |
| Flutter | per widget argument | `Theme`/`InheritedWidget` (CardTheme margin); `MediaQuery` padding used by ScrollView when `padding` is null | n/a | n/a | n/a | `InheritedWidget` |
| WinUI | per element | attached properties are read by the immediate parent only | n/a | n/a | VisualStateManager | resource dictionaries/styles |
| Tailwind | utility on the element | `space-*` is a child selector `& > :not(:last-child)` | n/a | siblings via `space`/`divide` | variants (`hover:`) | theme variable |

### D4 Nesting: avoiding double space

| Framework | Mechanism |
|---|---|
| CSS | margin collapsing (adjacent siblings, parent/first child) removes the double; not in flex/grid; padding/border/BFC stop it |
| Figma | no margin: only the parent's padding and gap exist, so nesting adds only what a frame sets |
| Qt | a layout that is not top level has margin 0 unless set (qlayout.cpp `getMargin`: user value, else 0 if not top level, else style) |
| GTK | no rule found; the author sets margins (nv) |
| SwiftUI | `.padding()` stacks (adds); `scenePadding` is meant for the root view of a window only (macOS); a stack asks the system for the distance between each pair of children |
| Android | no rule; margins of children are summed with parent padding (nv by quote) |
| Compose | no margin concept: only padding on the element, so nothing to collapse; `Scaffold` consumes insets so a child does not pad them twice (doc: "Exclude currently consumed window insets") |
| Flutter | padding is a widget: nesting adds; Container: padding inside decoration, margin outside; ScrollView consumes the MediaQuery main-axis padding and leaves the cross-axis padding for children |
| WinUI | no rule found (nv) |
| Tailwind | `space-*` skips the last child, so no trailing double; the docs say prefer `gap` |
| Bootstrap | `gap-*` "saves on adding margin utilities to individual children" |
| VS Code, JetBrains, Material | nv |

### D5 Panes, splits, tabs

| Framework | Content vs pane edges | Divider | Tables/lists in a pane |
|---|---|---|---|
| CSS | n/a (author's choice) | n/a | n/a |
| Figma | n/a | n/a | n/a |
| Qt | QTabWidget `documentMode` removes the tab widget frame, "helps when pages fill most of the area"; splitter handle by style (nv) | style | QAbstractScrollArea is a QFrame, so framed by default (nv: frame drawn in default style) |
| GTK / libadwaita | `.boxed-list` = card look (rounded, framed, separated rows); plain lists flush | 1px `.frame` border available | boxed list for settings; plain list/column view flush (nv by quote) |
| SwiftUI/AppKit | scene padding for window roots on macOS | nv | List/Form insets: `listRowInsets` "changes the default padding of the content of list items" |
| Android / Compose | n/a | n/a | `contentPadding` / padding on the list |
| Flutter | n/a | n/a | `Card` default margin 4.0 around; list padding is the list's `padding` |
| WinUI | panel `Padding`; page margin guidance: see D2 | n/a | n/a |
| VS Code | views are flush to the edges (nv by source: `.monaco-list` has no padding; tree rows indent only); editor.padding.top = 0 | sash 4px wide hit area (`--vscode-sash-size`) | flush, borderless |
| JetBrains | nv | n/a | "Do not add borders between rows or columns" in a table; only an edited cell gets a border |
| Material 3 | nv | spacer between panes 24dp (secondary source only) | list item padding 16dp horizontal, 8dp vertical (Compose ListItem.kt) |

### D6 Scrolling

| Framework | Does padding scroll with the content? |
|---|---|
| CSS | yes: the spec adds the container's own padding to the scrollable overflow so there is padding at the end when scrolled to the end (css-overflow-3 note); engine behavior at inline-end: nv |
| Figma | n/a |
| Qt | `setViewportMargins` reserves blank space outside the viewport (default 0), used for headers; it does not scroll |
| GTK | nv |
| SwiftUI | `contentMargins(_:for:)` insets scrollable content by safe area plus the amount; `.scrollContent` placement leaves indicators alone |
| AppKit | `NSScrollView.contentInsets` insets the document view; headers/rulers are tiled over it |
| Android Views | `clipToPadding` default true (`FLAG_CLIP_TO_PADDING` set in ViewGroup init): children clip to padding; set false so content scrolls through the padding |
| Compose | `contentPadding` "will add padding for the content after it has been clipped, which is not possible via modifier": it scrolls with the content |
| Flutter | `ScrollView.padding` is applied with `SliverPadding` inside the scrollable: it scrolls with the content; if null, MediaQuery padding is applied the same way |
| WinUI, Material, VS Code, JetBrains | nv |

### Sources

- CSS: https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_box_model/Mastering_margin_collapsing ; https://developer.mozilla.org/en-US/docs/Web/CSS/gap ; https://developer.mozilla.org/en-US/docs/Web/CSS/:has ; https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Cascading_variables/Using_custom_properties ; https://drafts.csswg.org/css-overflow-3/
- Figma: https://help.figma.com/hc/en-us/articles/360040451373-Explore-auto-layout-properties ; https://developers.figma.com/docs/plugins/api/properties/nodes-strokesincludedinlayout (via search result only)
- Qt: https://doc.qt.io/qt-6/qlayout.html ; https://github.com/qt/qtbase/blob/dev/src/widgets/kernel/qlayout.cpp (`getMargin`) ; https://github.com/qt/qtbase/blob/dev/src/widgets/styles/qcommonstyle.cpp (PM_LayoutLeftMargin, PM_LayoutHorizontalSpacing) ; https://doc.qt.io/qt-6/qabstractscrollarea.html ; https://doc.qt.io/qt-6/qtabwidget.html ; https://doc.qt.io/qt-6/stylesheet-customizing.html ; https://doc.qt.io/qt-6/qstyle.html
- GTK/libadwaita: https://docs.gtk.org/gtk4/class.Widget.html ; https://docs.gtk.org/gtk4/property.Box.spacing.html ; https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1-latest/style-classes.html ; https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1-latest/class.Clamp.html ; https://gitlab.gnome.org/GNOME/libadwaita/-/raw/main/src/adw-preferences-page.ui (ScrolledWindow > Clamp > Box) ; https://gitlab.gnome.org/GNOME/libadwaita/-/raw/main/src/stylesheet/widgets/_lists.scss
- Apple (Apple JSON doc API, since the HTML pages are script-rendered): https://developer.apple.com/documentation/swiftui/view/padding(_:_:) ; .../vstack/init(alignment:spacing:content:) ; .../view/scenepadding(_:edges:) ; .../view/listrowinsets(_:) ; .../view/contentmargins(_:_:for:) ; https://developer.apple.com/documentation/appkit/nsscrollview/contentinsets ; .../automaticallyadjustscontentinsets
- Android: https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/view/ViewGroup.java ; https://developer.android.com/reference/android/view/ViewGroup ; https://developer.android.com/develop/ui/compose/modifiers ; https://developer.android.com/reference/kotlin/androidx/compose/foundation/layout/Arrangement ; https://android.googlesource.com/platform/frameworks/support/+/refs/heads/androidx-main/compose/foundation/foundation/src/commonMain/kotlin/androidx/compose/foundation/lazy/LazyDsl.kt ; .../compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/ListItem.kt and Scaffold.kt
- Flutter: https://api.flutter.dev/flutter/widgets/Padding-class.html ; https://api.flutter.dev/flutter/widgets/Container-class.html ; https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/scroll_view.dart ; .../widgets/basic.dart ; .../material/card.dart ; .../material/list_tile.dart ; .../rendering/flex.dart
- WinUI/Fluent: https://learn.microsoft.com/en-us/windows/apps/design/layout/layout-panels ; https://learn.microsoft.com/en-us/windows/apps/design/basics/content-basics ; https://fluent2.microsoft.design/layout
- Material 3: official pages (m3.material.io) are script-rendered and could not be read. Secondary: https://www.sap.com/design-system/fiori-design-android/v26-4/foundations/adaptive-layout/layout-basics
- VS Code: https://github.com/microsoft/vscode/blob/main/src/vs/base/browser/ui/sash/sash.css ; .../editor/common/config/editorOptions.ts ; .../workbench/contrib/webview/browser/pre/index.html ; .../base/browser/ui/list/list.css ; https://code.visualstudio.com/api/references/theme-color
- JetBrains: https://plugins.jetbrains.com/docs/intellij/layout.html ; https://plugins.jetbrains.com/docs/intellij/table.html ; https://plugins.jetbrains.com/docs/intellij/kotlin-ui-dsl-version-2.html ; https://plugins.jetbrains.com/docs/intellij/tool-windows.html
- Tailwind/Bootstrap: https://tailwindcss.com/docs/theme ; https://tailwindcss.com/docs/padding ; https://tailwindcss.com/docs/margin ; https://getbootstrap.com/docs/5.3/utilities/spacing/

### Patterns

Agreed by almost all:
1. Two layers of space: space inside a container's edge (padding / contents margins / auto layout padding) and space between its children (gap / spacing / spacedBy / Spacing). Newer systems (CSS gap, Flutter `spacing`, Compose `spacedBy`, Figma gap, Tailwind advice) moved the between-children space to the parent, so a child does not know its neighbors.
2. Spacing comes from a scale on a 4-unit base (Tailwind 0.25rem, Fluent "four pixels", Bootstrap 0.25rem steps) or from the platform style (Qt `pixelMetric`, SwiftUI "system" default).
3. The container owns the space of its own edge. Qt makes this explicit: a nested layout has margin 0, only a top-level layout takes the style value.
4. Margin is the contested part. Compose, Figma and (by its docs) SwiftUI have no margin; the Compose docs say modifier order replaces it. Where margin exists (CSS, Android, Flutter Container, WinUI, GTK), it is the source of double space, and only CSS has a collapse rule.
5. Scroll content: padding of a scroll container is inside the scrolled extent in CSS (spec), Compose `contentPadding`, Flutter `SliverPadding`; Android Views clips to the padding by default and needs `clipToPadding=false` to scroll through it.
6. Tables and lists in a pane are flush and borderless in IDE-style tools (JetBrains: no borders between rows or columns; VS Code lists have no padding at the pane edge). Settings-style screens use framed cards (libadwaita boxed list, Flutter Card margin 4).

Where they split:
- Selection of a rule: CSS and Tailwind select by ancestor, child or sibling (`>`, `:has`, `:not(:last-child)`); toolkits select by the element's own type through a style or theme (Qt, GTK, WinUI) or by environment (Flutter InheritedWidget, SwiftUI environment, Compose Scaffold padding values). Only CSS selects by what a container holds.
- Whether the default is zero (CSS gap, GtkBox spacing, WrapPanel, Flutter) or a style value (Qt 6/9/11, SwiftUI "system default").
- Whether a child may add its own outer space (margin) or only the parent may (Compose, Figma, gap-only systems).
