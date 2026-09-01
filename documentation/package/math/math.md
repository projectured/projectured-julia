# The math domain

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [domain-inventory.md](../../design/domain-inventory.md)

A formula is a document. `MathAssignment(MathVariable("W"), MathFraction(…))` is
the structure; how it looks is the projection's business. Two projections read
it:

- **`MathToSyntax`** — one line of text, through the syntax and text layers. It
  is the save path (`document_to_text` runs it) and the plain-text view.
- **`MathToGraphics`** — real two-dimensional boxes: a fraction with a
  horizontal rule, a sum with its limits above and below the sign, an exponent
  off the baseline, a delimiter that grows with what it holds.

## The vocabulary

The type list is not a complete mathematical notation. It is what the formulas
of communication network simulation need — Shannon capacity, Friis
transmission, M/M/1 delay, Erlang B, a bit error rate, a reliability product.

| Type | What it holds |
| --- | --- |
| `MathVariable` | a name, set slanted |
| `MathSymbol` | a named glyph: `:lambda`, `:infty`, `:Delta` |
| `MathText` | upright words — a unit, a multi-letter name |
| `MathSpace` | an explicit space |
| `MathRow` | juxtaposition: `k T B` |
| `MathBinaryOperation` | an infix operator and two operands |
| `MathUnaryOperation` | a prefix (`−x`) or postfix (`n!`) operator |
| `MathAssignment` | the root of an equation |
| `MathParenthesized` | a delimiter pair around one child |
| `MathFraction` | a numerator over a denominator |
| `MathScript` | a base with a subscript, a superscript or both |
| `MathRadical` | a root, with an optional index |
| `MathBigOperator` | `∑ ∏ ∫ ∮ ⋃ lim` with optional limits |
| `MathDifferential` | `dt`, `∂x` |
| `MathDerivative` | `dQ/dt`, `∂P/∂t` |
| `MathFunction` | `sin x`, `log₂(n)`, `Q(x)` |
| `MathAccent` | `x̄`, `v⃗`, `p̂` |
| `MathMatrix`, `MathCase`, `MathCases` | a grid, and a piecewise definition |
| `MathInsertion` | an empty slot |

A number is a `PrimitiveNumber`; the math rules render it upright.

Three rules keep the vocabulary from saying the same thing twice:

1. An explicit operator is a `MathBinaryOperation`; adjacency without one is a
   `MathRow`.
2. `MathAssignment` is the root of an equation; a relation *inside* an
   expression is a `MathBinaryOperation`.
3. A slot that can be absent holds `nothing` when it is absent and a
   `MathInsertion` when it is present and empty. `nothing` prints nothing; an
   insertion prints a placeholder a mouse can hit.

`MathScript` covers `x²`, `P_t` and `A_i^n`; `MathSubscript(base, index)` and
`MathSuperscript(base, exponent)` build one with a single script.

One table in [Math.jl](../../../source/math/Math.jl) holds three columns per operator:
the text the linear form writes (ASCII where ASCII exists, a backslash name
where it does not), the glyph the page shows, and the class — `:binary`,
`:relation` or `:punctuation` — that decides the space around it.

## The linear form

A construct with no plain-text form writes its LaTeX-like name, so the saved
line stays unambiguous:

```
k T B        λ        1/(μ - λ)        P_{t}^{2}        \sqrt[n]{x}
\sum_{k = 0}^{n} (x/n)                 \int_{0}^{∞} (x dt)
\partial^2(P)/\partial(t)^2            log_{2}(1 + x)   \bar{L}
\matrix[2]{1, 2, 3, 4}                 \cases{1 if x < n; 0 otherwise}
```

The rules are `@projection_template` builders, so printing, reference mapping
and the structural readers are generic. Each compound rule collapses an unmapped
caret to a bounded flat offset — a formula is full of projection-introduced
chrome, and without the collapse the navigation walk grows its paths without
bound.

## The two-dimensional form

### The box protocol

Every rule answers a `MathIoMap`, which publishes the box beside the usual
projection/input/output: `width`, `ascent` (top of the box down to the baseline)
and `descent` (baseline down to the bottom). A parent reads its children's three
cells to place them, and wraps the placed children in a `GraphicsCanvas`.

