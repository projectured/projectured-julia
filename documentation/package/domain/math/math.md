# Math domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [natural.md](../../platform/natural/natural.md)

The math domain, `ProjecturedMath`, holds a formula as a tree of documents: its structure, not its picture and not its value. Two projections read the tree: `MathToSyntax` prints one line of text, and `MathToGraphics` sets real two-dimensional boxes. This document says where the domain differs from the [shape of every domain](../../../design/domain-anatomy.md): the vocabulary, the reader of the linear form, the box protocol of the two-dimensional form, and the keys that edit it.

<img width="396" alt="Math example" src="../../../asset/image/example/math.png">

## How it works

### The vocabulary

The types are not a complete mathematical notation. They are what the formulas of communication network simulation need: Shannon capacity, Friis transmission, M/M/1 delay, Erlang B, a bit error rate and a reliability product.

| Type | What it holds |
| --- | --- |
| `MathVariable` | a name, set slanted |
| `MathSymbol` | a named glyph: `:lambda`, `:infty`, `:Delta` |
| `MathText` | upright words: a unit, a name of more than one letter |
| `MathSpace` | an explicit space |
| `MathRow` | juxtaposition: `k T B` |
| `MathBinaryOperation` | an infix operator and two operands |
| `MathUnaryOperation` | a prefix operator such as `−x`, or a postfix operator such as `n!` |
| `MathAssignment` | the root of an equation |
| `MathParenthesized` | a delimiter pair around one child |
| `MathFraction` | a numerator over a denominator; `inline` for the slash form |
| `MathScript` | a base with a subscript, a superscript or both |
| `MathRadical` | a root, with an optional index |
| `MathBigOperator` | `∑ ∏ ∫ ∮ ⋃ lim` with optional limits |
| `MathDifferential`, `MathDerivative` | `dt`, `∂x`; `dQ/dt`, `∂P/∂t` |
| `MathFunction` | `sin x`, `log₂(n)`, `Q(x)` |
| `MathAccent` | `x̄`, `v⃗`, `p̂` |
| `MathMatrix`, `MathCase`, `MathCases` | a grid, and a piecewise definition |
| `MathInsertion` | an empty slot |

A number is a `PrimitiveNumber`, and the math rules set it upright. Three rules keep the vocabulary from saying the same thing twice:

1. An explicit operator is a `MathBinaryOperation`, and adjacency without one is a `MathRow`.
2. `MathAssignment` is the root of an equation. A relation inside an expression is a `MathBinaryOperation`.
3. A slot that can be absent holds `nothing` when it is absent and a `MathInsertion` when it is present and empty. `nothing` prints nothing, and an insertion prints a placeholder that a mouse can hit.

`MathSubscript(base, index)` and `MathSuperscript(base, exponent)` build a `MathScript` with one script. The table `_MATH_OPERATORS` in `source/domain/math/MathDocument.jl` has three columns for each operator: the text of the linear form, the glyph of the page, and the class, `:binary`, `:relation` or `:punctuation`, that sets the space around it.

### The linear form

`MathToSyntax` prints a formula as one line, in colours. It is the save path and the plain-text view. A construct with no plain-text form prints a LaTeX-like name, so the line stays unambiguous:

```
k T B        λ        1/(μ - λ)        P_{t}^{2}        \sqrt[n]{x}
\sum_{k = 0}^{n} (x/n)                 \int_{0}^{∞} (x dt)
\partial^2(P)/\partial(t)^2            log_{2}(1 + x)   \bar{L}
\matrix[2]{1, 2, 3, 4}                 \cases{1 if x < n; 0 otherwise}
```

Most rules are `@projection_template` builders, so the printer, the reference maps and the structural readers come from the template. A formula has much chrome that no field produces: braces, backslash names and parentheses. The template names a caret on it by the rule's own introduced step, which holds the path of the part in the rule's output, and the forward map gives that path back.

`parse_math(text)` reads the line back into a tree. The printer is the grammar: a line that the printer writes reads back to a tree that prints the same line. A read accepts more than a print writes: `ρ^n` reads as `ρ^{n}` does, and `\rho` as `ρ` does. An error names the position that the reader could not read, and the reader never evaluates. Where the line is ambiguous, the reader applies these rules:

