# A domain that embeds Julia code draws its own nodes again

**Status: done, on the branch `julia-embedded-notation`.** The owner asked for
the fix on 2026-09-27, after the S7 work found the fault.

## Problem

Commit 154f3306 (2026-09-23) ended the table of `JuliaToSyntax()` with the catch-all
`Document => JuliaObjectToSyntaxLeaf()`, which draws a pasted object as its title in
angle marks. The dispatch takes the first entry that matches. `FsmToSyntax()`,
`FormulaToSyntax()` and `ProcessToSyntax()` copy that table and append the entries of
their own types after it, so the catch-all takes every node of their domain, and the
notation prints `⟨FsmComponent⟩`, `⟨FormulaReference⟩` and so on. On the branch of S7,
`test_fsm()` had 23 failures, `test_formula()` 12 and `test_process()` 108; on clean
main 15b40434, `test_process()` had the same 108.

## Design

`JuliaToSyntax(entries::Pair...)` takes the entries of an embedding domain and puts
them after the entries of the Julia nodes and before the catch-all. The three
domains pass their entries to it, so only the Julia domain knows that the catch-all
comes last. `JuliaToSyntax()` with no entries is the table that it was.

## Steps

- [x] 1. `JuliaToSyntax(entries...)`, and the three domains call it.
- [x] 2. `test_julia()`, `test_fsm()`, `test_formula()` and `test_process()`: 362, 154,
  116 and 304 pass, none fails. Before the fix, the last three had 23, 12 and 108
  failures, so the catch-all was the cause of each one.
- [x] 3. `documentation/package/julia/julia.md` says how a domain adds its entries.
