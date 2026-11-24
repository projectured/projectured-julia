# Package owners hear which dependencies they can drop

**Status: PENDING.** Written on 2026-11-24. Steps 1 and 2 prepare the notes, and nothing leaves
this repository before step 3.

## The ask

The owner said: "prepare steps to notify package owners where they could rationalize their
dependencies to lower the number of dependent packages on their packages. for example, the Test
package that is brought in by HTTP transitively. I want them to fix their libraries".

## Why a needless dependency costs a binary

- **PackageCompiler puts each package of the manifest into the image**, also a package that no
  code loads: `include_transitive_dependencies` is `true` by default in `create_sysimage` and
  `create_app`. For example, PrettyTables loads `REPL` only on Julia 1.11 and 1.12, but `REPL` is
  in the image of the IDE, which runs on Julia 1.13.
- **Each JLL package opens all its libraries when it loads**, so a needless JLL costs memory and
  start time in each run, and its files are in each bundle.
- **What the images hold.** On 2026-11-24 the image of the IDE held 174 modules, among them `Pkg`,
  `LibGit2`, `Tar`, `REPL` and `Test`. The stock image of the Julia that builds it holds 13
  modules, and none of these five.
- **Sizes**, compiled alone in the depot of that Julia: `Pkg` 49 MB, `REPL` 25 MB, `Test` 3.7 MB,
  `LibGit2` 2.3 MB.

## The notes

A note goes to the repository of the package. "Checked" means that the assistant read it on
2026-11-24 in the newest registered version, in the local registry, in the installed source, or in
the recipe on GitHub. "From the survey" means that a research agent found it and nobody checked it
again yet.

| # | Package and repository | What it names and does not need | What it costs a user | Ask |
| --- | --- | --- | --- | --- |
| N1 | ExceptionUnwrapping.jl, JuliaServices/ExceptionUnwrapping.jl | `Test`, only for the macro `@test_throws_wrapped` (checked) | each user of HTTP 1.x loads `Test` | the macro in a package extension on `Test`, or in a package of its own |
| N2 | FixedPointNumbers.jl, JuliaMath/FixedPointNumbers.jl | `Statistics` in `[deps]` beside its extension, for Julia before 1.9 (checked) | `Statistics` for each user of ColorTypes | `Statistics` only in `[weakdeps]`, with `julia = "1.9"` |
| N3 | PrettyTables.jl, ronisbr/PrettyTables.jl | `REPL`, which it loads only on Julia 1.11 and 1.12 (checked) | `REPL` in each image that holds DataFrames, also on Julia 1.13 | `REPL` only where it helps: a weak dependency, or out when 1.12 support ends |
| N4 | SimpleDirectMediaLayer.jl, JuliaMultimedia/SimpleDirectMediaLayer.jl | `ColorTypes`, of which it uses nothing (checked); `SDL2_mixer_jll`, `SDL2_gfx_jll` and `alsa_plugins_jll` for each user | ColorTypes, FixedPointNumbers and Statistics; the sound chain | remove `ColorTypes`; the optional libraries as extensions |
| N5 | Yggdrasil `S/SDL2_image` | four image JLLs that the library does not link: the recipe sets `-DSDL2_IMAGE_WEBP=ON -DSDL2_IMAGE_TIF=ON`, but SDL_image 2.6 names the options `SDL2IMAGE_WEBP` and `SDL2IMAGE_TIF`, which are off by default (checked). The JLL of 2.6.2+1 names `Pkg`, and its compat holds `Libtiff_jll` at 4.3 to 4.4 | WebP and TIFF do not load at all; `Pkg`, `LibGit2`, `Tar` and an old Libtiff in each image | the right option names, or no image JLLs; a new build, because the 2.6.3 recipe has no registered JLL |
| N6 | Yggdrasil `S/SDL2` | `libSDL2` links `libsamplerate.so.0` and `libiconv.so.2` (checked), but the recipe does not name `libsamplerate_jll` or `Libiconv_jll` (from the survey). They arrive only through `alsa_plugins_jll` | an application that leaves out the sound plugins does not start | name the two JLLs in the recipe of SDL2 |
| N7 | Yggdrasil `A/alsa_plugins`, through `S/SDL2` | `FFMPEG_jll`, for the `a52` and `lavrate` plugins only (from the survey). `FFMPEG_jll` is built with `--enable-nonfree` and `libfdk-aac` (from the survey), and PulseAudio has GPL-3 and AGPL-3 parts | each application that bundles `SDL2_jll` bundles an FFmpeg that nobody may give to others | `FFMPEG_nogpl_jll` for alsa_plugins, or a JLL with only the pulse plugins for SDL2 |
| N8 | Yggdrasil `H/HarfBuzz` | `Cairo_jll`, only for `libharfbuzz-cairo.so`, which the wrapper does not name (checked) | Cairo, Pixman and their chain for each user of FFmpeg and of text | `-Dcairo=disabled`, or `libharfbuzz-cairo` as a product of its own JLL |
| N9 | Yggdrasil, several recipes | `Pkg`, in the newest version of `GStreamer_jll` 1.20.3+0, `BlueZ_jll` 5.54.0+1, `Libical_jll` 3.0.9+0, `SBC_jll` 1.4.0+0, `SoXResampler_jll` 0.1.3+0 and `SpeexDSP_jll` 1.2.0+0 (checked) | `Pkg` and its chain in each image that holds PulseAudio | a new build with the current BinaryBuilder, which names no `Pkg` |
| N10 | LDLFactorizations.jl, JuliaSmoothOptimizers/LDLFactorizations.jl | `Test`, which no file of `src/` uses (checked) | `Test` for each user | remove the line |
| N11 | Tulip.jl, ds4dm/Tulip.jl | `Test`, for test helpers of the KKT solvers in `src/` (from the survey) | `Test` for each user | the helpers in the tests, or in an extension |
| N12 | QPSReader.jl, JuliaSmoothOptimizers/QPSReader.jl | `Pkg` in the registered 0.2.1; the branch `main` already uses LazyArtifacts (from the survey) | `Pkg` for each user | a release |

