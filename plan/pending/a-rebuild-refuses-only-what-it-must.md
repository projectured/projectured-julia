# A rebuild refuses only what it must

## The goal

The user (2026-11-05): "I feel like it rejects everything, I could basically
not do an incremental compile from 10/10 because there's always a reason to
reject it".

A rebuild of a binary with a reactive store must apply the changes of a normal
day of work. These are a changed field of a `@document` or `@theme` struct, a new
file, and a changed docstring of a module. A rebuild refuses a change only when
the change really needs a founding build.

## Why a rebuild refuses now

The refusal of `bin/build_omnet_ide` on 2026-11-04 had four causes. The reasons
are the lines of the refusal, with the code of each rule of the compiler.

1. **A new include that is not a plain string (C4, 4 lines).** For example,
   `OmnetIde.jl:98` adds `include(joinpath(_SOURCE, "LegacyBaselineFileView.jl"))`.
   The walk that finds the tracked files (`tracked_sources` in the fork of
   PackageCompiler) computes this path, so the store tracks the file. But the
   check of the compiler for a new include (`rc_classify` in
   `stdlib/ReactiveCompiler/src/child.jl` of the Julia fork) takes only a string
   literal. It refuses every other form. In omnet-julia, 165 includes use
   `joinpath`, and 62 of them are in the packages of the IDE.
2. **A changed field of a `@document` struct (B2, 7 types).** When the fields of
   a struct change, the compiler finds every method that names the type. It
   refuses when one of them is in a file that is not tracked. The constructors
   that `@document` writes have no line, so Julia gives them the place
   `none:0`, and the compiler takes `none` as a file that is not tracked.
   Measured on 2026-11-05 with `rc_methods_on_type` of the compiler:
   `WidgetTheme`, `TaskTheme` and `ConversationTheme` each have 5 such
   constructors, and `HelpEntry` and `Assistant` have 6. They are the
   constructors of the layouts (`ICWidgetTheme(…)`, `MCWidgetTheme(…)`) and the
   positional constructors (`WidgetTheme(…)`). `@theme` writes its struct
   through `@document`, so it has the same cause.
3. **A changed docstring of a module (C5, 1 line).** `ExplorerModule.jl:1`
   changed one sentence of the docstring of the module. The compiler takes the
   docstring as part of the module header, and it refuses every change of a
   header.
4. **Methods in a file that is not tracked (B2, 2 types).** These lines named
   `LegacyFingerprintStoreToWidget.jl` and `LegacyStatisticalBaselineToWidget.jl`.
   Both files no longer exist, so this cause is gone.

## The design

1. **`@document` gives each method that it writes the line of the struct.**
   `macro document` passes `__source__` on, and every method in the code of the
   macro gets that `LineNumberNode`. Then a stack trace and `methods(T)` name the
   line of the struct, and the compiler finds the methods in the tracked file of
   the struct. When the fields change, the struct is one changed expression, and
   its evaluation writes all these methods again. The struct layer already does
   the same for its own methods with `build_cell_struct_exprs(…; source)`.
2. **The compiler takes a new include whose path it can compute.** The check of
   a new include computes the path by the rules of the walk: a string,
   `@__DIR__`, `@__FILE__`, and `joinpath`, `normpath`, `abspath` and `dirname` of
   those. A name, such as `_SOURCE`, is a `const` of the loaded module that holds
   a `String`. When the path is a file that the store tracks, the change is a
   new include. Every other form is refused as now.
3. **The compiler applies a changed docstring of a module.** The check compares
   the old header and the new header without their docstrings. When only the
   docstring changed, the apply sets the new docstring of the module and makes no
   new module. Every other change of a header is refused as now.

Design 2 and design 3 change the Julia fork. They take one rebuild of Julia
together. After that rebuild, every package compiles again at its first load,
and each store needs a founding build (`--found`), because the image of the
compiler server holds the code of the compiler.

## Decision: the struct layer sets the line

Design 1 had two ways to set the line:

