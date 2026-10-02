# The theme chooses the line spacing

> **Status:** pending, not started. A follow-up of
> [a-line-of-text-sits-on-one-baseline.md](../done/a-line-of-text-sits-on-one-baseline.md):
> the owner decided on 2026-09-26 to treat the theme value of question 3 there as
> a separate step. On 2026-10-02 the owner moved this work into
> [default-look-fits-a-desktop.md](default-look-fits-a-desktop.md) (decision
> D9). The spacing is a theme value, as section 4 recommends. Step V2 there sets
> it: code 1.35, prose 1.5, widgets single. This plan moves to `plan/done/` with
> that plan.

## 1. The request

Question 3 of the line plan decided single spacing by default, and a value that
a theme chooses for code, for prose and for widgets. The line plan implemented
the spacing, but no theme chooses it yet.

## 2. What exists

- `TextToGraphics(; measure, line_spacing = SingleSpacing())` sets the lines of
  a text block with the spacing it holds.
- `compute_line_box(measure, text, font; spacing = SingleSpacing())` gives the
  line of one text, for a widget label, a chart title and an overlay row.
- The spacing types are `SingleSpacing`, `MultipleSpacing(factor)`,
  `ExactSpacing(distance)` and `AtLeastSpacing(distance)`, in
  `source/style/LineSpacing.jl`.
- No theme reaches the text layout. Every builder of `TextToGraphics` passes
  only a measure: `NaturalToGraphics`, `SyntaxNatural`, the inspector, the
  gesture log, the command palette, the gesture help, the fault overlays, the
  catalog and the examples. The widgets have a theme (`WidgetTheme`), but it
  holds fonts, colors and sizes, and no spacing.

## 3. The questions for the owner

1. Where does the spacing of a text live? One choice is the document: a text
   block or a line carries its spacing, as a paragraph style of a word
   processor does. The other choice is the projection: the builder takes the
   spacing from a theme object and passes it to `TextToGraphics`.
2. Which spacing does each kind of text get? For example: code `SingleSpacing`,
   prose `MultipleSpacing(1.15)`, widgets `SingleSpacing`.

## 4. My recommendation

This is a recommendation, not a decision. The spacing is a property of how a
text looks, not of what it says, so I recommend the projection side: a theme
value that each builder reads, as the widgets read `WidgetTheme`. A document
that needs its own spacing (a Markdown document with a style sheet) can come
later, on top of it.
