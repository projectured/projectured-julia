# Release the packages

> **Kind:** procedure · **Status:** current · **Stands on:** [builder.md](../package/tool/builder/builder.md), [own-project-guide.md](own-project-guide.md)

A release gives a new version to each package that changed, and puts the
versions into the registry `ProjecturedRegistry`. This guide says what to check
before a release, how to write, test and publish it, and how to check it as a
new user. [builder.md](../package/tool/builder/builder.md) says how the build
makes the release copy.

## The repositories

| Repository | What it holds |
| --- | --- |
| this repository | the source of every package of the release |
| [projectured/Projectured.jl](https://github.com/projectured/Projectured.jl) | the release repository: one folder for each package, the licence files, one workflow for each package with tests, and the front page. The build writes all of it. Do not change it by hand. |
| [projectured/ProjecturedRegistry](https://github.com/projectured/ProjecturedRegistry) | the registry. `LocalRegistry` writes it. |
| [AutoIntegration.jl](https://github.com/projectured/AutoIntegration.jl), [AgentClientProtocol.jl](https://github.com/projectured/AgentClientProtocol.jl), [ClaudeCodeACP.jl](https://github.com/projectured/ClaudeCodeACP.jl), [ModelContextProtocol.jl](https://github.com/projectured/ModelContextProtocol.jl) | packages that the release depends on. Each one has its own repository, and the registry holds it from there. `environment/all` finds each one in a folder beside this checkout. |

The packages are not in General. The registry `ProjecturedRegistry` is the
place of each release until they move there.

## Warnings

- **Do not change a version that the registry holds.** A user who installed it
  keeps its tree. A later change is a new version.
- **Do not rewrite the history of the release repository.** The registry names
  each version by the git tree of the package folder, and Pkg must find that
  tree for as long as the version exists.
- **Do not make a release from a checkout with uncommitted changes.** The build
  copies the files that git tracks, but it reads them from the working tree. An
  uncommitted change goes into the release, and no commit holds it.

## The versions

The build gives each package its version. It reads the last release from the
last commit of the release repository.

- A package whose content did not change keeps its folder and its version.
- A changed package gets the next patch version: `0.1.1` becomes `0.1.2`.
- A changed package that no longer exports a name gets the next minor version:
  `0.1.2` becomes `0.2.0`. From `1.0.0`, it gets the next major version. The
  build reads the names of each `export` statement under `src/`, and the struct
  of each `@document` and `@projection`. It writes the names to the log, after
  "no longer exports".
- A package that depends on a package with a new minor version gets the next
  patch version, with a bound on the new minor version, also when it did not
  change.
- A new package gets `0.1.0`.

Each changed package names its siblings with a caret bound on their version in
this release. It names a package of another registry with a caret bound on the
version in `environment/all/Manifest.toml`. The Julia bound is
`PROJECTURED_JULIA_COMPAT` in
[ProjecturedProgram.jl](../../source/tool/builder/ProjecturedProgram.jl).
Because of these bounds, a user updates all packages of ProjecturEd together.

## Before the release

1. If a package of another repository changed, release it first:
   1. Increase the version in its `Project.toml`.
   2. Commit the change, and push it to its repository.
   3. Resolve `environment/all` again in this repository, so that its manifest
      names the new version.
2. Land every change of the release on `main`, the manifest too, and push it.
3. Make sure that the CI of this repository passes on that commit: the static
   guards and the job of each test package.
4. Clone this repository at that commit into a new folder beside this
   checkout, for example `../projectured-julia-release`. The folder must be
   beside the checkouts of the other repositories, because `environment/all`
   finds them there.
5. Clone the release repository and the registry into a work folder, for
   example `/var/tmp/release/Projectured.jl` and
   `/var/tmp/release/ProjecturedRegistry`.

## Write the release

1. Write the release into the clone of the release repository:

   ```julia
   using ProjecturedBuilder        # julia --project=environment/build, in the new clone
   results = build_projectured_package_release!("/var/tmp/release/Projectured.jl";
       registry = "/var/tmp/release/ProjecturedRegistry")
   order = [r.folder for r in results if r.status !== :unchanged]
   ```

   The build reads the packages of the checkout that holds the builder, here
   the new clone. `results` lists each package with its status (`:new`, `:changed` or
   `:unchanged`) and its version, dependencies first. The build stops if a
   version of the last release is not in the registry, because a version that
   skips the one before it can not go into a registry.
2. Read the log for "no longer exports". Each such line gives a package a
   minor step. If the step is not what you want, give the name back in this
   repository. Then discard the changes in the clone of the release
   repository, because the build stops on uncommitted changes, and start
   again from step 2 of "Before the release".
3. Read `git status` of the release repository. The folders of the changed
   packages and their workflows change. The front page changes when a row of
   it changes.
4. Commit the release repository. The message names the commit of this
   repository, for example "ProjecturEd: 84 packages 0.1.2, from
   projectured-julia 07f118d48".

## Test the release as a new user

Do this before the publication. The check compiles every package for some
minutes, so give each Julia process a memory cap and a timeout.

1. Copy the clone of the registry, with its `.git` folder, to a scratch
   registry, for example `/var/tmp/release/scratch-registry`.
2. Register each changed package in the scratch registry, with
   `repo = "file://…"` and `push = false`. First register the packages of the
   other repositories, then the folders of `order`.
3. Run each way of the front page of the release repository, as a new user
   types it:

   ```sh
   julia tool/check-release-as-new-user.jl /var/tmp/release/new-user /var/tmp/release/scratch-registry
   ```

   The script starts Julia again with a new `HOME` in the work folder, so the
   depot is empty and has no git credentials. It adds General and the
   registry, and runs each way in a new environment, with the window
   offscreen. Each way adds its packages, loads them, and shows a data frame
   with `display_in_editor`:
   - `using Projectured, DataFrames, SimpleDirectMediaLayer`, which loads the
     integrations;
   - each package by name: `using DataFrames, ProjecturedSDL,
     ProjecturedDataFrames`;
   - the setting `"manual"` of AutoIntegration, which must keep
     `ProjecturedDataFrames` out of the session;
   - `using ProjecturedIntegrations, DataFrames, SimpleDirectMediaLayer`.

   The last line, `RESULT`, gives each way `pass` or `FAIL`. Each display
   prints `FIRST FRAME`: after the compile, the first frame of the data frame
   takes about a second.
4. Do step 3 on the oldest Julia that the packages name, for example with
   `julia +1.12`, and on the newest. Use a new work folder for each run.

## Publish the release

1. Register each changed package in the clone of the registry, in the same
   order as in the scratch registry:

   ```julia
   using LocalRegistry
   register("../auto-integration";
            registry = "/var/tmp/release/ProjecturedRegistry",
            repo = "https://github.com/projectured/AutoIntegration.jl.git", push = false)
   for folder in order
       register(joinpath("/var/tmp/release/Projectured.jl", folder);
                registry = "/var/tmp/release/ProjecturedRegistry",
                repo = "https://github.com/projectured/Projectured.jl.git", push = false)
   end
   ```

   Register a package of another repository only when its version changed.
   LocalRegistry finds the folder of a package in the release repository, and
   the registry records its tree.
2. Push the release repository. The push starts the workflows: a job for each
   package with tests, on the Julia versions of `PROJECTURED_CI_JULIA_VERSIONS`.
   A job sends its coverage to Codecov. The upload needs the Codecov app on
   `projectured/Projectured.jl`, but a job does not fail without it.
3. Wait until every job passes.
4. Push the registry. This step publishes the release: a user gets the new
   versions at the next `pkg> update`.

If a job fails, do not push the registry. Fix the cause in this repository, and
make a new release on top of the one that failed. The clone of the registry
holds the versions that failed, so the build accepts them as the last release,
and the fix gets the next version. The registry then holds both versions, and
`pkg> update` gives the newest.

## After the release

1. Do the check of "Test the release as a new user" again, with the published
   registry. Without a registry argument, the script adds the published one:

   ```sh
   julia tool/check-release-as-new-user.jl /var/tmp/release/new-user-published
   ```
2. If the install lines changed, change them where they are written:
   - [README.md](../../README.md) of this repository;
   - [setup-guide.md](setup-guide.md) and
     [own-project-guide.md](own-project-guide.md);
   - the page "Try it" of the website.

   The build writes the front page of the release repository and the README of
   each package, so the release already holds their changes.

## Register in General

The packages are not in General yet. When they move there, General accepts
only `0.0.1`, `0.1.0` or `X.0.0` as the first version of a new package, and
each later version must not skip one. Register one level of dependencies at a
time, with a comment on the release commit, for each package:

```
@JuliaRegistrator register subdir=<Name>
```

A package goes into General only after the packages it depends on, because
General installs each new version to test it. A new version of a package that
General already holds merges after 15 minutes; the first version of a new
package waits 3 days.

## Where the pieces are

| Path | What |
| --- | --- |
| [source/tool/builder/PackageRelease.jl](../../source/tool/builder/PackageRelease.jl) | `build_package_release!`: the release copy, the versions, the scan of the paths |
| [source/tool/builder/ProjecturedProgram.jl](../../source/tool/builder/ProjecturedProgram.jl) | `build_projectured_package_release!`: which packages the release holds, their READMEs, the front page, the workflows and the Julia bound |
| [environment/build/](../../environment/build/) | the environment of the build |
| [tool/check-release-as-new-user.jl](../../tool/check-release-as-new-user.jl) | the check of a release as a new user, way by way |
| [test/tool/builder/PackageReleaseTest.jl](../../test/tool/builder/PackageReleaseTest.jl) | `test_package_release()`: the copy, the versions, the bounds and the scan |
