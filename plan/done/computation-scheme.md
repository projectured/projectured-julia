# One word for the computation of a cell: `Computation` and `@computation`

The cell layer uses several words for one concept. What a reactive cell runs to
get its value is the field `thunk`, the argument of `set_cell_function!`, "a
computation" in the docstrings and the marker `Computed`. A cell that holds a
value is "primitive" in `show` and in the guide, and "holds a value" in the
docstrings. The writing rules ask for one word for one thing.

On 2026-09-24 the owner accepted a scheme with "computation" as the one word,
chose `Computation` as the name of the marker, and chose a macro,
`@computation`, that writes the lambda for the caller. This plan carries both
through the three repositories.

## Decisions

**The scheme.** One word for each concept:

| Concept | The one word | Names |
| --- | --- | --- |
| the box | cell | `AbstractCell`, `Cell`, `ReactiveCell`, `MutableCell`, `ImmutableCell` |
| what a reactive cell holds | value or computation | the fields `value` and `computation` |
| the marker that gives a computation | computation | `Computation(f)`, `@computation expr` |
| the adjective | computed | `is_computed_cell` |
| the two writes | set | `set_cell_value!`, `set_cell_computation!` |
| must compute on the next read | up to date | `is_cell_up_to_date`; the private field `valid` stays |
| the graph | dependencies, dependents | the fields, `has_dependent_cells` |
| what `show` prints | value, computation | `Cell(value, 3)`, `Cell(computation, <invalid>)` |

**The marker and its macro.**
- `Computation(f)` marks the function `f` as the computation of a cell. Its one
  field is `computation`, the same word as the field of the cell.
- `@computation expr` expands to `Computation(() -> expr)`. The macro
  interpolates the type object, so a caller needs `@computation` in scope and
  not `Computation`.
- **The rule of use:** write `@computation` for an expression, and
  `Computation(f)` for a function that exists already, such as a named function
  or a function from an argument. `@computation f` is a computation that
  returns the function `f` as a value, not one that calls it; a test states
  that.
- **The rule of parsing:** inside an argument list, a macro call without
  parentheses takes every argument after it. `pair(@computation 1 + 2, 3)`
  passes one tuple. Where arguments follow, write `@computation(expr)`. After
  `=`, alone, or as the last argument, the plain form works:
  `c[] = @computation 2 * m[]`, `Cell(@computation a[] + 1)`. The guide and the
  docstring of the macro say this.

**The file** `CellComputed.jl` becomes `CellComputation.jl`, because a file is
named for what it defines. Its export statement in `CellModule.jl` is
`export Computation, @computation`, as the export rule asks.

**No alias.** `Computed` and `set_cell_function!` go with no deprecated alias,
as `ComputedCell` went: the three repositories change together.

**Out of scope.** The field `thunk` of `Tokens` in `ProjectionTemplate.jl`
belongs to the template of the projection layer, a concept of its own. The ID
`PAR-NO-WRITE-IN-THUNK` stays, because an ID never changes; its text can say
computation.

## Scope

Counted on 2026-09-24 in `source`, `test`, `example`, `package`, `tool`,
`sample` and `demo`:

| Repository | `Computed` lines | `Computed(() -> …)` | `Computed() do` | other `Computed(…)` | `set_cell_function!` lines | `thunk` field reads |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| projectured-julia | 907 in 143 files | 722 | 2 | about 156 | 252 | 12 |
| omnet-julia | 90 in 44 files | 48 | 0 | 4 | 244 | 3 |
| inet-julia | 3 in 2 files | 2 | 0 | 0 | 3 | 0 |

Markdown: 19 files in projectured-julia and 2 in omnet-julia name `Computed`,
`set_cell_function!` or the thunk. No test asserts the text that `show` prints.

## Steps

- [x] 1. The layer. `CellComputation.jl` with `Computation` and
  `@computation`; the fields `computation`; `set_cell_computation!`; `show`
  with the new words; the docstrings; the exports. Tests for the macro: the
  plain form, the parenthesized form in an argument list, a `begin` block, a
  typed cell, a write, and `@computation f` for a function `f`.
- [x] 2. The rewrite of the lambdas, with a script that walks the syntax tree,
  as for `ComputedCell`:
  - `Computed(() -> body)` becomes `@computation body`. The plain form stands
    where the call is alone, the right side of `=` or the last argument; the
    parenthesized form stands where arguments follow. A body that is a
    `begin` block keeps it: `@computation begin … end`.
  - `Computed() do … end` becomes `@computation begin … end`.
  - A lambda with arguments is not a computation, so the script leaves it and
    lists it.
  - Each continuation line aligned inside the old call moves with it, by the
    rule that the `ComputedCell` script used.