**No note:**
- **HTTP.jl.** HTTP 2.x has none of MbedTLS, OpenSSL and ExceptionUnwrapping (checked in the
  registry: 2.16.0 is the newest). So the cure is on our side, see below.
- **MathOptInterface and MutableArithmetics.** `Test` is a part of their public interface
  (`MOI.Test`, `MA.Test`), and MutableArithmetics declined an extension in issue #298 (from the
  survey).
- **Statistics → LinearAlgebra**, a real use. The stock image of Julia holds `LinearAlgebra` anyway.

**What is on our side, and not in a note:** HTTP 2.x for ProjecturedWeb, ProjecturedAnthropic,
ProjecturedOllama and ProjecturedMCP, and for the copies of AgentClientProtocol, ClaudeCodeACP
(both of the projectured organization) and ModelContextProtocol (a clone of
JuliaSMLM/ModelContextProtocol.jl). It removes MbedTLS, OpenSSL, ExceptionUnwrapping, `Test`,
ConcurrentUtilities, LoggingExtras, SimpleBufferStream and BitFlags from both binaries. HTTP 2.0 is
a rewrite on Reseau, a new TLS layer in Julia, so this needs a plan of its own.

## The rules for the text of a note

- Facts first: what the package names, what it uses of it, and what it costs a user. Then one
  proposed change, and an offer to send a pull request.
- Short and polite, in plain words. No guess is written as a fact.
- No name of a private project and no personal data. The context is "an application that
  PackageCompiler builds".
- One note for each repository and each recipe. When an issue about the same dependency exists,
  the note is a comment on it, not a new issue.

## Steps

1. [ ] **Check each note** on the day of the post: the newest version, the source or the recipe,
   and the open and closed issues and pull requests. Each "from the survey" becomes "checked", or
   the note changes or goes.
2. [x] **Write the draft of each note** in the section "Drafts" below: a title and a body, in the
   form that `gh issue create --title … --body-file …` takes.
3. [ ] **The owner reads the drafts** and says which ones go, and from which GitHub account.
4. [ ] **Post each approved note**, and record its link here. Nothing goes without the word of the
   owner for that note.
5. [ ] **A pull request where a maintainer agrees**, one small change each, with the word of the
   owner before each push.
6. [ ] **Four weeks after the posts:** record the answers here. When a fix is released, remove the
   stand-in of the builder that it makes needless, in a change of its own.

## Drafts

Step 1 checks each fact again before a draft goes. The drafts of N9 to N12 are short, because the
change is small.

### N1 — JuliaServices/ExceptionUnwrapping.jl

**Title:** `Test` is a hard dependency only for `@test_throws_wrapped`

> ExceptionUnwrapping lists the standard library `Test` in `[deps]`. As far as I can see, the only
> user is `src/test_throws_wrapped.jl`, which defines `@test_throws_wrapped`. The unwrap functions
> need nothing from `Test`.
>
> HTTP.jl 1.x depends on ExceptionUnwrapping, so each program that uses HTTP 1.x loads `Test`. In
> an application that PackageCompiler builds, each package of the manifest goes into the image, so
> the image holds `Test` although the application runs no test.
>
> Would you accept a change that moves `Test` to `[weakdeps]` and `@test_throws_wrapped` into a
> package extension on `Test`? The main module can keep the name with
> `function var"@test_throws_wrapped" end`, and the extension adds the method. A test file loads
> `Test` anyway. I can send a pull request.

