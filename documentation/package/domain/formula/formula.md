# Formula domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [julia.md](../julia/julia.md), [math.md](../math/math.md)

The Formula domain, `ProjecturedFormula`, holds named formulas that refer to each other and compute a value, as the cells of a spreadsheet do. A formula is a document of its own and is not tied to a grid. Its code is a Julia expression or a math expression. This document says where it differs from the [shape of every domain](../../../design/domain-anatomy.md).

<img width="396" alt="Formula example" src="../../../asset/image/example/formula.png">

## How it works

| Type | Fields that matter |
| --- | --- |
| `FormulaFormula` | `name`, `code` (a `JuliaDocument`, a `MathDocument` or a bare `PrimitiveNumber`), `result` (computed), `display_mode` (`:code`, `:result` or `:both`) |
| `FormulaEnvironment` | `formulas`, a `CellVector{FormulaFormula}`: the scope in which names resolve, one sheet |
| `FormulaInsertion` | the placeholder |

### References and names

A formula refers to another by its name. `C = A + B` holds two identifiers, and `get_formula_dependencies(formula, environment)` resolves each free name of the code in the environment. The code holds no node of the formula domain, so a formula that a file holds, `(1 - rho) * rho^n`, and a formula that a person types refer in the same way. `get_formula_key` reads a name as a one-line math expression, so `ρ` and `rho` are the same key and `p_{block}` becomes `p_block`.

`get_formula_names` gives the free names of the code. A name that the code binds itself is local, and refers to no formula: a parameter of a lambda, a function or a `do` block, a variable of a `let`, a `for` loop or a comprehension, and the target of an `=` in the statements after it. In `sum(x -> x * A, 1:3)`, only `sum` and `A` are free. A callee is a name like any other, because the value of a formula can be a function: `G = F(3)` depends on `F`. A free name that the environment does not hold, such as `sum`, stays for Julia.

### Evaluation

`wire_result!(formula, environment)` sets the function of the `result` cell. The function builds the Julia `Expr` of the code with `make_julia_expression`, so every Julia node evaluates, a lambda too. It binds each free name that resolves in the environment to the value of that formula in a `let` block, and evaluates the block in a scratch module that is made once. The `let` is the innermost scope, so the names of the environment win over a Julia global: a formula named `pi` means that formula. The read of each dependency's `result` records the dependency, so a change of one formula computes its dependents again. `FormulaEnvironment(formulas)` wires every formula that it holds.

The `result` holds the value itself, any value: a number, a vector, a function. So `F = x -> x^2` and `G = F(3)` give `9`, and `get_formula_value` gives the value. The views show the value on one line: a float to six digits, and another value in its `text/plain` form, or its compact form when that form takes more lines.

An error and a cycle do not raise. The result becomes a `FormulaError`, which shows as `#ERROR! …` or `#CYCLE!`, so a broken formula does not break the reactive graph. A formula that reads a `FormulaError` gives the same value on, as a spreadsheet does. Before it reads any result, the evaluation walks the names of the code through the environment, and a formula that reaches itself gives `#CYCLE!`. The walk reads the code and the name of each formula on the way, so each formula of a cycle computes again when a person breaks the cycle. `would_create_cycle(environment, from, to)` is the check that an editor runs before it adds a reference.

### Math code

When the code is a `MathDocument`, `convert_math_to_julia` reads it into Julia nodes, one rule for each math type. A fraction becomes a division, a superscript a power, a sum with limits a `sum` over a range, and a case list a chain of `ifelse`. A math node that has no value, such as an integral, a derivative or a matrix, raises a `MathReadingException` that names the node.

### Views

`FormulaToSyntax()` takes the dispatch table of `JuliaToSyntax()` and adds the four formula rules. One recursion then prints a formula and the Julia nodes of its code. An identifier that refers to a formula of the sheet draws in the reference style of `FormulaTheme`. `FormulaToSyntax()` puts `FormulaIdentifierToSyntaxLeaf` in front of the Julia table, because the dispatch takes the first match. The sheet rule gives each formula the sheet through the printer context, `:formula_environment`, and the formula rule gives its code the free identifiers that resolve, `:formula_references`, held by identity. So a local `x` stays plain when the sheet also has a formula `x`. A callee draws through the call rule of Julia, and keeps the callee style.

Ctrl+click on a reference selects the name of the formula that it refers to, and the whole formula when its layout does not show the name. A plain click selects the identifier, to edit it, as in the source of a Markdown page.

A key in the name of a formula renames it: the edit of the name and the new name in each use, as one `CompoundOperation`, so every use keeps its formula while a person types, and one undo takes back one key. The sheet rule makes the compound from the string edit of the name. A key that would make a use mean something else does nothing: a math formula uses the name, another formula has the new name, or a local name of the code would take the use. The sheet rule reads the click with its own `read_intent`, because the sheet is the lowest node that holds both the reference and the definition; a gesture binding can not do it, because its operation gets only the node and the event. So the jump works where the sheet is the root of the view. In a view that prints the sheet inside a template, the parent asks only the bindings of the parts, and a Ctrl+click selects the identifier. The rule for `FormulaFormula` has three layouts, one for each `display_mode`.

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

- **The code language is Julia.** The domain reuses the parser, the printer and the editing of the Julia domain, and adds no node to the code.
- **A reference is a name.** [plan/pending/formula-references-by-name.md](../../../../plan/pending/formula-references-by-name.md) holds the decisions. The code of a formula is plain Julia or plain math, and a file holds the same names that the view shows.
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
- Test: `test_formula()` runs the layering guard, `test_formula_to_syntax`, `test_formula_file`, `test_formula_math` and `test_formula_names`.

## Limits

- You can not type a new formula yet. `FormulaInsertion` prints a fixed label and has no reader, although its docstring describes a commit on Enter. This is Phase 5 of the plan.
- A formula inside another domain, for example in a table cell, is a goal of the plan (Phase 6). No test or example does it.
- Each evaluation of code that holds a lambda makes a new function type in the scratch module, as each line of the Julia REPL does. The cost grows with the edits of such a formula, not with the frames.
