# Pull request 4 lands with the fixes of its review

Pull request 4 (`mgonzalezlopezudc:fix/ui-repaint-and-appearance`, three commits on
de6b4e95d) repaints an SDL window after the window system drops its pixels, and
makes the controls of an Appearance card when the card first opens. The review
found one regression and some smaller points against the rules. The owner chose
to add the fixes as new commits on top of the branch of the pull request, with
no force push, and to see the diff before any push.

## Where the work happens

- The commits are made in the worktree `projectured-julia-pr4-review`, on the
  merge of main 2bbc18fb5 and the pull request (962e1c83e, a detached head), so
  the tests run on what lands.
- Main changes none of the files of the pull request, so the fix commits apply
  unchanged on the head of the pull request (4fb90a1d0). They are put there for
  the push.

## Steps

1. [x] **Appearance: the controls of a card that opens after the print hold
   their paths.** Done in 45e0ff40b. `_follow_section_body_paths!` wires the body
   inside `run_without_cell_tracking`, below `RangeReferenceStep(0, 1)` of the
   `CellVector` of the card, which is the step that the print walk uses for an
   element; the kernel compares a range step by its fields. The print gives each control its part of the caret path and of
   the hover path once (`set_output_tree_path_computations!`). A closed card has
   no controls at that time, and a fold prints nothing again, so a colour text of
   a card that opens later takes no typed text. The body wires its paths when it
   is made, as `_follow_layout_part!` in `WorkPlanToWidget.jl` does. A test opens
   the card after the print and types a digit into a colour text. The comments of
   the two functions say what each one makes.
2. [x] **SDL: the documents and the comments say what the repaint does.** Done in
   07a33b011. The `elseif` of the four events takes three lines, to stay in the
   budget of 90 characters.
   `sdl.md` gets the rows of the five window events. The docstring of
   `take_from_devices!` says it after the list of the inputs. The comment of
   `_request_window_repaint!` fits the line budget. `empty!(res.damage_history)`
   goes: a frame with `first_paint` copies the whole window anyway.
3. [x] **Tests: the new test sets join their suite functions, and the row test
   asserts the answers.** Done. The test set of the closed cards goes inside
   `test_appearance_tab()`, and that of the row panes inside
   `test_widget_rows_scroll()`. The row test asserts that the list declines and
   that the tree answers "Show the tooltip". The `using` line of the row test goes:
   the test module has the names.
4. [x] Run `test_appearance_tab`, `test_widget_rows_scroll`, `test_widget_card_fold`,
   `test_native_window`, `test_partial_paint` and the guards `naming.jl` and
   `style.jl`. Show the diff to the owner. Push only after the owner approves.
   - [x] The tests pass on main with the pull request and the fixes: the
     appearance tab 138, the row panes 36, the card fold 46, the native windows
     133, the partial paint 78. The guards give what main gives (naming clean,
     style one violation in `BookModule.jl:34`).
   - [x] The fix commits are on the head of the pull request in the worktree
     `projectured-julia-pr4-push`: 64fecdb1c, 624df9ced, 5debe8907. The changed
     files are the same as in the tested tree, but for one line of spaces in the
     docstring of `take_from_devices!`, which the push head has right.
   - [x] The push, after the owner approves: the branch of the pull request
     went from 4fb90a1d0 to 5debe8907, with no force.
   - [x] The landing: `merge --no-ff` of 5debe8907 into local main, 1fd445700.
     Local main was 30 commits ahead of `origin/main` (de6b4e95d), so the pull
     request was not merged on GitHub: that would have put it on the old base.
     The tree of 1fd445700 is the tree that the tests ran on, but for the line
     of spaces, so no test ran again.
   - [x] The push of main, after the owner approves: `de6b4e95d..1fd445700`,
     with the 30 commits before it. GitHub marks the pull request merged.
     The CI runs of the pull request ran no job ("a workflow file issue"), and
     the owner did not want the push run of main compared with that of
     de6b4e95d, which failed in five jobs already.

## Decisions

- The owner chose new commits on top of the branch of the pull request over a
  force push, so the three commits of the contributor stay as they were.
- "Land on main" is the local main, as for the other commits of the day.

## Facts found in the review

- `test_input_coalescing` fails on clean main 2bbc18fb5 with the offscreen driver
  (5 fail, 25 error), with and without the pull request.
- The list of the row test offers no command in this projection, also with two
  rows; the tree offers "Show the tooltip".
