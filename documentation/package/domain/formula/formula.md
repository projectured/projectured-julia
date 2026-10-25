# Formula domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [julia.md](../julia/julia.md), [math.md](../math/math.md)

The Formula domain, `ProjecturedFormula`, holds named formulas that refer to each other and compute a value, as the cells of a spreadsheet do. A formula is a document of its own and is not tied to a grid. Its code is a Julia expression or a math expression. This document says where it differs from the [shape of every domain](../../../design/domain-anatomy.md).

<img width="396" alt="Formula example" src="../../../asset/image/example/formula.png">

## How it works

| Type | Fields that matter |
| --- | --- |
| `FormulaFormula` | `name`, `code` (a `JuliaDocument`, a `MathDocument` or a bare `PrimitiveNumber`), `draft` (the code that edit mode edits, or `nothing`), `result` (the stored value) with `result_key` and `is_computing`, `current_value` (the value of the code now, for code to read), `display_mode` (`:code`, `:result` or `:both`) |
| `FormulaEnvironment` | `formulas`, a `CellVector{FormulaFormula}`: the scope in which names resolve, one sheet |
| `FormulaInsertion` | the placeholder |

### References and names

A formula refers to another by its name. `C = A + B` holds two identifiers, and `get_formula_dependencies(formula, environment)` resolves each free name of the code in the environment. The code holds no node of the formula domain, so a formula that a file holds, `(1 - rho) * rho^n`, and a formula that a person types refer in the same way. `get_formula_key` reads a name as a one-line math expression, so `ρ` and `rho` are the same key and `p_{block}` becomes `p_block`.

`get_formula_names` gives the free names of the code. A name that the code binds itself is local, and refers to no formula: a parameter of a lambda, a function or a `do` block, a variable of a `let`, a `for` loop or a comprehension, and the target of an `=` in the statements after it. In `sum(x -> x * A, 1:3)`, only `sum` and `A` are free. A callee is a name like any other, because the value of a formula can be a function: `G = F(3)` depends on `F`. A free name that the environment does not hold, such as `sum`, stays for Julia.

### Evaluation

The code of a formula is the code of a person, so it can take any time. A view therefore shows only the stored value, `result`, and no print runs the code. The value is any value: a number, a vector, a function. So `F = x -> x^2` and `G = F(3)` give `9`. The views show it on one line: a float to six digits, and another value in its `text/plain` form, or its compact form when that form takes more lines. A view shows `⋯` while a computation of the formula runs.

`ComputeFormulasOperation(environment, formulas)` computes formulas again, each after the formulas of the list that it names. While the loop of the editor runs, the formula task of that editor computes them, one at a time, off the loop: the loop prepares each job through the door (the `Expr` of the code with `make_julia_expression`, and the stored value of each formula that it names), the task runs the code in the scratch module of the editor, and `ReplaceFormulaResultOperation` brings the value back. With no loop, as in a test that drives the frames or a script with no editor, the formulas compute at once on the task that applies the operation. The code runs in a `let` block that binds each free name that resolves in the environment to the value of that formula. The `let` is the innermost scope, so the names of the environment win over a Julia global: a formula named `pi` means that formula.

A stored value keeps `result_key`, the key of the code and the inputs that it came from (`compute_formula_key`): the hash of the text of the code, and of the key of the stored value of each formula that the code names. A value that comes back for code that changed meanwhile is dropped, and the formula computes again. A new value computes again each formula that names the formula; an equal value does not, so a cycle ends. A computation starts at a commit, when a window acquires the sheet (`acquire_document!`, as when a tab opens with it), and at a new value of a formula that the code names. A key starts none.

Code that needs a value reads `get_formula_value`, which answers the value for the code and the inputs now and computes it on the task that calls it: a script that adds a formula reads its value at once. `wire_result!(formula, environment)` wires that `current_value` cell, and `FormulaEnvironment(formulas)` wires every formula that it holds. No print reads it; a view reads `get_formula_result`.

