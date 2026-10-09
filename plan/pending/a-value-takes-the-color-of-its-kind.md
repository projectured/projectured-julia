# A value takes the color of its kind

> **Status:** Part A, the values (sections 4 to 8), and Part B1, the names
> that the place gives (sections 10.6 to 10.10), landed on `main` by a
> fast-forward of the branch `value-colors` on 2026-10-09, on the owner's
> "land it". Nothing is pushed. Open: QB4, an `as` on `collection` (section
> 10.5), and B2, the scope analysis of Julia and more hues, which the owner
> deferred (section 10.6). B2 has a plan of its own since 2026-10-09:
> [a-julia-name-takes-the-color-of-its-binding.md](a-julia-name-takes-the-color-of-its-binding.md),
> whose analysis also covers the names of QB4. This plan stays in
> `plan/pending/` until QB4 is decided.

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

Part A is done on the branch `value-colors`. Nothing is on `main`.

1. ✅ `ColorTheme`: the five roles of section 4.2, with their high contrast
   values (`50f5674a5`).
2. ✅ Section 6.1: each field names the role of its kind (`89a2694dd`). The
   field `char_text` of `SyntaxTheme` (section 6.2) went into this commit,
   because it is in the same file as the fields of section 6.1.
3. ✅ Section 6.2: the fields of `JuliaTheme` and `JuliaCodePieces`
   (`289e6dfdd`). `<:`, `->` and the `$` of an interpolation take
   `operator_text`.
4. ✅ Section 6.3: `SqlTheme` has `bool_text`, `number_text` and `string_text`
   (`8a3f14465`). A `SqlScalarValue` can hold any kind, so the leaf computes
   its style from the present value, as `RstRoleToStyledLeaf` computes its
   color, and the style follows an edit that changes the kind.
5. ✅ Tests, in the commits above:
   - `ColorThemeTest`: the new roles join `_CONTRAST_RULES`, and a new test
     asserts an OKLab distance of at least 0.025 between the string, number,
     boolean and symbol roles in each palette and variant. The bound is 0.025,
     not the 0.03 of the first draft: a string and a symbol are 0.028 apart in
     the high contrast light variant of Radix, where a contrast of 7 takes
     green and teal to dark steps. They are 0.037 apart in the normal variant.
   - A test of each view asserts the role of each kind: `PrimitiveToTextTest`,
     `JsonThemeTest`, `YamlThemeTest`, `JuliaThemeTest`,
     `JuliaCodePiecesTest`, `SqlThemeTest` (with a change of the kind) and
     `ObjectFieldToSyntaxTest` (the rules of `ObjectToSyntax`).
   - Results on 2026-10-08: `test_color_theme` 1266 pass;
     `test_object_field_to_syntax` 19 pass; `test_json` 231 pass;
     `test_yaml` 58 pass and 2 broken, the two markers of `YamlParserTest`
     that `main` has too; `test_sql` 665 pass; `test_julia` 540 pass. No
     failure and no error. `test_syntax` holds only the 10 tests of the
     reactive syntax, so it does not cover the reflection of an object.
6. ✅ Screenshots, in `/var/tmp/value-colors/shots` (the JSON, YAML, Julia and
   SQL examples in each palette in light and dark, and in the high contrast
   variants of Radix) and `/var/tmp/value-colors/sample` (one line of Julia,
   SQL and JSON with each kind). Strings are green, numbers orange, booleans
   and nulls pink, and symbols teal. The weak pair is visible: in the high
   contrast light variant of Radix, `:name` and `"name"` are near.

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

In design. The search of 2026-10-08 found the facts below. The decisions that
Part B needs are in section 10.5.

### 10.1 What is there now

The name roles of `ColorTheme` are `definition`, `function_name`, `field`,
`type_name`, `reference`, `link`, `keyword`, `heading` and `markup`. Two of
them hold many kinds:

- `definition` colors a module, a SQL table, a schema, a database, a state of a
  machine, an event, a timer, the name of a process, the name of a formula and
  a directory.
