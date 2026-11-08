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

Decisions of the implementation:

- The export of `set_cell_struct_source!` is in `struct/CellStructModule.jl`,
  which is sealed too. The user allowed that change on 2026-11-05: "yes, I allow
  it, continue".
- `build_cell_struct_positional_constructors` takes no `source`. `_document_expr`
  gives the line to each part that it writes with `set_cell_struct_source!`, so a
  keyword of each builder repeats it. The struct of the programmer and its lines
  stay as they are, and only the inner constructor in it gets the line.
- `set_cell_struct_source!` also gives the line to the body of a `struct`. Julia
  takes the line of the default constructors from the body. The native struct of
  `@document` has no line node, so its two default constructors had the place
  `"":0`. The measurement of 2026-11-05 counted only `none:0`, so it did not see
  these.
- `@theme` writes more methods in a quote of `Theme.jl`, such as
  `make_scaled_theme(::T, …)` and the struct `ScaledT`. They name the type too, so
  `@theme` gives them the line of the declaration with the same function.
  `StyleModule` imports it from `CellStructModule`.

## Steps

The implementation is in two worktrees: one of projectured-julia, and one of the
Julia fork from `merged-next`. Each step ends with a commit, and the plan is
marked as each step is done. Nothing lands on `main` or `merged-next` without the
approval of the user.

- [x] **Step 1: `@document` gives its methods the line of the struct.** By the
  decision above: the public setter in `struct/CellStruct.jl`, and
  `macro document` and `@document_preset` pass `__source__` to `_document_expr`,
  which gives it to each part that it writes. `@theme` does the same for its own
  methods. Test: a test of the public setter in the struct suite, a new test in
  the document suite of the kernel, and a new test in the theme suite of the
  platform. For a `@document` struct and a `@theme` struct, every method that
  names the type has the file of the test and the line of the struct. The
  measurement of the methods that name `WidgetTheme`, `TaskTheme`,
  `ConversationTheme`, `HelpEntry` and `Assistant` gives no place other than the
  line of the declaration. Then run the suites of the struct layer and of the
  document layer, and `test_kernel_layering()`. Then report the four checks of
  the seal audit for `CellStruct.jl`.

  Done on 2026-11-05. The suites pass with Julia 1.13: CellStruct 103,
  CellStructPlan 72, the struct example 2, DocumentMacro 132, DocumentContract
  154, the kernel layering guard 10, and Theme 87. The measurement (the walk of
  `rc_methods_on_type`, copied into a script for Julia 1.13) finds each method
  that the macros write at the line of its declaration: `WidgetTheme.jl:24` ×22,
  `TaskTheme.jl:12` ×22, `ConversationTheme.jl:30` ×22, `HelpDocument.jl:66` ×9
  and `AssistantDocument.jl:138` ×9. No method that names one of the five types is
  at `none:0`, at an empty file, or in a file of a macro.

  The seal audit of `CellStruct.jl` and `CellStructModule.jl`, by an auditor
  agent: `CellStructModule.jl` passed the four checks. `CellStruct.jl` passed the
  example check and the guide check, and the fixes of its findings are in this
  step:
  - The docstring of `set_cell_struct_source!` names the forms that it handles,
    and the setter also handles an anonymous function and a `macro`.
  - `build_cell_struct_exprs` without `source` built the inner constructor with
    no line, so the promise "they point here" was false. The inner constructor
    now starts with the line of `CellStruct.jl`, and a test holds the promise.
  - The tests cover a definition with `where`, with a return type and with an
    empty body that has no line node.
  - `StyleModule` takes the module with a bare `using ..CellStructModule`
    (`PAR-QUALIFIED-EXTENSION`).

  Both files stay 🔒 in `SEALING.md`. The user decides if they are sealed again.
- [x] **Step 2: the builder says which includes the walk follows.** The docstring
  of `collect_tracked_sources` in `source/tool/builder/ReactiveBuild.jl` says
  that only a string literal is tracked. That is not true: it must give the rules
  of `tracked_sources`.

  Done on 2026-11-05. The docstring gives the rules of the docstring of
  `tracked_sources` in the fork, with the example
  `include(joinpath(_SOURCE, "View.jl"))` after `const _SOURCE = @__DIR__`. A
  probe package checked the example: `PackageCompiler.tracked_sources` of
  `environment/build` tracks that file in the module, as it tracks a plain
  `include("Plain.jl")`. No other document had the wrong rule; the builder guide
  says only that `collect_tracked_sources` reads the includes. No builder test
  calls the function, because the builder test package does not load
  PackageCompiler.