An error and a cycle do not raise. The value becomes a `FormulaError`, which shows as `#ERROR! …` or `#CYCLE!`. A formula that reads a `FormulaError` gives the same value on, as a spreadsheet does. Before it reads any value, the evaluation walks the names of the code through the environment, and a formula that reaches itself gives `#CYCLE!`. `would_create_cycle(environment, from, to)` is the check that an editor runs before it adds a reference.

### Edit mode

A formula edits as a cell of a spreadsheet does. A key reads at the stage nearest the output, and its operation comes up to the sheet as a path from it. In value mode, the sheet rule turns a write of the code of a formula into `BeginFormulaEditOperation`, which makes `draft` a copy of the code, and the same write of the draft. A view then shows the draft in place of the code, and no value, because the stored value belongs to the code. In edit mode, the bindings of `FormulaFormula` read Enter and Escape first, even inside the code: Enter gives `CommitFormulaOperation`, which writes the draft into the code as one operation and computes the formula; Escape gives `CancelFormulaEditOperation`, which drops the draft. Each leaves the selection on the whole code. An undo of a commit restores the old code, the draft and the old value together.

### Math code

When the code is a `MathDocument`, `convert_math_to_julia` reads it into Julia nodes, one rule for each math type. A fraction becomes a division, a superscript a power, a sum with limits a `sum` over a range, and a case list a chain of `ifelse`. A math node that has no value, such as an integral, a derivative or a matrix, raises a `MathReadingException` that names the node.

### Views

`FormulaToSyntax()` takes the dispatch table of `JuliaToSyntax()` and adds the formula rules and the rules of `MathToSyntax()`. One recursion then prints a formula and the nodes of its code, and math code prints in its linear form, such as `D = C/2`. An identifier that refers to a formula of the sheet draws in the reference style of `FormulaTheme`. `FormulaToSyntax()` puts `FormulaIdentifierToSyntaxLeaf` in front of the Julia table, because the dispatch takes the first match. The sheet rule gives each formula the sheet through the printer context, `:formula_environment`, and the formula rule gives its code the free identifiers that resolve, `:formula_references`, held by identity. So a local `x` stays plain when the sheet also has a formula `x`. A callee draws through the call rule of Julia, and keeps the callee style.

Ctrl+click on a reference selects the name of the formula that it refers to, and the whole formula when its layout does not show the name. A plain click selects the identifier, to edit it, as in the source of a Markdown page.

A key in the name of a formula renames it: the edit of the name and the new name in each use, as one `CompoundOperation`, so every use keeps its formula while a person types, and one undo takes back one key. The sheet rule makes the compound from the string edit of the name. A key that would make a use mean something else does nothing: a math formula uses the name, another formula has the new name, or a local name of the code would take the use. The sheet rule reads the click with its own `read_intent`, because the sheet is the lowest node that holds both the reference and the definition; a gesture binding can not do it, because its operation gets only the node and the event. So the jump works where the sheet is the root of the view. In a view that prints the sheet inside a template, the parent asks only the bindings of the parts, and a Ctrl+click selects the identifier. The rule for `FormulaFormula` has three layouts, one for each `display_mode`.

The graphics rows draw a formula with math code as a `MathAssignment` of the math domain, followed by `= value`. A formula with Julia code is one line: `name = code = value`. These rows print only; they have no reader.

`FormulaEnvironmentToTable()` draws a sheet as the grid of a spreadsheet, a `WidgetTable` for the natural renderer. A formula whose name is a cell name, such as `B3`, shows its stored value in that cell, a text without its quotes, and `⋯` while it computes. The grid has a column for each letter and a row for each number up to the last cell that a name names; a formula with another name is not in it. Each cell is a label that reads the stored value of its formula, so a new value draws only its own cell again. The grid prints only; a person edits the sheet in the text view.

A sheet in a page of another domain takes the keys when it is the root of a chain of its own. The natural renderer gives each block of a Markdown page its own chain, so a row `FormulaEnvironment => make_formula_projection_example()` in its `extra` makes a sheet in a page edit as a sheet alone does (`formula_report`). A sheet that one recursion prints inside a template of another domain gets only the gesture bindings from its parent: a key writes its code at once, with no edit mode, and Enter computes nothing.

