# The rotating vector video, for the web page

> **Status:** done. Written and implemented 2026-09-24, on the branch `feature-videos`.

The take of S1 of 2026-09-24 (`feature-video-screenplays.md`, §5 and Stage 4b)
is not yet good enough for the web page: it starts frozen, it is too long, and
some results and forms read badly. This plan holds the owner's decisions of
2026-09-24 and the work that follows from them.

## 1. The owner's decisions (2026-09-24)

> for 1, agree
> for 2, skip
> for 3, show me the API changes first, there's already a documentation rule how
> to handle functions with lots of positional arguments
> for 4, that's good

And the things the owner noticed:

> - add the axis at the end for the sin/cos
> - no need to return nothing when the result is not such a document which would
>   be presented and confuse the user
> - make sure that each julia form is turned into julia document for proper syntax
>   highlighting, some of them currently are not
> - if nothing is returned from a form, don't write done (that's weird), write
>   'nothing' just like Julia nothing would be printed from the Julia domain (I
>   guess it would use a different color)
> - instead of StyleColor(0, 0, 0, 0) use color_black? use predefined values if
>   they already exist

| # | Item | Decision |
| --- | --- | --- |
| 1 | The frozen start (F8) | A warm-up in the script: the first steps run once without recording. |
| 2 | The recorder times each key from the previous one | Skipped. |
| 3 | Shorter forms (A1) | The API change is shown to the owner first, under the rule "Arguments: three positional, then names" of `code-quality-rules.md`. |
| 4 | Readable results | A function shows as the REPL shows it; the clock gets a short display. |
| 5 | The axes of the traces | The last forms add the axes of the sine and the cosine traces. |
| 6 | `; nothing` at the end of a form | Only where the result would be a drawn document that confuses the viewer. |
| 7 | Syntax highlighting | Every form becomes a Julia document. |
| 8 | A result of `nothing` | Shows `nothing` as the Julia domain prints it, not `Done.`. |
| 9 | Colors | Predefined constants: `StyleColor(0.0, 0.0, 0.0, 0.0)` is `color_transparent` (its alpha is 0, so it is not black). |

The owner's answers to the three questions of 2026-09-24:

> for 1, I agree and extend it to other graphics domain constructors
> for 2, yes, agreed
> for 3, yes

| # | Decision |
| --- | --- |
| A | The API of item 3, for every constructor of the graphics domain: a geometric argument takes a number, a cell or a function of no arguments, and no optional positional argument stands beside a keyword. |
| B | The Julia domain keeps the keyword arguments of a call after `;` (a new field of `JuliaCall`), and prints a short function definition on one line. |
| C | `source/kernel/clock/Clock.jl` (sealed) may get a display, `Clock(time = 12.3)`. The permission is for this change of that file only. |

## 2. Steps

- [x] Step 1: item 4 for a function, and item 8.
      `_describe_last_value` of `CodeExecution.jl` shows a function as the REPL
      does, `phase (generic function with 1 method)`, through
      `Base.invokelatest`, because the code made the function in a newer world.
      This also changes what the assistant reads. The evaluator shows a
      `nothing` that printed nothing as the Julia `nothing`
      (`parse_natural_text(:jl, "nothing")`, a `JuliaNothing` in bold magenta);
      the tool keeps "Done." for a model. `test_code_execution()` and
      `test_evaluator_toplevel()` pass 233.
- [x] Step 2: item 4 for the clock, in the sealed `Clock.jl` with the owner's
      permission (decision C). `Base.show(io, ::Clock)` prints
      `Clock(time = 12.5)` with a sample of the time, so a display subscribes to
      nothing. The file stays sealed. `test_clock()` passes 16.