- **A.** `DocumentMacro.jl` walks the code that it returns and gives the line to
  every method in it. Only `DocumentMacro.jl` changes.
- **B.** The struct layer gives a public function that sets the line, and
  `build_cell_struct_positional_constructors` takes `source`. `@document` uses
  both.

The user (2026-11-05) allowed the change of the sealed `struct/CellStruct.jl`:
"I allow CellStruct.jl too". So the plan takes **B**. A was only a way around the
seal. With B, one function of the struct layer sets the line of every method
that the struct layer and `@document` write, and the private
`_set_cell_struct_source!` becomes that public function. The public function
must also set the line on each method in a block of many methods, because the
emitters of `@document` return such blocks. After the change, `CellStruct.jl`
gets the four checks of the seal audit again, and the user decides if it is
sealed again.

## Steps

The implementation is in two worktrees: one of projectured-julia, and one of the
Julia fork from `merged-next`. Each step ends with a commit, and the plan is
marked as each step is done. Nothing lands on `main` or `merged-next` without the
approval of the user.

- [ ] **Step 1: `@document` gives its methods the line of the struct.** By the
  decision above: the public setter and `source` of
  `build_cell_struct_positional_constructors` in `struct/CellStruct.jl`, and
  `macro document` passes `__source__` to `_document_expr`, which gives it to
  each emitter. Test: a test of the public setter in the struct suite, and a new
  test in the document suite of the kernel. For a `@document` struct and a
  `@theme` struct, every method that names the type has the file of the test and
  the line of the struct. The measurement of 2026-11-05 (the methods at `none:0`
  that name `WidgetTheme`, `TaskTheme`, `ConversationTheme`, `HelpEntry` and
  `Assistant`) gives 0. Then run the suites of the struct layer and of the
  document layer, and `test_kernel_layering()`. Then report the four checks of
  the seal audit for `CellStruct.jl`.
- [ ] **Step 2: the builder says which includes the walk follows.** The docstring
  of `collect_tracked_sources` in `source/tool/builder/ReactiveBuild.jl` says
  that only a string literal is tracked. That is not true: it must give the rules
  of `tracked_sources`.
- [ ] **Step 3: the compiler takes a new include whose path it can compute.**
  In `rc_classify` of `child.jl`. Test: a check in `rc_warm` with
  `include(joinpath(@__DIR__, "x.jl"))` and with a `const` path of the module.
  An include of a path that it can not compute is still refused.
- [ ] **Step 4: the compiler applies a changed docstring of a module.** In
  `rc_classify` of `child.jl`, and in the apply. Test: a check in `rc_warm`.
  After the apply, `@doc` of the module gives the new text, and the module is the
  same object as before.
- [ ] **Step 5: one rebuild of Julia, and the gate.** Build the Julia of the
  worktree with step 3 and step 4. The gate is a small app that depends on
  `ProjecturedKernel`. It has a `@document` struct, a module with a docstring,
  and a root file that includes with `joinpath(_SOURCE, …)`. Found it, then do
  three edits one after another: add a field to the struct, add a new file with
  `joinpath`, and change the docstring of the module. Each rebuild must apply its
  edit, and the program must show the new state after it. Then do one edit that
  must be refused, a new dependency (F3), and check that the refusal is still
  there.
- [ ] **Step 6: the real IDE.** After the user approves the landing of both
  worktrees: rebuild the `+merged` Julia, and found the IDE store with
  `bin/build_omnet_ide --found`. Then add a field to `WidgetTheme` in a copy of
  the change, and run `bin/build_omnet_ide`. The rebuild must apply it. Do not
  commit the field.

## Not in this plan

- The other rules of refusal: a module option (F1), a new dependency (F3), an
  import that conflicts with a binding (C3), and top-level code outside the
  `module` block of a root file (C5). They need a founding build.
- The refusal of the trimmer (T1) for a trimmed build.
- A count of how many commits of the last weeks a rebuild would have applied,
  before and after this plan.
- A refused build restarts the compiler server.
