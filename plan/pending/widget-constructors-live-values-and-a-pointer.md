# Widget constructors without a position, live values, and a pointer in a video

> **Status:** in progress. Written 2026-09-24.

S4 ("A tool window from widgets") types forms that are long and do not become
Julia documents. The owner decided five changes on 2026-09-24, after the take
`build/video/widget_tool_v2.mp4`.

## 1. The owner's decisions (2026-09-24)

> point 1, I agree with the widget changes, I would even change the default
> button size to nothing meaning that the button fits its label, I agree with
> your recommendation
>
> point 2, agreed
>
> A5, fixed by point 2
> A6, closed
> G3, yes, on by default for recording a video

and before:

> for 3, I agree (add! helper)
>
> for point 6, yes better
>
> also, make sure all typed-in forms are properly parsed into Julia documents
> and printed with style just like in earlier videos

1. **The position of a widget becomes a keyword**, `position = Point2D(0, 0)`,
   in one shape: every constructor and every call change at once (the
   recommendation (a)).
2. **A widget that shows a value takes a function** where it shows it.
3. **S4 defines an `add!` helper**, as S1 does, so no form ends with `; nothing`.
4. **A5** is covered by 2. **A6 is closed**: a `WidgetComposite` places each
   child at the child's own position, which is its purpose.
5. **The video backend draws the mouse pointer**, on by default.
6. **S4 shows each widget at work when it is added**: the presses after the label
   that counts them, the drag after the label that reads the slider.
7. **Every typed form becomes a Julia document.**
8. **A cell that is the result of a form is shown live** (2026-09-24): "for the
   cell I vote for option 2", "add option 2 for the cell to the plan". The
   result row of `presses = Cell(0)` shows `Cell(0)` and follows the cell, so it
   counts up with the presses of the button.

## 2. What exists

- 27 widget types take the position as their first positional argument, in 56
  hand-written constructors (`build/suites/s4/list_widget_ctors.log`). Three more
  (`WidgetScrollBar`, `WidgetScrollPane`, `WidgetTransformPane`) have a
  `position` field that is not first; they do not change. `@document` generates
  only the constructors that take every field, so a constructor with the content
  first collides with none.
- Calls with a literal `Point2D(…)` first: 600 in projectured-julia (529 of them
  `Point2D(0, 0)`), 222 in omnet-julia (all `Point2D(0, 0)`), none in
  inet-julia. A call that passes a variable as the position also exists and is
  found by a scan of the syntax tree, not by a text search.
- The documents that teach the old shape: `documentation/package/widget/widget.md`,
  `documentation/package/pane/pane.md`, the example of
  `documentation/rule/code-quality-rules.md` §4, the docstrings, and 7 Markdown
  files of omnet-julia. A plan under `plan/done/` is history and does not change.
- No file under `source/kernel/`, the one sealed folder, calls a widget
  constructor.
- A form of the evaluator becomes a Julia document when its print has the same
  tokens as the typed code (`_parse_evaluated_form!`, `Evaluator.jl`). A form with
  `;` prints as an indented block of several lines, so it stays a string: that is
  why the S4 forms with `; nothing` were drawn plain. The probe
  `build/suites/s4/probe_forms.jl` shows that each proposed form of §3.6 becomes a
  Julia document. A string that interpolates a bare name, `"a $x b"`, prints as
  `"a $(x) b"` and stays a string; S4 does not use it.
- `Cell(f)` holds a function as a plain value; only a computed cell, `Cell(@computation f())`, follows it.
  So `WidgetLabel(position, () -> …)` draws the function (A2).

## 3. The design

### 3.1 The position is a keyword

Each of the 56 constructors loses its positional `position` and takes
`position::Point2D = Point2D(0, 0)` as a keyword. The rest keeps its order.

