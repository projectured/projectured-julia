# The developer environments hold no Cairo

**Status: DONE on 2026-11-25.** Written on 2026-11-24. The owner approved it on 2026-11-24 ("yes,
implement both plans"), and added the sound plugins ("yes, remove the sound-plugins in the
developer environment"). The owner approved the landing and the push on 2026-11-25 ("Land and
push"). It landed on `main` of projectured-julia, omnet-julia and inet-julia.

## The ask

The owner asked: "We should try to get rid of the cairo dependency, what are we using it for?" The
answer was: no code uses Cairo, and neither binary holds it, but the developer environments do. To
the question "Do you want me to plan the removal of Cairo from the developer environment too?", the
owner said: "Yes". With the approval, the owner also said: "yes, remove the sound-plugins in the
developer environment". So `alsa_plugins_jll` moved from "Not in this plan" into decision 1.

## What the environments hold now

| Environment | Packages | Cairo comes by |
| --- | --- | --- |
| projectured-julia `environment/all` | 338 | `ProjecturedVideo` → `FFMPEG`, and `SDL2_jll` → `alsa_plugins_jll` |
| projectured-julia `environment/readme-data-frame` | 161 | `SDL2_jll` → `alsa_plugins_jll` |
| omnet-julia `environment/all` | 426 | both ways |
| inet-julia `environment/all` | 290 | both ways |

Both ways end in one chain: `FFMPEG_jll` → `libass_jll` → `HarfBuzz_jll` → `Cairo_jll`. An empty
`Cairo_jll` frees three packages in each environment: `Cairo_jll`, `Pixman_jll` and
`LLVMOpenMP_jll`. The counts come from the manifests of 2026-11-22 (projectured-julia `all`,
omnet-julia) and 2026-10-29 (`readme-data-frame`, inet-julia).

## The facts that the steps use

- **No code uses Cairo.** No source file of the three repositories names it. The only mention is a
  comment of the PDF backend, which says that the backend needs no Cairo.
- **No version choice removes Cairo.** Each version of `HarfBuzz_jll` in the General registry
  names `Cairo_jll`: 2.x, 8.x and 100.x. `libass_jll` 0.17.5, which `FFMPEG_jll` 8.1.2 needs,
  accepts only `HarfBuzz_jll` 100.14003 and later.
- **HarfBuzz uses no Cairo library.** `HarfBuzz_jll` 100.14004.0+0 wraps three libraries:
  `libharfbuzz`, `libharfbuzz-gobject` and `libharfbuzz-subset`. None of them links `libcairo`.
  Only `libharfbuzz-cairo.so` links it, and the wrapper does not name or open that file. The
  artifact holds no program.
- **What HarfBuzz reads of `Cairo_jll`.** Its wrapper runs `using Cairo_jll`. JLLWrappers adds
  `Cairo_jll.PATH_list` and `Cairo_jll.LIBPATH_list` to the lists of HarfBuzz when they exist. The
  stand-in that the builder writes defines both as empty lists.
- **HarfBuzz stays while FFmpeg stays.** `ffmpeg` links `libavfilter`, `libavfilter` links
  `libass`, and `libass` links `libharfbuzz`. The video code runs `ffmpeg`
  ([VideoRecording.jl:213](../../source/backend/video/VideoRecording.jl#L213)).
- **Pkg allows `[sources]` only for a package in `[deps]` or `[extras]`**
  (`Pkg/src/project.jl:213`). For this reason the builder lists each stand-in in `[deps]` of the
  app package.
- **Pkg checks the compat of each dependent against a package that a path gives.** On 2026-11-24 a
  scratch project held `HarfBuzz_jll` and an empty `Cairo_jll`. With version 0.0.1 the resolve
  stopped: "Cairo_jll [83423d85] is fixed to version 0.0.1". With version 1.18.7 it resolved, with
  `HarfBuzz_jll` 100.15001.0+0. `HarfBuzz_jll` 100 accepts `Cairo_jll` 1.18.5 to < 2. The builder
  writes each stand-in with version 0.0.1 (`_write_stand_in_package`, `AppPackage.jl`).
- **Where the manifests are.** The manifests of projectured-julia are in git, and those of
  omnet-julia and inet-julia are not. The `environment/all` of omnet-julia and of inet-julia names
  each package of projectured-julia by the path `../../../projectured-julia/package/<name>`.
- **The build tests.** omnet-julia has `test/build.jl`, and inet-julia has
  `test/runner/build.jl`.

## Decisions

Each decision is proposed by the assistant.

1. **An empty `Cairo_jll` and an empty `alsa_plugins_jll` in the four environments.** Each
   environment lists both in `[deps]`, with a `[sources]` path to an empty package. The sound
   plugins are the decision of the owner. An empty `alsa_plugins_jll` alone does not remove Cairo,
   because `ProjecturedVideo` still brings `FFMPEG_jll`, and Cairo with it. Rejected: a wait for a
   HarfBuzz build without Cairo upstream, which nobody has proposed.
2. **One empty package for the three repositories**, at projectured-julia
   `package/Cairo_jll/` (and `package/alsa_plugins_jll/`). The builder function that writes the
   stand-ins of a binary writes it too, so both have one form. The constant
   `ENVIRONMENT_STAND_INS` in `ProjecturedProgram.jl` holds it, and
   `write_environment_stand_ins!()` writes the folder. The folder is in git, because an
   environment resolves before any tool can run. omnet-julia and inet-julia name it by
   `../../../projectured-julia/package/Cairo_jll`, the same way that they name the packages.
   Rejected: a copy in each repository, which can drift.
   - **Changed in the implementation:** the plan first put the folders at
     `environment/stand_in/`. The tree guard `test/suite/tree.jl` stops on that: "an
     environment holds no code". A stand-in is a package of a `Project.toml` and
     `src/<Name>.jl`, which is what the rule for `package/` asks. The release copy of the
     packages takes each folder of `package/`, so `PROJECTURED_RELEASE_EXCLUSIONS` names the two
     stand-ins.
3. **Each stand-in claims a version.** `StandIn` gets the keyword `version`, with no default,
   because Pkg checks the compat of dependents against it. The value is the version of the package
   that the stand-in replaces. `Cairo_jll` claims 1.18.7. The stand-in of the binaries,
   `alsa_plugins_jll`, claims 1.2.13.
4. **A check of each environment.** `check_stand_ins(manifest, ENVIRONMENT_STAND_INS)` in the
   builder stops with an error in two cases. It is the check of the binaries too, so no second
   function was made.
   - The manifest holds a package of `ENVIRONMENT_STAND_INS` as a real package.
   - A package outside the `named_by` of the stand-in names it.

   For `Cairo_jll`, `named_by` is `HarfBuzz_jll`. A package that draws with Cairo, such as
   `Cairo.jl`, then stops the test. Without the check, it fails only when it runs. The build test
   of each of the three repositories calls the check with its environment.
5. **One change of `StandIn` for both plans.** The plan
   [the-binary-leaves-out-what-no-run-reads.md](the-binary-leaves-out-what-no-run-reads.md) needs
   the keywords `version` and `named_by` too. The plan that runs first adds both keywords, and the
   other plan uses them.

## Steps

Each step is one commit with its tests, in a worktree that `julia-worktree new` makes. Mark each
step done here. A step lands on `main` only with the word of the owner.

1. [x] **projectured-julia: the empty package, the check, and its two environments**
   (decisions 1 to 5). Done on 2026-11-24. What the implementation found and decided:
   - The keywords `version` and `named_by` came with step 1 of the other plan, and
     `check_stand_ins` is the one check for both. `ENVIRONMENT_STAND_INS` takes the stand-in of
     `alsa_plugins_jll` from `PROJECTURED_STAND_INS`, so the two lists can not differ for it.
   - `Pkg.resolve` sorts the lines of `[deps]` and `[sources]` again when it writes the
     project. The commit keeps the order of the lines as it was and adds only the new ones; the
     project hash in the manifest depends on the content, not on the order.
   - Counts: `environment/all` 338 → 309 packages, `environment/readme-data-frame` 161 → 107.
     Only the two stand-ins changed their version.
   - Tests: the builder test 436 pass and 1 broken; the SDL, video and builder suites together
     1913 pass and 6 broken (the known markers). The video suite writes `.mp4` files, so
     `ffmpeg` runs with `libass` and HarfBuzz and without Cairo. The packages of
     `environment/readme-data-frame` load.
   - Source: `version` and `named_by` in `StandIn` (`AppPackage.jl`), if they are not there yet;
     the version of `alsa_plugins_jll`; `ENVIRONMENT_STAND_INS`,
     `write_environment_stand_ins!` and `check_environment_stand_ins`; the folder
     `environment/stand_in/Cairo_jll/`; `Cairo_jll` in `[deps]` and `[sources]` of
     `environment/all` and `environment/readme-data-frame`, and a resolve of each. `builder.md`
     says what an environment stand-in is and when the check stops.
   - Test `test/tool/builder/BuilderTest.jl`:
     - The folder in git is equal to a new write.
     - The check passes on the manifests of the two environments.
     - The check stops on a small written manifest in which a package outside `named_by` names
       `Cairo_jll`, and on one in which `Cairo_jll` has no path.
   - The suite of `ProjecturedVideo` writes a video, so `ffmpeg` runs with `libass` and HarfBuzz
     and without Cairo. The suite of `ProjecturedSDL` passes. The packages of
     `environment/readme-data-frame` load.
2. [x] **omnet-julia: its environment.** `Cairo_jll` and `alsa_plugins_jll` in `[deps]` and
   `[sources]` of `environment/all`, and a resolve. `test/build.jl` calls the check. Done on
   2026-11-24, commit `252fc968a` of omnet-julia.
   - `OmnetIdeExample` is not in `environment/all`, so the check loads `ProjecturedVideo` and
     `OmnetIde` there instead; both load.
   - `test/build.jl` in `environment/build`: 123 pass and 1 broken (the known marker).
   - The worktree ran it before step 1 landed: `julia-worktree run --with` mounts the projectured
     worktree at the neutral path of projectured-julia. Count: 426 → 397 packages. The resolve in
     the worktree also moved `LibSSH2_jll` from 1.11.103 to 1.11.104, a JLL of the standard
     library: the worktree runs Julia 1.13.1, and the main checkout another Julia.
3. [x] **inet-julia: its environment.** `Cairo_jll` and `alsa_plugins_jll` in `[deps]` and
   `[sources]` of `environment/all`, and a resolve. `test/runner/build.jl` calls the check.
   Done on 2026-11-24, commit `86910a9` of inet-julia.
   - `julia-worktree` knows only projectured-julia and omnet-julia, so the run used `bwrap`
     directly: the projectured and omnet worktrees mounted over the paths of their main
     checkouts. A tree of links does not work, because Pkg resolves a path from the real place
     of the project.
   - Count: 290 → 263 packages; only the two stand-ins changed their version. The build test
     passes, 16 of 16.

Record here the count of packages of each environment before and after.

## Landing

- Steps 2 and 3 run after step 1 is on `main`, because their path goes to the main checkout of
  projectured-julia.
- The other worktrees of projectured-julia take the change at their next rebase. Until then their
  manifests name the real `Cairo_jll`.
- When a step lands, its worktree, its depot `/var/tmp/<worktree>-depot` and its branch go in the
  same step.
- Every run goes through `/home/projectured/workspace/bin/bounded-run`. This plan measures no time.

## Not in this plan

- **The environments of single packages**, such as `package/ProjecturedSDLTest`. Each one resolves
  alone and keeps the real `Cairo_jll`.
- **A HarfBuzz build without Cairo in Yggdrasil**, so that `HarfBuzz_jll` names no `Cairo_jll`.
  It removes Cairo for each Julia user. It needs a pull request, and only the owner approves one.
- **`Test` in the binaries.** HTTP needs `ExceptionUnwrapping`, and each version of
  `ExceptionUnwrapping` names `Test` for its macro `@test_throws_wrapped`.
