# One spelling for a computed cell

A cell computes when it gets a `Computed(f)`. The function `ComputedCell(f)` is
a second spelling of the same thing: its body is `ReactiveCell{Any}(Computed(f))`,
which is `Cell(Computed(f))`. The owner chose on 2026-09-24 to remove
`ComputedCell` and to write `Cell(Computed(f))`, in a plan of its own, after the
audit of the cell layer ([cell-layer-audit.md](cell-layer-audit.md)).

## Why

- Two spellings for one thing. `Computed` is the one that works everywhere: a
  typed cell, a write into a cell, the field of a document, a `CellVector`.
- `ComputedCell` looks like a type and is a function, so `x isa ComputedCell`
  throws. The naming law says a function name starts with a verb, and none of
  its exemptions covers it.

## Scope

Counted on 2026-09-24:

| Repository | Lines | Files |
| --- | ---: | ---: |
| projectured-julia, `source/`, `example/`, `package/`, `tool/` | 681 | |
| projectured-julia, `test/` | 45 | |
| projectured-julia, all | 726 | 126 |
| omnet-julia | 84 | 44 |
| inet-julia | 2 | 2 |

One sealed file changes: the example in `CellInterface.jl`. The owner gave
permission for that file in the same conversation.

## `ComputedCellVector`

`ComputedCellVector(f)` in the collection layer was `CellVector(Computed(f))` in
the same way. The owner chose on 2026-09-24 to remove it too, as step 5.

## Steps

- [x] 1. A script that parses each file and rewrites each call
  `ComputedCell(x)` as `Cell(Computed(x))`. A text substitution can not find the
  closing parenthesis. The script is a one-off and is not in the repository:
  - It walks the syntax tree of `Base.JuliaSyntax`. A call with a `do` block
    becomes `Cell(Computed() do ... end)`, so the block stays the argument of
    `Computed`.
  - `Cell(Computed(` is one character longer than `ComputedCell(`, so a
    continuation line aligned to a column inside the parentheses moves one
    column to the right. A line indented less than that is a block, and stays.
  - The realignment stops at the first line of the call that is indented as a
    block. A line below a block line aligns to that line, which does not
    move. The first version of the script moved such lines too, inside the
    `begin` block of a thunk, and a merge of the difference between the two
    versions put 10 files right after the fact.
  - It leaves a definition, an import, an export, a value reference and every
    mention in a string or a comment alone, and lists each of them.
  - It rewrote 723 calls in 105 files of projectured-julia.
- [x] 2. Rewrap every line that the rewrite takes over 90 characters. Each call
  grows by 2 characters, not by the 10 that the first estimate said: 13 lines
  in 8 files went over the limit, and each is rewrapped.
- [x] 3. Remove `ComputedCell` from `ReactiveCell.jl` and from the exports, and
  update the docstrings and the guides that name it.
  - The 16 import lists that named `ComputedCell` next to `Cell` name
    `Computed`.
  - The "Use it to" text of `ComputedCell` moves to the docstring of
    `Computed`, so a search by description still finds a derived value.
  - Prose that named "a `ComputedCell`" says "a computed cell". Plans keep the
    old name, because they are history.
- [x] 4. The same rewrite in omnet-julia and inet-julia, each on a branch
  `computed-cell-spelling` in a worktree of its own.
  - omnet-julia: 40 calls in 18 files, 38 import lists, six prose mentions, a
    call inside the code string of `demo/recording/Mm1kLive.jl`, one Markdown
    sample, and one line rewrapped.
  - inet-julia: one call and one import list.
  - Both repositories reach projectured-julia by a relative `[sources]` path to
    its main checkout, so they must land right after projectured-julia does.
- [x] 5. The same removal for `ComputedCellVector`, with the same script and the
  name and the replacement as constants.
  - projectured-julia: 121 calls in 59 files, 6 import lists, 7 prose
    mentions, 6 Markdown mentions and one line rewrapped. The docstring moves
    onto the `CellVector(computed::Computed)` method.
  - `ComputedCellVector` came from `CollectionModule`, but `Computed` comes
    from `CellModule`. A file that imported only some names of `CellModule` can
    miss `Computed` now: `DatabaseInstanceToDbCatalog.jl` imports it
    explicitly, and a check at run time looks for every module that sees
    `CellVector` and not `Computed`.
  - omnet-julia: 9 calls in 7 files and 39 import lists. inet-julia: one call
    and one import list.

## Verification

- Every changed file parses, and no line that the rewrite touched goes over 90
  characters.
- A check at run time loads the umbrella test package, maps each method to its
  file and its module, and asks each module that runs a rewritten file whether
  it sees `Computed` and `Cell` or `CellVector`: 366 checks, none failed. Three
  files have no method: two changed only in docstrings, and
  `FaultCatchingTest.jl` belongs to `ProjecturedFaultTest`, which the fault
  suite runs.
- `test_kernel()`: 2143 pass, with the 3 fails and 3 errors that `main` has.
  `test_substrate()`: 80457 pass, with the 3 fails and 2 errors of the split
  pane drag test that `main` has. `test_fault()`: 73 pass.
- The owner asked for less than `test_all()`, so that run stopped before its
  first test, and the check at run time took its place: the call is the same before and after, so a name out of
  scope is the one failure the rewrite can cause.
- omnet-julia loads against the two worktrees in a scratch environment: every
  package compiles with no error, and its check at run time passes 38 checks.
  Four test files whose packages that environment does not load see the names
  through the imports of their test modules.