| Now | After |
| --- | --- |
| `WidgetLabel(position, content; …)` | `WidgetLabel(content; position, …)` |
| `WidgetText(position, content; width, …)` | `WidgetText(content; position, width, …)` |
| `WidgetButton(position, size, content; action, …)` | `WidgetButton(content; position, size = nothing, action, …)` |
| `WidgetSlider(position, value = 0.5; width, …)` | `WidgetSlider(value; position, width, …)` |
| `WidgetProgress(position, value = 0.0; …)` | `WidgetProgress(value; position, …)` |
| `WidgetTable(position, headers, rows; …)` | `WidgetTable(headers, rows; position, …)` |
| `WidgetTable(position; column_headers, …)` | `WidgetTable(; position, column_headers, …)` |

- **The size of a button** is a keyword, `size = nothing`, and `nothing` is a
  button that fits its label. The field keeps a `Point2D`: `nothing` becomes
  `Point2D(0, 0)`, which the printer already reads as "fit the content", because
  an authored width and height are minimums.
- **A value that was an optional positional argument becomes required**, because
  the rule allows no optional positional argument beside keyword arguments. A
  call that left it out passes the old default.
- **The rule document** changes its example to
  `WidgetLabel(content; position, text_style, padding, tooltip)`.

### 3.2 The calls

Every call changes in the same commit as the constructors. A call that passes
`Point2D(0, 0)` loses the argument; any other position becomes
`position = …`. A button size of `Point2D(0, 0)` goes; any other size becomes
`size = …`. A scan of the syntax tree lists every call of the 27 constructors
before the change and checks after it that no call has the old arity.

omnet-julia changes its 222 calls on a branch of its own, tested against the
projectured-julia worktree through a scratch environment. It lands right after
projectured-julia, because its main breaks from the moment the new constructors
land.

### 3.3 A function where a widget shows a value

The same rule as the graphics of S1: a value, a cell, or a function of no
arguments, and a function becomes a computed cell, `Cell(@computation f())`,
that follows what it reads.

- `WidgetLabel(content)`: a string, a document, a cell or a function. An answer
  that is neither a string nor a document shows as `string(answer)`.
- `WidgetProgress(value)`: a number, a cell or a function.
- A cell of `WidgetTable(headers, rows)`: a function becomes a live label.
- Not a value that a person edits (the content of `WidgetText`, the value of
  `WidgetSlider`): a function there would make a field that can not be edited.

### 3.4 The pointer in a video

`VideoBackend(…; pointer = true)` and `record_application_video(…; pointer = true)`.

- The pointer appears at the first mouse event of a take, and stays where the
  last one left it.
- `write_to_devices` draws the window canvas inside a canvas of its own and the
  pointer on top: an arrow (`GraphicsPolygon`, white with a dark border), a ring
  around the tip while the left button is held, and the ring fading out for
  about 0.3 s after the release. The canvas is made for the frame only, so
  nothing enters the document of the application; the supersampling draws it
  smooth.
- The time of the fade is the time of the backend's schedule: the video time
  when the take keeps it, the wall clock otherwise.

### 3.5 Every typed form is a Julia document

The evaluator's own test becomes a function of its API:
`find_form_document(code)` answers the Julia document of the code, or `nothing`
when the code would stay a string. `_parse_evaluated_form!` uses it, and the
scripts of S1 and S4 call it on each of their forms before the take and stop
with the list of the forms that would stay strings.

### 3.6 The forms and the order of S4

```julia
presses = Cell(0)
button = WidgetButton("Press me"; action = () -> presses[] += 1)
tool = VerticalLayout([button]; gap = 12)
      # Alt+click, split, paste, name the pane "My tool"
add!(widgets...) = foreach(widget -> push!(tool.children, widget), widgets)
add!(WidgetLabel(() -> "Pressed $(presses[]) times"))
      # three presses of the button
slider = WidgetSlider(0.3)
add!(slider, WidgetLabel(() -> "Slider at $(round(slider.value; digits = 2))"))
      # a drag of the slider to 0.8
name = WidgetText("Ada")
add!(name, WidgetTable(["what", "value"], [["presses", () -> presses[]], ["slider", () -> round(slider.value; digits = 2)], ["name", () -> name.content]]))
name.content = "Ada Lovelace"
      # one more press and a short drag, and the table follows
```

