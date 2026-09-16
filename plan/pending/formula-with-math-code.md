# A formula whose code is an equation

**Status:** pending. Design settled in dialogue on 2026-09-15. Nothing is
built.
**Scope:** `ProjecturedFormula`, slice `source/formula/`: a conversion of a
math tree to a Julia expression, a formula that evaluates math code, its file
half, and the block that draws the equation with its value.
**Stands on:** [math-linear-form-reader.md](math-linear-form-reader.md), for
the reader that turns a line into a tree;
[math.md](../../documentation/package/math/math.md).
**Serves:** omnet-julia `plan/done/assistant-develops-a-study.md`, section
4.2b: the closed form of a study is one block, an equation with its value.

## 1. The problem

The math domain is notation. `MathAssignment`, `MathFraction` and `MathScript`
draw as boxes, and nothing evaluates them, because the notation holds
integrals, derivatives and set operators that Julia does not compute. The
formula domain evaluates: a `FormulaFormula` is a name and a Julia tree, and
its result is a live cell. A closed form on a page needs both. It must read as
an equation, and it must have a value.

Today that takes two blocks, an equation to read and a formula to compute,
and a person writes the same closed form twice in two notations.

## 2. The design

### 2.1 A math tree has a Julia reading, where one exists

```julia
convert_math_to_julia(tree::MathDocument) -> JuliaDocument
```

in `source/formula/MathToJulia.jl`, one rule per node type:

| math | Julia |
| --- | --- |
| `MathVariable("n")` | the identifier `n` |
| `MathSymbol(:rho)` | the identifier `rho`; a symbol binds by its name |
| `MathText("block")` | the identifier `block` |
| `PrimitiveNumber` | the number |
| `MathScript(base; subscript)` with a name for both | the identifier `p_block`: a subscript on a name is part of the name |
| `MathScript(base; superscript)` | `base^superscript` |
| `MathBinaryOperation` with `+ - * / times cdot` | the operator; `\div` is `/` |
| a relation, `< <= > >= = !=` | the comparison |
| `MathUnaryOperation` prefix `-` | `-x`; postfix `!` is `factorial(x)` |
| `MathRow` | a product, left to right |
| `MathParenthesized` | the content |
| `MathFraction` | `numerator / denominator` |
| `MathRadical` | `sqrt(x)`, or `x^(1/n)` with an index |
| `MathFunction` | the call, `sin(x)`; `log_{2}(x)` is `log(2, x)` |
| `MathBigOperator` `sum`, `prod` with limits | `sum(k -> body, lower:upper)`, `prod(...)` |
| `MathCases` | a chain of `ifelse` |
| `MathAssignment` | the value side; the target is the formula's name |

**What has no reading is refused by name.** An integral, a derivative, a
differential, a limit, a matrix, an accent, a set operator and a big operator
with no limits throw a `MathReadingException` whose message names the node:
"an integral has no value here". A formula whose code is refused has a result
that says so, and a page shows the equation all the same.

### 2.2 A formula evaluates math code

`FormulaFormula.code` may be a `MathDocument`. `convert_formula_to_expr`
converts a Julia tree as it does today, and a math tree through
`convert_math_to_julia` first. `get_formula_names` walks the converted tree,
so a symbol `ρ` in an equation binds to the formula named `ρ` or `rho` in the
sheet: the name of a formula is normalized the same way its symbols are, so
`ρ` and `rho` are one name.

### 2.3 The file half says the notation

`pred_arguments` writes `code` as the linear form of the math domain when the
code is a math tree, and `notation = :math` beside it; a Julia tree writes its
source and `notation = :julia`. `make_pred_document` reads the code with the
parser the notation names. No field holds the notation: the type of the code
says it, and the file writes what the type says.

```
FormulaFormula(
    name = "p_{block}",
    code = "(1 - ρ) ρ^{n} / (1 - ρ^{n + 1})",
    notation = :math,
    display_mode = :both,
)
```

### 2.4 The block draws the equation with its value