### N2 — JuliaMath/FixedPointNumbers.jl

**Title:** `Statistics` is still in `[deps]` beside `FixedPointNumbersStatisticsExt`

> Since #277, the method for `Statistics` is in an extension, with `Statistics` in `[weakdeps]`.
> `Statistics` is also still in `[deps]`, for the fallback on Julia before 1.9
> (`src/FixedPointNumbers.jl`, the `include` when `Base.get_extension` is not defined). So each
> user loads `Statistics`, also each user of ColorTypes that never computes a mean.
>
> Would you consider removing `Statistics` from `[deps]`, with `julia = "1.9"` in `[compat]`?
> I understand from #255, #277 and #281 that old Julia versions were the reason to keep it. If a
> lower bound of 1.9 is acceptable now, I can send the pull request.

### N3 — ronisbr/PrettyTables.jl

**Title:** `REPL` goes into each application image on Julia 1.13, where it is not used

> `src/PrettyTables.jl` loads `REPL` only on Julia 1.11 and 1.12, to cut the precompile time
> (JuliaLang/julia#56080). The comment says that on 1.13 it would only add load time, so it is not
> loaded there. But `REPL` stays in `[deps]`, so Pkg resolves it on each version. PackageCompiler
> puts each package of the manifest into the image, so each application that holds DataFrames or
> PrettyTables compiles `REPL` into its image, also on Julia 1.13.
>
> Do you see a way to keep the help for 1.11 and 1.12 without the dependency on later versions? Two
> ideas: `REPL` as a weak dependency (in an interactive session on 1.11 or 1.12 it is loaded
> anyway), or no dependency when the support for 1.12 ends. I can test a change with
> PackageCompiler, if that helps.

### N4 — JuliaMultimedia/SimpleDirectMediaLayer.jl

**Title:** `ColorTypes` is loaded but not used

> `src/SimpleDirectMediaLayer.jl` has `using ColorTypes`, and as far as I can see no line of the
> package uses a name of ColorTypes. The dependency brings ColorTypes, FixedPointNumbers and
> Statistics to each user. Would you accept a pull request that removes it?
>
> A second, larger point: each user also loads `SDL2_mixer_jll`, `SDL2_gfx_jll` and
> `alsa_plugins_jll`, also a program that only opens a window. Package extensions could make the
> bindings of the mixer and of gfx optional. Is that a change that you would want?

### N5 — JuliaPackaging/Yggdrasil, `S/SDL2_image`

**Title:** [SDL2_image] WebP and TIFF are off, because the CMake option names are wrong

> `S/SDL2_image/build_tarballs.jl` passes `-DSDL2_IMAGE_WEBP=ON -DSDL2_IMAGE_TIF=ON`. SDL_image
> 2.6 names these options `SDL2IMAGE_WEBP` and `SDL2IMAGE_TIF` (`CMakeLists.txt` at
> `release-2.6.2`, lines 75 and 76), and both are off by default. So the build ignores the two
> flags. With `SDL2IMAGE_BACKEND_STB=ON`, the default, JPEG and PNG use the stb code.
>
> The result in `SDL2_image_jll` 2.6.2+1 for x86_64-linux-gnu: `libSDL2_image-2.0.so.0.600.2`
> links none of libtiff, libwebp, libjpeg and libpng, and holds no name of them to load. So WebP
> and TIFF do not load, and the four JLL dependencies only add packages: `Libtiff_jll`,
> `libwebp_jll`, `JpegTurbo_jll` and `libpng_jll`, and through them `LERC_jll` and `Giflib_jll`.
>
> Two more points: the registered 2.6.2+1 is of the old JLL form that lists `Pkg` in `[deps]`, and
> its compat holds `Libtiff_jll` at 4.3 to 4.4, an old version that lists `Pkg` too. The recipe is
> at 2.6.3 now, but no 2.6.3 JLL is registered.
>
> Proposal: either the right option names, so that the dependencies are used, or no image
> dependencies; and a new build. I can open a pull request for either choice.

### N6 — JuliaPackaging/Yggdrasil, `S/SDL2`

**Title:** [SDL2] libSDL2 links libsamplerate and libiconv, but the recipe does not name them

> `readelf -d` of `libSDL2-2.0.so.0.3200.10` in `SDL2_jll` 2.32.10+0 (x86_64-linux-gnu) lists
> `libiconv.so.2`, `libasound.so.2` and `libsamplerate.so.0` as needed. The recipe names
> `alsa_jll` and `alsa_plugins_jll`, but not `libsamplerate_jll` or `Libiconv_jll`. The two
> libraries reach an environment only because `alsa_plugins_jll` depends on them. When an
> environment does not hold `alsa_plugins_jll`, libSDL2 does not load.
>
> Proposal: `Dependency("libsamplerate_jll")` and `Dependency("Libiconv_jll")` in the recipe of
> SDL2. I can open the pull request.

### N7 — JuliaPackaging/Yggdrasil, `A/alsa_plugins` and `S/SDL2`

**Title:** SDL2_jll brings an FFmpeg built with `--enable-nonfree`, through alsa_plugins_jll

> `SDL2_jll` depends on `alsa_plugins_jll` since #5568, so that audio works on PulseAudio and
> PipeWire (#1432). `alsa_plugins_jll` depends on `FFMPEG_jll`, for the `a52` and `lavrate`
> plugins, and on `PulseAudio_jll`. `FFMPEG_jll` is configured with `--enable-gpl --enable-nonfree
> --enable-libfdk-aac` (`F/FFMPEG/common.jl`), and FFmpeg says that such a build may not be given
> to others.
>
> So each application that bundles `SDL2_jll`, also one that only draws a window, carries an
> FFmpeg that it may not give to others, and about 25 more JLLs, among them PulseAudio, GStreamer,
> BlueZ and D-Bus.
>
> Proposals: `alsa_plugins` depends on `FFMPEG_nogpl_jll` (registered, 9.0.2), if that build has
> what `a52` and `lavrate` need; or the pulse plugins get a JLL of their own, and SDL2 depends
> only on that one. I can help with a pull request.

### N8 — JuliaPackaging/Yggdrasil, `H/HarfBuzz`

**Title:** [HarfBuzz] Cairo_jll is a dependency only for libharfbuzz-cairo, which is not a product

> `H/HarfBuzz/common.jl` configures `-Dcairo=enabled` and lists `Cairo_jll` as a dependency. The
> products are `libharfbuzz`, `libharfbuzz_subset` and `libharfbuzz_gobject`, and none of them
> links libcairo (`readelf -d`, `HarfBuzz_jll` 100.14004.0+0, x86_64-linux-gnu). Only
> `libharfbuzz-cairo.so` links it, and no product names that file. The programs are off
> (`-Dutilities=disabled`).
>
> So each user of `HarfBuzz_jll`, for example each user of `FFMPEG_jll` through `libass_jll`, gets
> `Cairo_jll`, `Pixman_jll` and their chain, and the wrapper of HarfBuzz loads Cairo at each start.
>
> Proposal: `-Dcairo=disabled` and no `Cairo_jll`, if no recipe uses `libharfbuzz-cairo`. I found
> no recipe that names it. I can open the pull request.

### N9 — JuliaPackaging/Yggdrasil, several recipes

**Title:** The newest version of some JLLs still lists Pkg in `[deps]`

> JLLs of an old BinaryBuilder list `Pkg` in `[deps]`. In an application that PackageCompiler
> builds, `Pkg` and with it `LibGit2`, `Tar` and `p7zip_jll` then go into the image. The newest
> registered versions of these JLLs still list `Pkg`: `GStreamer_jll` 1.20.3+0, `BlueZ_jll`
> 5.54.0+1, `Libical_jll` 3.0.9+0, `SBC_jll` 1.4.0+0, `SoXResampler_jll` 0.1.3+0,
> `SpeexDSP_jll` 1.2.0+0 and `SDL2_image_jll` 2.6.2+1. Most of them are in the chain of
> `PulseAudio_jll`. Is a new build of each welcome? I can open the pull requests.

### N10 — JuliaSmoothOptimizers/LDLFactorizations.jl

**Title:** `Test` is in `[deps]` but not used

> `Project.toml` lists `Test` in `[deps]`, and no file of `src/` uses it. So each user, for example
> through Tulip, loads `Test`. Would you accept a pull request that moves it to `[extras]` and the
> test target?

### N11 — ds4dm/Tulip.jl

**Title:** `Test` is a dependency for the KKT test helpers in `src/`

> `src/KKT/KKT.jl` includes `src/KKT/Test/test.jl`, which has `using Test`. So each user of Tulip
> loads `Test`. Would you accept a change that moves these helpers into `test/`, or into a package
> extension on `Test`? I can send the pull request.

### N12 — JuliaSmoothOptimizers/QPSReader.jl

**Title:** A release with LazyArtifacts in place of Pkg

> The registered 0.2.1 has `using Pkg.Artifacts`, so each user loads `Pkg`. The branch `main`
> already uses `LazyArtifacts`. Could you tag a release?
