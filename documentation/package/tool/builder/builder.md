# Builder

> **Kind:** design · **Status:** current · **Stands on:** [package-rules.md](../../../rule/package-rules.md), [build-guide.md](../../../guide/build-guide.md)

`ProjecturedBuilder` makes a native binary of a program: it writes a package for the binary, compiles it with PackageCompiler, and can test a copy and pack it as a distribution. It also writes the release copy of the packages that a registry serves. This document describes the architecture: the app package under `build/app/`, the preferences, the distribution, the workload that runs `warm_application()`, and the release copy. [build-guide.md](../../../guide/build-guide.md) holds the steps and the options.

## How it works

### Two halves

The core names no program and no repository: `BuildContext`, `Preference`, `Usage`, `write_app_package`, `build_executable`, `build_distribution`, `build_package_release!` and `collect_outside_paths`. A `BuildContext` gives the root that a build writes into and the folders where `get_package_directory` finds a package by its name, in order. `ProjecturedProgram.jl` is the half of this repository. It describes the binary `projectured`: its backends, its options, its assets, its licences and the test of a copy. It also says which packages go into the registry, which folders each of them reads, and the oldest Julia they name. It names the packages as strings and loads none of them, so a downstream program can use the same core with a context of its own.

The package depends on `Dates`, `Pkg`, `Preferences`, `SHA` and `TOML`, and on no package of ProjecturEd. It loads PackageCompiler only in the step that compiles, through `Base.PkgId` and `Base.require`. So a build that only writes the package, and the tests, need no compiler, and no `import` at run time makes a binding in a later world age.

### The app package

`write_app_package` writes the package that the build compiles, under `build/app/<name>/`. It is a build artefact like an object file: every build writes it again, and nobody commits it.

- **`Project.toml`** gets `[deps]` and `[sources]` from one list of packages, so the two can not disagree. Its UUID comes from the SHA-256 of the module name, so a rebuild keeps the identity of the package and the caches of PackageCompiler stay valid.
- **The module**, `ProjecturedApp` for `projectured`, loads every package and holds the constant `BUILD_INFO` that `--build-info` prints. It takes `--log-level=` out of `ARGS` before the program sees it, and reads `PROJECTURED_LOG_LEVEL` behind the flag. With a `Usage` it answers `--help` and `--version` and stops on an unknown flag; without one, the program owns the command line. On Linux, `_end_on_terminate!` gives `SIGTERM` back its default action on the main thread, so the program ends at once, with exit status 143 and no output. The signal listener of the Julia runtime would take the signal as fatal and print the stack of every thread.
- **Stand-ins.** A JLL that the binary must not carry is named in `stand_ins`. The build writes a package of the same name and uuid under `stand_in/`, with no dependency and empty paths, and lists it in `[deps]` and `[sources]`, so the chain of JLLs behind the real one leaves the manifest and the bundle. `projectured` replaces `alsa_plugins_jll`, which SDL loads and which brings an FFmpeg that nobody may redistribute; the application plays no sound.
- **`julia_main()`** has the expression `main` as its body. `main` and `workload` are `Expr` values, so the parser checks them while the build function runs and not minutes later inside PackageCompiler.

`write_if_changed` writes a file only when its content differs, apart from the line with the build time. Julia takes a changed source file as a stale cache, and this module compiles from nothing at each build. `bin/projectured` writes the same package with `compile = false` and runs its `julia_main` in a Julia session, so a person tries a change with no build.

### The workload