- `field` colors the field of a struct, a JSON key, a YAML key, an XML
  attribute, a column of a database, the name of a field of a packet and the
  name of a step of a reference.

In Julia, every name is a `JuliaIdentifier` with `identifier_text`, the role
`reference`. Only the module name (`name_text`), the callee of a call and the
name of a macro (both `callee_text`) differ.

### 10.2 Two ways that a printer knows the kind of a name

1. **By its place in the document.** The printer of a parent knows the slot of
   a child: the name of a function definition, a parameter of a signature, a
   type parameter in `where`, the name of a keyword argument, a module name, a
   field after a dot, a SQL table, a SQL column, an XML tag, an XML attribute,
   a JSON key, an FSM state, an event and a timer. The Julia call printer
   already gives its callee a leaf of its own with
   `project(:callee; as = v -> v isa JuliaIdentifier ? JuliaIdentifierToSyntaxLeaf(style = p.callee) : nothing)`
   ([JuliaToSyntax.jl:200](../../source/domain/julia/JuliaToSyntax.jl#L200)).
   The same feature can style each slot, so this way needs no new mechanism.
2. **By a scope analysis.** A use of a name in a body, such as `x` in
   `function f(x) x + 1 end`, is a plain `JuliaIdentifier`. Only an analysis
   that finds the binding of the name can say if it is a parameter, a local
   variable, a global, a function or a type. No such analysis exists. The only
   near code is `find_julia_definition`, which finds a top-level definition by
   its name ([JuliaFile.jl:57](../../source/domain/julia/JuliaFile.jl#L57)).
   This is a new mechanism.

Some kinds have no document type yet: the names inside a `using` path (one
string), a SQL function name (raw text), an XML namespace prefix, a YAML
anchor, alias or tag, and a reference-style Markdown link.

### 10.3 The hues

The value roles of Part A take all the hues that are free: the token roles now
use violet, blue, green, orange, amber, pink and teal, red is the color of an
error, and neutral is the text. The Solarized palette has exactly eight
accents, and each one is a hue of the palette now
([SolarizedPalette.jl](../../source/platform/style/SolarizedPalette.jl)).

So a new kind of name can have a color of its own only in one of three ways:

- **(a) More hues.** Add hues to `PALETTE_HUES`, for example indigo, cyan,
  lime, brown and plum. Radix and Tailwind have such scales, and the OKLCH
  palette can compute any hue. Solarized must give a new hue the ramp of an
  accent that it has, so two kinds share a color in Solarized.
- **(b) Another step of a hue.** For example a parameter at blue 12 beside a
  field at blue 11.
- **(c) A font, not a color.** A definition is bold, and a parameter is italic.
  The kinds that share a color fall back to a role.

I measured option (b) on 2026-10-08, as the OKLab distance of the raw steps of
the ramps. Step 12 of a hue is far from step 11 of the same hue (0.095 to
0.275), but it is near the plain text, which is neutral 12:

| Palette, mode | blue 12 – text | violet 12 – text | amber 12 – text |
| --- | --- | --- | --- |
| oklch light | 0.076 | 0.069 | 0.059 |
| oklch dark | 0.020 | 0.024 | 0.040 |
| radix light | 0.105 | 0.115 | 0.125 |
| radix dark | 0.055 | 0.056 | 0.076 |
| solarized light | 0.053 | 0.076 | 0.119 |
| solarized dark | 0.068 | 0.069 | 0.038 |
| tailwind light | 0.097 | 0.137 | 0.166 |
| tailwind dark | 0.050 | 0.054 | 0.109 |

So a name at step 12 looks almost like the plain text in a dark theme. Option
(b) does not give a color that a reader can trust.

### 10.4 The vocabulary

My recommendation, not a decision. It follows the semantic tokens of the
Language Server Protocol: a token has a **type**, which gives its color, and
**modifiers**, which give its font. A definition is a modifier, not a kind:
the name of a function at its definition is a function name in bold.

| Role | Default | Kinds |
| --- | --- | --- |
| `module_name` | new, falls back to `type_name` | A Julia module, a SQL schema and database, a directory. |
| `type_name` | amber 11 (as now) | A type, a struct, an abstract type, a type in an annotation, a SQL table, a data type, a machine and a component of an FSM, the name of a projection in a reference. |
| `type_parameter` | new, falls back to `type_name` | A variable of `where`, a parameter in braces. |
| `function_name` | blue 11 (as now) | A function at its definition and at a call, a function of mathematics, a process. |
| `macro_name` | new, falls back to `function_name` | A Julia macro. |
| `event` | new, falls back to `function_name` | An event and a timer of an FSM. |
| `parameter` | new, falls back to `variable` | A parameter of a signature and of a lambda, the name of a keyword argument, the name of an option of an RST directive. |
| `variable` | the role `reference` with a new name, neutral 12 | A variable, a `for` variable, a variable of mathematics, of an FSM and of a formula, a SQL alias, and a name of a kind that the printer does not know. |
| `field` | blue 11 (as now) | A field, a field after a dot, a key, an attribute, a column. |
| `tag` | new, falls back to `keyword` | An XML tag. |
| `constant` | orange 11 (as now) | A state of an FSM, a member of an enumeration, an RST substitution, a constant of mathematics. |

The modifiers are fonts in the field of the view theme, as `TextRole` already
allows: a definition has `weight = 700`, and a parameter has `italic = true`.

The role `definition` goes away: each field that names it takes the role of
its kind, in bold. The role `reference` takes the name `variable`, because
"reference" is also the name of a kernel concept, `Reference`.

With these defaults, these names change their color on the screen:

- Julia: a type (amber, now neutral), the name of a function at its definition
  (blue and bold, now neutral), a field after a dot (blue, now neutral), a type
  parameter (amber, now neutral), a parameter (italic).
- SQL: a column (blue, now the plain text), a table and a data type (amber,
  now blue and the plain text), a schema (amber and bold).
- FSM: a state (orange), an event and a timer (blue).

### 10.5 Questions

- **QB1. The hues.** (c), a font for the modifiers and a fallback for the kinds
  that share a hue (my recommendation)? Or (a), more hues in the palettes, so
  that more kinds have a color of their own by default, with the shared colors
  in Solarized?
- **QB2. A scope analysis for Julia.** It is a new mechanism: it finds the
  binding of each use of a name, so a use of a parameter, a local, a global, a
  function and a type each gets its role. Do it in a plan of its own, after
  the names that the place gives (my recommendation)? Or in this plan?
- **QB3. The vocabulary** of section 10.4, with the role `definition` removed
  and `reference` named `variable`?
The answers so far: QB1 and QB2 go with the split of section 10.6. B1 takes
option (c) and the hues that exist; more hues and the scope analysis wait with
B2. QB3 has no answer of its own; B1 follows the vocabulary of section 10.7,
which the message of the split named.

- **QB4. An `as` on `collection`.** The parameters of a signature, of a
  lambda and of `where`, and the names of keyword arguments, are elements of
  a collection (section 10.10). An `as` on `collection(:f)` in the kernel
  template engine, the same as on `project(:f)`, lets each take its role. Add
  it?

### 10.6 Decision: B1 now, B2 later

The owner asked on 2026-10-08 whether the conflict was only a Julia one. It is,
in practice: only Julia shows more kinds of name side by side than the hues
that are free, and only Julia needs a scope analysis. FSM guards and actions,
process steps and fields of code hold Julia code too. The owner answered "yes,
sounds good" to this split, and "for the Julia analysis I would defer that for
now":

- **B1, now.** The kinds of name that a printer knows from their place, in
  every view, with the hues that exist (option (c) of section 10.3). It
  includes the Julia names in a known slot.
- **B2, deferred.** The scope analysis of Julia, and more hues for the kinds of
  Julia that share a color.

### 10.7 The roles of B1

The vocabulary of section 10.4, with one change: a state of an FSM takes a new
role `enum_member`, not `constant`, because a guard holds Julia numbers in
orange beside the states.

| Role | Default |
| --- | --- |
| `module_name` | falls back to `type_name` |
| `type_name` | amber 11 (as now) |
| `type_parameter` | falls back to `type_name` |
| `function_name` | blue 11 (as now) |
| `macro_name` | falls back to `function_name` |
| `event` | falls back to `function_name` |
| `parameter` | falls back to `variable` |
| `variable` | neutral 12, the role `reference` with a new name |
| `field` | blue 11 (as now) |
| `tag` | falls back to `keyword` |
| `enum_member` | falls back to `symbol_literal` |
| `constant` | orange 11 (as now) |

The role `definition` goes away. A name at its definition takes the role of
its kind with `weight = 700`, and a parameter has `italic = true`.

### 10.8 The fields of B1

| Theme | Field now | After |
| --- | --- | --- |
| `JuliaTheme` | `identifier_text` (`reference`) | `variable` |
| `JuliaTheme` | `name_text` (`definition`, bold), a module | renamed `module_text`: `module_name`, bold |
| `JuliaTheme` | `callee_text` (`function_name`), also a macro | a call only; a new `macro_text`: `macro_name` |
| `JuliaTheme` | new | `function_definition_text` (`function_name`, bold), `type_text` (`type_name`), `type_definition_text` (`type_name`, bold), `type_parameter_text`, `parameter_text` (italic), `field_text` |
| `SqlTheme` | `name_text` (`definition`), a table and a schema | a table: `type_name`; a new `schema_text`: `module_name` |
| `SqlTheme` | `plain_text`, also a column, an alias and a data type | new `column_text` (`field`), `alias_text` (`variable`), `type_text` (`type_name`) |
| `DbCatalogTheme` | `table_text`, `schema_text`, `database_text` (`definition`, bold) | `type_name`, `module_name`, `module_name`, bold |
| `FsmTheme` | `name_text` (`definition`) | `variable_name_text` (`variable`), `event_name_text` (`event`, an event and a timer), `state_name_text` (`enum_member`), `machine_name_text` (`type_name`, a machine and a component), all bold |
| `FsmTheme` | `reference_text` (`reference`) | `event_reference_text` (`event`, a trigger, also in a diagram) and `state_reference_text` (`enum_member`, a target and `initial`) |
| `FsmTheme` | `state_label_text` (`definition`, bold) | `enum_member`, bold |
| `ProcessTheme` | `name_text` (`definition`) | `function_name`, bold |
| `ProcessTheme` | `terminal_text` (`definition`, bold), the word `start` or `stop` | `keyword`, bold |
| `FormulaTheme` | `name_text` (`definition`, bold) | `variable`, bold |
| `FileSystemTheme` | `directory_text` (`definition`, bold) | `module_name`, bold |
| `ReferenceTheme` | `projection_color` (`definition`) | `type_name` |
| `XmlTheme` | `tag_text` (`keyword`, bold) | `tag`, bold |
| `MathTheme` | `variable_text` (`reference`) | `variable` |
| `RstTheme` | `reference_text` (`link`), also a field name and an option name | new `field_text` (`field`) and `option_text` (`parameter`) |

The FSM transition prints `on EVENT` and `-> STATE` as one leaf each. Each
leaf takes the style of what it names, so the leaves and the places of the
caret stay as they are.

### 10.9 The steps of B1

1. ✅ `ColorTheme`: the roles of section 10.7; the themes that change only a
   role (`DbCatalogTheme`, `ProcessTheme`, `FormulaTheme`, `FileSystemTheme`,
   `ReferenceTheme`, `XmlTheme`, `MathTheme`) (`fa2eeb022`). The old roles
   `definition` and `reference` stayed until step 6, so that each commit
   builds with no view that names a role the theme does not have.
2. ✅ SQL (`25e077b8b`). Each name stays one leaf: `q.col` takes the style of
   a column, and `table AS alias` the style of a table, so the leaves and the
   places of the caret stay as they are. The alias of a select item and of a
   subquery is a leaf of its own and takes `alias_text`.
3. ✅ FSM (`7501ec702`). `stay` and `ignore` take the keyword style, because
   the ending leaf is a target only when the transition has one.
4. ✅ RST (`a1c0f31a4`).
5. ✅ Julia: the names in a single slot (`758c9f10c`). A slot whose place gives the kind
   prints a bare identifier with
   `project(:slot; as = _style_identifier(style))`, the feature that the callee
   of a call uses: the name of a function at its definition (bold), the result
   type, a type after `::`, the right side of `<:`, the head of `T{…}`, a
   field after a dot, the name of a struct and of an abstract type (bold, also
   on the left of `<:` through the new `lhs_style` of
   `JuliaSubtypeToSyntaxNode`), a module (bold) and a macro. A new test helper,
   `draw_texts`, gives the text, the color and the weight of each drawn piece,
   so the test asserts what the screen shows.
6. ✅ The roles `definition` and `reference` go away; the style guide names the
   roles of the names (`f3619da2d`).
7. ✅ Tests of each step, and screenshots in `/var/tmp/value-colors/sample2`
   (a Julia module, a SQL query, an XML element and the reflection of an FSM,
   in light and dark). The tests of each step ran before its
   commit:
   - B1.1: `test_color_theme` 1463, `test_help_themes` 107, `test_filesystem`
     84, `test_xml` 80, `test_dbcatalog` 74, `test_math` 182, `test_formula`
     123, `test_process` 312.
   - B1.2 to B1.4: `test_sql` 671, `test_fsm` 174, `test_rst` 111.
   - B1.5 and B1.6: `test_text_and_syntax_themes` 17, `test_appearance_tab`
     119, `test_julia` 538 and `test_julia_theme` 25, `test_fsm` 174,
     `test_process` 312, and the style guard.
   - All with no failure and no error, after one fix: `test_appearance_tab`
     asserted the old role of `SyntaxTheme.bool_text`. Part A changed that
     role in `89a2694dd`, and the test run of Part A did not include the
     appearance tab. `fa45c5d30` makes the test follow.
   - The sweep after B1, on 2026-10-09: `test_platform` 114502 pass, 41 fail,
     25 error, 8 broken; `test_json` 231; `test_yaml` 58 and 2 broken;
     `test_markdown` 262; `test_book` 33; `test_integration` 1382050 pass,
     4 fail, 0 error, 1578 broken. The failures are in
     `ExternalAgentTurnTest` (63), `InterfaceApiTest` (2, the docstring of
     `WidgetProgressRing`), `McpLogTest` (1, known when the umbrella is
     loaded), the navigation of the progress bar and the progress ring (2),
     the catalog coverage (1, seven new document types of other work) and
     `FirstWindowTest` (1, 7.3 s of compilation against a limit of 2.0). The
     branch changes none of these areas.
   - The check on `main` at `33710e99f`, with the same packages loaded: the
     interface API fails twice in the same way, the external agent turn has
     the same 38 failures and 25 errors, the navigation of the progress bar
     fails, and the first window takes 6.75 s of compilation (7.30 s on the
     branch). So every failure of the sweep is on `main` too.

### 10.10 What B1 does not cover in Julia

The template engine has an override for a single slot, `project(:f; as = …)`,
but none for a collection, `collection(:f)`. So these names keep the role
`variable`:

- a parameter of a signature and of a lambda;
- a parameter of `where` and the parameters in braces, such as `T` in `Q{T}`;
- the name of a keyword argument of a call;
- a field of a struct, which is a statement of the block of the struct;
- the defined name of a header with braces, such as `P` in `struct P{T}`.

The first three need an `as` on `collection(:f)` in
`source/kernel/projection/ProjectionTemplate.jl`, the same as on `project`.
This is a change of the kernel, so it waits for the owner (question QB4). The
last two need a place two levels down, such as a statement in the block of a
struct. The analysis of B2 can give them.