A graphics row for `FormulaFormula` and for `FormulaEnvironment`, registered
with the natural graphics registry from the formula module's `__init__`. A
formula with math code draws as `MathToGraphics` of
`MathAssignment(parse_math(name), code)`, and a label beside it with the value
read from `result`, reactive. A formula with Julia code draws as today, one
line of text. A sheet draws its formulas as a column.

### 2.5 The syntax rung reads the linear form

`FormulaToSyntax` merges the Julia dispatch table today. It merges the math
table too, so a formula with math code prints as its linear form in the text
view and in `format_conversation`.

## 3. Steps

Each step is a commit on branch `study` of the worktree
`projectured-julia-study`, then a fast-forward of `main`, because
omnet-julia's `[sources]` reach the main checkout.

### Step 1 — the conversion (done)

- [x] `test/formula/FormulaMathTest.jl`, `test_formula_math()`: every builder
      of `example/math/MathDocumentExample.jl` converts or is refused by name;
      the blocking formula converts to the expression that evaluates to
      `0.066341` at ρ = 0.8 and n = 6; a subscripted name is one identifier.
- [x] `source/formula/MathToJulia.jl`: `convert_math_to_julia`,
      `MathReadingException`. `ProjecturedFormula` depends on
      `ProjecturedMath` and `ProjecturedPrimitive`. `test_formula()` 101/101.

### Step 2 — a formula with math code, and its file half

- [x] `convert_formula_to_expr` and `get_formula_names` accept a math tree.
- [x] `pred_arguments` writes the notation; `make_pred_document` reads by it.
      A bare number is math code too: the math reader answers one for a line
      that is one number.
- [x] Tests: a sheet of three math formulas evaluates; it round-trips through
      `print_pred_text` and `parse_pred_text` byte for byte; a mixed sheet
      reads both notations. `test_formula()` 111/111.
- [x] **Decided while building.** A formula binds under `get_formula_key`
      of its name: the identifier its name reads as in the math notation, so
      `ρ` and `rho` are one name and `p_{block}` is `p_block`. `ρ` is an
      identifier to Julia too, so the reading comes first and the text is the
      fallback.

### Step 3 — the block

- [x] `source/formula/FormulaToGraphics.jl` with the rows of 2.4: a formula
      with math code draws as the assignment of its name to its code through
      the math boxes, with a label of its value after it; a Julia formula draws
      as one line of text; a sheet as a column. The math table in
      `FormulaToSyntax` is open: a formula prints as text through the natural
      notation of its code already.
- [x] A headless print of a sheet with three math formulas and one Julia
      formula through `NaturalToGraphics`: the canvas holds the symbol, the
      subscript of the name, the value, and a changed input redraws the value.
      `test_formula()` 116/116.

### Step 4 — the guide

- [ ] `documentation/package/formula/formula.md`: what a formula is, the two
      notations, the conversion table and the refusals, the file form.

## 4. Decisions taken here

- **D1. No notation field.** The type of the code says the notation, and the
  file writes what the type says.
- **D2. A refusal names the node.** "An integral has no value here" is what a
  person can act on; a silent `nothing` is not.
- **D3. A symbol binds by its name.** `ρ` is `rho`, in an equation and in the
  name of a formula.
- **D4. The name of a formula is a math line too.** `p_{block}` draws as a
  subscript, and the sheet holds it as one identifier `p_block`.

## 5. Decisions left open

- Whether a set operator and a matrix get a Julia reading later, as a set and
  an array. Nothing in the study needs one.
- Whether a formula with Julia code should draw through the math domain too,
  by a conversion the other way. The syntax line is enough today.

## 6. Risks

- **A conversion is a second evaluator in disguise.** It is not: it produces a
  Julia tree and the formula domain evaluates that, as it evaluates every
  other. The test that every corpus builder converts or is refused keeps the
  line visible.
- **Names with subscripts.** `p_{block}` and `p_block` must be one name in the
  sheet, or a formula written one way is not found the other way. D3 and D4
  settle it, and the test asserts it.

## 7. Validation

`test_formula()` with `test_formula_math()`, and `test_file_project()` for
the notation keyword. The layering guard `test_formula_layering()` stays
green with the one new dependency.