Nothing depends on the app package, so it is a leaf in the sense of [package-rules.md](../../../rule/package-rules.md#why-the-leaf-matters). Its `@compile_workload` runs the expression `workload`, and the compiled code stays in the image. It is the second leaf beside `ProjecturedREPL`; see [repl.md](../repl/repl.md).

For `projectured` the workload is `ProjecturedPlatform.warm_application()`. The binary loads the platform and not the umbrella: it holds a fixed set of packages and imports its domains by name, so AutoIntegration has no part in it. It builds the application window over a temporary folder with files of several formats, on a `ConsoleBackend` with no display. Then it sends a key, a click in the navigator, Enter on a file and a save. Last, it makes a new tab with Ctrl+T and Insert, and types its name key by key. The first key in the name buffer compiles a method for every document type that the buffer can make. A failure of the warm-up is logged, and the build goes on.

### Preferences

A `Preference` is a value that the build writes into `LocalPreferences.toml` of the app package, for one package to read with `@load_preference`. It names that package, because a preference is keyed by the UUID of the package that reads it. `make_baked_preference` makes a value that no flag changes. `make_exposed_preferences` makes the value and a second key, which the program reads to find whether a flag may change the value.

A build value travels as a preference and not as generated code. Julia records a preference read at module scope as a dependency of the precompile cache, so a new value compiles again. A generated file that a module includes only when it exists is not noticed, and the old image keeps the old value. `write_preferences` writes every key at every build, so no value stays from the build before. The `projectured` build passes no preference.

### Compile

`build_executable(context; name, packages, main, workload, …)` checks first that every local dependency has a path in the `[sources]` of the package that uses it, because Pkg can not resolve it otherwise. It then writes the build record, the package and the preferences, and resolves the package. A `Manifest.toml` that names a path with no package, or another path than the project, is deleted first. `compile_app!` calls `create_app` with one executable, `name => "julia_main"`. A caller that links its own launcher, prelinks or trims passes its own `compile_app`. Last, the build copies the fonts and the assets into `share/projectured/` of the bundle.

A build is incremental by default: it compiles on top of the image of the running Julia, which already holds the standard libraries. It compiles for `native`, or for `PROJECTURED_CPU_TARGET`. A distribution passes `incremental = false` and `PORTABLE_CPU_TARGET`, the empty string, with which `create_app` compiles several variants of the architecture.

### Distribution

`build_distribution` proves that a copy of the bundle runs on a machine that did not build it:

1. It checks that each path the build declared in `expect` exists and is not empty.
2. It copies the bundle outside the root: to `TMPDIR`, else `/var/tmp`, because `/tmp` is often a RAM disk.
3. `check_relocation` starts the copy with `--build-info`, an empty `JULIA_DEPOT_PATH` and an empty `JULIA_LOAD_PATH`, under `bwrap`, which puts an empty folder over the checkout, the package folders and the depot. It stops when the build record says `INCREMENTAL BUILD`.
4. The `check` of the program runs. For `projectured`, `check_projectured_copy` starts the copy with `--backend=web --mcp --assistant=none` and reads the web client, a font and the list of guides over HTTP.
5. It copies the licence files, writes the licence texts of what the bundle holds into `share/licenses/` with `bundle_licence_texts!` (the runtime of Julia, the libraries it ships, the packages, and under `data/` the data from others that the code holds, such as the colours of the palettes of `PROJECTURED_DATA_TEXTS`), writes a README with the requirements, and packs `<name>-<version>-<system>-<architecture>.tar.gz`.

### The release copy

Pkg installs only the folder of a package, and a package of this repository includes its code from `source/<group>/<slice>/`, outside that folder. `build_package_release!(context; packages, output, …)` writes a copy in which each package is a folder, `<Name>/`, that holds everything the package reads. All folders are in one release repository, so a registry can serve the copy while this repository keeps its layout:

1. It checks that the set is closed: every package of the repository that a released package depends on is released too.
2. For each package, in dependency order, it writes into a staging folder: the `Project.toml`, the entry file, the slice under `src/` (`source/<path>` becomes `src/<path>`, and the include names the path from `src/`, so a file keeps its depth and a path from `@__DIR__` reaches the same folder), the folders that the package reads while it runs (`assets`), and the licence files. It copies only what git tracks. With `readme`, it writes the `README.md` of the folder, which GitHub shows as the page of the package; `build_projectured_package_release!` takes the sentence and the document of each package from `PROJECTURED_PACKAGE_READMES`, adds the install lines with `ProjecturedRegistry`, which add the package alone, and says when AutoIntegration loads the package, from the table `[auto-integration]` of its `Project.toml`. It stops at a package without an entry.
3. With `tests`, a package with a test package gets `test/`: its `runtests.jl`, the test package and every package it needs that the release leaves out in `test/support/<Name>/`, and a `test/Project.toml` that names them by `[sources]`. `Pkg.test` reads those paths in the installed folder, so a user and PkgEval run the tests of the development repository with no package that a registry lacks. A support package gets the folders that its paths name, and its `assets`.
4. `collect_outside_paths` reads the syntax tree of every file of the copy. A literal `include` path or a `joinpath(@__DIR__, …)` path that leaves the package folder, or names nothing there, stops the build, and so does a path that the scan can not follow. In `test/`, a form that the scan can not follow and a `joinpath(@__DIR__, …)` path inside the package are left to the tests themselves.
5. Each package gets its version. A package whose content did not change keeps its folder byte for byte, so its tree and its version stay; the content leaves `test/` out, so a change of a test gives no new version, and a released folder keeps the tests of its version. A changed package gets the next patch version and caret `[compat]` bounds on its siblings from their versions in this release; a package of another registry gets a caret bound from `environment/all/Manifest.toml`.
6. Only when every package passed does it replace the folders of the changed packages in `output`, the working tree of the release repository, and copy the licence files to its root. Another file at the root stays as it is, and git shows what a release changed.
7. With `workflow`, it writes one workflow for each package with tests at the root, `.github/workflows/<Package>.yml`, so each package has a badge of its own: its job, with the folders of the released packages that its test needs, the folders of its support packages, and the folders of its code. A package that keeps its folder gets the job of the tests it keeps. `build_projectured_package_release!` runs each job on the Julia versions of `PROJECTURED_CI_JULIA_VERSIONS`, Julia 1.12 alone, and a job develops its folders into a new environment, runs `Pkg.test` with coverage, and sends the coverage to Codecov.
8. With `overview`, it writes `README.md` at the root, the front page of the release repository. `build_projectured_package_release!` gives it the install lines, the two ways to load, the setting of each package, `ProjecturedIntegrations`, a table of the integrations with their triggers from the tables `[auto-integration]`, and one row for each package, with the sentence of `PROJECTURED_PACKAGE_READMES`.

The last release is what the last commit of the release repository holds: an uncommitted change stops the build. With `registry`, every version of the last release must be in that registry too, because a registry refuses a version that skips one; `build_projectured_package_release!` checks General unless it gets another registry. The registration is a separate step, in the order that the build answers; [build-guide.md](../../../guide/build-guide.md) holds it.

## How it fits

`ProjecturedBuilder` is a tool: it loads in the environment `environment/build`, and no package of the editor depends on it. The code is the slice `BuilderModule`, in `source/tool/builder/`, and the package exports every name of it. `run_build_command` is its command line; the script `tool/build-binary.jl` and the scripts `bin/build_projectured` and `bin/projectured` call it. The binary it builds holds `Projectured`, the packages that `PROJECTURED_APPLICATION_IMPORTS` names (the console, PDF and the seventeen domains), `ProjecturedOllama`, `ProjecturedAnthropic`, `ProjecturedMCP` and the backend packages that `PROJECTURED_BACKENDS` names, `ProjecturedSDL` for `sdl` and `ProjecturedWeb` for `web`. `main` calls `run_application_command(ARGS; backends)`, and the first backend is the default of `--backend`. `juliac --trim` is a separate experiment that this package does not call; see [static-compilation-guide.md](../../../guide/static-compilation-guide.md).

## Design decisions

- **The core names no program.** A downstream program reuses it with a `BuildContext` and a build function of its own. See [plan/done/application-and-build.md](../../../../plan/done/application-and-build.md).
- **The app package is written, not committed.** What a binary holds is a choice of the build, and a `Project.toml` written once can not hold a choice.
- **`main` is an expression.** A syntax error stops the build function at once, not a compile of several minutes.
- **A build value is a preference.** A change then compiles again, and a stale image can not keep an old value.
- **The copy is tested out of sight of the checkout.** A copy tested where it was built proves nothing: an absolute path into the checkout or the depot works there and nowhere else.
- **An incremental image is never distributed.** One constant, `INCREMENTAL_MARK`, is written by `build_info` and read by `check_relocation`, so the two ends can not disagree.
- **The release copy takes what git tracks.** A coverage file or an editor lock file in a slice never reaches a user, and never changes a version.
- **A package that did not change keeps its folder.** Its tree stays, so the registry sees no new version, and a user downloads nothing for it.
- **A job of the release repository develops the folders of its test, and adds nothing from the registry.** A registry holds a version only after the commit that makes it, so a job that added the siblings from the registry would test the last release and not the commit, and a new `[compat]` bound would not resolve. A support package names a released sibling without `[sources]`, so the folders of a job come from the test project and every support package, not only from the package. The job develops the support packages too: the sandbox of `Pkg.test` keeps the version of a developed sibling only when the manifest of the environment reaches it, and only the test project names a support package, so a sibling that only a support package needs would be resolved again from the registry, where it is not. See [plan/done/release-repository-ci.md](../../../../plan/done/release-repository-ci.md).
- **The last release is the last commit.** The builder reads no registry, and a release copy with an uncommitted change is refused, so a registration that was cut short is safe to run again.
- **The smoke test passes `--build-info`.** The builder writes that flag into every binary. `--version` reaches the `main` of a binary with no usage. A window program can take it for a folder to open, and the measure of the start then does not end.

## Usage

```julia
using ProjecturedBuilder                     # julia --project=environment/build
build_projectured_executable()               # build/projectured/bin/projectured
build_projectured_executable(; compile = false, backends = (:sdl,))
build_projectured_distribution()             # build/projectured-<version>-linux-x86_64.tar.gz
build_projectured_package_release!("../Projectured.jl")   # the release copy of the packages
```

- Test: `test_builder()` of the test package `ProjecturedBuilderTest` runs the layering guard of the builder and the two suites below. The tests compile nothing.
- Test: `test_build_executable()` in `test/tool/builder/BuilderTest.jl`: what a build writes, which inputs stop it, the manifest repair, the staging folder, the licences and the hidden folders.
- Test: `test_package_release()` in `test/tool/builder/PackageReleaseTest.jl`: the layout of the copy, the versions, the bounds, the scan, the test folders, the jobs of the workflow, and a release copy of this repository with its workflow.

## Limits

- A distribution needs `bwrap`, and the test of `projectured` also needs `curl` and the ports 8080 and 9876.
- A file that the program reads at run time needs two changes: a name in `assets`, and a reader that looks in the bundle first. Nothing checks the second.
- A build takes minutes and much memory; [build-guide.md](../../../guide/build-guide.md) gives the numbers.
- The guides live in the copy of `ProjecturedKernel`, so a change to a guide gives the kernel a new version, and Julia compiles every package above it again after an update.