- [x] **Step 3: the compiler takes a new include whose path it can compute.**
  In `rc_classify` of `child.jl`. Test: a check in `rc_warm` with
  `include(joinpath(@__DIR__, "x.jl"))` and with a `const` path of the module.
  An include of a path that it can not compute is still refused.

  Done on 2026-11-05, in the worktree `julia-rebuild-refusals` of the Julia fork,
  branch `rebuild-refusals` from `merged-next` (cd1d275035). `rc_include_path`
  and `rc_static_path` in `child.jl` follow `_static_path` of the walk. The one
  difference: a name is read as a `const` `String` of the loaded module, where
  the walk reads the definition of the `const`. The module is loaded, so both
  give the same path. A new `const` in the same edit as its first include is
  not loaded yet, so that include is still refused.

  Facts found:
  - The apply evaluates no include item. It evaluates a new tracked file whole,
    as the added file of the match. So the check is the only change.
  - `tracked` and `item.path` hold the real paths of the files, not the copies
    of a snapshot, so `@__DIR__` is `dirname(item.path)`.
  - The check in `rc_warm` reads a `const` that it defines itself, so it calls
    `rc_include_path` with `Base.invokelatest`: the function can not see a binding
    that is newer than its world.

  Test, without a rebuild of Julia: the sources of `ReactiveCompiler` of the
  worktree, loaded into `Main` of the built Julia of `merged-next` (the same
  commit before the change), pass `rc_warm()`. The new check takes
  `include(joinpath(@__DIR__, "warm2.jl"))` as C4 and refuses
  `include(joinpath(pwd(), "warm2.jl"))`, and the `const` of a module gives the
  path where a global that is not `const` gives none.
- [x] **Step 4: the compiler applies a changed docstring of a module.** In
  `rc_classify` of `child.jl`, and in the apply. Test: a check in `rc_warm`.
  After the apply, `@doc` of the module gives the new text, and the module is the
  same object as before.

  Done on 2026-11-06, in the Julia worktree (58014b9669). The
  change has the id H2, the docstring category of the catalog of change ids.
  - `rc_split_module_doc` splits a header into its docstring (`Core.@doc` or
    `@doc`) and the module with the empty body. Two headers are a docstring
    change when their modules are equal without line nodes, also when one of
    them has no docstring.
  - The H2 change takes no old method. The old methods of a change are deleted
    after the apply, and the methods at the line of the old header must stay.
  - The evaluation loop does not evaluate the header of an H2 module change,
    because that makes a new, empty module. It resolves the module by its full
    path, so a root module of a package works too. `rc_set_module_doc!` deletes
    the old entry of `Base.Docs.meta`, so `doc!` prints no "Replacing docs"
    warning, and evaluates in the module the expression that
    `Base.Docs.moduledoc` gives for a module that exists
    (`Base.Docs.docm(…, false)`). So the binding and the metadata are the ones of
    the definition. A header without a docstring removes it.

  Test, without a rebuild of Julia: `rc_warm()` passes with a new check, which
  classifies a header with a changed docstring, a header without its docstring
  and a `baremodule` header (H2, H2, refused C5), and replaces and removes the docstring of a module in place.
  A probe ran `rc_apply_tracked` on a small loaded package, with a new
  `include(joinpath(_SOURCE, "View.jl"))` and a new docstring of its submodule.
  With the changed sources it applies C4, H2 and the new file, with no refusal:
  the submodule is the same object, its docstring is the new text, and `view()`
  gives 42. With the sources of `merged-next` before the change, the same apply
  is refused with the two reasons of the IDE build: C4 "includes a file that is
  not tracked" and C5 "the header of a module changed".
- [x] **Step 5: one rebuild of Julia, and the gate.** Build the Julia of the
  worktree with step 3 and step 4. The gate is a small app that depends on
  `ProjecturedKernel`. It has a `@document` struct, a module with a docstring,
  and a root file that includes with `joinpath(_SOURCE, …)`. Found it, then do
  three edits one after another: add a field to the struct, add a new file with
  `joinpath`, and change the docstring of the module. Each rebuild must apply its
  edit, and the program must show the new state after it. Then do one edit that
  must be refused, a new dependency (F3), and check that the refusal is still
  there.

  Done on 2026-11-06. The Julia of the worktree `julia-rebuild-refusals`
  (58014b9669) took 8 min 51 s with `make -j8`, at a peak of 9.5 GB. The build
  used the `Make.user` of `merged-next` (`JULIA_PRECOMPILE=1`) and copies of
  its `deps/srccache` and `stdlib/srccache`, which hold only downloads.

  The gate is a throwaway app in the scratchpad of the session, in the shape of
  gate I1 of the fork. It is not committed. `GateApp` has a `@document struct
  GateShape` in `Shape.jl`, a module `Notes` with a docstring in `Notes.jl`, and
  a root file with `const _SOURCE = @__DIR__` and `include(joinpath(_SOURCE, …))`.
  `materialize_app` founds it with `track_dependencies = true`, with the
  PackageCompiler of the build environments (`projectured/PackageCompiler.jl`,
  rev `reactive`). The binary prints the fields of `GateShape`, their values,
  the value of `get_view_value` or 0, and the docstring of `Notes`.

  | edit | the Julia of the worktree | `merged-next` and the kernel of `main` |
  | --- | --- | --- |
  | a field `height` | A4 `Shape.jl:1 GateShape`, 23 methods replaced | refused: "the untracked none:0 GateShape names the type" |
  | `include(joinpath(_SOURCE, "View.jl"))` | C4 include, C4 new file `View.jl` | refused C4: "includes a file that is not tracked" |
  | the docstring of `Notes` | H2 `Notes.jl:1 Notes` | refused C5: "the header of a module changed" |
  | `using CRC32c`, not in `Project.toml` | refused F3: "CRC32c is not in the image" | refused F3, the same |
  | `CRC32c` in `Project.toml` and the Manifest, its `using` and a call | C3 using, A2 `print_report` | C3 and A2, the same |

  The founding took 2 min 20 s at 6.7 GB, and each rebuild took 6 to 7 s at
  0.9 GB. After each rebuild that applied, the binary printed the new state. After
  each refusal, it printed the state before the edit.

  Facts found:
  - The rebuild of a field takes the `@document` struct as one macro call,
    A4, "constructors only". The new type and its 23 generated methods replace
    the old ones, because each method now names `Shape.jl:1`.
  - F3 refuses a package that the image does not hold and `Project.toml` does
    not name. The child of a rebuild is a `create_sysimage` process with the
    project of the app, and it loads each direct dependency before the apply. So
    a dependency that `Pkg.add` writes applies as C3, and the binary calls it.
    Both Julia builds do this, so steps 3 and 4 did not change it.
  - A new path package applies too: the store tracks every path package of the
    Manifest, so its root file is a new tracked file (C4).
