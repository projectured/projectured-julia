# A `;` hides the result, and every form of S7 is a Julia document

**Status: done, on the branch `s7-reflective-video`.** The owner asked for
it on 2026-09-26, after the rehearsal of screenplay S7
(`plan/pending/feature-video-screenplays.md`): "use the semicolon. Some forms still
don't parse and turn into Julia documents".

## Problem

The rehearsal of S7 found two faults of the evaluator:

1. **A result that nobody asked to see.** `push!(toolbar.elements, WidgetToolbarItem("Hello"))`
   returns the `CellVector` of the buttons. That is a document, so the evaluator
   draws it: a column of nine icons, 300 px high. The Julia REPL hides the result
   of a line that ends with `;`, and the evaluator does not.
2. **Forms that keep their string.** A form becomes a Julia document only when the
   parse prints back the same tokens (`find_form_document`). Two gaps of the Julia
   domain break that:
   - `isa`, `in`, `∈`, `=>`, `|>`, `%` and the dotted operators parse to a
     `JuliaCall` and print as a prefix call: `d isa Workspace` prints as
     `isa(d, Workspace)`, and `a => b` as `=>(a, b)`.
   - `Meta.parseall` marks a `;` list on one line with an inner `Expr(:toplevel, …)`.
     The parser turns it into a `JuliaBlock`, which prints as an indented block of
     lines, so `a; b` and `x = 1;` lose their `;`.

## Design

1. **The infix operators.** `BINARY_OPERATORS` holds `isa`, `in`, `∈`, `∉`, `=>`,
   `|>`, `%`, `÷` and the dotted forms of the arithmetic and comparison operators.
   `_julia_precedence` follows the table of the Julia manual: `=>` binds looser
   than `||`, `isa`, `in`, `∈` and `∉` are comparisons, `|>` binds tighter than a
   comparison and looser than `+`, `%` and `÷` bind as `*`, and a dotted operator
   binds as the operator without the dot. `=>` associates to the right.
2. **`JuliaToplevel`, the `;` list on one line.** A new node of the Julia domain,
   named after the `Expr` head that the Julia parser gives it:
   `JuliaToplevel(statements; trailing_semicolon = false)`. It prints its
   statements on one line with `; ` between them, and a `;` after the last one
   when `trailing_semicolon` is true. `parse_julia` sets that field when the last
   token of the code, apart from a comment, is `;`. A `;` inside a `begin` block
   still parses to a `:block`, so it stays a `JuliaBlock`.
3. **The evaluator hides the result of a form that ends with `;`.** The rule is
   the rule of the Julia REPL: the last token of the code, apart from a comment,
   is `;`. The code runs, what it prints still shows, and the value is not drawn.
   The rule reads the source text of the form, so it holds for a string form and
   for a form that is a Julia document.

## Steps

- [x] 1. The infix operators parse to `JuliaBinaryOperation`, with the precedence
  of the Julia manual. Round-trip tests in `test/julia/document/JuliaParserTest.jl`.
  - A dotted comparison is written `Symbol(".==")`: in Julia 1.13 `:(.==)` is an
    `Expr` of the dotted operator, not a `Symbol`.
  - A comparison still associates to the left in the printer, as before. A rule
    that put parentheses around a comparison inside a comparison broke
    `a < b < c`, which the parser folds to the left and which is much more common.
    So `(a < b) == c` still prints without its parentheses: the domain has no node
    for a chained comparison. That gap is older than this plan.
- [x] 2. `JuliaToplevel`: the node, its parse, its syntax projection and its
  export. Round-trip tests for `a; b`, `x = 1;`, `a; b;`, a `;` before a comment,
  and a line of a block that ends with `;`.
  - `statements` has no default, so `@document` keeps the positional
    constructors: the parser calls `JuliaToplevel(statements, true)`.
  - `test_julia()`: 392 pass, none fails.
  - The FSM code generator (`source/fsm/FsmToJuliaCode.jl`) reads an action of
    a `;` line as the statements of a block, as it did when that line was a
    `JuliaBlock`, so the generated code keeps one statement on each line.
- [x] 3. The evaluator hides the result of a form that ends with `;`. Tests in
  `test/projectured/editor/EvaluatorToplevelTest.jl`: the forms of S7 become
  Julia documents, and a `;` hides the result but keeps what the code prints.
  - The value is described with an empty text, so the output holds only what the
    code printed; with nothing printed, the result is an empty `TextBlock`, which
    draws no result row. An error still shows.
  - A form that holds a pasted object has no source text, so a `;` after the
    object does not hide it.
  - The evaluator marks an error by the words `ERROR` or `Error` in the output,
    so `error("stop")` is shown but not marked. That rule is older than this plan.
  - `test_evaluator_toplevel()`: 237 pass. `test_julia()`: 392 pass.
    `test_conversation()`: 166 pass, 1 fail, the layering guard that fails on main.
  - `test_fsm()` 23, `test_formula()` 12 and `test_process()` 108 fail, and the
    cause is not in this branch: since commit 154f3306 the table of
    `JuliaToSyntax` ends with the catch-all `Document => JuliaObjectToSyntaxLeaf()`,
    and `FsmToSyntax`, `FormulaToSyntax` and `ProcessToSyntax` append their own
    entries after it, so their notation prints `⟨FsmComponent⟩` and the like.
    `FsmToJuliaCode` passes 39 of 39.
- [x] 4. The documents: `documentation/package/julia/julia.md`, the evaluator
  document, and the docstring of `find_form_document`.
- [x] 5. The S7 forms use `nameof(typeof(…))` (the owner's choice for the type
  names) and a `;` after `push!`, and the take is recorded
  (`tool/video/record_reflective_editor.jl`; the take is described in S7 of
  `plan/pending/feature-video-screenplays.md`).
