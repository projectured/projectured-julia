# The three faults of the state machine examples are fixed

The work on the state machine examples (`plan/done/the-state-machine-examples-run.md`)
found three faults that `main` had before it. The owner asked to fix them and push
them.

## The faults and their causes

1. **A tall screenshot shows only its first lines.** `write_image` with a height
   cap draws the TCP notation (`fsm_example`) down to its first empty line and no
   further. The print is correct; the render stops early. Cause:
   `_make_output_line` in `SyntaxToText.jl` keys the `TextLine` of a line by its
   indentation and the identity of its spans. An empty line has no span, so all
   the empty lines of one indentation in a compound get one `TextLine` object.
   `TextToGraphics` keeps the cells of a line by the identity of its `TextLine`, so
   these lines share one line canvas, at the place of the last of them (y = 2506
   for line 11 of the TCP text). The renderer of a vertical stack stops at the
   first element below the clip, which is that canvas.
2. **`,` in a state machine diagram fails** with `SelectionMismatchException`.
   The `,` of a selected state reads "Insert a new transition": a
   `CompoundOperation` of a `ReplaceReferencedValueOperation` (no document of its
   own) and a `ReplaceSelectionOperation`. `_reroot_part_answer` in
   `GraphLayoutToGraphics.jl` drops a `ReplaceReferencedValueOperation` with no
   document, and keeps the other members of a compound. So only the selection of a
   transition that was never inserted goes back. The kernel default reader has two
   rules that the graph breaks: a write with no document gets its reference mapped,
   and a compound goes back whole or not at all, except the answer to a move.
3. **The generated code calls names that the runtime does not define.** The
   generator emits `fsm_state`, `fsm_enter!`, `fsm_leave!`, `fsm_goto!`,
   `fsm_drain!`, `fsm_cascade_error` and `fsm_unhandled_error`, and the examples
   call `fsm_defer!`. The runtime of omnet-julia (`FsmModule`) names them
   `get_fsm_state`, `enter_fsm!`, `leave_fsm!`, `record_fsm_transition!`,
   `drain_fsm!`, `make_fsm_cascade_error`, `make_fsm_unhandled_error` and
   `defer_fsm_action!`. inet-julia's generated `MacFsm.jl` and `PlcaFsm.jl` use the
   runtime names, because a text rename changed them after the generation.

## Steps

1. ✅ Syntax: each line of a compound is its own `TextLine`. Count the lines of each
   key in one layout, and put the count in the key. Test in `SyntaxToTextTest.jl`.
   Make `fsm.png` again, now that the cap draws the whole page.
   - Done. A line keeps its object from one layout to the next, as before; only
     lines with one key get a count. `test_syntax_to_text()`,
     `test_text_to_graphics()`, `test_syntax()`, `test_fsm()` (266) and
     `test_julia()` (694) pass. The JSON text had no shared line; the FSM
     notation had two shared objects (indentation 0 and 4) at 5 and 18 places.
   - `fsm.png` now shows the TCP notation down to the height cap of the
     screenshot (1080), as each other tall example does.
2. ⬜ Graph: a write into the content of a vertex or a label goes back with the steps
   to that part, and a compound that is no move goes back whole or not at all.
   Remove the `repl_broken` entry of the two diagram examples. Run `test_repl` on
   both and `test_graph()`.
3. ⬜ FSM generator: emit the runtime names of omnet-julia. Change `ProbeRuntime`,
   the examples, the tests and `fsm.md`. Check that the generator of inet-julia
   gives its two files without a change.
4. ⬜ Land on `main`, push, remove the worktree and the branch.
