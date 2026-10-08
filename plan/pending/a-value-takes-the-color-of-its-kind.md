# A value takes the color of its kind

> **Status:** in progress on the branch `value-colors`, in the worktree
> `projectured-julia-value-colors`. Part A, the values (sections 4 to 8), is
> decided and goes first. Part B, the names (section 10), is in design. The
> owner answered the questions on 2026-10-08 (section 9).

## 1. The request

The owner wrote on 2026-10-08:

> in projectured-jula, JSON number/string/boolean or Julia
> string/number/boolean/symbol constants and primitive string/number/boolean,
> they should have different style roles to be different color on the screen

and then:

> generalize this idea

## 2. What is there now

The colors have three layers
([ColorTheme.jl](../../source/platform/style/ColorTheme.jl)):

1. A palette gives 9 hues of 12 steps: `neutral`, `red`, `orange`, `amber`,
   `green`, `teal`, `blue`, `violet` and `pink`.
2. `ColorTheme` gives 63 roles. Each role names a step of a hue.
3. Each theme of a domain or a view names a role in each color field, with
   `TextRole(:role)` or `ColorRole(:role)`.

The themes already have one field for each kind of value. For example,
`JsonTheme` has `null_text`, `bool_text`, `number_text` and `string_text`. But
the token group of `ColorTheme` has only two roles for a value:

- `string_literal` (green 11): "A string, a character, a code span, a literal
  block."
- `constant` (orange 11): "A number, a boolean, a null, a symbol, an index."

So a number, a boolean, a null and a symbol have the same orange in every view.
A person can split them for one view in the appearance tab, field by field, but
the defaults do not.

29 fields in 11 themes name one of the two roles (section 6).

## 3. The rule

**A value of one kind has one role in every view, and two kinds that a reader
tells apart have two roles.** A view that knows the kind of a value names the
role of that kind. It never names a group role, such as `constant`, for it.

This rule is the general form of the request:

- It covers every kind of value, not only the kinds of the request: a string,
  a character, a number, a boolean, a null and a symbol.
- It covers every view that shows a value: a domain (JSON, YAML, Julia, SQL,
  XML), the syntax view, the primitive projection, the reflection of an object,
  and a cell of a table.
- A number in JSON, in Julia, in YAML and in a cell of a data frame has the same
  color. A person who changes the color of the role `number_literal` changes it
  in each view.

Real tools have the same model. The semantic tokens of the Language Server
Protocol name `string`, `number`, `regexp`, `enumMember` and more. A TextMate
grammar names `string.quoted`, `constant.numeric`, `constant.language` and
`constant.character`, and a theme that does not name a fine scope falls back to
the coarse scope.

## 4. The roles

### 4.1 A fine role can fall back to a coarse role

