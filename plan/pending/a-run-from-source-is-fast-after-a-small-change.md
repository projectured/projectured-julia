# A run from source is fast after a small change

## The goal

The goal of the user (2026-11-02), in short: there are binary and source
versions. The binary version makes an executable, and that is what the build
scripts are for. The source versions can compile the packages, but load them
as Julia does. Both versions work in a reactive way, and are fast when the
change of the source code is small. With vanilla Julia, all of them work as
usual.

So there are two ways to run the programs of projectured-julia and
omnet-julia:

- **The binary way**: `bin/build_projectured` and `bin/build_omnet_ide` make
  an executable. With the reactive Julia, a rebuild after a small change takes
  about 11 s. This works now.
- **The source way**: `bin/projectured`, `bin/omnet_ide` and the aliases
  `jo`, `jp` and `ji` load the packages as Julia does, and compile a package
  when its compiled file is out of date. This plan makes it fast after a small
  change. It does not work now.

With vanilla Julia, both ways must work as they do today.

The user decided (2026-11-02) that the run scripts run from source and the
build scripts make the binary. Until the source way is fast, the run scripts
stay as they are now: with the reactive Julia and a store, they rebuild the
binary and start it (the user: "leave it as it is"). Step 5 puts them back
on the source way.

## Why the source way is slow now

Measured on 2026-10-31 in projectured-julia, with Julia 1.13.1 on this
machine: a change in `ProjecturedPlatform` makes Julia compile 99 of the 114
packages again, and the longest chain of those compiles takes 279 s.

1. **The changed package compiles from nothing.** The platform takes 101 s,
   and 80 s of that is its list of 11,456 recorded calls: inference 39 s,
   code generation about 12 s, the write about 24 s.
2. **Every package above it compiles from nothing too.** A compiled package
   file names the exact build of each package that it depends on, and points
   into their files by position. Julia does not know which parts of a
   dependency a package used, so a new build of the dependency makes every
   file above it out of date.

## The design

These are my recommendations; each step checks them before the next one.

1. **The changed package is rebuilt from its old compiled file.** The
   reactive Julia loads the old file of the package, applies the changed
   definitions, as the reactive compiler does for the executable, and writes
   the new file. It keeps the compiled code of every function that the change
   did not reach, so it does not run the inference and the code generation of
   the whole recorded list again.
2. **The packages above keep their compiled files.** The new file of the
   changed package keeps every object at its old position and puts the change
   on top, as the executable does with its overlay. So a file above still
   points at the right objects. A changed method becomes a new method object,
   as a redefinition in Julia does, so the check that Julia already runs when
   it loads a compiled file drops each compiled function that called the old
   method. Julia compiles that function again when the program first calls it.
3. **What that check does not see is recorded.** While a package compiles,
   its top-level code can read its dependencies: it expands their macros,
   computes with their constants, and names their types. The reactive Julia
   records these reads for each compiled file. A change of one of them makes
   that file out of date, and it is rebuilt by rule 1.
4. **Vanilla Julia sees no change.** Only the reactive Julia writes and reads
   the new files. Julia checks which Julia wrote a compiled file, so a vanilla
   Julia never loads one of them and compiles its own, as today. The scripts
   and the aliases need no switch: they get the fast way when the Julia that
   they find is the reactive one.

The work is in the Julia fork: the loading of compiled packages
(`base/loading.jl`), the format of a compiled package file
(`src/staticdata.c`), and the apply of the reactive compiler
(`contrib/reactive-compiler`). The two repositories change only in step 5.

**Rejected: one compiled image for the whole session.** `jo` could start from
one image that holds every package, rebuilt as the executable is. The user
wants the packages loaded as Julia does, and a package that the session loads
later, such as a test package, would still compile from nothing.

## Steps

Each step has a check. If a check fails, stop and report.

