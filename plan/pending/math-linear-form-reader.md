# A reader for the linear form of the math domain

**Status:** Steps 1 to 4 done on 2026-09-15; Step 5, type-in, is open.
**Scope:** `ProjecturedMath`, slice `source/math/`: a parser of the linear
form, a `.math` file type, and the guide.
**Serves:** omnet-julia `plan/done/assistant-develops-a-study.md`, Step 2b,
where an assistant writes the closed form of a queue as one line and the study
page draws it. Also every person who types a formula.
**Stands on:** [math.md](../../documentation/package/math/math.md).

## 1. The problem

A formula is a tree: `MathAssignment(MathVariable("W"), MathFraction(…))`. Two
projections read the tree. `MathToSyntax` prints it as one line, the linear
form, and that line is what a save writes. `MathToGraphics` draws it as
two-dimensional boxes. Nothing reads the line back. A formula reaches the
editor by constructors, or key by key through the readers of the graphics
projection.

So a language model that wants an equation on a page writes about fifteen
nested constructor calls. A person who has the line in a paper types it node
by node. The printer defines a notation and no reader accepts it.

## 2. The design

### 2.1 One function

```julia
parse_math(text::AbstractString) -> MathDocument
```

in a new fragment `source/math/MathParser.jl`, included from `MathModule.jl`
after `MathDocument.jl`. A recursive descent over a cursor of characters, the
shape of `parse_json` in `source/json/JsonParser.jl`: a position in every
error message, no lookahead beyond one token, and no `eval` anywhere. The
reader builds documents and nothing else.

### 2.2 The grammar is what the printer writes

One production per template of `MathToSyntax.jl`. The printer is the
authority: a line the printer writes must read back to an equal tree.

| the line | the node |
| --- | --- |
| `x`, one letter | `MathVariable` |
| `λ`, `\lambda`, `∞`, `\infty` | `MathSymbol`; both the glyph and the backslash name read, and the table is `_MATH_SYMBOLS` |
| `bit/s`, a word of two letters or more that no rule below claims | `MathText` |
| `12`, `0.8` | `PrimitiveNumber` |
| `a b c`, elements set apart by spaces | `MathRow` |
| `a + b`, `a \times b`, `a < b`, every operator of `_MATH_OPERATORS` by its text | `MathBinaryOperation` |
| `-x`, `n!` | `MathUnaryOperation`, prefix or postfix |
| `x = y` at the top | `MathAssignment` |
| `(x)` | `MathParenthesized` |
| `a / b` | `MathFraction` |
| `x_{i}`, `x^{2}`, `x_{i}^{2}` | `MathScript` |
| `\sqrt{x}`, `\sqrt[n]{x}` | `MathRadical` |
| `\sum_{k = 0}^{n} body`, `\prod`, `\int`, `\oint`, `\bigcup`, `\lim` | `MathBigOperator`, by the names of `get_math_big_operator_name` |
| `dt`, `\partial x` | `MathDifferential` |
| `d(P)/d(t)`, `\partial^2(P)/\partial(t)^2` | `MathDerivative` |
| `sin x`, `log_{2}(1 + x)`, `Q(x)` | `MathFunction`, with or without parentheses |
| `\bar{L}`, `\vec{v}`, `\hat{p}` | `MathAccent` |
| `\matrix[2]{1, 2, 3, 4}` | `MathMatrix` |
| `\cases{1 if x < n; 0 otherwise}` | `MathCases` of `MathCase` |
| `\,` | `MathSpace` |

**Precedence**, loosest first: `=`; a relation (`<`, `\le`, …); `+` and `-`;
`\times`, `\cdot` and `\div`; juxtaposition; `/`; a prefix sign; `^` and `_`
and a postfix; an atom. So `(1 - ρ) ρ^n / (1 - ρ^(n + 1))` reads as a
fraction whose numerator is a row of a parenthesized difference and a script,
which is what the printer writes for that tree.

### 2.3 Where the line is ambiguous, the reader decides

The printer writes two different nodes the same way in four places. A reader
must pick one, and the pick is a decision written here.

- **`/` is a fraction.** `MathBinaryOperation(:/)` prints `/` too. The reader
  answers a `MathFraction`, and a person who wants the binary operator writes
  `\div`. The two draw differently, and a fraction is what a formula on a page
  means by `/`.
- **A letter is a variable; a word is text; a word before `(` or `_{` is a
  function.** `MathVariable("n")`, `MathText("block")` and
  `MathFunction("sin", …)` all print their name. Length and what follows
  decide. `MathVariable("block")` therefore does not survive a round trip; it
  comes back as text, and the two draw the same.
- **A space is juxtaposition.** `MathSpace` prints one space, and so does the
  gap between the elements of a row. The reader reads a space as a row. The
  printer changes to write `\,` for a `MathSpace`, so the explicit space has a
  spelling of its own. This is the one printer change of this plan.
- **A script accepts one atom without braces.** The printer writes `ρ^{n}`.
  The reader also takes `ρ^n` and `ρ^(n + 1)`, because that is what a person
  and a model write, and prints them back with braces. A read is wider than
  a print; a print is canonical.