A role of `ColorTheme` can hold a `ColorRole`, not only a `PaletteColor`.
`resolve_theme_color` follows a chain of roles up to 8 steps, and it stops a
cycle with an error. The appearance tab shows such a role with `‹ role ›`
buttons, and its "Step" button copies the step of the role that it names
([AppearanceToWidget.jl:485](../../source/platform/appearance/AppearanceToWidget.jl#L485)).

So the theme can declare a role for each kind, but give its own hue only to the
kinds that must differ by default. A kind that can share a color falls back to
a role. A person can split it with "Step" and then change the hue. This is the
TextMate fallback, and it needs no new mechanism.

### 4.2 The vocabulary

The group "Tokens" of `ColorTheme` gets a subgroup "Values":

| Role | Default | What it colors |
| --- | --- | --- |
| `string_literal` | green 11 (as now) | A string. |
| `character_literal` | new, falls back to `string_literal` | A character. |
| `number_literal` | new, orange 11 | A number: an integer, a float, an index. |
| `boolean_literal` | new, pink 11 | `true` and `false`. |
| `null_literal` | new, falls back to `boolean_literal` | `null`, `nothing`, `missing`. |
| `symbol_literal` | new, teal 11 | A symbol, such as `:name`. |
| `constant` | orange 11 (as now) | A named constant that is no literal: a constant of mathematics, a substitution, a member of an enumeration. |

The high contrast variants get each new role with `minimum_contrast = 7.0`, as
the other token roles.

`constant` stays, because it still colors the named constants of section 6.4.

### 4.3 Why these hues

The token roles use violet (keyword), blue (definition, function, field), green
(string), orange (constant) and amber (type). The free hues are teal, pink and
red. Red is the color of an error, so a value must not take it.

I measured the OKLab distance between the step 11 colors of the hues, in each
of the four palettes and both modes, on 2026-10-08. The pairs that are nearer
than 0.06:

| Pair | radix light | radix dark | tailwind light | tailwind dark | oklch light | oklch dark | solarized |
| --- | --- | --- | --- | --- | --- | --- | --- |
| green – teal | 0.038 | 0.054 | 0.043 | 0.050 | 0.081 | 0.051 | > 0.12 |
| orange – amber | 0.073 | 0.119 | 0.048 | 0.106 | 0.067 | 0.051 | 0.115 / > 0.12 |

Pink is far from green and from orange in every palette. Teal is near green in
three palettes. A JSON or a YAML view shows strings and booleans side by side,
but it never shows a symbol. So the boolean takes pink, and the symbol takes
teal. In Julia, the colon in front of a symbol marks it too.

This is my recommendation, not a decision (question Q2).

## 5. Each view names the role of the kind

A view that prints a value names the role of its kind:

- **A domain with a grammar of values** (JSON, YAML, the Julia document, a SQL
  literal): its reader knows the kind of each value. Its theme has one field
  for each kind, and each field names the role of the kind.
- **A view that prints a Julia value** (the primitive projection, the
  reflection of an object, the syntax view, a cell of a table): the type of the
  value gives the kind. These views already pick a leaf by the type of the
  value, with a `TypeDispatchingProjection`
  ([ObjectToSyntax.jl:320](../../source/platform/syntax/ObjectToSyntax.jl#L320),
  [PrimitiveToText.jl:365](../../source/platform/text/PrimitiveToText.jl#L365)),
  so they need no new function. The roles follow this table:

  | Julia type | Role |
  | --- | --- |
  | `Bool` | `boolean_literal` |
  | `Number` other than `Bool` | `number_literal` |
  | `AbstractString` | `string_literal` |
  | `AbstractChar` | `character_literal` |
  | `Symbol` | `symbol_literal` |
  | `Nothing`, `Missing` | `null_literal` |
  | any other | the plain text of the view |

  `Bool` comes before `Number`, because `Bool <: Number`.

A text that is not a value does not take a value role. For example, the Julia
theme now colors `<:`, `->` and the `$` of an interpolation with `symbol_text`.
After the change they take the operator role, so that they do not turn teal.

The rule covers a value that a view prints as a token of a text. It does not
cover a control of a widget that edits a value (a switch, a spin box, a text
field of the settings or of the appearance tab), a tick label of a chart, or a
count in a log. Those keep the colors of the widget or of their column.

## 6. The fields that change

A search on 2026-10-08 found these places. The paths are under `source/`
unless they name another repository.

### 6.1 A field for each kind exists: change the role only

| Theme | Fields | Role now | Role after |
| --- | --- | --- | --- |
| `JsonTheme` | `null_text`, `bool_text`, `number_text` | `constant` | `null_literal`, `boolean_literal`, `number_literal` |
| `YamlTheme` | `null_text`, `bool_text`, `number_text` | `constant` | the same three |
| `TextTheme` (the primitive projection) | `bool_text`, `number_text` | `constant` | `boolean_literal`, `number_literal` |
| `SyntaxTheme` | `bool_text`, `reflected_bool_text`, `number_text`, `symbol_text`, `nothing_text` | `constant` | `boolean_literal` (two fields), `number_literal`, `symbol_literal`, `null_literal` |
| `ReferenceTheme` | `index_color` | `constant` | `number_literal` |

The string fields keep `string_literal`. A data frame cell and a cell of an
ODBC result go through the primitive projection
([DataFrameView.jl:291](../../source/adapter/dataframes/DataFrameView.jl#L291),
[CellTableToWidgetTable.jl:20](../../source/platform/widget/CellTableToWidgetTable.jl#L20)),
so they follow `TextTheme` with no change of their own.

### 6.2 One field holds two kinds: split it

- **`JuliaTheme`.** `constant_text` colors an integer, a float, a boolean and
  `nothing`. `literal_text` colors a string and a character. `symbol_text`
  colors a symbol, `<:`, `->` and the `$` of an interpolation. The printer has
  one leaf for each kind
  ([JuliaToSyntax.jl:943](../../source/domain/julia/JuliaToSyntax.jl#L943)).
  The new fields are `number_text`, `bool_text`, `nothing_text`, `string_text`,
  `char_text` and `symbol_text`, with the names that `JsonTheme` and
  `SyntaxTheme` use. `<:`, `->` and `$` take `operator_text`. The docstring and
  the quotes of an interpolated string keep the string role.
- **`JuliaCodePieces`**, the tokenizer of Julia code in a form, follows the same
  fields: a number token, the words `true`, `false` and `nothing`, a symbol
  token and a character token
  ([JuliaCodePieces.jl:23](../../source/domain/julia/JuliaCodePieces.jl#L23)).
- **`SyntaxTheme`.** A `Char` in the reflection of an object takes
  `string_text` ([ObjectToSyntax.jl:327](../../source/platform/syntax/ObjectToSyntax.jl#L327)).
  It gets a field `char_text` that names `character_literal`.

Only the Julia printer and `JuliaThemeTest` name the Julia fields, so the
rename stays in `projectured-julia`.

### 6.3 The kind is known, but one style colors every value: add fields

- **SQL.** `SqlScalarValueToSyntaxLeaf` styles a value with `plain_text`. It
  already branches on `Bool` and `AbstractString`
  ([SqlToSyntax.jl:828](../../source/domain/sql/SqlToSyntax.jl#L828)), and the
  tokenizer knows a string token from a number token. `SqlTheme` gets
  `bool_text`, `number_text` and `string_text`. `NULL` is a keyword of the
  parser, with no document of its own, so it stays a keyword.

### 6.4 No change

- `MathTheme.symbol_text`: the name of a glyph, such as a Greek letter, not a
  Julia symbol. It keeps `constant`.
- `RstTheme.substitution_text`: a name. It keeps `constant`.
- `RstTheme` and `MarkdownTheme` code spans, literal blocks and alt texts: they
  are markup, not values. They keep `string_literal`.
- `XmlTheme.attribute_value_text`: every value of an attribute is a string. It
  keeps `string_literal`.
- inet-julia `PacketDiagramTheme.value_color`: the text of a field of a packet,
  with its hex and decimal forms. It keeps `constant`.

### 6.5 Later, in a plan of its own

- **The value of a formula.** `FormulaTheme.result_text` names `constant`, but
  the document keeps only `string(value)`
  ([FormulaDocument.jl:40](../../source/domain/formula/FormulaDocument.jl#L40)),
  so the kind is lost before the print. The document must keep the value first.
- **A data frame cell of another type**, such as a `Date` or a `Symbol`, prints
  as a plain `WidgetLabel`
  ([DataFrameView.jl:299](../../source/adapter/dataframes/DataFrameView.jl#L299)).
  The pivot labels and the row form of a data frame print every value as a
  plain label too.
- **omnet-julia NED and INI.** Their themes hold fixed Solarized colors, not
  roles. The NED parser knows the type of a literal (`:string`, `:bool`,
  `:int`, `:double`), but the printer tests only for a leading quote. A move of
  these views to roles is the larger work that the color set plan left open.

## 7. A saved appearance

`save_appearance!` writes every field of every theme of a view, not only the
fields that a person changed
([Appearance.jl:256](../../source/platform/style/Appearance.jl#L256)). So a
file that the released 0.2.0 wrote holds `number_text = constant` for
`JsonTheme`, and a person with that file keeps the old roles.

**Decision (the owner, 2026-10-08): ignore the backward compatibility.** The
change does not touch `save_appearance!` and does not move an old file to the
new roles.

## 8. Steps

1. ⬜ `ColorTheme`: add the five roles of section 4.2 with their high contrast
   values, and narrow the docstrings of `string_literal` and `constant`.
2. ⬜ Section 6.1: each field names the role of its kind.
3. ⬜ Section 6.2: split the fields of `JuliaTheme`, `JuliaCodePieces` and the
   `Char` of `SyntaxTheme`.
4. ⬜ Section 6.3: give `SqlTheme` a field for each kind.
5. ⬜ Tests:
   - `ColorThemeTest`: the new roles join `_CONTRAST_RULES`.
   - `ColorThemeTest`: the string, number, boolean and symbol roles resolve to
     four different colors in each palette and each variant, with an OKLab
     distance of at least 0.03 between each pair.
   - A test in each view asserts the role of each kind, as
     `PrimitiveToTextTest` and `JuliaCodePiecesTest` do now. These two tests
     and `JuliaThemeTest` assert `constant` for a number or a boolean now, so
     they change.
   - inet-julia `packetdiagram.jl:367` asserts `constant`, which stays.
6. ⬜ Screenshots of a JSON, a YAML and a Julia document in each palette and
   mode, for the owner to check the hues.

## 9. Decisions

The owner answered the four questions on 2026-10-08:

- **Q1. The scope.** "extend to those things too": the rule covers the names
  as well as the values. That is Part B, section 10.
- **Q2. The hues.** "yes": boolean pink, symbol teal, null falls back to
  boolean, character falls back to string.
- **Q3. The names of the roles.** "agreed": `number_literal`,
  `boolean_literal`, `null_literal`, `symbol_literal` and `character_literal`,
  beside `string_literal`.
- **Q4. A saved appearance.** "ignore backward compatiblitiy": no change of the
  save and no move of an old file (section 7).

## 10. Part B: the names

In design. A search of the names that each view prints, and of what each
printer knows about the kind of a name, runs now.
