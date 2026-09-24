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

## Open question

`ComputedCellVector(f)` in the collection layer is `CellVector(Computed(f))` in
the same way. The owner decides whether it goes with `ComputedCell`.

## Steps

- [ ] 1. A script that parses each file and rewrites each call
  `ComputedCell(x)` as `Cell(Computed(x))`. A text substitution can not find the
  closing parenthesis.
- [ ] 2. Rewrap every line that the rewrite takes over 90 characters.
- [ ] 3. Remove `ComputedCell` from `ReactiveCell.jl` and from the exports, and
  update the docstrings and the guides that name it.
- [ ] 4. The same rewrite in omnet-julia and inet-julia.
