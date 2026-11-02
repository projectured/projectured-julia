# A Julia file saves its top level as written

Status: DONE.

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

6. **Found in step 2: the notation of the FSM domain.** The FSM examples and the
   generator scripts of inet-julia make the entry of a state and the action of a
   transition with `parse_julia` of a snippet. An entry of two statements was a
   `JuliaBlock` only because the parser made every snippet of many statements a
   body; the notation printed it below `entry /`, indented, by the break and the
   indentation of the block. As a `JuliaToplevel`, its first statement stayed on
   the `entry /` line and the second went to the column of `entry`, so it read as
   two lines of the state (`FsmToSyntaxTest.jl:29` failed). *My decision:* the
   notation lays out the code itself. `_project_fsm_code` in `FsmToSyntax.jl`
   puts code of statements on lines of their own on the next line, indented, and
   keeps any other code on the line of the keyword; the entry and the action use
   it. The template body gives it the `project(:entry)` or `project(:action)`
   slot, because `@projection_template` resolves its marker words only in the
   body. The document keeps what the parser gives, and the generator already makes
   a body of any entry or action (`_block`). The other way was a parse of a body
   in the Julia domain that the FSM authors call, which needs a new function and
   a change at 15 sites of the examples and in the scripts of inet-julia.

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
2. [x] **The wider check.** On the branch and on main 50f94f5b9, each in a process
   of its own:
   - `test_julia()` (744 on main), `test_fsm()`, `test_process()`, `test_formula()`;
   - `test_example(julia_example)` and `test_example(julia_code_example)`. Main has
     507 known type-in failures there. The printer and navigation counts can
     change, because the empty first line goes away. So a probe compares the
     drawn caret places of each reached state, on the branch and on main.
   - `test_julia_file_view()`, the view of a file as the window draws it;
   - `test_evaluator_toplevel()`, `test_file_project()` and `test_application()`
     of the umbrella suite: an evaluated form of several lines draws as Julia now.

   As run, branch against main 50f94f5b9:
   - `test_julia()` 759 pass, with `test_julia_file_view()`; `test_process()` 316
     and `test_formula()` 308 pass.
   - `test_fsm()` 273 pass against 271. The notation fix of design item 6 makes
     `FsmToSyntaxTest.jl:29` pass.
   - The FSM examples have the same failures as main: `fsm_toggle` 488,
     `fsm_crossing` 1929, `fsm_alternating_bit` 2664; each has about 100 more
     passes. `fsm_example` passes its printer, reader and REPL tests on both;
     its navigation does not end in 45 minutes on main either, so it is not run.
   - `julia_example` has the same 84 type-in failures; `julia_code_example` the
     same 423. The printer of `julia_code_example` has 16,529 checks against
     16,938, and its navigation 373 against 420, because no state is on the empty
     first line now. The probe finds 346 distinct caret places on both sides,
     equal after a shift of (14, 14), the width of the line that went away.
   - `test_application()` 387 pass against 386, with the same 2 failures as main
     (`ApplicationTest.jl:677` and `:789`) and 2 broken. Two of its checks
     changed: the evaluator check reads the column of a code line from the drawn
     text, and a form of two statements prints as written.
3. [x] **The precompile lists.** The template of `JuliaToplevelToSyntaxNode`
   changes, so recorded calls that name it or a later closure of its file no
   longer resolve. Record again, in this order: `ProjecturedJulia`,
   `ProjecturedExample`, then the application `projectured`. Then check that a
   load of `ProjecturedAll` gives no warning about a stale list.

   As run: the recording took 23 minutes, with a peak of 8.6 GB. The application
   recording also records the list of `ProjecturedBuild`, which names
   `JuliaToplevel` too. 12 lists changed. The Julia workload list holds 14 calls
   of `JuliaToplevelToSyntaxNode` against 4, because the workload file prints as
   a `JuliaToplevel` now. `using ProjecturedAll` gives no warning. A load of
   `ProjecturedExample` and `ProjecturedBuild`, which `ProjecturedAll` does not
   load, gives none either. A warning shows only past 10% of stale calls, so a
   count of the calls that no longer resolve compares each list with main: the
   `ProjecturedBuild` workload 3 of 3672 against 44 of 3721, the
   `ProjecturedExample` workload 18 of 7500 against 35 of 7464, the
   `ProjecturedPlatform` application list 0 of 2045 against 40 of 2010, the
   `ProjecturedKernel` application list 3 of 291 against 3 of 288, and 0 in the
   other 8 lists.
4. [x] **The landing.** Report the result and ask the owner. After the landing of
   projectured-julia, record again on omnet-julia main: `OmnetPresentationExample`,
   `OmnetIde`, then the application `omnet_ide`, and ask to land that commit too.

   As done: on 2026-11-02 the owner answered "Yea" to the landing of
   projectured-julia, which is a fast-forward merge of `julia-top-level` on main
   50f94f5b9, d60e75c21.

   On omnet-julia, branch `julia-top-level` from main f95c6f138 records the lists
   again as 5e2c3cbc5: `OmnetPresentationExample`, `OmnetIde`, then `omnet_ide`,
   whose recording also records `OmnetIdeBuild` and `OmnetLegacyFormat`. It ran
   from the projectured environment with `root` and `environment` of the omnet
   worktree, because the omnet environment has no `ProjecturedPrecompile`; the
   peak was 9.9 GB of a 10 GB cap. The calls that no longer resolve, against
   the lists of omnet main on the same projectured code: `OmnetIde` 0 of 1026
   against 9 of 1034 and 1 of 3633 against 1 of 3584, `OmnetIdeBuild` 3 of 1260
   against 4 of 1256, `OmnetLegacyFormat` 3 of 1373 against 3 of 1392,
   `OmnetPresentationExample` 13 of 8033 against 22 of 8012. No load gives a
   warning.