The slice typesets its own boxes rather than reusing the generic layouts. Those
align by top, center or bottom, which cannot put a fraction on the baseline of
the row that holds it. `GridLayoutIoMap` is the precedent for the other half:
an IO map may publish geometry so a parent can place its child.

A `MathChild` records the reference steps that reach a child and where the
parent put it. A matrix cell sits two canvases down — inside the grid, inside
the delimiter row — so an element index cannot name it, but two offset cells
can.

### The numbers

`MathMetrics` holds every number the rules use, derived from one font at one
style level. Tune math there and nowhere else.

- `axis` — half the x height. A fraction rule, a large operator and a delimiter
  all center on it, which is what keeps `a/b + c` reading as one line.
- `rule` — the thickness of a fraction rule, a radical bar and an accent bar.
- `thin` / `medium` / `thick` — the space of the three operator classes.
- A superscript's baseline rises by 0.36 em, a subscript's falls by 0.2 em, and
  neither is ever less than the base's own reach.

The style level rides in `ctx.properties[:math_style]`, because the recursion is
one table and one rule instance serves every depth: `:display` and `:text` at
full size, `:script` at 0.7, `:scriptscript` at 0.5.

The vertical metrics come from the font's own tables through `font_ascent`,
`font_descent` and `font_x_height`. A measurer answers only a width and a
height, and the two measurers answer different heights, so neither can say where
a baseline sits.

### The glyphs

Math is set in **DejaVu** — the one vendored family that carries the whole math
set, including the delimiter extension pieces and the Greek letters in an
oblique face. A variable and a lowercase Greek letter are slanted; a number, an
operator, a sign and a function name are upright. Everything is one ink color,
the way a formula is printed.

A tall sign is placed by its *ink*, not by its text box: a `∑`, a `∫` and a `√`
sit anywhere inside their boxes, so centering the box leaves the sign visibly
high. `font_glyph_bounds` answers where the ink is.

A delimiter past 1.6 times the line height is tiled from the Unicode extension
pieces (`⎛ ⎜ ⎝` and their kin) rather than scaled, because a uniformly scaled
parenthesis grows as wide as it is tall. The radical has no such pieces in this
face, so its sign is capped at 2.2 times the base size; past that the bar runs
on above a sign that no longer follows it. A real math font is the fix, not a
wider glyph.

## Selecting and editing

A selection in a two-dimensional formula names a whole sub-expression — an
`EmptyReference` on the node — because there is no line of text to put a caret
in. A selected box paints a translucent wash over itself; the wash is element 1
of every box and paints nothing while nothing is selected, so selecting is a
repaint and never a re-layout.

A press finds the smallest box under it by the same descent the backward
reference map uses, so a click and a selection always agree. A press on a
fraction's rule — which belongs to no child — selects the fraction.

A key is offered to the selected child first, and a node acts only on what the
child declined:

| Key | What it does |
| --- | --- |
| `Left` / `Right` | move between siblings |
| `Down` / `Enter` | go into the first child |
| `Up` / `Escape` | come back out |
| `/` | wrap the selection in a fraction, caret in the denominator |
| `^` / `_` | give the selection a superscript / subscript |
| `(` | parenthesize the selection |
| a letter / a digit | fill an empty slot with a variable / a number |
| `Backspace` | clear the selection back to an empty slot |

A symbol (`λ`) has no keyboard gesture yet: `\lambda` needs a text buffer that
lives across keystrokes, which is an insertion type of its own rather than a
reader rule.

## Testing

`test_math_to_graphics()` in the domain suite asserts coordinates — where the
fraction rule landed, how far the script baseline moved, which face a nested
script uses — and walks `math_display_example` through the printer, the REPL
loop and the arrow keys.

`math_display_example` is deliberately **not** in the `examples` registry.
`test_typein` types a character at every rendered caret, and a two-dimensional
formula offers none; every position would be reported as a failure. Use
`run_example(math_display_example)` and the domain test for it.

The examples are in [example/document/Math.jl](../../../example/math/document/Math.jl):
one function per formula of the scope table, and
`make_math_display_document_example` stacks them all.
