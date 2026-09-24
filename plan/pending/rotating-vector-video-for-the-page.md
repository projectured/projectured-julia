# The rotating vector video, for the web page

> **Status:** in progress. Written 2026-09-24.

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
- [ ] Step 2: item 4 for the clock. `source/kernel/clock/Clock.jl` is sealed, so
      it waits for the owner's permission for that file.
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
- [ ] Step 4: item 3, the API proposal, shown to the owner (2026-09-24).
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
- [ ] Step 5: the script: items 1, 5, 6 and 9, and the forms of item 3.
- [ ] Step 6: record S1 again and give it to the owner.
