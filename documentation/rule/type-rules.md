# Type

> **Kind:** rule · **For:** developer · **Status:** current · **Stands on:** [style.md](../package/platform/style/style.md)

Which font each text of a window takes, and why. A font field of a theme names a role of the font theme of the appearance, and the role gives the family, the size, the weight and the slant. [style.md](../package/platform/style/style.md#themes-and-the-appearance) says how a role becomes a font, and this document says which role a text takes.

## 1. The six differences

A person must see six differences at a glance. Each one has a means that shows it, and each means is a difference between two roles.

| Difference | How the type shows it | Roles |
| --- | --- | --- |
| the window frame against the content | the frame is 13 px, and a document is 14 px | `text` against `document_text` and `document_code` |
| a title against what it heads | a title is larger and medium | `title`, `page_title` and the headings against `text` and `document_text` |
| a label against its value | the label is medium, at the same size | `label` against `text` |
| main text against quiet text | quiet text is smaller and muted | `quiet` against `text` |
| code against normal text | code is monospaced | `code` and `document_code` against `text` and `document_text` |
| emphasis inside text | the weight or the slant changes, and the size does not | a role with `weight = 700` or `italic = true` |

A title differs from the text that it heads in size and in weight, and quiet text differs from main text in size and in colour. A label differs from its value only in weight, because the two stand side by side in one row, and the position of the label shows the rest.

## 2. The roles

A role is a field of `FontTheme` ([FontTheme.jl](../../source/platform/style/FontTheme.jl)). It holds a `FontStep`: a kind of family, a size in logical pixels, a weight and a slant. The values below are the defaults at scale 1.

| Role | Size | Weight | Family | Colour in the usual case | For |
| --- | --- | --- | --- | --- | --- |
| `page_title` | 20 | 500 | sans | text | a help page, an about page, the title of an outline |
| `title` | 16 | 500 | sans | text | a pane, a card, a dialog |
| `text` | 13 | 400 | sans | text | the frame, a control, a row, a cell of a table, a tool panel |
| `label` | 13 | 500 | sans | text | the name of a field of a form, of a setting, of a scale |
| `strong_text` | 13 | 700 | sans | text or tone | the head of a row: an accordion item, an alert title, a tooltip title, the label of a turn |
| `section` | 12 | 700 | sans | muted | the heading of a group inside a pane |
| `column` | 12 | 500 | sans | muted | the header of a table, the title of an axis |
| `quiet` | 12 | 400 | sans | muted | a caption, a description, a hint, a footer, the status bar, a time, a count |
| `badge` | 12 | 500 | sans | tone | a badge, a chip, the level of a log message, a key cap |
| `document_text` | 14 | 400 | sans | text | prose in a document, a message, a help text |
| `heading_1` to `heading_6` | 24, 20, 16, 14, 14, 14 | 700 | sans | heading; 5 and 6 muted | the headings of a document |
| `code` | 13 | 400 | mono | syntax | code in a tool panel |
| `document_code` | 14 | 400 | mono | syntax | code in a document, and every code view |

The window uses six sizes, 12, 13, 14, 16, 20 and 24, and three weights, 400, 500 and 700. The font theme names two families: `sans_family`, Ubuntu by default, and `mono_family`, Ubuntu Mono by default. A role names a kind of family, `:sans` or `:mono`, and no family, so a change of a family moves every role of that kind. DejaVu Sans Mono and Noto Emoji give the glyphs that a family does not have ([style.md](../package/platform/style/style.md#fonts-and-their-faces)).

Two rules hold inside one view:

- **A code view keeps one size and one family.** Every text of a code domain takes `document_code`, and a keyword, a name and a delimiter differ only in colour and in weight. So the columns of the code stay in line.
- **A placeholder keeps the size of its field.** The text that a field shows when it is empty takes the font of the field, and only its colour is muted.

## 3. A role with its own weight or slant

A field that names a role can set its own weight and its own slant over those of the role. Emphasis inside a text is this form:

```julia
keyword_text::ThemeText = TextRole(:keyword; font_role = :document_code, weight = 700)
selected_tab_font::ThemeFont = FontRole(:text; weight = 500)
```

A field never sets its own size. If it could, the sizes would drift apart again, one theme at a time. A text that needs another size takes another role.

## 4. The exceptions

A field that needs another size or another family holds an exact `StyleFont`. No role changes it, and only the font scale of the appearance scales it. The exact fonts of the themes are these:

| Field | Font | Why |
| --- | --- | --- |
| the marks of a tooltip (`TooltipTheme`) | Lucide 13 | an icon is a glyph of the icon font |
| the role icons of a conversation (`ConversationTheme`) | Lucide 14 | an icon is a glyph of the icon font |
| the rendered markers of Markdown and of reStructuredText | DejaVu Sans Mono 14 | the arrows and the rules of a marker are glyphs that Ubuntu Mono does not have |
| the type name of a help page (`HelpTheme`) | Ubuntu Mono 20 at weight 700 | the name is code at the size of a page title, and Ubuntu Mono has no medium face |

Three other texts keep a font of their own:

- **A text with no font.** A `TextString` made with no font stores `UNSTYLED_TEXT_FONT` in the document, and the printer draws each span with the font that the span holds.
- **A document with a style of its own.** A chart document holds a `ChartStyle`, whose fonts are values of the document, as its colours are.
- **The scripts of a formula.** The math typesetter draws a script at 0.7 and a second script at 0.5 of the size of its font. They follow the role, because the typesetter multiplies the size of the font that the role gives.

A projection holds the fonts of its theme as style fields, and its builder fills them from the theme, as `make_conversation_composer_projection` fills the `code_font` of the composer. No builder takes a font beside its theme.

## 5. How a new widget, panel or domain gets its fonts

1. **Find the job of the text** in section 2: a title, a label, the text of a control, quiet text, code.
2. **A widget reads the font of its part** from `WidgetTheme`. [widget.md](../package/platform/widget/widget.md#the-theme) lists the font field of each part. A part with a job that no field names gets a field with a role and a docstring that says what it changes on the screen.
3. **A panel or a domain names the role in its theme.** A text field is `TextRole(color; font_role = :role)`. A font field that a projection reads, such as the font of the line breaks of a code view, is `FontRole(:role)`. The builder gives the projection the styles of the theme, as [new-domain-guide.md](../guide/new-domain-guide.md) shows.
4. **Show emphasis by weight or by slant** over the role, as section 3 shows.
5. **Hold an exact font only for a glyph** that only one family has, such as an icon. Write in the docstring of the field why the font is exact.

A builder must not do these:

- **A font as a literal value in a projection.** A `StyleFont("…` in `source/`, outside a theme, fails the style guard `test_style()` ([testing-guide.md](../guide/testing-guide.md#the-style-guard)).
- **A font argument beside a theme.** `WidgetToGraphics` takes no font: the fonts of the widgets come from the widget theme. A builder takes the theme, and the theme gives each font. A view that needs larger text scales the fonts of its appearance.
- **Two themes for one text.** One theme gives the fonts of a text. The Reference tab takes the text of a reference from `ReferenceTheme`, and its own theme gives only its headers.
- **A size of its own on a role.** A role has no size keyword. A text that needs another size takes another role.