- [x] 3. The renames with `julia-rename.jl`: every other `Computed` becomes
  `Computation`, and `set_cell_function!` becomes `set_cell_computation!`.
  Then a pass over the prose, because the tool skips strings and comments.
- [x] 4. The import lists that name `Computed` name `Computation` and, where
  the file uses the macro, `@computation`.
- [x] 5. The guides and the rules: `cell.md`, `macros.md`,
  `architecture-invariants.md` and the other Markdown files. 23 lambdas in
  Markdown became `@computation`. "Thunk" became "computation" where it names
  the computation of a cell, and "primitive cell" became a cell that holds a
  value. "Thunk" stays where it names something else: the `tokens(thunk)` of
  the template and the operation thunks of playback. "Primitive" stays where it
  means a basic building block or the Primitive domain.
  - **Follow-up, not in this plan:** comments and docstrings in other layers
    say "thunk" 103 times in 51 files, in several senses, and one of the files,
    `kernel/fault/FaultStore.jl`, is sealed. They need a pass of their own.
- [x] 6. omnet-julia and inet-julia: steps 2 to 5, each on a branch in a
  worktree of its own. They land right after projectured-julia, because their
  `[sources]` reach its main checkout.
- [x] 7. Verification, the smaller set that the owner asked for instead of
  `test_all()`:
  - `test_cell()`, `test_kernel()`, `test_substrate()` and `test_fault()`,
    against the baselines of `main`;
  - the check at run time that each module that runs a rewritten file sees
    `@computation`, `Computation` and `Cell` or `CellVector`;
  - the naming guard, the export guard and the argument guard;
  - omnet-julia compiled against the worktrees, with its own check at run time.

## Verification results

- projectured-julia loads with the umbrella test package, so the macro is in
  scope everywhere: Julia expands a macro when it loads the code.
- The check at run time passes 401 checks: each module that runs a changed
  file sees `Computation`, `Cell`, `CellVector` and `set_cell_computation!`
  where the file uses them. Three files have no method: two interface files
  that changed only in docstrings, and `tool/video/record_widget_tool.jl`,
  whose code is in strings.
- `test_kernel()`: 2158 pass, the 11 tests of the macro more than before, with
  the 3 fails and 3 errors of `main`. `test_substrate()`: 80445 pass, with the 3
  fails and 2 errors of the split pane test on `main`. `test_fault()`: 73 pass.
- The substrate count is 12 below an earlier run. Measured the same way, one
  example at a time, every one of the 68 examples gives the same count on
  `main` and on this branch, 76119 in all. The earlier run did not load the
  umbrella test package, which registers more domains; the difference is the
  process, not the change.
- The naming guard, the export guard and the documentation guard pass. The
  argument guard reports only `start_application!`, which is on `main` too.

- omnet-julia compiles all 512 packages against the two worktrees, and its
  check at run time finds no module that misses a name. Three package roots
  of omnet-julia import the names of `CellModule` by list, and a file that
  they include uses the macro: `OmnetPresentation`, `OmnetIdeTest` and
  `OmnetLegacyTictocTest`. The first load found `OmnetPresentation`; a search
  of every package root found the other two, whose test packages the scratch
  environment does not load.
- inet-julia was not loaded. Its change is two lambdas, a qualified call and
  one import list, which gets `@computation`.

## Risks

- **Open branches of other sessions** use `Computed` and `set_cell_function!`.
  Checked on 2026-09-24: `feature-videos` in projectured-julia, 13 commits
  ahead, and `widget-keywords-on-main` in omnet-julia, one commit ahead, both
  conflict with this change: 7 files in projectured-julia and 12 or more in
  omnet-julia, mostly widgets. The omnet branch also adds 11 lines with the old
  names. `one-interface` and inet's `t1s-sealed-trim` add nothing and do not
  conflict.
- **The parse trap** of a macro call in an argument list. The script writes the
  parenthesized form wherever an argument follows, and a test covers both forms.
- **The line width.** `@computation body` is shorter than
  `Computed(() -> body)`, but `Computation(f)` is three characters longer than
  `Computed(f)`. The script and the renames report every line that goes over
  90 characters.
