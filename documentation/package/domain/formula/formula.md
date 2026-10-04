# Formula domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [julia.md](../julia/julia.md), [math.md](../math/math.md)

The Formula domain, `ProjecturedFormula`, holds named formulas that refer to each other and compute a value, as the cells of a spreadsheet do. A formula is a document of its own and is not tied to a grid. Its code is a Julia expression or a math expression. This document says where it differs from the [shape of every domain](../../../design/domain-anatomy.md).

<img width="396" alt="Formula example" src="../../../asset/image/example/formula.png">

## How it works

| Type | Fields that matter |
| --- | --- |
| `FormulaFormula` | `name`, `code` (a `JuliaDocument` or a `MathDocument`), `result` (computed), `display_mode` (`:code`, `:result` or `:both`) |
| `FormulaReference` | `target`, the formula it cites |
| `FormulaEnvironment` | `formulas`, the scope in which names resolve: one sheet |
| `FormulaInsertion` | the placeholder |

### References and names

A `FormulaReference` holds its target formula, not the name of the target. The view shows `target.name` through a cell, so a rename of the target changes every reference at once and no rewrite pass exists.

A formula loaded from a file has no `FormulaReference` objects. Its code is text such as `(1 - rho) * rho^n`, and `rho` is a plain identifier. So `get_formula_dependencies` also resolves each plain name that the code reads against the names of the environment. `get_formula_key` reads a name as a one-line math expression, so `ρ` and `rho` are the same key and `p_{block}` becomes `p_block`.

### Evaluation

`wire_result!(formula, environment)` sets the function of the `result` cell. The function builds a Julia `Expr` from the code, binds the value of each dependency in a `let` block, and evaluates it in a scratch module that is made once. The read of each dependency's `result` records the dependency, so a change of one formula computes its dependents again. `FormulaEnvironment(formulas)` wires every formula that it holds.

An error and a cycle do not raise. The result becomes a `TextBlock` with the text `#ERROR! …` or `#CYCLE!`, so a broken formula does not break the reactive graph. The cycle check has two parts. `would_create_cycle(environment, from, to)` is the check that an editor runs before it adds a reference. A guard in the evaluator returns `#CYCLE!` if a cycle gets through.

### Math code

When the code is a `MathDocument`, `convert_math_to_julia` reads it into Julia nodes, one rule for each math type. A fraction becomes a division, a superscript a power, a sum with limits a `sum` over a range, and a case list a chain of `ifelse`. A math node that has no value, such as an integral, a derivative or a matrix, raises a `MathReadingException` that names the node.

### Views

`FormulaToSyntax()` takes the dispatch table of `JuliaToSyntax()` and adds the four formula rules. One recursion then prints a tree that mixes Julia nodes and formula nodes, and a reference can stand inside Julia code. The rule for `FormulaFormula` has three layouts, one for each `display_mode`.

The graphics rows draw a formula with math code as a `MathAssignment` of the math domain, followed by `= value`. A formula with Julia code is one line: `name = code = value`. These rows print only; they have no reader.

### The file

The domain has no file type and no parser of its own. It stores formulas in `.pred` files of the serialization slice. `pred_arguments` writes the name, the code as text, the notation (`:math` or `:julia`) and the display mode. It does not write the result, because a load computes it again. `make_pred_document` reads the code back with `parse_math` or `parse_julia`, by the notation.

### The theme

`FormulaTheme` holds the look of the Formula projections: the text of the insertion, a reference, a name, an operator and a result, and the plain font of an environment. Each value has
the default that the domain draws with no appearance. A projection holds its
styles as fields, and no theme; nothing in it scales or asks whether a theme is
scaled. `FormulaToSyntax(; theme, julia_theme, syntax_theme)` gives each
projection the style of its role with `get_formula_style`, from `theme`, a
`FormulaTheme` scaled or not, or the default styles for `nothing`, and the
Julia code of a formula takes `julia_theme`. The natural registration gives the
scaled theme of the `Appearance` of the editor, so the view follows its
scales, and the appearance tab shows a section for `FormulaTheme`.

## How it fits

`ProjecturedFormula` depends on two domains: `ProjecturedJulia` for the code and the printer table, and `ProjecturedMath` for the math code and its drawing. It also uses the layout and widget slices of the platform for the graphics rows. No package depends on it.

Its `__init__` registers the graphics rows with `register_natural_graphics!(:formula, …)`.

## Design decisions

The decisions are in [plan/pending/excel-julia-formulas.md](../../../../plan/pending/excel-julia-formulas.md), whose first phases are done.

- **The code language is Julia.** The domain reuses the parser, the printer and the editing of the Julia domain. The only new leaf is the reference.
- **A reference points by identity and shows by name.** A rename needs no pass over the other formulas.
- **The scope is a document.** A `FormulaEnvironment` is a value, not a global registry. So two sheets can exist at the same time, and a sheet has a view. The link design of [plan/pending/document-link-feature.md](../../../../plan/pending/document-link-feature.md) uses a global registry; the formula design does not.
- **An error is a value.** A spreadsheet shows `#ERROR!` in the cell. A reactive cell that raises would stop every view that reads it.
- **Math notation is a second way to write code.** [plan/pending/formula-with-math-code.md](../../../../plan/pending/formula-with-math-code.md) holds its design. The list of math nodes with no value is a fixed limit, not a gap.

## Usage

```julia
sheet = FormulaEnvironment([                 # wires every result
    FormulaFormula("rho", parse_julia("0.8")),
    FormulaFormula("n", parse_julia("6")),
    FormulaFormula("p_block", parse_julia("(1 - rho) * rho^n / (1 - rho^(n + 1))")),
])
get_formula_value(sheet.formulas[3])         # ≈ 0.066341
sheet.formulas[1].code = parse_julia("0.5")  # p_block computes again on the next read
```

- Examples: `formula_example`, from `make_formula_document_example()` and `make_formula_projection_example()`.
- Test: `test_formula()` runs the layering guard, `test_formula_to_syntax`, `test_formula_file` and `test_formula_math`.

## Limits

- You can not type a new formula yet. `FormulaInsertion` prints a fixed label and has no reader, although its docstring describes a commit on Enter. This is Phase 5 of the plan.
- A formula inside another domain, for example in a table cell, is a goal of the plan (Phase 6). No test or example does it.
- The evaluator handles literals, operators, calls, ranges, indexing, field access, tuples, arrays, `if`, blocks and assignments. Code that uses another Julia type, such as a `for` loop, prints but does not evaluate.