### 3.7 A cell that is a result follows the cell

Today the evaluator keeps a result that is a `Document`, which renders live, and
makes any other value a text snapshot of its display (`Evaluator.jl`,
`evaluate_operation(::EvaluateSelectedFormOperation)`). A cell displays as
`Cell(primitive, 0)` (`Base.show(::ReactiveCell)`, `ReactiveCell.jl`, not
sealed).

- A cell shows as its constructor makes it, as `MutableCell(0)`,
  `ImmutableCell(0)` and `Clock(time = 12.5)` already do: `Cell(0)`. A computed
  cell shows as `Cell(@computation …)` with its value now, and `<invalid>` when it
  has none yet; the display computes nothing and subscribes to nothing.
- When the value of a form is a `ReactiveCell`, its result is a text whose
  content is a computed cell: it reads the cell and gives its display, so the
  row prints again at each write. The result is one document object for the
  life of the form, so undo and a new evaluation of the form work as they do
  for any result.
- A test evaluates `c = Cell(1)`, writes `c[] = 2`, and checks the text that the
  printed row draws.

## 4. Steps

- [x] Step 0: the baseline. Run the suites of the packages whose files the
      change touches, on this branch before the change, and keep the counts.
      **Done.** `build/suites/widget_ctor/sweep.jl` runs 16 suites in one
      process: substrate 80459 pass, 3 fail, 2 error, 1 broken; shell 175/5;
      conversation 166/1; formula 104/12; table 68/9/1; chart, graph, fault,
      sequencechart, dbcatalog, video, filesystem, arguments, naming and
      documentation pass. The places of the failures are in
      `build/suites/widget_ctor/baseline_failures.txt`.
- [x] Step 1: the constructors of §3.1, every call of projectured-julia (§3.2),
      the docstrings and the documents. The suites of Step 0 give the same
      counts, and the scan finds no call of the old shape. **Done.** Three
      scripts under `build/suites/widget_ctor/` make the change:
      `rewrite_calls.jl` edits the byte ranges of the syntax tree (62 files; a
      removed argument goes with its separator, so the layout of a call stays),
      `edit_constructors.py` moves the position in 22 signatures and 30
      docstring signatures, and `edit_text.py` edits the examples in docstrings
      and Markdown. Six examples of a button, a switch, an alert and a placed
      label are edited by hand, and one call that passes a variable position
      (`FileSystemChooserToWidget.jl`). Two more signatures break the argument
      rule and change with the position: `WidgetSwitch` takes `checked` as a
      keyword (a `Bool` is never positional), and `WidgetAlert` takes
      `description` as a keyword (no optional positional argument beside
      keywords). After the change the 16 suites give the same counts and the
      failures stand at the same places; the scan finds 619 calls and none
      with a `Point2D` first. The forms of the S4 script still have the old
      shape; Step 5 writes them again.
- [x] Step 2: the calls of omnet-julia, on a branch, tested against this
      worktree. **Done.** Branch `widget-keywords` of omnet-julia, worktree
      `omnet-julia-widget-keywords`, commit 09cf33b9: the same three passes
      (46 files of calls, 3 Markdown files), and by hand the code of
      `test/ide/AssistantSessionTest.jl` that the assistant runs. The suites
      run twice, over both main checkouts and over both worktrees (a scratch
      environment in `/var/tmp/omnet_widget_env`, with `OmnetIdeTest` added):
      74 suites of presentation, legacy, result, cosim and study, and two IDE
      suites. They give the same counts, except `test_legacy`, where main runs
      two tests more: its checkout has the untracked `mm1k/` with a `.ned` and
      an `.ini` file, which the agreement tests walk. `test_parallel_sim_dashboard_panel`
      spins on a parallel engine and is left out of both runs; the IDE
      environment of main needed a `Pkg.resolve()` for the new dependency of
      `ProjecturedStatistics`. The branch lands right after projectured-julia.