- [x] 1. **Measure what the design can win.** No change to Julia. Take the
      ten latest commits of projectured-julia that change only the platform
      package. For each, compile the packages before and after the commit,
      and count the packages above the platform whose compiled code and
      top-level reads stay the same. Check: the counts exist for the ten
      commits. If fewer than half of the packages above stay the same, rule
      2 wins little: stop and report. **Done 2026-11-03: every package above
      stays the same in all ten commits.** The method and the results are in
      "Step 1: the measurement" below.
- [x] 2. **Rebuild the changed package from its old file** (rule 1). Check:
      after a change of one method body in the platform package, its new
      file is written in at most 15 s, and a new process that loads it gives
      the same answers as one that loads a file compiled from nothing.
      **Done 2026-11-03: the patch of the platform is written in 2.7 s, and
      the platform suite gives the same results as after a whole compile.**
      The design as built and the results are in "Step 2: the patch of a
      package file" below.
- [x] 3. **Keep the files above** (rules 2 and 3). Check: after the change
      of step 2, a new process loads all 114 packages of projectured-julia
      and compiles no other package. Three changes in the platform: a method
      body keeps the files above; a changed macro and a changed constant
      rebuild the files that read them. The answers are correct after each.
      The load time is measured against today's.
      **Done 2026-11-03: after a method body change a load of all 125
      packages writes only the patch of the platform; a changed macro and a
      changed constant compile only their readers and the packages above
      them; the platform suite gives the same results as after a whole
      compile; the load takes 17.4 s against 16.6 s with no change.** The
      design as built and the results are in "Step 3: keep the files above"
      below.
- [x] 4. **Use it in omnet-julia.** Check: the same change of the platform
      package, then `jo` loads every package of `OmnetRepl` in at most 15 s
      more than a start with no change.
      **Done 2026-11-03: the first start of `jo` after the change takes
      27.0 s against 22.8 s with no change, and writes only the patch of the
      platform; later starts take 22.9 s; Revise in the session revises an
      edit and keeps the patched method.** The design as built and the
      results are in "Step 4: use it in omnet-julia" below.
- [ ] 5. **The run scripts run from source again**, and the guides say how
      the fast way works. Check: with the reactive Julia, a change of the
      platform, then `bin/omnet_ide` and `bin/projectured` start from source
      in at most 15 s more than with no change. With vanilla Julia 1.13.1,
      `jo`, `jp`, `ji`, `bin/omnet_ide`, `bin/projectured`,
      `bin/build_omnet_ide` and `bin/build_projectured` work as they do
      today.

## Step 1: the measurement

**The method.** The ten commits, oldest first: 9f69cea5f, 02cc25e0c,
da66da0f0, d84c2f19b, 221e106fe, 1d0961f99, 51fdc9ebd, 7990ce187, 56f470093
and dee4bc5f2. For each commit, the reactive Julia compiled `environment/all`
before and after it, with 4 compile tasks and a depot of its own. Then a script
loaded all packages (122 to 125) and wrote a digest of each package:

- each method: the hash of its lowered code;
- each type: its super type and its field types;
- each constant: its printed form;
- each compiled function in a loaded file: the key of `ReadKey` from
  `contrib/reactive-compiler`, which covers its own code, the globals that it
  reads and the keys of the functions that it calls.

A package keeps its file when its methods, types and constants are the same
before and after. Two digests of the same state are equal, checked before the
run.

**The results.**

| Commit | Platform definitions changed | Packages above that keep their file | Compiled functions that change, platform and kernel | Today's compile after the commit |
|---|---|---|---|---|
| 9f69cea5f | 1 | 97 of 97 | 0 | 394 s |
| 02cc25e0c | 3 | 97 of 97 | 36 | 423 s |
| da66da0f0 | 2 | 97 of 97 | 53 | 398 s |
| d84c2f19b | 22 | 97 of 97 | 369 | 594 s |
| 221e106fe | 3 | 98 of 98 | 27 | 359 s |
| 1d0961f99 | 2 | 98 of 98 | 3 | 333 s |
| 51fdc9ebd | 4 | 98 of 98 | 0 | 350 s |
| 7990ce187 | 7 | 98 of 98 | 38 | 353 s |
| 56f470093 | 11 | 98 of 98 | 58 | 341 s |
| dee4bc5f2 | 2 | 98 of 98 | 58 | 334 s |