- **`/` with no space around it is a fraction, and ` / ` with spaces is the binary division.** A fraction binds tighter than juxtaposition, so `1/n x` is a row of a fraction and a variable. A numerator that is a row is written in parentheses: `((1 - ρ) ρ^{n})/(1 - ρ^{n + 1})`.
- **A letter is a variable, a word is text, and a name directly before `(` is a function.** `f(x)` is a call, `f (x)` is juxtaposition, and `log_{2}(x)` is a call with a base. `d` followed by one lower-case letter is a differential, `dt`.
- **A space is juxtaposition.** An explicit `MathSpace` prints as `\,`, `\:`, `\;` or `\quad`, so the two never print the same.
- **Every `(…)` reads as a `MathParenthesized`**, the parentheses that the printer adds around a numerator, a base or a body too. The tree that comes back equals the tree that went in, except for those nodes, and the line is the same.
- **`-` directly before digits is a negative number.** Before anything else it is the prefix minus.

### The two-dimensional form

`MathToGraphics(; measure, font, slanted, style, ink, hint)` typesets its own boxes. The generic layouts align by top, centre or bottom, and none of them can put a fraction on the baseline of the row that holds it.

**The box protocol.** Every rule returns a `MathIoMap`, which publishes the box as three cells beside the usual fields: `width`, `ascent` from the top of the box down to the baseline, and `descent` from the baseline down. A parent reads the cells of its children to place them, and wraps the placed children in a `GraphicsCanvas`. A change in one leaf computes again only the boxes above it. `GridLayoutIoMap` is the precedent: an IO map can publish geometry so that a parent can place its child.

- A `MathChild` records the reference steps that reach a child, its IO map, and the `x` and `y` cells where the parent put it. A matrix cell is two canvases down, inside the grid and inside the delimiter row, so an element index can not name it.
- A `MathGlyphBox` is a box that the projection adds: an operator sign, a delimiter or a fraction rule. It has the same three metrics, so a row can hold both kinds of box, but it carries no reference, so a selection never lands on it.
- A box of another domain reports no baseline. If it draws text, the first text run gives the baseline one font ascent below its top, so a number from the natural renderer sits on the line of the formula. A box with no text centres on the axis.

**The numbers.** `MathMetrics` holds every number that the rules use, computed by `compute_math_metrics` from one font at one style level. You tune the layout there and nowhere else.

- `axis` is half the x height. A fraction rule, a large operator and a delimiter centre on it, so `a/b + c` reads as one line.
- `rule` is the thickness of a fraction rule, a radical bar and an accent bar.
- `thin`, `medium` and `thick` are the spaces of the three operator classes.
- A superscript baseline rises by 0.36 em and a subscript baseline falls by 0.2 em, and neither is less than the reach of the base.

The style level travels as the property `:math_style` of the printer context, so one rule instance serves every depth: `:display` and `:text` at full size, `:script` at 0.7 and `:scriptscript` at 0.5. The vertical metrics come from the tables of the font through `font_ascent`, `font_descent` and `font_x_height`, because a text measurer returns only a width and a height.

**The glyphs.** Math is set in DejaVu, the one vendored family that has the whole math set, the delimiter extension pieces and an oblique Greek face. A variable and a lower-case Greek letter are slanted. A number, an operator, a sign and a function name are upright, and all have one ink colour. A tall sign such as `∑`, `∫` or `√` is placed by its ink, which `font_glyph_bounds` returns, because the ink can be anywhere in the text box. A delimiter taller than 1.6 times the line height is built from the Unicode extension pieces, such as `⎛ ⎜ ⎝`, and not scaled, because a scaled parenthesis grows as wide as it is tall.

### Selecting and editing

A selection in the two-dimensional form names a whole sub-expression, an `EmptyReference` on the node, because there is no line of text to put a caret in. The first element of every box is a translucent wash that paints only when the box is selected, so a selection is a repaint and never a new layout. A press selects the smallest box under the pointer, with the same descent that the backward reference map uses, so a click and a selection always agree. A press on the rule of a fraction selects the fraction.

A key goes to the selected child first, and a node acts only when the child returns `nothing`:

| Key | What it does |
| --- | --- |
| Left, Right | select the previous or the next sibling |
| Down, Enter | select the first child |
| Up, Escape | select the parent |
| Ctrl+Home, Ctrl+End | select the first or the last part of the formula |
| `/` | wrap the selection in a fraction, and select the denominator |
| `^`, `_` | give the selection a superscript or a subscript, and select it |
| `(` | put the selection in parentheses |
| a letter, a digit | fill an empty slot with a variable or a number |
| Backspace | replace the selection with an empty slot |

### The file

