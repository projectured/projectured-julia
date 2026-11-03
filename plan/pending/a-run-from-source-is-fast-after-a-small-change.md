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
- [ ] 3. **Keep the files above** (rules 2 and 3). Check: after the change
      of step 2, a new process loads all 114 packages of projectured-julia
      and compiles no other package. Three changes in the platform: a method
      body keeps the files above; a changed macro and a changed constant
      rebuild the files that read them. The answers are correct after each.
      The load time is measured against today's.
- [ ] 4. **Use it in omnet-julia.** Check: the same change of the platform
      package, then `jo` loads every package of `OmnetRepl` in at most 15 s
      more than a start with no change.
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
  is made from its founding. Patches do not stack.
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

## Not in this plan

- One store of compiled code for several worktrees of the same commit.
- A faster compile of a package that changed a lot.