No compiled function of a package above changes, in any commit. The platform
and the kernel together have about 120,000 to 170,000 compiled functions, and
at most 369 of them change. Julia compiles these again at their first call. The
count of a package above holds only its own methods: a compiled copy of a
platform or kernel method in a file above counts under the platform or the
kernel.

**The differences that are not a read of the platform.** The comparison showed
five, and none of them makes a file out of date:

- `json_*_live` of `ProjecturedSDLExample` and `_WARMUP_EVENTS` of
  `ProjecturedExample` hold `time()` from the compile, so each build differs.
- The `_enum_hash` method of `@enum SqlTokenKind` holds a hash that differs in
  each build.
- The docstring table of `ProjecturedPDF.PdfModule` prints in one of two
  orders at random.
- `EDITOR_SYSTEM` of `ProjecturedAll` and `ProjecturedREPL` is a `using` of the
  platform name. The kept file refers to the platform binding, so it reads the
  new value. Step 3 must keep this true.

## Step 2: the patch of a package file

Built in the Julia fork, branch `fast-source-run` (worktree
`workspace/julia-fast-source-run`, from `merged-next` 9f976ebb6d), commits
6a74737a2f, 1c0d097366 and 56d740f7b9.

**The design as built.**

- The new file of a changed package is a **patch**: two small files beside
  the old file, `<file>.patch.ji` and `<file>.patch.so`. The old file stays
  as it is.
- `Base.compilecache` makes the patch when the sources of a package changed
  and a file of it is fresh in all else. The patch build is a precompile
  process: it loads the old file, applies the changes of the sources since
  that file with the apply of the reactive compiler (`rc_apply_tracked`),
  compiles again the code that the changes closed, and writes only that.
- The loader loads the patch right after the old file. So the package keeps
  the build id of its old file, and a file of a package above still loads.
  Julia's check of the edges at the load of that file drops the code that
  called a replaced method, and Julia compiles it again at its first call.
- The patch is a module of its own (`<name>#patch`). A file that Julia
  compiles while a patch is loaded names this module, so a new patch makes
  that file out of date. A file compiled before the patch does not name it.
- Every patch is made from the old file, as every overlay of the executable
  is made from its founding. Patches do not stack. (Step 3 replaced this
  with a chain of patches; see "Step 3".)
- The patch carries what no file can carry: the new bindings of the package
  (the type of a changed closure), the deleted methods and the changed
  docstrings. The loader installs them.
- The patch build takes three kinds of change: a new, a changed and a
  removed method (A1, A2, A3 of the change catalog). It refuses all others,
  and a changed `__init__`; the package then compiles whole, as today.
  Reason: until step 3 records the top-level reads, a file above must not
  keep a value that a changed macro, constant or type made old.
- `JULIA_REACTIVE_PACKAGE_PATCH=0` turns the patch off.
- The runtime opens the modules of the patched package to the patch build:
  the checks of an eval and of a new global in a closed module, of a method
  overwrite and of a method delete, and the writer keeps the new methods of
  a module of an older file.

**Rejected: the overlay of the executable for a package file.** The
overlay code is tied to the system image: 848 lines of `staticdata.c` name
it. Julia already loads a later file that adds methods to the functions of
an earlier package, and replaces a method with the same signature as a
redefinition does.

**The results.**

- A toy pair of packages, B calls A: a changed body, a changed closure and a
  removed method of A each write a patch in under a second. The answers are
  right, and B keeps its file. A changed constant compiles A and B whole.
