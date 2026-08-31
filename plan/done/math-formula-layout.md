# Lay out and render math formulas in two dimensions

The math layer holds five document types and one projection to syntax. A formula
therefore renders as one line of text: `X = (3 * A + B) / 2`. A fraction has no
horizontal rule, a sum has no limits above and below the sign, and an exponent
sits on the baseline.

This plan grows the math domain to the vocabulary that the formulas of
communication network simulation need, and adds a second projection that places
the parts as real two-dimensional boxes.

## What exists now

**The domain.** [Math.jl](../../package/domain/main/math/Math.jl) defines
`MathInsertion`, `MathVariable`, `MathBinaryOperation` (`+ - * /`),
`MathParenthesized` and `MathAssignment`. A number is a `PrimitiveNumber`.

**The projection.**
[MathToSyntax.jl](../../package/domain/main/math/MathToSyntax.jl) maps each type
to a `SyntaxLeaf` or a `SyntaxNode` with colored tokens. The example chain is
`Math → Syntax → Text → Graphics`
([Math.jl](../../package/domain/example/projection/Math.jl)). The natural
renderer routes every `MathDocument` through the same projection
([NaturalProjection.jl:154](../../package/domain/main/insertion/NaturalProjection.jl#L154)).

**The visual parts a typesetter needs.** `GraphicsCanvas` nests canvases at an
`(x, y)` and carries reactive `w` / `h` cells. `GraphicsText` draws a string in a
`StyleFont`. `GraphicsRect` draws a crisp axis-aligned rule.
[TrueType.jl](../../package/visual/main/style/TrueType.jl) parses the `hhea`
ascender and descender, the `OS/2` cap height and the advance widths, and
`truetype_measure_text` measures a string without a backend.
`make_style_font(path, size)` mints a font at any size.

**The precedent.** The graph slice is a diagram, not a syntax tree. It computes
its own geometry in [GraphToGraphLayout.jl](../../package/domain/main/graph/GraphToGraphLayout.jl)
and paints it in
[GraphLayoutToGraphics.jl](../../package/domain/main/graph/GraphLayoutToGraphics.jl),
and the natural renderer gives it its own table entry
([NaturalProjection.jl:229-230](../../package/domain/main/insertion/NaturalProjection.jl#L229-L230)).
`GridLayoutIoMap` shows the second half of the pattern: an IO map may publish
geometry cells so that a parent can place and decorate its child
([LayoutToGraphics.jl:105-125](../../package/visual/main/layout/LayoutToGraphics.jl#L105-L125)).

## The formulas that decide the scope

The type list below is not a complete mathematical notation. It is the set that
covers these formulas, which the simulation domain uses every day.

| Formula | Parts that it needs |
| --- | --- |
| `C = B log₂(1 + S/N)` | function with a base, fraction, relation |
| `P_r = P_t G_t G_r (λ/(4πd))²` | subscript, juxtaposition, Greek symbol, superscript, stretchy parenthesis |
| `W = 1/(μ − λ)` | fraction, Greek symbol |
| `B = (Aⁿ/n!) / Σ_{k=0}^{n} Aᵏ/k!` | nested fraction, big operator with two limits, postfix factorial |
| `E[T] = ∫₀^∞ t f(t) dt` | integral with side limits, differential, bracket delimiter |
| `P_b = Q(√(2 E_b/N₀))` | radical, nested subscript, function |
| `R = ∏ᵢ₌₁ⁿ (1 − p_i)` | big product, subscript index |
| `∂P/∂t` and `dQ/dt` | partial and total derivative |
| `L̄ = λ W` | accent, juxtaposition |
| `SNR = P/(k T B)` | upright multi-letter name, juxtaposition |

## Decisions

**The math slice typesets its own boxes.** A formula is not a row of aligned
widgets. Every part needs a width, an ascent above the baseline and a descent
below it, and the parent decides the position from those three numbers. The
generic layouts (`HorizontalLayout`, `VerticalLayout`, `GridLayout`) align by
top, center or bottom, so they cannot put a fraction on the baseline of the row
that contains it. The new projection computes each box itself and wraps the
children in a `GraphicsCanvas`, exactly as `LayoutToGraphics` does internally.

**The IO map carries the metrics.** `MathIoMap` holds `projection`, `input`,
`output`, `child_iomaps` and three more cells: `width`, `ascent` and `descent`.
A parent rule reads the cells of its children to place them. This is the
`GridLayoutIoMap` pattern, and it keeps the metrics reactive: a change of a
variable name invalidates only the boxes above it.

**Do not add baseline alignment to the layout layer.** A `:baseline` alignment in
`HorizontalLayout` needs a baseline on every child canvas, so it needs a new
field on `GraphicsCanvas` and a new rule in every projection that produces one.
The math slice is the only client today. Keep the change local. If a second
client appears, promote `MathIoMap`'s three cells to a general protocol then.

**One font family: DejaVu.** I checked the glyph coverage of the vendored fonts
against 60 math code points. DejaVu Sans has all of them, including the
stretchy delimiter pieces (`U+239B` to `U+23AD`) and the combining accents.
Liberation Serif misses 31 of them (`∮ ∬ ∇ ⋅ ∈ ⟨ ⟩ ⊕ ⊗ ∼ ⋯ ⋮ ⋱` and more) and
Ubuntu Mono misses 34. SDL renders no font fallback, so a missing glyph is a
tofu box on screen. Math
therefore renders in DejaVu Sans: oblique for a variable, regular for a number,
an operator and a symbol, bold for a matrix name.

**A tall delimiter is assembled, not scaled.** A font renders at one size, so a
parenthesis that grows three times taller also grows three times wider. Up to
about 1.4 times the base height, a single glyph at a larger size is enough.
Above that, assemble the delimiter from the Unicode extension pieces that DejaVu
has: `⎛ ⎜ ⎝` for a parenthesis, `⎡ ⎢ ⎣` for a bracket, `⎧ ⎨ ⎩ ⎪` for a brace.
This is the purpose of those code points; it is not a fake built from segments.

**The script size comes from the printer context.** A superscript renders at 0.7
of the base size and a script inside a script at 0.5, as in TeX. The style rides
in `ctx.properties[:math_style]` with the values `:display`, `:text`, `:script`
and `:scriptscript`, and `with_property` isolates each branch.

**The linear projection stays.** `MathToSyntax` is the save path and the plain
text path: `document_to_text` runs it, and a formula in a code block must still
read as `(a + b)/2`. Every new document type gets a rule there too. Both
projections stay in the tree, and each new type has one rule in each.

**Two dimensions become the default last.** The natural renderer keeps
`MathDocument => MathToSyntax()` until the reader of the new projection handles
selection and navigation. Part H flips it. Until then the two-dimensional form
is reachable through its own example projection.

## Part A — extend the math domain — **done**

File: [Math.jl](../../package/domain/main/math/Math.jl)

Keep the five types that exist. `MathAssignment` stays the root of an equation;
a relation inside an expression is a `MathBinaryOperation`. Add the types below.
Follow the file's convention: bare field types, and `Any = nothing` for a slot
that can be absent.

| Type | Fields | Renders as |
| --- | --- | --- |
| `MathRow` | `elements::CellVector` | juxtaposition, `k T B` |
| `MathSymbol` | `name::Symbol` | a named glyph, `λ`, `∞`, `Δ` |
| `MathText` | `content::String` | upright words and units |
| `MathSpace` | `kind::Symbol = :thin` | an explicit space |
| `MathFraction` | `numerator`, `denominator`, `inline::Bool = false` | a horizontal rule between two boxes |
| `MathScript` | `base`, `subscript::Any = nothing`, `superscript::Any = nothing` | `P_t`, `x²`, `A_i^n` |
| `MathRadical` | `radicand`, `index::Any = nothing` | `√x`, `ⁿ√x` |
| `MathBigOperator` | `operator::Symbol`, `lower::Any`, `upper::Any`, `body`, `limits::Symbol = :auto` | `∑ ∏ ∫ ∮ ⋃ ⋂ ⨁ lim` |
| `MathDifferential` | `variable`, `kind::Symbol = :total` | `dt`, `∂x` |
| `MathDerivative` | `body`, `variable`, `order::Int = 1`, `kind::Symbol = :total` | `dQ/dt`, `∂P/∂t` |
| `MathFunction` | `name::String`, `argument`, `base::Any = nothing`, `parenthesized::Bool = true` | `sin x`, `log₂(n)`, `Q(x)` |
| `MathAccent` | `base`, `accent::Symbol` | `x̄`, `v⃗`, `p̂` |
| `MathUnaryOperation` | `operator::Symbol`, `operand`, `postfix::Bool = false` | `−x`, `n!` |
| `MathMatrix` | `elements::CellVector`, `columns::Int`, `delimiter::Symbol = :bracket` | a matrix or a column vector |
| `MathCase` | `value`, `condition::Any = nothing` | one branch of a piecewise definition |
| `MathCases` | `cases::CellVector` | a piecewise definition |

Two more changes to the types that exist:

1. Give `MathParenthesized` a `kind::Symbol = :parenthesis` field. The other
   values are `:bracket`, `:brace`, `:absolute`, `:norm`, `:angle`, `:floor`
   and `:ceiling`. One type then covers `|x|`, `‖v‖` and `⟨x⟩`.
2. Widen the operator set of `MathBinaryOperation` and give each operator a
   class in `_operator_string`'s neighbour, `math_operator_class(op)`. The
   classes are `:binary` (`+ − × ⋅ ÷ ± ∪ ∩ ⊕ ⊗`), `:relation`
   (`= ≠ ≤ ≥ ≈ ≡ ∼ ∈ ⊂ → ∝`) and `:punctuation` (`,` `;`). The class decides
   the space around the operator, so the table lives in the domain and both
   projections read it.

A slot that holds `nothing` is absent and prints nothing. A slot that holds a
`MathInsertion` is present and empty, and prints a placeholder box. Keep that
rule: an untyped empty slot breaks navigation.

Add a symbol table `math_symbol_glyph(name::Symbol) -> String` with the Greek
letters, the constants (`∞`, `ℓ`, `∅`) and the arrows. The name is what the user
types (`\lambda`); the glyph is what the printer draws.

**Commit A.** The new types, the symbol table and the operator classes.

**Found during the work.** One table holds three columns per operator — the
text the linear form writes, the glyph the page shows and the class. The text
column keeps `+ - * /` exactly as they were, so no existing output moved, and
the glyph column is free to use a real minus sign and a real multiplication dot.
`math_big_operator_name` does the same for a large operator (`\sum`, `\int`).
A `MathCase` type joined the list: `MathCases` needs an element type that holds
a value and its condition.

## Part B — keep the linear projection complete — **done**

File: [MathToSyntax.jl](../../package/domain/main/math/MathToSyntax.jl)

Every type from Part A needs a rule here, so that the text path and the existing
tests stay complete. A two-dimensional shape collapses to its linear form:

- `MathFraction` prints `numerator / denominator`, in parentheses when a child is
  a `MathBinaryOperation`.
- `MathScript` prints `base^exponent` and `base_index`.
- `MathRadical` prints `sqrt(radicand)`.
- `MathBigOperator` prints `sum(lower, upper, body)`, and the integral prints
  `integral(lower, upper, body)`.
- `MathMatrix` and `MathCases` print a bracketed row list.

Use `@projection_template` for the new rules where the rule is a plain builder.
An introduced token needs a flat-offset reader, so keep the
`_syntax_to_flat` fallback in `read_intent` that the current rules use.

Register the new rules in `MathToSyntax()`'s dispatch table.

**Commit B.** Linear rules for every new type. Run `test_printer(math_example)`
and `test_reader(math_example)`.

**Result.** `test_example(math_example)` gives 1116 pass / 18 fail against a
clean-main baseline of 1115 pass / 18 fail. The 18 failures are the pre-existing
type-in deletions at a value-to-chrome boundary; the extra pass follows the one
new cell on `MathParenthesized`. The linear forms are:

```
k T B          λ          bit/s        1/(μ - λ)      P_{t}^{2}
\sqrt{2 * x}   \sqrt[n]{x}             \sum_{k = 0}^{n} (x/n)
\int_{0}^{∞} (x dt)       d(P)/d(t)    \partial^2(P)/\partial(t)^2
log_{2}(1 + x)            \bar{L}      n!             |x|
\matrix[2]{1, 2, 3, 4}    \cases{1 if x < n; 0 otherwise}
```

## Part C — publish the font metrics — **done**

Files: [TrueType.jl](../../package/visual/main/style/TrueType.jl),
[Font.jl](../../package/visual/main/style/Font.jl)

The injected `measure(text, font)` returns a width and a height. The height is
the em size on the TrueType path and the rasterized height on the SDL path, so
it cannot decide where a baseline sits. Read the vertical metrics from the font
file instead.

1. Parse `sxHeight` from the `OS/2` table (offset 86, version 2 and above) in
   `_parse_truetype`. Fall back to the cap height when the table is older.
2. Export from the style slice, each in logical pixels at
   `font_logical_size(font)`, so a font zoom relayouts the formula:
   `font_ascent(font)`, `font_descent(font)`, `font_line_height(font)`,
   `font_x_height(font)` and `font_cap_height(font)`.

`GraphicsText` draws from the top left of the glyph box, so the baseline of a
text box sits at `font_ascent(font)` below its top. Every rule in Part D uses
that identity.

**Commit C.** The metrics API plus a test in the visual test package that asserts
the ascent and the descent of DejaVu Sans at size 20.

**Found during the work.** DejaVu ships an OS/2 **version 1** table, which
carries neither `sxHeight` nor `sCapHeight`, so step 1 alone would have given
math a cap height equal to the ascent and an x height half of that — a fraction
bar a pixel too low at every size. The parser now falls back to the outlines:
the `yMax` of `x` is the x height and the `yMax` of `H` is the cap height, which
is what those numbers mean. That needed a small `loca`/`glyf` lookup
(`_glyph_ymax`). A CFF font has no `glyf` table and keeps the old fallback.
The values for DejaVu Sans at size 20: ascent 19, descent 5, cap height 15,
x height 11. `test_visual()` stays green (52469 pass, 1 broken, 0 fail).

## Part D — typeset the boxes — **done**

New file: `package/domain/main/math/MathToGraphics.jl`, included after
`math/MathToSyntax.jl` in
[ProjecturedDomain.jl](../../package/ProjecturedDomain/src/ProjecturedDomain.jl).

### D1. The box protocol

```julia
@iomap struct MathIoMap
    projection::Any
    input::Any
    output::Any          # a GraphicsCanvas
    child_iomaps::Cell
    width::Cell
    ascent::Cell         # top of the box → baseline
    descent::Cell        # baseline → bottom of the box
end
```

A rule builds its children first, reads their three cells inside computed cells,
places each child canvas at an `(x, y)`, and publishes its own three cells. A
child that is not a math document (a `PrimitiveNumber`, an embedded document)
goes through `recursion`; its box centers on the axis, which is the fallback
rule for a foreign box.

### D2. The metric constants

Put every constant in one place, `MathMetrics`, derived from the base font:

- `axis = font_x_height(font) ÷ 2` — the height of the fraction rule and the
  center of a big operator above the baseline.
- `rule_thickness = max(1, round(Int, size / 18))`.
- `numerator_gap = 3 * rule_thickness` in display style, `rule_thickness` in
  text style. The denominator gap is the same.
- `superscript_shift = round(Int, 0.45 * font_x_height(font))` above the
  baseline of the base, and never less than the descent of the superscript plus
  a quarter of its x height.
- `subscript_shift = round(Int, 0.25 * font_x_height(font))` below the baseline.
- `thin = size ÷ 6`, `medium = size ÷ 4.5`, `thick = size ÷ 3.6` — the spaces of
  the three operator classes.

Tune the numbers once, in this struct, and never in a rule.

### D3. The rules

One projection struct per document type, in the order below. Each entry states
the geometry that the rule must produce.

1. `MathVariableToGraphics`, `MathSymbolToGraphics`, `MathTextToGraphics`,
   `PrimitiveNumber` — one `GraphicsText`. Width from `measure`, ascent from
   `font_ascent`, descent from `font_descent`. A variable renders oblique, a
   number and a symbol render regular, and text renders regular.
2. `MathRowToGraphics` — place the children left to right on a common baseline.
   The ascent is the maximum child ascent, the descent the maximum child
   descent. Insert a thin space between two adjacent boxes.
3. `MathBinaryOperationToGraphics` — the same, plus the space of the operator
   class on both sides of the operator glyph.
4. `MathFractionToGraphics` — the rule is a `GraphicsRect` of `rule_thickness`,
   as wide as the wider child plus twice `thin`, with its top at `axis` above
   the baseline. Center both children on it. The ascent is the numerator height
   plus the gaps plus `axis`; the descent is the mirror. `inline == true`
   prints a slash row instead.
5. `MathScriptToGraphics` — recurse the scripts in the next style level with
   `with_property`. The superscript baseline rises by `superscript_shift`, the
   subscript baseline drops by `subscript_shift`. When both are present, keep at
   least `4 * rule_thickness` of gap between them and move them apart equally.
6. `MathRadicalToGraphics` — draw `√` at a size that covers the radicand height,
   then a `GraphicsRect` of `rule_thickness` above the radicand from the tip of
   the sign to its right edge. The index sits at the top left in script style.
7. `MathBigOperatorToGraphics` — draw the operator glyph at 1.8 of the base size
   in display style and 1.2 in text style, centered on `axis`. `limits === :under_over`
   (the default for `∑ ∏ ⋃ ⋂` in display style) centers the limits above and
   below the sign. `limits === :side` (the default for `∫ ∮` and for every
   operator in text style) places them as a subscript and a superscript to the
   right of the sign. `:auto` picks by operator and style.
8. `MathDifferentialToGraphics` — a thin space, then `d` or `∂` upright, then
   the variable.
9. `MathDerivativeToGraphics` — a fraction whose numerator is `d`/`∂` with the
   order as a superscript, and whose denominator is `d`/`∂` with the variable.
10. `MathFunctionToGraphics` — the name upright, the base as a subscript on the
    name, a thin space, then the argument in stretchy parentheses when
    `parenthesized`.
11. `MathParenthesizedToGraphics` — the stretchy delimiter rule. Measure the
    content, then pick a single glyph at a fitted size, or assemble the
    extension pieces above 1.4 of the base height. Center the delimiter on
    `axis`.
12. `MathAccentToGraphics` — the accent glyph centered above the base, its
    bottom at the base ascent plus `rule_thickness`. A wide accent (`bar`,
    `vec`) stretches with a `GraphicsRect` or a repeated glyph.
13. `MathUnaryOperationToGraphics` — prefix or postfix, with the class space on
    one side only.
14. `MathMatrixToGraphics` and `MathCasesToGraphics` — a grid. The column width
    is the maximum child width in the column, the row ascent and descent the
    maxima in the row. Center each cell in its column and put each row on its
    own baseline. Wrap the grid in the delimiter rule of item 11. The whole grid
    centers on `axis`.
15. `MathInsertionToGraphics` — an empty box one `em` wide and one x height
    tall, with a dotted border, so an empty slot is visible and clickable.

`MathToGraphics(; measure, font = font_dejavu_sans_regular_20, style = :display)`
builds the `TypeDispatchingProjection` over all of them.

**Commit D.** The rules landed together rather than in five commits: they share
`_row`, `_glyph_box` and the metric struct, and a half-built table renders
nothing to look at. The geometry test (38 assertions) came with them.

**Found during the work.**

1. **The style level cannot live in the rule.** The recursion is one table, so
   one rule instance serves every depth. The level rides in
   `ctx.properties[:math_style]`, and a rule that changes it says so with
   `_with_style`. `p.style` is only where a root print starts.
2. **A gap is named two ways.** A rule says either the class of the operator
   that follows (`:relation`) or the size it wants (`:thin`). One table answers
   both. The first render had no spaces at all, because half the rules spoke the
   other language.
3. **A script shift is a shift of the baseline, not of the box.** The first
   version added the script's own ascent on top of the shift, which dropped
   every subscript a full line. The numbers are TeX's: 0.36 em up, 0.2 em down,
   and never less than the base's own reach.
4. **A tall sign must be placed by its ink, not by its text box.** A `∑`, a `∫`
   and a `√` sit anywhere inside their boxes, so centering the box leaves the
   sign visibly high. `font_glyph_bounds` (added to Part C's API) answers where
   the ink is, and the radical and the large operators place by it.
5. **The radical sign is capped at 2.2 times the base size.** DejaVu has no
   extensible radical, and a uniformly scaled one grows as wide as it is tall.
   Past the cap the bar runs on above a sign that no longer follows it. A real
   math font is the fix, not a wider glyph.
6. **The tiled delimiters work.** A parenthesis, a bracket and a brace around a
   fraction, a matrix or a case list are tiled from the Unicode pieces and show
   no seam.

## Part E — map the selection — **done**

The printer alone is half a projection. Each rule needs
`map_reference_forward` and `map_reference_backward`.

1. A child box is a `GraphicsCanvas` at a known index in the parent canvas's
   elements, so the maps are the School A delegation that the syntax rules
   already use: match the field, delegate the tail through the stored child IO
   map, and prepend `elements[i]`. Do not re-walk the math types.
2. A glyph that the projection introduces (the operator, the rule, the
   delimiter, the `d` of a derivative) carries no domain reference. Wrap a caret
   on it into this projection's own step with `introduced_reference`, and let
   `read_intent` decline an edit by its exact operation type.
3. Draw the caret. A caret on a box paints a `GraphicsRect` of two logical
   pixels at the left or the right edge of the box, from its ascent to its
   descent. A whole-element selection (an `EmptyReference`) paints a
   translucent `GraphicsRect` behind the box.

**Commit E.** The maps and the wash.

**Found during the work.**

1. **One supertype, three methods.** Every rule answers the same box protocol,
   so `MathProjection` is the supertype of all of them and the forward map, the
   backward map and the reader are written once against the protocol. There is
   no per-rule mapping code at all.
2. **A child records where it was placed, not which element it is.** A matrix
   cell sits two canvases down, inside the grid inside the delimiter row, so an
   element index cannot name it. `MathChild` carries the reference steps that
   reach the child and the two cells that say where the parent put it; the
   delimiter wrapper shifts its inner children by the grid's own offset.
3. **A selection is a whole sub-expression.** A two-dimensional formula has no
   line of text to put a caret in, so an `EmptyReference` on the node is the
   selection, and a selected box paints a translucent wash over itself. The wash
   is element 1 of every box and paints nothing while nothing is selected, so
   selecting is a repaint and never a re-layout.
4. **A press finds the smallest box under it.** The reader descends the same
   child table the backward map does, so a click and a selection always agree. A
   press on a fraction's rule — which belongs to no child — selects the
   fraction.

## Part F — navigate and edit — **done**

1. **Move.** `Left` and `Right` step through the linear order of the leaves,
   which is the order the linear projection prints. `Up` and `Down` step between
   the numerator and the denominator, the base and its scripts, and the limits
   of a big operator. `Home` and `End` go to the ends of the row.
2. **Build.** On a selected box, `/` wraps it in a `MathFraction` and puts the
   caret in the denominator. `^` and `_` add a script slot. `\` starts a symbol
   name that completes on a space, so `\lambda` becomes `MathSymbol(:lambda)`.
   `(` wraps the selection in a `MathParenthesized`.
3. **Delete.** `Backspace` on an empty slot removes the construct and keeps the
   remaining child.

**Commit F.** The reader, in one commit.

**What landed, and what changed from the sketch above.**

1. **A key is offered to the child first.** Every node hands the key to the
   child its selection points into and acts only on what the child declined.
   One small rule per key then adds up to whole-tree navigation: `Left` and
   `Right` move between siblings, `Down` and `Enter` go into the first child,
   `Up` and `Escape` come back out. There is no flat leaf order and no
   numerator-to-denominator special case — the tree already says which parts are
   siblings.
2. **The build gestures are `/`, `^`, `_` and `(`.** Each one wraps what is
   selected and points the new node's own selection at the hole it opened, so
   `replace_document` leaves the editor inside that hole.
3. **A letter or a digit fills an empty slot**: a letter becomes a
   `MathVariable`, a digit a `PrimitiveNumber`.
4. **`Backspace` clears a selected part back to an empty slot.**
5. **The reader never touches the document.** An earlier version cleared the
   wrapped node's selection by hand; that is the job of the trailing selection
   write, which clears every other selection in the tree.
6. **`\lambda` name entry is not in.** It needs a text buffer that lives across
   keystrokes, which is a domain insertion type of its own
   (`JuliaInsertion` is the precedent), not a reader rule. A symbol is built in
   code today. This is the one part of Part F left undone.

The gestures are not yet verified in the live editor — the tests drive the
reader directly.

## Part G — examples, tests and documentation — **done**

1. **Examples.** Add to
   [Math.jl](../../package/domain/example/document/Math.jl) one function per
   formula of the scope table: `make_math_shannon_document_example`,
   `make_math_friis_document_example`, `make_math_queue_document_example`,
   `make_math_erlang_b_document_example`, `make_math_delay_document_example`,
   `make_math_ber_document_example`, `make_math_reliability_document_example`
   and `make_math_derivative_document_example`. Add
   `make_math_display_document_example` that stacks them, and
   `make_math_display_projection_example` that chains `MathToGraphics`.
   Register `math_display_example` in
   [Examples.jl](../../package/domain/example/Examples.jl) and add one
   `AtomicDocument(:math, …)` per new type.
2. **Geometry tests.** New file
   `package/domain/test/projection/MathToGraphicsTest.jl`. Assert coordinates,
   not existence: the fraction rule top sits at `axis` above the baseline; the
   numerator center equals the rule center; the superscript baseline sits
   `superscript_shift` above the base baseline; the two limits of a sum center
   on the sign; a nested script uses 0.5 of the base size.
3. **Pipeline tests.** `test_printer(math_display_example)`,
   `test_reader(math_display_example)`,
   `test_position_navigation(math_display_example)` and
   `test_repl(math_display_example)`. Keep `test_printer(math_example)` green
   throughout, because it covers the linear path.
4. **Look at the result.** Write an image with `write_example_image` after Part
   D and after Part F, and open the formula in the live editor. A test that
   asserts a type or a bound can pass while the render is wrong.
5. **Documentation.** Write `package/domain/doc/math.md`: the type list, the box
   protocol, the metric constants and the two projections. Add the file to the
   per-domain guide list in [CLAUDE.md](../../CLAUDE.md).

**Commit G.** Examples, tests and the guide.

**Found during the work.**

1. **`math_display_example` is not in the `examples` registry.** `test_typein`
   types a character at every rendered caret, and a two-dimensional formula
   offers none — a selection there is a whole sub-expression. All 159 positions
   were reported as failures. The example is registered but kept out of the
   sweep, the way `lazy_example` is, and its printer, its REPL loop and its
   arrow-key navigation are walked by `test_math_to_graphics()` instead. Text
   editing inside a formula would need a caret inside a leaf, which is the
   text-range work this plan deferred.
2. **The printer walk found a real bug.** A function's base was registered as a
   child through the *wrapper* box the projection introduced, not through the
   base's own IO map, so every key on it threw. The wrapper is now marked and
   the real child re-hung with both offsets added — the same trick the delimiter
   wrapper uses.
3. The test count is 72 assertions.

## Part H — make two dimensions the default — **done**

Change `MathDocument => MathToSyntax()` in
[NaturalProjection.jl](../../package/domain/main/insertion/NaturalProjection.jl)
to a `MathDocument` entry in the graphics table of `NaturalToGraphics`, beside
the `GraphGraph` entry. A formula in a markdown page, in a table cell and in a
widget card then renders in two dimensions.

Keep `MathToSyntax` in `natural_to_syntax_dispatch`, because the save path and
`document_to_text` still need it.

After this change, diff a full `test_domain()` run against the same run on clean
main. A wide change on a shared seam hides new errors from a targeted test.

**Commit H.** The default flip and the baseline diff.

**Found during the work.**

1. **The rules are spliced one type at a time**, not as one dispatching
   projection, so every child of a formula re-enters the natural renderer. The
   `PrimitiveNumber` and `PrimitiveString` entries are dropped from the splice —
   they are right for a table that holds nothing else and wrong for a renderer
   that already knows what a number is. `math_to_graphics_dispatch` does that.
2. **A foreign box that draws text reports that text's baseline.** Without it a
   number rendered by the natural renderer would center on the axis and sit two
   pixels below the variables beside it. The rule is general: descend to the
   first `GraphicsText` and read its font's ascent.
3. **A selection carries type checkpoints.** A whole-element selection on a node
   is an empty path *plus* that node's type, so every comparison in the reader
   strips them first and every path it answers is annotated. The tests passed
   before this fix because they set raw references by hand; the table did not.
4. **`Ctrl+Home` / `Ctrl+End` select the first / last part of a formula.** That
   is how a container asks a cell's content to take a selection — a table's
   `Enter` routes exactly this key into the cell — and it is the seed gesture
   the navigation walker uses.

**Result.** `test_domain()` gives 209089 pass / 0 fail / 0 error / 5 broken,
against a clean-main baseline of 208880 / 0 / 0 / 5 — 209 more assertions and no
new failure. `test_visual()` stays at 52469 pass / 1 broken.

## What is left undone

- **A symbol has no keyboard gesture.** `\lambda` needs a text buffer that lives
  across keystrokes — an insertion type of its own, the way `JuliaInsertion` is
  — rather than a reader rule. A symbol is built in code today.
- **The gestures are not verified in the live editor.** The tests drive the
  reader directly. A headless probe misses a reference-less start and an unwired
  card, so this is worth doing before the gestures are relied on.
- **A radical taller than 2.2 times the base size** outgrows its sign: the bar
  runs on above a sign that no longer follows it. Only a real math font fixes it.
- **`MathCases` draws a brace on both sides.** A piecewise definition
  conventionally has only the left one.

## Out of scope

- **A math font with a `MATH` table.** STIX Two Math or Latin Modern Math gives
  real growable glyphs and italic correction. DejaVu covers the glyphs today.
  Add the asset later, behind the same `MathMetrics` struct.
- **A LaTeX reader.** `.. math::` in RST keeps its LaTeX source as a string
  ([Rst.jl:479](../../package/domain/main/rst/Rst.jl#L479)). A parser from that
  subset into a `MathDocument` is the natural follow-on plan, and it needs no
  change to the parts above.
- **Inline math on the prose baseline.** A formula inside a paragraph must sit
  on the text baseline of that line. That needs the baseline protocol in the
  text layer, which this plan deliberately leaves out. A display formula is a
  block and needs none of it.
- **Evaluation.** The math domain describes a formula; it does not compute one.
  The formula domain owns that.