- [x] Step 3: item 7, find which forms stay strings and why.
      `build/suites/s1/probe_forms.jl` parses each form as the evaluator does and
      compares the print with the typed code, token by token. Four reasons:

      | Reason | Example | Where the fix is |
      | --- | --- | --- |
      | Keyword arguments after `;` print after `,` | `GraphicsCircle(90, 90, 60; color = …)` | The Julia domain: the parser flattens the `:parameters` of a call into its arguments on purpose (`JuliaParser.jl`, `_convert_head(::Val{:call})`), so `JuliaCall` has no place for `;`. Keeping it is a new field of `JuliaCall`, a change of the data model: the owner decides. |
      | A short function definition prints its right side on a new line | `phase() = -0.5 * …` prints `phase() = \n  -0.5 * …` | The Julia domain: Julia's parser wraps that right side in a block, and the domain prints a block over several lines. |
      | A number before a call prints with `*` | `60cos(x)` prints `60 * cos(x)` | The forms: write `60 * cos(x)`. |
      | Two statements on one line print on two lines | `push!(…); nothing` | The forms: item 6 removes most `; nothing`. |

      `clock = get_wall_clock()` and `push!(canvas.elements, dot)` become Julia
      already. A candidate form of the new API, such as
      `GraphicsPolyline(() -> [(170 + i, 90 - 60 * sin(phase() - i / 50)) for i in 0:120]; …)`,
      differs only by the `;`.
- [x] Step 4: item 3, the API proposal, shown to the owner (2026-09-24), and
      approved with decision A.
      Under §4 of `code-quality-rules.md`:

      ```julia
      GraphicsCircle(cx, cy, radius; color = color_black, border_width = 0, border_color = nothing)
      # @positional: the two ends of a line: x, y and x, y.
      GraphicsLine(x1, y1, x2, y2; color = color_black, width = 1, dash = nothing)
      GraphicsPolyline(points; color = color_black, width = 1, dash = nothing,
                       start_arrow = false, end_arrow = false, arrow_size = 8)
      ```

      1. Each geometric argument (`cx`, `cy`, `radius`, `x1` to `y2`, `points`)
         is a number, a cell, or a function of no arguments. A function becomes
         a computed cell, so the shape follows what the function reads. A number
         a function answers is rounded to a whole pixel, and so is each point.
      2. `color` of `GraphicsPolyline` becomes a keyword. Today it is an
         optional positional argument beside keywords, which the rule forbids.
         About 8 call sites change (charts, sequence charts, graph layout).
      3. Every call with numbers stays valid.

      The forms then read, for example:
      `dot = GraphicsCircle(() -> 90 + 60 * cos(phase()), () -> 90 - 60 * sin(phase()), 5; color = color_solarized_magenta)`.
      The four axes of the example are four `GraphicsLine`s of numbers.
- [x] Step 4a: decision A, the constructors of the graphics domain.
      `GraphicsDocument.jl`: `_make_pixel_cell`, `_make_points_cell` and
      `_make_text_cell` turn a number, a cell or a function into the cell of a
      field; a function becomes a `ComputedCell`, and a number is rounded to a
      whole pixel. `GraphicsText`, `GraphicsRect`, `GraphicsLine`,
      `GraphicsCircle`, `GraphicsPolyline`, `GraphicsPolygon`, `GraphicsSpline`,
      `GraphicsViewport`, `GraphicsImage` and the box of `GraphicsCanvas` take
      them. The color of `GraphicsPolyline`, `GraphicsPolygon` and
      `GraphicsSpline` is a keyword now; 14 calls in the chart, the sequence
      chart, the graph layout and two tests changed with it. `test_graphics` 35,
      `test_chart` 345, `test_graph` 369, `test_sequencechart` 279, and
      `test_substrate` 80451 with the known failures at the same places.
      **When this lands on `main`:** `omnet-julia`
      (`source/presentation/result/VectorPlot.jl:236`) passes the color of a
      polyline positionally and must change to `color = p.line_color` in the
      same step; `inet-julia` has no such call.