- The platform of projectured, a change of the body of `_child_w`
  (`source/platform/layout/LayoutToGraphics.jl`): `compilecache` of the
  platform takes **2.67 s**, against 102 s for its whole compile. The patch
  process loads the old file in 1.06 s, applies the change in 0.8 s, and
  compiles 21 of the 23 closed functions again in 0.1 s. The patch is 52 KB
  of header and 130 KB of native code. In a new process the method has the
  new body, and its object comes from the patch.
- The answers: `test_platform()` on the patched build and on a whole compile
  of the same sources in another depot give the same result: 174,794 passes,
  3 failures and 7 broken. The outputs differ only in temporary folder names
  and times. The patched run compiled no package again; it took 1,345 s and
  10.6 GB, the whole compile 1,439 s and 11.8 GB.
- The 3 failures are on `main` 408c71359 in both builds: the layering rule
  about a `using` with a name list (`FileChangeModule.jl`), an interface count
  of 33 against 32, and a docstring of `WidgetLink` without "Use it to".

**Open for the next steps.**

- `Pkg.precompile` compiles the packages above again when a dependency
  compiled in the same run, even when its build id stayed. Step 3 must change
  that, or rule 2 holds only for `using`.
- A method below an edit keeps its old line number in a stack trace.
- Revise reads the source text of the old file, so in a session it applies
  the changes since the old file again (step 4).
- Each rebuild of the system image of the fork makes every package file out
  of date, as in any Julia.

## Step 3: keep the files above

Built in the Julia fork, branch `fast-source-run`, commits 689dedb96c,
74ba7050c9, bab8c6e89c, e8bcf5d744 and 8c24db4d53.

**What changed from step 2.**

- **The patches form a chain.** Patch k is made on top of the file and of
  patches 1 to k-1, at most 32. Each patch is a module of its own,
  `<name>#patch<k>`, with files in a cache folder of its own. Reason: when
  every patch was made from the old file, a file above that Julia compiled
  with patch 1 loaded named patch 1, and patch 2 replaced it. So each patch
  made that file out of date, and `Pkg` and a load of the package above alone
  did not find the patch module.
- The loader finds the package of a patch among the modules that a file
  requires. A patch is fresh while the includes of the last patch of the
  chain match the sources.
- A patch carries the methods that moved to another line, so a stack trace
  shows the new line. This closes an open item of step 2.
- **Rule 3, the stamps of names.** A whole compile records each constant and
  each macro of another package that its top level names. Each one is a
  stamp file in the folder `<file>.names` of the file of that package, and
  the compile records it as an `include_dependency`. A stamp holds "base", or
  the id of the last patch that changed the name. A patch that changes a name
  writes its own id into the stamp, so only the files that read the name go
  out of date. A method body that reads a constant needs no stamp: Julia's
  check of the edges at the load drops its code.
- The names that a top level reads are the heads of its macro calls and the
  names in its expressions. A method definition at the top level counts too,
  so the set is larger than needed. This is safe: a file compiles when it
  did not have to, never the reverse.
- The patch build takes a changed constant and a changed macro (C1 and D1 of
  the change catalog) as well as A1, A2 and A3. It still refuses a changed
  type, a non-constant global, a changed `__init__` and a changed include
  that is no source file.
- A changed constant with an equal value is no change. The patch changes no
  binding and no stamp.
- **A name that a patch adds** is defined from the require world on, as a
  name of a package file is. A name that a patch adds is a closure type or a
  keyword body. A changed name of the file is declared at the current world,
  and that drops the code that reads it. Reason: the first platform run
  failed an assertion in `scan_new_method!` at the load of a file compiled
  on top of a patch with 126 new names. The install had declared them at the
  current world, and Julia's fast check of the bindings of a file expects
  that no binding that a file names starts after the require world.
- A patch carries the counter of generated names of each module of its
  package, and its load raises each counter. Reason: the counter is in the
  module of the package file, so the build of the next patch started from it
  again and could make a name that an earlier patch made.

**The results.** The scratch checkout of projectured-julia at `main`
408c71359, `environment/all` with 125 packages, a new depot. The changes
come one after the other, in the order of the table. The numbers are from
the last run, with all fixes.

