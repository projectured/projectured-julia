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

- [ ] 1. The search shows one docstring of a function: the one of the generic
  function, else the one of a method with a "Use it to" line, else the first.
  When other methods have their own docstring, one line says how many, and that
  `read_function_documentation` with a `type_name` reads one of them.
- [ ] 2. Every function that a window declares to the assistant, in both
  repositories, has its docstring on the generic function: the docstring stands
  above `function name end`, and the methods follow it. The argument guard reads
  a marker above such a docstring.
- [ ] 3. The documentation tests of both repositories assert, for every declared
  function, a docstring on the generic function with the form of the assistant
  plan; a test of the kernel covers the rule of step 1 on a module of its own.
- [ ] 4. The tests, a commit per step, and the report.

## Not in this plan

A generic docstring for a function that no window declares.