- [x] Step 4b: decision B, the keyword arguments after `;` and the short function
      definition in the Julia domain.
      `JuliaCall` has `keyword_arguments`, which the parser fills from the
      `:parameters` of a call; a keyword written after `,` stays in `arguments`.
      The printer draws a call as its name, the arguments `(a, b` and the
      keyword arguments `; k = 1)`, whose `; ` shows only when a keyword is
      there, so the paths of the arguments do not change. `@document` makes the
      constructor that turns a plain vector into a collection only for a struct
      with one collection (Rule C), so `JuliaDocument.jl` adds the two for a call
      by hand. The parser unwraps a body of one statement of every short
      function definition, not only of one with `where`. The formula slice builds
      its own `Expr` of a call and carries the keywords in `:parameters`.
      `phase() = …` and `f(a; k = 1)` print back as written. `test_julia` 133,
      `test_evaluator_toplevel` 210, and the navigation of `julia_example` 84
      pass with the same 28 positions unreached as the baseline.
      **Found, and not fixed:** `test_formula` fails 12, `test_fsm` 23 and
      `test_process` 108, and all of them come from `main`. Commit 154f3306
      ("a pasted object runs as itself") puts `Document => JuliaObjectToSyntaxLeaf()`
      last in the table of `JuliaToSyntax`, and the formula, FSM and process
      projections copy that table and append their own rows after it, so the
      catch-all row wins: a formula reference draws `⟨FormulaReference⟩`, a
      component `⟨FsmComponent⟩`.
- [x] Step 4c: a lambda keeps its parentheses as the code wrote them. The new
      forms need a helper, `draw!(elements...) = foreach(element -> …, elements)`,
      and the domain printed `element -> …` as `(element) -> …`, so the form kept
      its string. `JuliaLambda` has `parenthesized` (default `true`), which the
      parser sets from the shape Julia gives, `(x) -> …` or `x -> …`. The
      evaluator test that named `map(x -> x^2, [1, 2])` as a form that keeps its
      string now names `y = 2x + 1`, and a new check says that a lambda, a
      keyword after `;` and a short definition become Julia.
      `test_evaluator_toplevel` 213, `test_julia` 133, the Julia navigation with
      the same 28 unreached positions. All 13 forms of the new take become Julia
      documents (`build/suites/s1/probe_forms.jl`).
- [x] Step 5: the script: items 1, 5, 6 and 9, and the forms of item 3.
      `tool/video/s1_forms.jl` holds the 13 forms; `record_rotating_vector.jl`
      types them and first runs the warm-up. The helper is `add!`, because
      `draw!` is a name of the graph layout port (`LcgRandom.jl`), which the
      evaluator sees. `build/suites/s1/probe_evaluate.jl` evaluates the forms
      headless before a take: all 13 are Julia documents, and none fails.
- [x] Step 6: record S1 again and give it to the owner.
      The take of 2026-09-24 (`build/video/rotating_vector_v3.mp4`, 220.2 s,
      3.8 MB), on `main` at c6da5faf: the evaluator opens at 1 s, every form has
      the colors of the Julia notation, each `add!` answers `nothing`, and the
      axes come last. Three things remain:
      1. **A Julia form does not wrap.** The Julia notation never breaks a line,
         so a long form is cut at the edge of the left pane; as a string it
         wrapped. This waits for the owner: a soft wrap for Julia code, in the
         evaluator or everywhere, is a design choice.
      2. **The length.** 220 s, over the 3 min of D5.
      3. **The time of the clock** has all its digits: `Clock(time = 39.41121697425842)`.

      The owner on the take: "the video looks perfectly fine, no need to deal with
      too long Julia lines", "the video length should be shortened by faster
      typing", and asked why the circle and the curves are not anti-aliased.

      - **Faster typing:** `hold = 0.06, jitter = 0.5` in place of the rhythm of
        D13. The take lasts 113.8 s.
      - **Anti-aliasing:** the SDL backend draws every shape without it and gets
        smooth edges from supersampling: it draws the frame larger and scales it
        down. A live window supersamples at 2 (`PROJECTURED_SUPERSAMPLE`), but
        `record_application_video` defaulted to 1, so S1, S2 and S4 were drawn
        at 1 and their curves were jagged. Its default is 2 now, as a live
        window's; the test of the recorder passes 1 for speed. A small step stays
        on a curve, because the points of a polyline are whole pixels.
      - The take of 2026-09-24 at 2 (`build/video/rotating_vector_v4.mp4`,
        113.8 s, 2.0 MB, 3413 frames at 30 per second, the animation at the full
        rate).
      The owner accepted this take for the web page (2026-09-24): it is the second
      video of the Videos section of `projectured.github.io` (commit 41a726b
      there), and the JSON video there links `JsonDocument.jl` and
      `JsonToSyntax.jl`. The JSON take was drawn at 2 already (`record_video`
      defaults to 2), so it was not recorded again.