| Change | What compiles | Time | Load after |
| --- | --- | --- | --- |
| None | all, whole | 427 s | 16.6 s |
| Method body of `_child_w` | the patch of the platform, at the load | 22.0 s for the load | 16.9 s |
| Macros `@insertion` and `@domain` | the patch, and 68 packages whole | 260 s | 16.9 s |
| `color_black` to an equal value | the patch | 4.6 s | 16.9 s |
| `RUN_RESULT_CODES` to a new value | the patch, and 25 packages whole | 179 s | 17.4 s |

- After the change of the method body, a load of all 125 packages writes
  only the patch of the platform. Then `Pkg.precompile` compiles nothing, in
  1.0 s. This closes the other open item of step 2.
- The macro change: 10 packages read `@domain` or `@insertion` at their top
  level. The 68 packages that compiled are these 10 and the packages that
  load them; the manifest and the imports give the same set. All others
  kept their files. The patch of the platform holds 126 new names, deletes
  71 methods and compiles 134 of 215 closed instances again: load 1.2 s,
  apply 2.2 s, compile 0.8 s. Each deleted method names `TextBlock` or
  `EvaluatorToplevel`, the two types that the patch makes again.
- The constant change: the patch changes 3 names, the constant and its two
  re-exports. Only `ProjecturedPlatformTest` reads it at its top level, and
  the 25 packages are it and the packages that load it.
- The load of all packages with the chain of 4 patches takes 17.4 s, against
  16.6 s with no change.
- The toy of four packages gives the right answers after a constant, a macro
  and a method body change, and `Pkg.precompile` and a load of one package
  alone compile nothing more.
- The answers: the platform suite on the depot with the chain of 4 patches,
  and on a whole compile of the same sources in a new depot, gives the same
  result: 174794 pass, 3 fail, 7 broken. The 3 failures are the same tests
  in both, and they are checks of the source: `CheckLayering.jl:889` and
  `InterfaceApiTest.jl:46` and `:49`. The suite compiled no file in either
  depot.

**Faults found by the check, and fixed.**

- `binding_module` throws for a name that two imports give (`DecFP`), so a
  whole compile of that package failed. The record of the names skips that
  name: it has no owner module and no stamp.
- The 126 new names of a patch, above.
- The counter of generated names, above.
- A refused patch left an empty folder.
- The first suite run of the patched build had 1 error that the whole
  compile did not have: `TextInsertion(::String)` had no method. The macro
  patch deleted the 9 methods that the expansion of `@domain` in the
  platform makes. So it deleted 80 methods, not 71. The reactive compiler
  gives an entry the methods at its
  lines, and a method that a macro expansion makes carries the lines of the
  macro body. So the definition of the macro owned the products of all its
  expansions. The expansion made the same methods again, and the method
  filter kept the old ones, so the new definition did not have them and the
  apply deleted them. Now a macro owns only the methods whose signature
  names the macro: its own method and the functions of its body. The fault
  is in the reactive compiler, so the executable had it too. The toy now has
  a macro of PA that defines a method of PA, and the macro change keeps the
  product the same; without the fix the toy fails with the same error.

**Open for the next steps.**

- A changed macro that many packages use compiles them whole, and all the
  packages above them: 68 packages for `@domain`, 277 s against 424 s for
  all. A patch of a reader whose sources did not change could expand its
  macro calls again. This is not in this plan.
- A changed constant of a file makes Julia take the full check of the
  bindings at each later load of a file. The load time did not change by a
  measurable amount (17.5 s against 17.1 s).
- A method that a macro call makes belongs to no entry. So when a macro call
  is removed, its methods stay until a whole compile.
- Revise reads the source text of the old file. Step 4 closed this.

## Step 4: use it in omnet-julia

