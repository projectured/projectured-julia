# The appearance tab groups its settings in cards

> **Status:** done on 2026-10-05. Written on 2026-10-05 at the owner's request.
> The owner agreed with the fix (section 3) and with the answers of section 4
> the same day. The branch `appearance-tab-cards` landed on `main` by a
> fast-forward, at `46302b4f4`; the owner said "land it". After the landing the
> owner wrote "looks fine", which closes questions 1 and 3 of section 6: the tab
> keeps `2 × section_gap` between groups and the step of 12 px in the titles.

## 1. The request

The owner wrote on 2026-10-05:

> on the appearance tab the first few groups (sizing, themes) are not grouped
> nicely. what can we do?

Claude rendered the tab offscreen and found five problems (section 2). Claude
gave a small fix and a full fix, and recommended the full fix. The owner wrote:
"I agree with your recommended fix". Then Claude gave its view on the open
questions (section 4), and the owner wrote: "yes".

## 2. The facts (2026-10-05)

1. `print_document` of `AppearanceToWidget`
   ([AppearanceToWidget.jl:159](../../source/platform/appearance/AppearanceToWidget.jl#L159))
   puts all parts in one `VerticalLayout` with the gap `section_gap` (8 px).
   The parts are, in order:
   1. a `GridLayout` of the seven rows of `_APPEARANCE_ROWS` (Zoom, Text, Icons,
      Spacing, Controls, Corners, Lines), with no heading;
   2. a row of the buttons "Reset all", "Save" and "Load";
   3. the heading "Colors", a bold label in the muted color;
   4. a `GridLayout` of the five colour settings (`_make_color_settings`);
   5. the card of the colour theme of the present mode and contrast;
   6. for each of "Editor", "Tools" and "Documents", a heading and one card for
      each theme (`_get_theme_groups`).
2. The rows of items 1 and 4 have no frame. Each theme is a collapsible
   `WidgetCard` with a title and a summary (`_make_theme_section`).
3. "Reset all" is a `CompoundOperation` of the reset of the seven scales
   (`_make_step_operation(appearance, field, 0)`) and of the writes of the five
   defaults of `_COLOR_SETTING_DEFAULTS`. It resets no theme. "Save" and "Load"
   write and read the whole appearance.
4. A heading is `section_gap` from the part above it and `section_gap` from its
   own first card, so it does not join its group.
5. Each card hugs its content. In a render at 900 px the cards are from about
   400 px to 900 px wide. `VerticalLayout` takes `child_width = Fill`
   ([LayoutDocument.jl:147](../../source/platform/layout/LayoutDocument.jl#L147)),
   and `McpLogToWidget` uses it for the same purpose.
6. The colour theme is not in `appearance.themes`. It is one of
   `appearance.color_themes`, and `get_color_theme(appearance)` gives the one
   in use. So `_get_theme_groups` does not hold it, and `print_document` adds
   its card by hand under "Colors".
7. The settings tab makes one `WidgetCard` for each group
   ([SettingsToWidget.jl:107](../../source/platform/settingsmanaging/SettingsToWidget.jl#L107)),
   with a title, a description and a grid of rows. It puts "Reset all", "Save"
   and "Load" at the bottom.
8. `WidgetCard` has a `footer` part
   ([WidgetDocument.jl:1586](../../source/platform/widget/WidgetDocument.jl#L1586)).
   No producer in `source/platform` sets it now. The printer draws it as a
   caption text, `string(w.footer)`
   ([WidgetToGraphics.jl:6675](../../source/platform/widget/WidgetToGraphics.jl#L6675)),
   so it can not hold a button. Found in step 1.
9. A collapsible card draws a chevron in a column of its own, and its title and
   body start past it. A card that is not collapsible has no such column.
10. The widget theme has `item_gap` (2), `title_gap` (4, "the space under a
    title"), `label_gap` (6) and `section_gap` (8)
    ([WidgetTheme.jl:124](../../source/platform/widget/WidgetTheme.jl#L124)).
    It has no gap between groups.
11. Tests and documents that name the parts that change:
    - [AppearanceTabTest.jl:70](../../test/platform/appearance/AppearanceTabTest.jl#L70)
      looks for "Reset all";
    - [AppearanceTabTest.jl:155](../../test/platform/appearance/AppearanceTabTest.jl#L155)
      checks the order "Editor", "Widget", "Syntax", "Tools", "Fault";
    - [AppearanceTabTest.jl:412](../../test/platform/appearance/AppearanceTabTest.jl#L412)
      looks for "Colors";
    - [appearance.md:54](../../documentation/package/platform/appearance/appearance.md)
      and the docstring of `AppearanceToWidget` describe the order of the tab.

    No video, site page, omnet-julia or inet-julia file names "Reset all" of
    this tab. No file of the change is sealed.

## 3. The fix

The order of the tab after the change:

1. A row with "Save" and "Load".
2. The card "Scale": the seven rows of `_APPEARANCE_ROWS`, and a button "Reset".
3. The card "Colors": the five rows of the colour settings, and a button
   "Reset".
4. The heading "Editor", then the card of the colour theme, then the cards of
   `_EDITOR_THEME_TYPES`.
5. The heading "Tools" and its cards; the heading "Documents" and its cards.

The rules:

- The two new cards do not fold. They are short, and people use them most.
- Each new card has a fixed summary as its `description`, because no theme type
  gives one:
  - Scale: "The zoom of every view, and the size of the text, the icons, the
    gaps, the controls, the corners and the lines."
  - Colors: "The mode, the contrast and the palette of the colours, and the hues
    of the accent and the neutral."
- The "Reset" of the Scale card resets the seven scales. The "Reset" of the
  Colors card writes the five defaults. Together they do what "Reset all" did.
  "Reset all" goes away.
- The heading "Colors" goes away: the card title replaces it.
- Each group is a `VerticalLayout` of its heading and its cards. The gap under
  the heading is `title_gap`. The gap between two cards of a group is
  `section_gap`. The gap between two groups is larger (section 6, question 1).
- Every card fills the width of the pane: `child_width = Fill` on the outer
  layout and on each group.

## 4. The answers of 2026-10-05

1. Cards, not only headings.
2. The title is "Scale", not "Size". Each row is a factor in percent, and the
   code uses the same word (`*_scale`, `APPEARANCE_SCALES`,
   `AdjustScaleOperation`).
3. The action row is at the top, with "Save" and "Load" only. At the top,
   "Reset all" would promise to reset the themes, and it does not. So each top
   card gets its own "Reset".
4. The colour theme stays a separate theme card, first in "Editor". It stays
   right under the Colors card, near the settings that select it.

## 5. Steps

Work in the worktree `projectured-julia-appearance-tab-cards` on the branch
`appearance-tab-cards`. Commit each step. Do not land on `main` until the owner
says so.

- [x] **Step 1. The cards and the groups.** Done on 2026-10-05. Decisions in
  the code:
  - The button under the rows of each new card is "Reset all", not "Reset". The
    Scale card has a "Reset" on each row, so a "Reset" under the rows looks like
    one more row reset. The button is in the card, so its scope is the card.
  - The button is in `content`, under the grid, because the `footer` is a text
    (fact 8). This answers question 2.
  - The gap between groups is `2 × section_gap` (question 1, the suggestion of
    Claude, not yet the choice of the owner).

  In
  [AppearanceToWidget.jl](../../source/platform/appearance/AppearanceToWidget.jl):
  - make the action row of "Save" and "Load" the first part;
  - add `_make_scale_card(controls)` and `_make_color_settings_card(controls)`,
    each a `WidgetCard` with its title, its summary, its grid and its "Reset";
  - put the colour theme first in the group "Editor" of `_get_theme_groups`;
  - make each group a `VerticalLayout` of its heading and its cards;
  - set `child_width = Fill` on the outer layout and on each group;
  - change the docstring of `AppearanceToWidget` to the new order.
- [x] **Step 2. The tests.** Done on 2026-10-05. In
  [AppearanceTabTest.jl](../../test/platform/appearance/AppearanceTabTest.jl):
  - the first testset also looks for "Save", "Load" and "Scale";
  - a new testset: the "Reset all" of the Scale card answers the reset of the
    seven scales, and the "Reset all" of the Colors card the writes of the five
    defaults of a new `Appearance`;
  - the test of the groups checks the order "Save", "Scale", "Colors",
    "Editor", "Color", "Widget", "Syntax", "Tools", "Fault";
  - a new render test, as the rule "cards fill" asks: it prints the tab at the
    offers 800 and 500, and takes the width of each card from the IO map tree.
    Every card has one width, and that width grows by 300 between the two
    offers. The helper `_at_collect_card_widths` walks the fields of each IO
    map and the tuples of `child_iomaps`, because a `FaultCatchingIoMap` gives
    no children through `get_child_iomaps`.

  `test_appearance_tab()` alone: 119 of 119 pass. The same test file on the
  old code fails 7 and errors 1: the new names, the two "Reset all", the order,
  and the widths, which at the offer 800 go from 606 to 798.
- [x] **Step 3. The look.** Done on 2026-10-05. Renders offscreen with
  `write_image` and `NaturalToGraphics`, before and after:
  - At 900 px every card is 900 px wide. The heading of a group is 4 px above
    its first card and 16 px below the group above it.
  - The titles "Scale" and "Colors" start at x = 13, and the titles of the
    theme cards at x = 25, past the chevron: a step of 12 px (question 3).
  - With the Color and Widget cards open, at 520 px both versions fit. At
    380 px both versions cut the rows of the open Color card at the same
    place, so `Fill` adds no cut: the pane clipped that card before.
- [x] **Step 4. The document.** Done on 2026-10-05. The list of the tab in
  [appearance.md](../../documentation/package/platform/appearance/appearance.md)
  has the new order.
- [x] **Step 5. Report.** Done on 2026-10-05. Give the commits, the test counts, the two renders and
  the command that lands the branch. Then stop and ask.

## 6. Open questions

1. **The gap between two groups.** The widget theme has no field for it. Claude
   suggests `2 × section_gap` first, because it follows the spacing scale and
   adds no field. A new field `group_gap` is the other choice. It shows on the
   tab as a row of the widget theme, as every field does. The branch uses
   `2 × section_gap`; the owner has not chosen yet.
2. **The place of "Reset" in a card.** Answered in step 1: the `footer` is a
   text (fact 8), so the button "Reset all" is under the grid in `content`.
3. **The indent of the titles.** A card that does not fold has no chevron
   column, so the titles "Scale" and "Colors" start further left than the titles
   of the theme cards. Step 3 measured a step of 12 px. Open for the owner: keep
   it, or give the two cards the same indent.

## 7. Not in this plan

- The settings tab keeps its action row at the bottom. To make the two tabs
  agree is a separate small step, if the owner wants it.
- The summary of the colour theme shows `[ColorRole](@ref)` as text:
  `strip_code_marks` does not remove a Documenter link. That is a separate
  fault.
