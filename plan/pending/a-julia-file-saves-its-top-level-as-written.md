# A Julia file saves its top level as written

Status: IN PROGRESS. Step 1 is done.

## The ask

The plan [every-kind-of-julia-code-prints-with-no-compile.md](../done/every-kind-of-julia-code-prints-with-no-compile.md)
found a fault outside its steps: a save of a Julia file with more than one
statement changes the layout of the whole file. On 2026-11-01 the owner agreed to
fix it so that the top level is a node of its own, as in Julia ("Agreed"). The
owner then answered "Yes" to the question "Shall the top level of a file be a
`JuliaToplevel` with a layout field?"

## The problem

`parse_julia` makes the top level of many statements a `JuliaBlock`
(`source/domain/julia/JuliaParser.jl:69`), the same type as the body of a
`function` or a `while`. A block prints a break before each statement and indents
it (`JuliaBlockToSyntaxNode`, `source/domain/julia/JuliaToSyntax.jl:815`). That is
correct for a body and wrong for a file. Printed on main 50f94f5b9:

| Code | Print |
| --- | --- |
| `"x = 1\ny = x + 1\n"` | `"\n  x = 1\n  y = x + 1"` |
| `"function f(x)\n    x + 1\nend\nf(2)\n"` | `"\n  function f(x)\n    x + 1\n  end\n  f(2)"` |

Julia reads the same code from both, so the round trip test of the workload file,
which compares the parsed code, does not see the fault. The code of a component of
the FSM domain without a module (`FsmToJuliaCode.jl:436`) is a root `JuliaBlock` too.

Julia itself tells the two apart: its parser gives `:toplevel` for a file and
`:block` for a body. `JuliaToplevel` already stands for `:toplevel`, but only for
statements on one line, `a = 1; b = 2`. The only difference is the layout.

## The design

1. **`JuliaToplevel` gets a layout field.** `on_one_line::Bool = false`. With
   `true`, the statements print on one line with `; ` between them, as now. With
   `false`, each statement prints on a line of its own, with no break before the
   first one and no indentation. The field name follows the other layout fields
   of the domain (`parenthesized`, `bare`, `trailing_semicolon`). *My decision:*
   the default is `false`, because a generator writes a file, and only the parser
   makes `a; b`.
2. **The print.** `JuliaToplevelToSyntaxNode` takes its separator from the field:
   `"; "` or a break. The separator is a computed text, as the `else` prefix of
   `if` is (`make_text_block`). The close text stays: a `;` when
   `trailing_semicolon`.
3. **The parser.** `parse_julia` returns `JuliaToplevel(statements)` for more than
   one statement. `_convert_head(::Val{:toplevel})`, the nested `a; b`, makes a
   `JuliaToplevel` with `on_one_line = true`. These do not change:
   - a file of one statement parses to that statement alone;
   - an empty file parses to an empty `JuliaToplevel`, which prints `""`;
   - `trailing_semicolon` stays on the `JuliaToplevel` of the last line;
   - the body of a `module` stays a `JuliaBlock`, because Julia gives it `:block`.
4. **The code that reads a root.**
   - `get_julia_expression_without_comments` (`JuliaDocument.jl:372`) takes the
     one statement out of a `JuliaToplevel` too. A formula with a comment needs it.
   - `_julia_toplevel_statements` (`JuliaFile.jl:129`) takes a `JuliaToplevel`, so
     the `definition` verb finds the definitions of a file.
   - The FSM generator makes a `JuliaToplevel` for a component without a module.
   - The formula walk of free names and the statement helper of the FSM generator
     already take a `JuliaToplevel`.

5. **Found in step 1: the evaluator and the conversation.** The evaluator keeps
   typed code as a plain string when the print of the parsed code puts a token
   on another line (`find_form_document`, `_has_same_tokens` in
   `source/platform/conversation/Evaluator.jl`). The old print added a first
   break, so code of several statements always stayed a plain string. Now it
   parses to a `JuliaToplevel` with its colours, which is what the check is for.
   The conversation of the assistant parses the code of a call with no such check
   (`_eval_form_doc`), so it showed the first empty line and the indentation; now
   it shows the code as written. `EvaluatorToplevelTest.jl` asserted the plain
   string and asserts the `JuliaToplevel` now. Its history test made a string
   form from two statements; it makes one from a juxtaposed product, `x = 2pi`,
   which the print writes as `2 * pi`.

What this plan does not change:
- the indentation of the body of a `module`;
- the keyword parameters of an anonymous function (the next open item);
- the unit of indentation of the print, two spaces: a body written with four
  spaces saves with two;
- the generated files of inet-julia, `t1s/MacFsm.jl` and `t1s/PlcaFsm.jl`, which
  show the fault now (two empty lines, two spaces before each top-level line). A
  new generation with this change writes them without it.

## The steps

1. [x] **The top level is a `JuliaToplevel`.** The design above, its docstrings,
   and the paragraph of `documentation/package/domain/julia/julia.md` that names
   the top level. That paragraph also says that `begin … end` becomes a
   `JuliaBlock`, which is wrong since 5a65e8d69; it becomes a `JuliaBegin`.
   Tests:
   - `JuliaParserTest.jl`: `_has_julia_statements` and the assertions of a root
     `JuliaBlock` take a `JuliaToplevel`. New round trips that compare the text,
     not the parsed code: the two examples above; a file with an `a; b` line
     among other lines; a file that ends with `x = 1;`; an empty file.
   - `JuliaWorkloadFileTest.jl`: the root of the workload file is a `JuliaToplevel`
     whose print starts with its first statement.
   - `FileProjectTest.jl:377` makes its Julia page as a `JuliaToplevel`.
   - The FSM test of a component without a module.

   As built: the parser passes the field by position,
   `JuliaToplevel(statements, false, true)`, as it passes the other layout fields;
   the `@document` constructor takes no keyword next to a raw vector. The
   docstrings of `JuliaBlock` and `JuliaEmpty` say what they are now. Tests:
   `test_julia_parser()`, `test_julia_workload_file()`, `test_julia_to_syntax()`
   227 of 227; `test_fsm_to_julia_code()` 46 of 46; `test_evaluator_toplevel()` and
   `test_file_project()` 408 of 409, with 1 known `@test_broken` (the Julia page).
2. [ ] **The wider check.** On the branch and on main 50f94f5b9, each in a process
   of its own:
   - `test_julia()` (744 on main), `test_fsm()`, `test_process()`, `test_formula()`;
   - `test_example(julia_example)` and `test_example(julia_code_example)`. Main has
     507 known type-in failures there. The printer and navigation counts can
     change, because the empty first line goes away. So a probe compares the
     drawn caret places of each reached state, on the branch and on main.
   - `test_julia_file_view()`, the view of a file as the window draws it;
   - `test_evaluator_toplevel()`, `test_file_project()` and `test_application()`
     of the umbrella suite: an evaluated form of several lines draws as Julia now.
3. [ ] **The precompile lists.** The template of `JuliaToplevelToSyntaxNode`
   changes, so recorded calls that name it or a later closure of its file no
   longer resolve. Record again, in this order: `ProjecturedJulia`,
   `ProjecturedExample`, then the application `projectured`. Then check that a
   load of `ProjecturedAll` gives no warning about a stale list.
4. [ ] **The landing.** Report the result and ask the owner. After the landing of
   projectured-julia, record again on omnet-julia main: `OmnetPresentationExample`,
   `OmnetIde`, then the application `omnet_ide`, and ask to land that commit too.
