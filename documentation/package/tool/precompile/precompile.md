# Precompile

> **Kind:** design · **Status:** current · **Stands on:** [compile-ahead.md](../../../design/compile-ahead.md)

`ProjecturedPrecompile` is the one mechanism that compiles a package ahead of time, in this repository and in each repository that builds on its packages. [compile-ahead.md](../../../design/compile-ahead.md) holds the requirements and the decisions; this document says how the package carries them out.

## How it works

### The call of a package

The entry file of a package calls `@compile_ahead` once, at its end, with the workload of the package:

```julia
using ProjecturedPrecompile: @compile_ahead
@compile_ahead begin
    run_natural_rows_workload(JsonModule)
    run_file_workload(JsonModule.JsonFile)
end
```

The workload drives the package as a person does, and it throws an error when a step fails. A package with no workload of its own writes `@compile_ahead` alone, so that it still compiles the calls that an application records for it.

The call defines two names in the package: `run_package_workload()`, which runs the workload, and `PRECOMPILE_FAILURE`, the kept failure or `nothing`. It defines no module, because many entry files bind each submodule of the packages below them under its own name, and a module of the same name in each package would collide there.

A recorded call names each type by the module that defines it. The compile puts the module object in place of the first name of each dotted name, the package itself included, and evaluates the expression in the package. So it defines no name, and a build writes nothing into the image of another package.

### The two preferences

While the package precompiles, the call reads two preferences of the package. Each read makes the image depend on the preference, so a change of one builds the image again.

| Preference | Values | Default |
| --- | --- | --- |
| `precompile_calls` | `"none"`, `"recorded"`, `"live"` | `"recorded"` |
| `precompile_failure` | `"error"`, `"warning"`, `"silent"` | `"warning"` |

At `"recorded"` the package compiles each call of each file `precompile/*.txt` in its folder. At `"live"` it runs its workload. At `"none"` it does nothing. In both cases that compile, the newly compiled code stays in the image, the code of other packages included, as `@compile_workload` of PrecompileTools keeps it. An unknown value stops the build with a message that names the allowed values.

### A failure

A failed workload, or a list of which more than 10 % of the calls no longer resolve (`PRECOMPILE_STALE_SHARE`), is a failure. At `"error"` the build stops. At `"warning"` the build writes a warning and keeps the failure in `PRECOMPILE_FAILURE`, and the package shows it again when it loads: `ProjecturedPrecompile` reports the packages that loaded before it, as in a binary, and each package that loads after it. At `"silent"` nothing shows.

### The recording

A recording runs `run_package_workload()` of a package in a new process under `--trace-compile`, with `precompile_calls = "none"` for that package. A call that the image already holds does not compile again, so a recording on top of a recorded image would write a shorter list each time. A temporary environment first on the load path sets the preference, and the image of `"none"` is cached apart from the others. With no display, SDL runs on its dummy video driver. When the workload fails, the recording keeps the calls that it compiled before the failure and shows the failure in a warning, as the default of `precompile_failure` does for a build.

The trace keeps each call once, sorted, and it drops a call that names `Main` or that does not parse. Julia prints a value in a type parameter with the names of its fields, for example `Rational{Int64}(num=1, den=1)` in each type of Unitful, and that text does not read back. The trace removes the names, and the positional form means the same value. There are three scopes:

- `record_package_calls!(package)` writes `precompile/workload.txt` of the package.
- `record_repository_calls!()` records each package that calls `@compile_ahead`, each one after the packages that it depends on.
- `record_application_calls!(package, application)` runs the workload of the package of a binary while the other packages keep their own recorded calls, so it records only the calls that their workloads do not compile. Each call goes to `precompile/<application>.txt` of the lowest package of the repository that sees each package that the call names. Of two that are equally low, the one that more packages depend on wins. A call that no package sees goes to the package of the application. The old files of the application go first, so that their calls compile again and the trace sees them. A package that loads later can make the code of such a call invalid in the image of the lower package that keeps it, so at the end the recording records the workload of the package of the application again, into its `precompile/workload.txt`. That trace holds each call that the binary still compiles, also each call that compiles again, and the package of the application, which loads last, keeps it.

`compare_display_recordings(package)` traces a workload with a display and without one, and answers the calls that only one of the two compiled.

## How it fits

`ProjecturedPrecompile` depends only on PrecompileTools, Preferences and TOML, so each package of each repository can depend on it. The recording reads the manifest of the environment for the graph of the dependencies, and the folder `package/` of the repository for the packages that call `@compile_ahead`.

## Usage

```julia
using ProjecturedPrecompile
record_package_calls!("ProjecturedJSON")            # one package
record_repository_calls!()                          # each package of the repository
record_application_calls!("ProjecturedBuild", "projectured")   # one application
```

```toml
# LocalPreferences.toml of the environment
[ProjecturedJSON]
precompile_calls = "live"
precompile_failure = "error"
```

## The measurements

`tool/measure-compile-ahead.jl` runs the measurements of U7 of [compile-ahead.md](../../../design/compile-ahead.md): the build time and the size of the image of each package, in a depot of its own; the `using` line and the first frame of the session of the README; the calls that the first window and each gesture of the binary compile (`test_first_window_compiles_little` and `test_gestures_compile_little`, which no default suite runs); and, with `--binaries`, the build time, the peak memory and the size of the binary `projectured`. With `--record` it records the calls of each package and of the binary first. A person runs it by hand, and the release runs it with both options; see [release-guide.md](../../../guide/release-guide.md).

```bash
julia --project=environment/all tool/measure-compile-ahead.jl                       # the measurements
julia --project=environment/all tool/measure-compile-ahead.jl --record --binaries   # what the release runs
```

## Tests

- Test: `test_precompile()` of the test package `ProjecturedPrecompileTest` runs the layering guard, `test_precompile_recording()` and `test_compile_ahead()`.
- Test: `test_precompile_recording()` in `test/tool/precompile/PrecompileRecordingTest.jl`: the trace, the list, the graph of the dependencies, and the package that keeps a call.
- Test: `test_compile_ahead()` in `test/tool/precompile/PrecompilePackageTest.jl`: a probe package in a temporary repository, built in new processes at each value of the two preferences, and recorded once.