### 2.4 A `.math` file

`MathFile(filename, content)` in `source/math/MathFile.jl`, on the pattern of
`JsonFile`: `get_file_domain` is `MathDocument`, `parse_file_content` calls
`parse_math`, `emit_text` runs the printer, and neither notation writes a
reference, so a node of a `.math` file belongs to that file alone, as a NED
node does. `register_file_document_type!(".math", MathFile)` in the module's
`__init__`, and

```julia
register_natural_domain!(MathDocument; rung = :syntax, make = () -> MathToSyntax(),
                         format = :math, extension = ".math", parse = parse_math)
```

A page then embeds an equation with a `pred-ref` fence that names
`file("equation-1.math")`, the load splices the tree in, and the graphics rung
draws it with `MathToGraphics`. Check that the natural graphics table holds a
row for `MathDocument`; add one if it does not.

### 2.5 Type-in, optional

`MathInsertion` is the empty slot. With a reader, Enter on a slot that holds
typed text can parse the text into a tree, as `FormulaInsertion` does. This is
one reader rule and it is optional here; the study needs the function and the
file, not the gesture.

## 3. Steps

Each step is a commit on `main`; omnet-julia's `[sources]` reach this
checkout, so a worktree would hide the change from it.

### Step 1 — the tests, first

- [x] `test/math/document/MathParserTest.jl`, `test_math_parser()`, included in
      `test_math()`:
  - every builder of `example/math/MathDocumentExample.jl` prints, reads back
    and prints the same line again; and the tree read back equals the tree
    built, compared field by field with the cells read through;
  - every line of the guide's "The linear form" reads;
  - the wider forms of 2.3 read and print canonically: `ρ^n` prints `ρ^{n}`;
  - an unbalanced brace, an unknown `\name` and an operator with no right
    operand are refused with the position in the message;
  - `run(\`touch pwned\`)` reads as a function named `run` applied to text, and
    nothing runs.

### Step 2 — the reader

- [x] `source/math/MathParser.jl`: the cursor, the tokens (a number, a letter,
      a word, a glyph, a backslash name, an operator, a brace or a bracket or
      a parenthesis, a comma, a semicolon), and one function per precedence
      level of 2.2.
- [x] `MathSpace` prints `\,`, and `\:`, `\;`, `\quad` for its other kinds.
- [x] `export parse_math` from `MathModule`.

### Step 3 — the file

- [x] `source/math/MathFile.jl`, the registrations of 2.4, and a round trip in
      `test_file_project` or a small `test_math_file()`: a page with a
      `pred-ref` fence to a `.math` file loads with the tree in place and saves
      the same bytes.
- [x] The natural graphics row for `MathDocument` was there already.

### Step 4 — the guide

- [x] `math.md`: "The linear form" says it has a reader, lists the four
      decisions of 2.3, and names the file type. The testing section names
      `test_math_parser()`.

### Step 5 — type-in, optional

- [ ] Enter on a `MathInsertion` with typed text parses it.

## 4. Decisions taken here

- **D1. The printer is the grammar.** A reader that accepted a notation the
  printer does not write would make two notations.
- **D2. A read is wider than a print.** Bare scripts read; braces print. The
  canonical line is the printer's.
- **D3. `/` is a fraction.** The binary operator is `\div`.
- **D4. An explicit space is `\,`.** One printer change, so a row and a space
  no longer print alike.
- **D5. An equation is a `.math` file.** The line is the file. A tree written
  as nested `.pred` calls would be fifteen lines nobody reads.

**Decided while building.** The printer writes a binary division with spaces
and a fraction without, so `\div` is not needed to tell them apart: `/` with
no space is a fraction, ` / ` a division. A fraction binds tighter than
juxtaposition, which is what the printer's parentheses say. A number inside a
formula is a `PrimitiveNumber`, and the `.math` file counts it as its own. The
printer of `\neg` gained the space it lacked before its operand. `test_math()`
173/173.

## 5. Decisions left open

- Whether `MathVariable` of more than one letter should exist at all, or
  whether every multi-letter name is text. The reader's rule makes the second
  true on every round trip.
- Whether a glyph outside `_MATH_SYMBOLS` (a Cyrillic letter, an arrow) reads
  as a symbol by its code point or is refused.

## 6. Risks

- **The printer's helpers decide parentheses.** `_math_is_sequence` wraps an
  operand in a fraction, a script or a function. The reader must accept the
  parentheses the printer adds and must not add a `MathParenthesized` for
  them, or a round trip grows a node. The test of Step 1 catches it on every
  builder.
- **Two spellings of one glyph.** `λ` and `\lambda` both read to
  `MathSymbol(:lambda)`, and the printer writes the glyph. A file written by a
  person with backslash names is rewritten with glyphs on the first save.
  That is canonical form, and the guide says so.

## 7. Validation

`test_math()` with `test_math_parser()` and `test_math_file()`, and
`test_file_project()` for the `.math` leaf. The layering guard
`test_math_layering()` must stay green: the parser depends on nothing new.
