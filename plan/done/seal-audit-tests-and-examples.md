# The seal audit checks the tests and the examples

## The ask

The owner, 2026-10-12: "the audit should check if there are sufficient tests for
the public interface, for domains there should not only be tests but also
examples which the user can run from the repl", and "preferably the kernel layers
should also have some examples if it can be done which the user can test from the
repl".

## Decisions

1. The test check runs for each file, for the public names that the file defines.
   The example check runs once for each kernel layer and each domain, at the audit
   of its last file. The owner: "for 1, agreed".
2. A kernel layer gets a walkthrough function in `ProjecturedKernelExample`, not
   runnable docstring examples. The owner: "for 2, agreed".
3. The two new checks apply to projectured-julia only. omnet-julia and inet-julia
   keep the architecture check alone. The owner: "for 3, only projectured".

## Steps

- [x] `SEALING.md`: the audit protocol has three checks. The architecture check
  stays as it was. The test check and the example check are new.
- [x] `tool/survey-interface-tests.jl`: the exported names of a module that no
  test names.
- [x] `example/kernel/Walkthrough.jl` and `example/kernel/CellExample.jl`:
  `print_cell_example()`, the walkthrough of the cell layer, with
  `test/kernel/cell/CellExampleTest.jl`, and a paragraph in
  `documentation/guide/examples-tour.md`.
- [x] omnet-team, `role/requirements-seal-auditor.md`: the agent follows the
  protocol of `SEALING.md`, does the two new checks in projectured-julia, and
  reads the law at `documentation/rule/architecture-invariants.md`. The rule 2 of
  `role/editor-lead.md` says the same.

## Design notes

- **A walkthrough runs what it prints.** Each line is a string that is parsed and
  run in a new module that uses the layer, so the printed code is the code that
  runs. A line and its value can not disagree. A new module for each call keeps
  two calls apart, and the test asserts the full text twice. The new module binds
  the layer as a constant and does `using .Layer`, so it does not need the package
  of the layer in the active environment.
- **The survey reads syntax trees.** It parses `source/`, `package/*/src` and
  `test/` with `Meta.parseall` and loads no package. A comment, a docstring and a
  `using` line do not count as a test. A string macro counts by its literal, so
  `reference_pattern"…"` names `@reference_pattern_str`, which a text search
  missed. It runs in about 2 seconds.
- **A domain package gives out its names when it loads.** `ProjecturedJSON`
  exports the names of `JsonModule` in a loop, so the survey names the module under
  `source/domain/`, for example `JsonModule`.
- **The survey reads exports only.** A method that a file adds to a public
  function of another module is a public name too, and the audit finds its tests
  by hand.

## Facts found

- On main f9bacecd5, 79 of the names that the 24 kernel modules export have no
  test that names them. The largest counts are `DocumentModule` 18,
  `ProjectionModule` 17, `ToolModule` 9 and `ReferenceModule` 7.
- `SqlModule` has 31 of 51 exported names with no test, and `JsonModule` 2 of 6.
- The lead roles of omnet-team name more paths that do not exist, for example
  `documentation/architecture-rules.md` and `documentation/design-decisions.md` in
  `role/editor-lead.md`, and the law paths of `role/network-model-lead.md` and
  `role/simulator-lead.md`. This change repairs only the two lines of the seal law
  in `role/editor-lead.md`.