- [x] Step 3: the live values of §3.3, with tests. **Done.** A label takes a
      cell as it is (no caller passed one before) and makes a function a
      computed cell whose answer shows as it is when it is a string or a
      document, and as its text otherwise. A progress bar makes a function a
      computed cell of a `Float64`. `_table_cell_doc` makes a function a live
      label. `test_widget_live_values()` checks the text that the printed canvas
      draws before and after the cell changes: 14 of 14.
- [x] Step 4: the pointer of §3.4, with a test. **Done.** `VideoBackend` and
      `record_application_video` take `pointer = true`. `_track_pointer!` notes
      the left button: a `MouseDown` holds it, a `MouseUp` or a scripted
      `MousePress` releases it at the second of the schedule
      (`_get_schedule_seconds`, which `read_from_devices` uses too). The arrow
      is a `GraphicsPolygon` of 7 points, white with a black border; the ring
      is `color_solarized_orange`, 11 px, 3 px wide, and after a release it
      grows by 6 px while its alpha falls to zero in 0.3 s. The test records
      one take with the pointer and one without, over the same folder (the
      navigator shows its name), and finds the pixels that differ in the last
      frames: they start at the place of the last mouse event and fit in the
      arrow, 5 of 5.
- [ ] Step 5: `find_form_document` and the check in the scripts (§3.5); S4 with
      the forms and the order of §3.6, recorded and given to the owner.
      **In progress.** Written: `find_form_document` (the evaluator's
      `_parse_evaluated_form!` calls it), `tool/video/julia_forms.jl` with
      `check_julia_forms`, which the scripts of S1 and S4 call before a take, the
      forms of S4 in `tool/video/s4_forms.jl`, and the script in moments, with a
      probe mode. Facts from the probes (`build/video/widget_tool_probe.mp4`):
      - In video time the backend fires one entry a frame, so keys held 0.01 s
        slip the schedule; the probe types one key a frame, and its video is
        exactly as long as its schedule (59.8 s).
      - In video time the gesture recognizer measured a click with the wall
        clock, so the first Alt+click, slow to compile, was no click. The
        recorder now gives the recognizer the clock of the frames in video time
        (`editor.recognizer.clock`, a parameter the recognizer already has).
      - The smaller button stands one form higher: the Alt+click is at
        (336, 285).
      - A press or a drag in the tool's pane leaves the focus and the caret in
        the evaluator, so no key brings the caret back after them; a
        Ctrl+Alt+Left there moved the focus to the navigator.
      - Open for the owner: a widget that is the whole result of a form fills
        its row (the button of `button = …`, the field of `name = …`), because
        the result row gives its document `Fill` so that text wraps at the edge
        of the pane; and `presses = Cell(0)` shows `Cell(primitive, 0)`.
- [ ] Step 6: a cell that is a result follows the cell (§3.7), with a test.
- [ ] Step 7: the landing of both repositories, when the owner says so.
      **Landed, not pushed** (2026-09-24, "land in main first"): projectured-julia
      `main` f954f90e and omnet-julia `main` b532199b, by fast-forward. Both mains
      moved twice while the branches were tested (the cell renames
      `ComputedCell` → `Cell(Computed(f))` → `Cell(@computation expr)`), so both
      branches were built again twice on the newest main: the commits before and
      after the keyword change were applied again, and the keyword change was
      made again by its three scripts, which found the same 619 calls each time.
      The 16 suites of projectured-julia and the 76 of omnet-julia gave the same
      counts over main and over the branches, apart from the 33 new tests and the
      untracked `mm1k/` of the omnet checkout. Steps 5 and 6 are still open.