- [x] **Step 6: the real IDE.** After the user approves the landing of both
  worktrees: rebuild the `+merged` Julia, and found the IDE store with
  `bin/build_omnet_ide --found`. Then add a field to `WidgetTheme` in a copy of
  the change, and run `bin/build_omnet_ide`. The rebuild must apply it. Do not
  commit the field.
  - 2026-11-06: the `+merged` Julia is rebuilt. The founding (omnet main
    b8878b93a, projectured main d4ee8153d) stops after 15 min at 3.8 GB in the
    workload of the IDE: "The window did not draw the target of
    WorkloadWait(DrawnText("DONE", :first))", the `Run` of the `Runner` page.
    This failure is on `main` without this plan (`IdeWorkloadTest.jl:17`, seen
    the same day on omnet 21ec66b1e). The old store and binary stay. The step
    waits for a fix of that workload step.
  - 2026-11-07: the cause of that failure is in the workload, not in this plan.
    `click("Run")` hit the Run of the protocol test runner, which the left pane
    still showed, so the workload never ran the simulations, also on the good
    states of 2026-11-04. The wait for `DONE` passed only while the status line
    of the test page, "Before the tasks: preparing workload — DONE", wrapped, so
    that "DONE" was a text of its own; after the landing one-system-for-space the
    line fits. A bisect of seven states and a trace of the drawn texts found it.
    The fix is on omnet main: 9964a6d45 runs the Runner before the test runner,
    and 831a34b82 waits for `r"^Ran simulations"`, which the page of a finished
    group says for any count of runs. A first wait for `7 DONE` held only for
    the plain workload: `warm_omnet_ide` adds 17 sample file types, an INI file
    and a NED file among them, so the founding found other runs.
  - 2026-11-07: done. The founding (omnet main 831a34b82, projectured main
    91311c4f2) passes in 46 min 53 s at a 24.5 GB peak and writes the store in
    `build/omnet_ide/reactive-store`; the binary starts in 0.05 s. A new field
    `rebuild_test_minimum::IconSize` at the end of `WidgetTheme` applies: the
    rebuild takes 1 min 2 s at 4.1 GB, the server says `change B2
    WidgetTheme.jl:4 WidgetTheme, 143 methods, 5 kept, 137 deleted` and
    `applied 8 expressions and 0 removals`, and snapshot s2 has no refusal. With
    the field removed, the next rebuild takes 17 s: a rebuild compares the
    sources with the founding snapshot s1, so it applies 0 changed files. The
    field was never committed.
  - 2026-11-08: this step checked the apply, but it did not start the rebuilt
    binary. A start after a rebuild crashed in `lookup_root`. The cause is in
    the overlay writer of the Julia fork (`reactive_overlay_emit`,
    `staticdata.c`). It put only the words that differ from the founding file
    in a patch run. A memory reference is two words, its pointer and its owner.
    A rewritten array keeps the pointer offset 0 and gets a new owner, so only
    the owner was in the run. A start of a prelinked binary then added the new
    data address to the old converted pointer. The fix puts both words of a
    reference in a run when either word differs: julia merged-next 34672676c4,
    pushed to levy/julia `merged`. After a library build, a server restart and
    rebuild s3, the binary decodes all 106 015 method sources, and the IDE
    window workload passes in 127 s. No test starts a prelinked binary with an
    overlay. The owner declined a regression test.

## Not in this plan

- The other rules of refusal: a module option (F1), a `using` of a package
  that the image does not hold and `Project.toml` does not name (F3), an
  import that conflicts with a binding (C3), and top-level code outside the
  `module` block of a root file (C5). They need a founding build.
- The refusal of the trimmer (T1) for a trimmed build.
- A count of how many commits of the last weeks a rebuild would have applied,
  before and after this plan.
- A refused build restarts the compiler server.