**The method.** A scratch copy of omnet-julia at `main` a0dde28db, beside a
copy of projectured-julia at `main` 6938caf1c and the four repositories that
their packages name by a path. The `Manifest.toml` of `environment/all` comes
from the checkout of the user. A new depot, then `~/.julia` for the
registered packages. The start of `jo` is the command of the alias with no
startup file: `using Revise, OmnetRepl` in `environment/all`. The change is
the method body of `_child_w` of step 2.

**Revise after a patch.** Revise reads the text of a file from the package
file at the first edit of the file in a session, and compares the edit with
it. After a patch, that text is older than the code that the session runs.
So Revise applied the changes of the patch again: in the toy, an edit of `g`
after a patch of `f` defined `f` again. Now the loader keeps the texts that
the last patch of a fresh chain holds, and `Base.read_dependency_src` gives
them for the file of the package. The last patch holds every file that
differs from the package file, so it holds the text that the session runs.
Revise needs no change. The build of a patch loads the chain that is not
fresh, and it keeps reading the text of the package file. Built in the Julia
fork, branch `fast-source-run`, commit 66f9946a11. The toy now gives the
right answer: the edit of `g` keeps the method object of `f`.

**The results.** Each start is a new process. `jo` loads 405 packages, and
406 with the patch module.

| State | What compiles | `using Revise, OmnetRepl` |
| --- | --- | --- |
| Whole compile of `environment/all` | all | 616 s |
| No change, three starts | nothing | 22.8 to 23.0 s |
| After the change, the first start | the patch of the platform, at the load | 27.0 s |
| After the change, three more starts | nothing | 22.8 to 22.9 s |

- The patch build of the platform takes the same time as in step 2: load
  1.2 s, apply 0.8 s, compile 0.2 s, and 21 of 23 closed instances compiled
  again.
- No package of omnet-julia compiled again.
- Revise in a `jo` session with the patch: an edit of `_child_h` in the same
  file as `_child_w`, then `Revise.revise`. `_child_h` has a new method, and
  `_child_w` keeps the method object of the patch. The revise takes 4.9 s,
  of which 1 s is the wait for the file event.
- Then `Pkg.precompile` compiles nothing, in 1.3 s.
- The cost of the change without the patch was not measured in omnet-julia.
  The whole compile, 616 s, is its upper limit.

## Step 5: the run scripts run from source

**What changes.**

- [x] `prepare_program_start!` writes the package of the binary with
      `compile = false` and answers the package and its module. It has no
      branch that rebuilds and starts the binary, and no notice.
- [x] `bin/projectured` and `bin/omnet_ide` load that package as Julia does.
- [x] The test of `prepare_program_start!` follows. `test_build_executable()`
      and `test_builder_layering()` pass with Julia 1.13.1: 371 tests.
- [x] The guides say how a start is fast after a small change: the build
      guide and the builder document in projectured-julia, and the guide of
      the reactive build in omnet-julia. The function moved to
      `AppPackage.jl`, beside `get_app_module_name`, because it reads no store.
- [ ] The check of step 5.
- [ ] The comparison below.

**The comparison.** The user (2026-11-03): "At the end I want to see a
comparison between vanilla and reactive for various building and starting
cases." Vanilla is Julia 1.13.1 (`julia +1.13`); reactive is the fork, branch
`fast-source-run`. Each case runs in a scratch copy with a new depot, for
`projectured` and for `omnet_ide`:

1. A build of the binary from nothing: a plain build, and the founding of a
   store.
2. A build of the binary after a method body change of the platform: a plain
   build, and a rebuild.
3. A start of the binary.
4. A start from source in a new depot.
5. A start from source with no change.
6. A start from source after a method body change of the platform.
7. With the reactive Julia, a start from source after a macro change and
   after a constant change of the platform. Vanilla Julia compiles the same
   packages for every change of the platform, so case 6 stands for it.
8. `jo` with no change and after the method body change.

A start is the start of the program with `--build-info`, which prints after
the load of every package of the program and exits. So it measures the load
and the compile of packages, and not the first frame.

## Not in this plan

- One store of compiled code for several worktrees of the same commit.
- A faster compile of a package that changed a lot.
