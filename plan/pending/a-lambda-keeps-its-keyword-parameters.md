# A lambda keeps its keyword parameters

Status: PENDING.

## The ask

The plan [a-julia-file-saves-its-top-level-as-written.md](../done/a-julia-file-saves-its-top-level-as-written.md)
left one open item of the Julia print: the keyword parameters of an anonymous
function. On 2026-11-02 the owner answered "Yes" to the question "Shall
`JuliaLambda` hold its keyword parameters in a field of its own,
`keyword_parameters`, as `JuliaFunction` does?"

## The problem

`parse_julia` puts the keyword parameters of a lambda among its positional
parameters, so a save changes what the code means. Printed on main 037307cf2:

| Code | Print | Julia reads the print as |
| --- | --- | --- |
| `(x; y = 1) -> x + y` | `(x, y = 1) -> x + y` | `y` is an optional positional parameter |
| `(x, z; y = 1, w) -> x` | `((; y = 1, w), x, z) -> x` | a first parameter that destructures a named tuple |
| `function (x; y = 1) … end` | `((; y = 1), x) -> x + y` | the same as the row above |
| `(; y = 1) -> y` | `((; y = 1)) -> y` | the same code, with one more pair of parentheses |

Julia writes the parameters of a lambda in two forms:
- a tuple, `(x, z; y = 1, w)`: the keyword parameters are in its leading
  `Expr(:parameters, …)`. `(; y = 1)` is a tuple with no positional parameter.
- a block, `(x; y = 1)`: Julia reads its first element as the one positional
  parameter and its second as the one keyword parameter. A block of one element,
  `(x;)`, is one positional parameter. Two semicolons are an error in Julia.

The parser converts the `Expr(:parameters)` to a `JuliaNamedTuple`
(`_convert_head(::Val{:parameters})`, `JuliaParser.jl:702`), and it takes each
element of the block as a positional parameter (`JuliaParser.jl:537`). The long
anonymous form `function (x; y = 1) … end` makes a `JuliaLambda` too
(`JuliaParser.jl:817`), with the same fault. The plan of the Julia print gave
`JuliaFunction` the field `keyword_parameters` for the same fault of a named
function.

## The design

1. **`JuliaLambda` gets `keyword_parameters`.** A last field,
   `keyword_parameters::CellVector{JuliaDocument}`, empty by default. As the last
   field, it keeps the positional constructor calls valid: the parser
   `(parameters, body, parenthesized)` and `MathToJulia.jl:135` `(parameters, body)`.
   `@document` makes a constructor from a plain vector only for a struct with
   one collection, so an outer constructor takes plain vectors, as the one of
   `JuliaFunction` does. The docstring names the field.
2. **The parser.** One helper splits the parameters of a lambda for the three
   places:
   - a tuple: the elements of a leading `Expr(:parameters)` are keyword
     parameters, the other elements are positional parameters;
   - a block of two elements: the first is positional, the second is a keyword;
   - a block of one element: one positional parameter;
   - a single name, `x -> …`: one positional parameter, as now.
   A keyword parameter converts as the keyword parameter of a `function` does,
   so `y = 1` is a `JuliaAssignment` and `y` is a `JuliaIdentifier`.
3. **The print.** `JuliaLambdaToSyntaxNode` writes the keyword parameters after
   the positional ones, as `JuliaFunctionToSyntaxNode` does: a second collection
   that opens with `; ` only when it holds a parameter, and that closes the list
   with `) -> `. So `(x; y = 1) -> x + y` prints as written, and `(; y = 1) -> y`
   prints with one pair of parentheses. *My decision:* a block form prints as
   the tuple form, `(x; y = 1)`, which is the same text. A lambda with a keyword
   parameter is always parenthesized, because the parser sees one only in
   parentheses.
4. **The formula.** `_collect_free_identifiers!` of a `JuliaLambda`
   (`FormulaDocument.jl:276`) binds the keyword parameters too, as the method of
   a `JuliaFunction` does. A default of a keyword can name a free variable of the
   formula: in `(x; y = a) -> x + y`, `a` is free and `y` is not.