### The file

The domain has no file type and no parser of its own. It stores formulas in `.pred` files of the serialization slice. `pred_arguments` writes the name, the code as text, the notation (`:math` or `:julia`) and the display mode. It does not write the value: a window that acquires the sheet computes it again. `make_pred_document` reads the code back with `parse_math` or `parse_julia`, by the notation.

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
- **A reference is a name.** [plan/done/formula-references-by-name.md](../../../../plan/done/formula-references-by-name.md) holds the decisions. The code of a formula is plain Julia or plain math, and a file holds the same names that the view shows.
- **The scope is a document.** A `FormulaEnvironment` is a value, not a global registry. So two sheets can exist at the same time, and a sheet has a view. The obsolete link design of [plan/obsolete/document-link-feature.md](../../../../plan/obsolete/document-link-feature.md) uses a global registry; the formula design does not.
- **An error is a value.** A spreadsheet shows `#ERROR!` in the cell. A reactive cell that raises would stop every view that reads it.
- **Math notation is a second way to write code.** [plan/pending/formula-with-math-code.md](../../../../plan/pending/formula-with-math-code.md) holds its design. The list of math nodes with no value is a fixed limit, not a gap.

## Usage

```julia
sheet = FormulaEnvironment([                 # wires every result
    FormulaFormula("rho", parse_julia("0.8")),
    FormulaFormula("n", parse_julia("6")),
    FormulaFormula("p_block", parse_julia("(1 - rho) * rho^n / (1 - rho^(n + 1))")),
])
get_formula_value(sheet.formulas[3])         # ≈ 0.066341, computed on this task
sheet.formulas[1].code = parse_julia("0.5")  # get_formula_value(sheet.formulas[3]) computes again
evaluate_operation(editor, ComputeFormulasOperation(sheet))  # the values that a view shows
```

- Examples, each with `make_formula_projection_example()` unless it says otherwise:
  - `formula_example`, from `make_formula_document_example()`: one feature of the sheet on each row.
  - `formula_invoice`, from `make_formula_invoice_document_example()`: a spreadsheet, an invoice whose formulas are named by their cells, A1 to D7.
  - `formula_invoice_grid`: the same invoice as a grid, with `make_formula_grid_projection_example()`.
  - `formula_queue`, from `make_formula_queue_document_example()`: the M/M/1 queue in math code, with Greek names and subscripts.
  - `formula_estimate`, from `make_formula_estimate_document_example()`: estimates of π and of the Euler–Mascheroni constant that compute for a second or more, off the loop. Its sheet holds no value when it is built, and the window computes them when it opens.
  - `formula_report`, from `make_formula_report_document_example()` and `make_formula_report_projection_example()` of the umbrella: a Markdown page about a loan that holds the sheet that computes it.
- Test: `test_formula()` runs the layering guard, `test_formula_to_syntax`, `test_formula_file`, `test_formula_math`, `test_formula_names`, `test_formula_evaluation`, `test_formula_stored_value`, `test_formula_task` and `test_formula_grid`. `test_formula_examples()` of the umbrella types a digit and Enter in the invoice and in the report.

## Limits

- You can not type a new formula yet. `FormulaInsertion` prints a fixed label and has no reader, although its docstring describes a commit on Enter. This is Phase 5 of the plan.
- A key edits the code of a math formula only. An identifier of Julia code prints through `FormulaIdentifierToSyntaxLeaf`, which maps no text, so a key there reads nothing. Alt+Enter has no new line of the code yet.
- A formula in a cell of a table of another domain is a goal of the plan (Phase 6). A sheet in a Markdown page works through the natural renderer, as `formula_report` shows; one recursion that prints a sheet inside a template gives it no edit mode.
- A text literal of the code, such as `"Paper"`, draws no caret. Because a key edits only math code, each input of the examples is math code.
- The grid of `FormulaEnvironmentToTable` only shows the sheet.
- Each evaluation of code that holds a lambda makes a new function type in the scratch module of the editor, or of the wiring of the formula, as each line of the Julia REPL does. The cost grows with the computations of such a formula, not with the frames.
