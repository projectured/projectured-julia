# Compile ahead

> **Kind:** decision · **Status:** current; in design, not built yet · **Stands on:** [candidate-requirements.md](../requirement/candidate-requirements.md)

This document is the one design of the compilation ahead of time of the
packages of this repository, of their binaries, and of each repository that
builds on these packages. Each change to a workload, a recording, a preference
of precompilation or the build of a binary follows it. Each repository that
builds on these packages has the same design in its own documentation.

## The issue

Julia compiles a function at its first call, for the types of its arguments. It
keeps the compiled code only in memory, so the code is lost when the process
ends. So each new process waits at the first use of each action.

Example: with no precompilation, the first frame of a data frame takes 48.3 s.

## The requirements

- **U1** A binary loads quickly, and it runs with no compilation, or very
  little, during the load and the use.
- **U2** Packages loaded from source load and run with no compilation, or very
  little, during the load and the use.
- **U3** Packages load quickly, and they compile later, as needed.
- **U4** How much precompilation is done for a package is a preference of
  that package. It chooses between U2 and U3. The preference has three steps:
  1. `:none`: nothing.
  2. `:recorded`: everything recorded in the last run of the workload.
  3. `:live`: everything in the workload.

  The default is step 2, the recording.
- **U5** The recording is made again by hand when a person starts it, and
  automatically before each release. A recording by hand covers one package, all
  packages of a repository, or one application with the packages that it
  records for.
- **U6** The workload of a package does whatever that package needs, so that
  most compilation is avoided at the start and at run time. This is true
  especially for the binary `projectured` and for each binary that a
  repository builds on these packages.
- **U7** This is measured, and the measurements guard the performance:
  - The build time and the size of the image of each package.
  - The time of the `using` line.
  - The time of the first frame, and the part of it that compiles.
  - The calls that compile at the start and at each gesture, the gestures that
    compile more than 10 calls, and the calls that compile again.
  - The build time, the peak memory and the size of each binary.

  A person starts these measurements by hand, and they run automatically
  before each release.
- **U8** Ideally no code is compiled again because of a method invalidation, or
  very little.
- **U9** The build is fast and its result is small, with reasonable effort,
  because it avoids compilation and re-compilation that are not necessary.
- **U10** This design applies to this repository and to each repository that
  builds on its packages, with one mechanism that all of them share.
- **U11** This design is documented explicitly in the documentation of each of
  these repositories, not only in a plan.
- **U12** A preference of each package controls what happens when the
  precompilation of that package fails: when its workload fails, and when lines of its recorded list fail to
  compile. The control has three choices:
  1. Stop the build with an error.
  2. Continue, and show the failure when the session or the binary starts.
     This is the default.
  3. Continue, and show nothing.
- **U13** The build of a binary chooses how the binary is produced, also the
  step of U4 that its packages use.
- **U14** The recording runs with no display, but only if its result is the
  same as with a display. It records the code of the SDL backend too. A check
  compares the list of a run with no display with the list of a run with a
  display.
  - At `:live`, the package runs its workload, and a failure of the workload is
    shown.
  - At `:recorded`, the package does not run its workload. It compiles the
    stored list. The list fails when more than 10 % of its lines no longer
    resolve.

## The solution in principle

Compile the code before the person needs it, and save the compiled code in a
file that a new process loads. Two questions make the whole solution:

- **What** to compile: which functions, for which types of arguments.
- **Where** to save it, so that a new process finds it and can use it.

## What to compile

Julia cannot find by itself which calls a person will make, because most types
are known only at run time. Only a run of what a person does finds them. That
run is the **workload**.

**Decision 1.** Run the workload once, write the list of the compiled calls to
a file, and reuse that list (step 2 of U4). A run of the workload at the build
is step 3 of U4, which the preference chooses.

**Decision 3.** Each package gives its own workload. An application can record
more calls for each package when that is necessary, for example a call that its
own workload makes but the workload of the package does not.

**Decision 7.** A recording runs with `precompile_calls = "none"` for the
packages that it records. A call that an image already holds does not compile
again, so a trace does not see it, and a recording on top of recorded images
would write a shorter list each time.

## Where to save it

A binary saves everything in one system image, which the build of the binary
makes (U1, U13).

**Decision 2.** For packages loaded from source, the recorded calls of each
package go into the image of that package. The REPL package of a repository
can hold more compiled code, for any call. Examples are a call that joins
packages where neither depends on the other, and code that a package loaded
later made invalid. The examples have their own packages, and each one records its
own workload. The REPL package gets a workload of its own only if a measurement
shows that it needs one.

**Decision 4.** The recorded list of a package is a file in the folder of the
package, under version control, so that a release ships it with the package.
Each file has the name of the workload that recorded it:
`precompile/workload.txt` for the workload of the package itself, and
`precompile/<application>.txt` for the calls that an application records for
the package, for example `precompile/projectured.txt`.

**Decision 5.** An application of another repository keeps the calls that it
records for a package of this repository in a package of its own repository
that depends on that package. That image can hold them, because it sees the
types of the package. No repository writes files into another.

**Decision 8.** When an application records, each call goes to the package of
the repository of the recording that sees all the types of the call and that is
lowest in the graph of the dependencies. That package loads in the most
sessions, so the call helps the most sessions. When no package of the repository sees all the types
of a call, the call goes to the package of the application itself, which loads
all the others.

**Decision 9.** Each application has a real package under version control, and
the build of its binary uses that package. So the lists that an application
records for itself have a folder under version control, as Decision 4 needs.

## The preferences

**Decision 6.** Each package has two preferences, in `LocalPreferences.toml`:

```toml
[ProjecturedPlatform]
precompile_calls = "recorded"      # "none", "recorded" or "live" (U4)
precompile_failure = "warning"     # "error", "warning" or "silent" (U12)
```

The values shown are the defaults. The name `precompile_workload` stays free,
because PrecompileTools reads a preference of that name from the same section.

## The code today

The code does not follow this design yet:

- The build writes the package of each application under `build/app/<name>/`
  again at each build, and nobody commits it.
- Each package has the preference `precompile_workload` of PrecompileTools,
  which is only on or off.
- Only the leaf `ProjecturedREPL` has levels: `:none`, `:recorded` and `:live`.
- The workloads in the packages run the gestures at each build, as step 3 does.
  No preference chooses step 2 for them.