5. **The workload file.** `_WORKLOAD_FILE_TEXT` (`JuliaModule.jl:150`) gets a
   lambda with a keyword parameter next to `x -> x + 1`, so the image of the
   package holds the print of the keyword part, and a window that shows such a
   lambda compiles nothing new.

What this plan does not change:
- the long anonymous form keeps its print as a short lambda,
  `function (x) … end` → `(x) -> …`;
- the arguments of a `do` block.

## The steps

1. [x] **A lambda holds its keyword parameters.** The design above, with its
   docstring. Tests:
   - `JuliaParserTest.jl`, a new test set next to "a long function keeps its
     keyword parameters after the `;`": the round trips of
     `(x; y = 1) -> x + y`, `(x, z; y = 1, w) -> x`, `(; y = 1) -> y` and
     `g = function (x; y = 1)\n  x + y\nend` (which prints as
     `g = (x; y = 1) -> x + y`), each also with `_julia_prints_back`; the counts
     of the two lists of `(x, z; y = 1, w) -> x`.
   - `FormulaNameTest.jl`: the free names of a formula with `(x; y = a) -> x + y`.
   - `test_julia_workload_file()` with the new line of the workload file.
   *Done:* `test_julia_parser()` 210 pass, `test_julia_workload_file()` 8,
   `test_formula_names()` 39. The parser helper is `_convert_lambda_parameters`;
   the long anonymous form uses it too, because its signature is always a tuple.
   The printer puts the close `) -> ` on the second collection, so the first one
   has no close, as the parameters of a named function have none.
2. [x] **The wider check.** On the branch, each in a process of its own:
   `test_julia()` (759 on main), `test_formula()` (308),
   `test_example(julia_example)` and `test_example(julia_code_example)`, against
   the type-in baseline of main: 84 and 423 failures.
   *Done:* `test_julia()` 768 pass (759 + the 9 new tests), `test_formula()` 309
   (308 + 1). `test_example(julia_example)` 3443 pass and 84 failures,
   `test_example(julia_code_example)` 17554 pass and 423 failures: each failure
   is the known "no cursor" at `TypeinTest.jl:747`, as on main.
3. [x] **The precompile lists.** The template of `JuliaLambdaToSyntaxNode`
   changes, and the workload file has a new line. Record again, in this order:
   `ProjecturedJulia`, `ProjecturedExample`, then the application `projectured`.
   Count the calls that no longer resolve in each changed list, against main,
   and check that a load of `ProjecturedAll`, `ProjecturedExample` and
   `ProjecturedBuild` gives no warning.
   *Done:* the record changed eight lists: the two of `ProjecturedJulia`, the
   workloads of `ProjecturedExample` and `ProjecturedBuild`, and the application
   lists of `ProjecturedKernel`, `ProjecturedPlatform`, `ProjecturedSDL` and
   `ProjecturedYAML`. The lambda has one more cell, so each call that names its
   type changes. Stale calls on the code of the branch, the list of main against
   the new list: `ProjecturedJulia` workload 29 of 1903 against 0 of 1900, its
   application list 8 of 760 against 0 of 763, `ProjecturedExample` 29 of 7500
   against 18 of 7484, `ProjecturedBuild` 11 of 3672 against 3 of 3711,
   `ProjecturedKernel` 3 of 291 against 3 of 291, and 0 in the others. The 18, 3
   and 3 that stay are the counts after the last record of main. The workload of
   `ProjecturedExample` fails 3 of 135 examples, as on main. The precompile with
   the new lists and a load of the three packages give no warning.
4. [ ] **The landing.** Report the result and ask the owner. After the landing of
   projectured-julia, record again on omnet-julia: `OmnetPresentationExample`,
   `OmnetIde`, then the application `omnet_ide`, and ask to land that commit too.
