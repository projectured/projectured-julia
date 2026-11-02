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

- [ ] 1. **Measure what the design can win.** No change to Julia. Take the
      ten latest commits of projectured-julia that change only the platform
      package. For each, compile the packages before and after the commit,
      and count the packages above the platform whose compiled code and
      top-level reads stay the same. Check: the counts exist for the ten
      commits. If fewer than half of the packages above stay the same, rule
      2 wins little: stop and report.
- [ ] 2. **Rebuild the changed package from its old file** (rule 1). Check:
      after a change of one method body in the platform package, its new
      file is written in at most 15 s, and a new process that loads it gives
      the same answers as one that loads a file compiled from nothing.
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

## Not in this plan

- One store of compiled code for several worktrees of the same commit.
- A faster compile of a package that changed a lot.