`MathFile` is the file type for `.math`. It holds one formula in its linear form, and `emit_text` writes `print_natural_text` of the content. Neither the linear form nor the tree can hold a reference to another file, so a node of a `.math` file belongs to that file alone. A `MathFile` with no content holds a `MathInsertion`.

### The theme

`MathTheme` holds the look of the Math projections: the text of a variable, an operator, the chrome, a symbol, a name, a word and the equals sign of the linear form, and for the typeset form its font, its slanted font, its ink, its hint color and the wash of a selection. Each value has
the default that the domain draws with no appearance. A projection holds its
styles as fields, and no theme; nothing in it scales or asks whether a theme is
scaled. `MathToSyntax(; theme, syntax_theme)` gives each projection the style of
its role with `get_math_style`, from `theme`, a `MathTheme` scaled or not, or
the default styles for `nothing`. `MathToGraphics(; measure, theme, …)` builds
one `MathConfig` the same way, and a font or a color that a keyword of
`MathToGraphics` names stays fixed. The natural registration gives the scaled
theme of the `Appearance` of the editor, so the view follows its scales, and
the appearance tab shows a section for `MathTheme`.

## How it fits

`ProjecturedMath` depends on the kernel and the platform. It depends on no other domain. `ProjecturedFormula` depends on it: a formula can have math code, which it converts to Julia to compute, and it draws that code with the boxes of this domain; see [formula.md](../formula/formula.md).

Its `__init__` makes four calls:

- `register_natural_domain!(MathDocument; rung = :syntax, …, format = :math, extension = ".math", parse = parse_math)`, so a file and the tools use the linear form;
- `register_natural_syntax!(:math, …)` with `MathToSyntax`;
- `register_natural_graphics!(:math, …)` with `make_math_to_graphics_dispatch`, so a tab draws a formula in two dimensions;
- `register_file_document_type!(".math", MathFile)`.

`make_math_to_graphics_dispatch` drops the `PrimitiveNumber` and `PrimitiveString` rows of `MathToGraphics`. A number in a formula then draws through the general renderer, and its text baseline puts it on the line of the formula.

## Design decisions

- **The tree is the structure only.** One tree serves a text line to save and a typeset picture, and neither projection owns the model.
- **The printer is the grammar of the reader.** `test_math_parser()` checks that every formula of the corpus prints, reads and prints the same line. See [plan/pending/math-linear-form-reader.md](../../../../plan/pending/math-linear-form-reader.md).
- **The domain sets its own boxes.** An IO map that publishes a baseline is the one thing a formula needs that the generic layouts do not have. See [plan/done/math-formula-layout.md](../../../../plan/done/math-formula-layout.md).
- **A selection in two dimensions is a whole node.** A caret has no position in a fraction, so the keys move between nodes and build around the selected node.
- **A delimiter is tiled, not scaled.** The radical has no extension pieces in DejaVu, so its sign stops at 2.2 times the base size. A real math font is the fix, not a wider glyph.

## Usage

```julia
tree = MathAssignment(MathVariable("W"),
                      MathFraction(MathSymbol(:lambda), MathVariable("mu")))
line = print_natural_text(tree)        # the linear form
back = parse_math(line)                # a tree that prints the same line
flat = MathToSyntax()
boxes = MathToGraphics(measure = FontFileMeasure())
```

- Examples: `math_example` shows the linear form. `math_table_example` puts numbers and formulas in the cells of a `WidgetTable`. `math_display_example` stacks every formula of `example/domain/math/MathDocumentExample.jl` in two dimensions. The atomic catalog has one document for each type.
- Test: `test_math()` runs the layering guard, `test_math_to_graphics()` and `test_math_parser()`. `test_math_to_graphics()` asserts coordinates: where a fraction rule lands, how far a script baseline moves, and which size a nested script has. It also walks `math_display_example` through the printer, the REPL loop and the arrow keys.

## Limits

- **`math_display_example` is not in the `examples` registry.** `test_typein` types a character at every rendered caret, and a two-dimensional formula has none, so every position would report a failure. Run it with `run_example(math_display_example)`.
- **No key types a symbol.** `\lambda` needs a text buffer that lives across keystrokes, which is an insertion type of its own. Step 5 of [plan/pending/math-linear-form-reader.md](../../../../plan/pending/math-linear-form-reader.md), type-in of the linear form, is open.
- **The radical sign stops growing at 2.2 times the base size.** Past that, the bar continues above a sign that does not follow it.
