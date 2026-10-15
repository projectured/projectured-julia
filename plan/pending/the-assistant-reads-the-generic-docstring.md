# The assistant reads the docstring of the generic function

Status: a plan. Written 2026-10-15 from the answer of the owner on that day. It
stands on the branch `docstring-above-marker`, which is not landed yet.

## 1. The ask of the owner (2026-10-15)

- "all functions which can be used by the assistant to carry out tasks should
  have documentation on the generic function which the tool should return"
- "otherwise, I agree with your recommendation": for every other function, the
  search shows the docstring of the generic function, else the docstring of a
  method that has a "Use it to" line, else the first, and one line counts the
  methods that have their own docstring.

## 2. The facts (2026-10-15)

- `_render_doc` (`source/kernel/tool/Documentation.jl`) renders the first entry
  of a `MultiDoc` (`md.order[1]`), so the search and `read_function_documentation`
  show the docstring of the method defined first.
- Julia keys the docstring of `function f end` with the signature `Union{}`, apart
  from the docstrings of the methods.
- Of the functions with two or more docstrings, 26 of 48 in projectured-julia and
  26 of 45 in omnet-julia have a docstring on the generic function.

## 3. The steps

- [x] 1. Done 2026-10-15. The search shows one docstring of a function: the one of the generic
  function, else the one of a method with a "Use it to" line, else the first.
  When other methods have their own docstring, one line says how many, and that
  `read_function_documentation` with a `type_name` reads one of them.
- [x] 2. Done 2026-10-15. Every function that a window declares to the assistant, in both
  repositories, has its docstring on the generic function: the docstring stands
  above `function name end`, and the methods follow it. The argument guard reads
  a marker above such a docstring.
- [x] 3. Done 2026-10-15. The documentation tests of both repositories assert, for every declared
  function, a docstring on the generic function with the form of the assistant
  plan; a test of the kernel covers the rule of step 1 on a module of its own.
- [ ] 4. The tests, a commit per step, and the report.

## What was built

- `_binding_doc` collects every docstring of a binding in every module that
  documents it (`_collect_binding_docs`), answers the one that
  `_choose_binding_doc` picks, and adds the line that counts the others.
  `read_function_documentation` did not use its `type_name`; it now answers the
  docstring of the method whose signature names that type.
- 130 declared functions had no docstring on the generic function: 127 with one
  docstring and 3 with two. A script put `function name end` under the docstring
  of 126 of them; `get_simulation_runs`, `check_expectations!` and `save_study!`
  were done by hand, and the docstring of the form that the assistant calls
  became the generic one. A macro has no generic form, so `@reference` keeps its
  docstring and the tests skip a macro.
- The parser gives a definition under `function name end` a line of its own, so
  the argument guard also steps over that line under a marker.
- The documentation tests check 316 names in projectured-julia and 114 in
  omnet-julia, the generic docstring of each function among them.
- Added on the owner's word (2026-10-15, "yes"): the shared list declares the two
  reads of the clock, `get_reactive_clock_time` and `get_clock_time`, so a shape
  can move. `clock/Clock.jl` is sealed, and the owner allowed its docstrings to
  change: each read has its docstring on the generic function, and the "Use it
  to" line of the reactive read is written in that form.

## Not in this plan

A generic docstring for a function that no window declares.
