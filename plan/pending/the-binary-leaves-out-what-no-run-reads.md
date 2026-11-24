# The binary leaves out what no run reads

Status: PENDING. Written on 2026-11-24 at the request of the owner. Not approved yet.

## The ask

On 2026-11-23 the owner asked: "are there any additional libraries which we could leave out
because they are not really needed/used?" The session measured the bundle of the omnet IDE and
named four items. The owner answered: "yes, write a plan for items 1 to 4".

1. The files in the JLL folders that are not libraries: static libraries, C headers, manuals and
   command-line tools.
2. Six image-format packages: `Libtiff_jll`, `JpegTurbo_jll`, `libwebp_jll`, `LERC_jll`,
   `libpng_jll` and `Giflib_jll`.
3. `SDL2_mixer_jll` and `SDL2_gfx_jll`.
4. Five files in `lib/` that never load and that no library links: four parts of `libunwind`, and
   `libuv.so`.

## What the bundle holds now

Measured on 2026-11-23 and 2026-11-24 on `omnet-julia/build/omnet_ide`, the reactive build of
2026-11-23 22:41 for the CPU target `native`. A size is the bytes in the files, which is what an
archive holds; 1 MB is 2^20 bytes. The blocks on the disk are more, because many files are small.

- The bundle holds 4642 MB. Of this, the program `bin/omnet_ide` is 1738 MB, the second copy of
  the image `lib/julia/sys.so` is 1731 MB, and the store `reactive-store` is 778 MB. The other
  files are 395 MB.
- `share/julia/artifacts` holds 30 folders, 106.3 MB. Each folder is the artifact of one JLL
  package.
- The four items free 64.2 MB:

| Item | What goes | MB |
| --- | --- | --- |
| 1 | Files that are not libraries, in the 22 folders that stay | 36.7 |
| 2 | The folders of the six image-format packages (10.1 MB of it libraries) | 22.8 |
| 3 | The folders of `SDL2_mixer_jll` and `SDL2_gfx_jll` (1.7 MB of it libraries) | 2.3 |
| 4 | Four parts of `libunwind`, and `libuv.so`, in `lib/` | 2.4 |

Item 1 in detail: headers 10.7 MB, static libraries (`.a`, `.la`) 11.5 MB, manuals 3.4 MB,
documents 7.0 MB, programs in `bin/` 4.1 MB (3.0 MB of it the example programs of MbedTLS), and
pkg-config files 0.1 MB.

## The facts that the steps use

- **Each JLL package opens all its libraries when it loads.** After a start of 40 s, the IDE had
  mapped 100 libraries, almost all of the bundle. So a library that loads is not always used.
  The start ran with `SDL_VIDEODRIVER=offscreen` and a scratch home folder.
- **What `libSDL2` links:** `libiconv`, `libasound`, `libsamplerate`, `libX11`, `libXext` and
  `libXcursor`. It opens the GL libraries of `Libglvnd_jll` and more X11 libraries by name.
- **`SDL2_image` 2.6.2+1 reads PNG and JPEG with its own code** (`IMG_stb.c`). It does not link
  libtiff, libwebp, libpng, libjpeg, giflib or LERC, and its file holds no name of them to open.
  So its functions for TIFF and WebP have no code behind them, and a stand-in changes nothing that
  a program can do. The projectured code calls only `IMG_SavePNG` of `SDL2_image`.
- **Who names the image packages.** In the manifests of `projectured`, `omnet_ide` and
  `omnet_ide_guard`, `SDL2_image_jll` names `Libtiff_jll`, `libwebp_jll`, `JpegTurbo_jll` and
  `libpng_jll`. Only the real `Libtiff_jll` names `LERC_jll`, and only the real `libwebp_jll` names
  `Giflib_jll`. So `LERC_jll` and `Giflib_jll` leave the manifest with the stand-ins of the other
  two, and they need no stand-in of their own.
- **A chain of packages can name `libpng_jll`.** In the old manifest of `omnet_ide_guard`, which
  still holds the whole sound chain, `HarfBuzz_jll` names `Cairo_jll`, and `Cairo_jll` names
  `libpng_jll`. A Cairo library links `libpng16.so.16`. A stand-in for `libpng_jll` in such a
  binary would break the start.
- **Pkg checks the compat of each dependent against a stand-in.** On 2026-11-24 a scratch project
  with `HarfBuzz_jll` and an empty `Cairo_jll` of version 0.0.1 did not resolve, and one of
  version 1.18.7 did. `SimpleDirectMediaLayer` 0.5.0 accepts `SDL2_mixer_jll` 2.6.2 to < 3 and
  `SDL2_gfx_jll` 1.0.3 to < 2. `SDL2_image_jll` 2.6.2+1 accepts `Libtiff_jll` 4.3.0 to 4.4. The
  builder writes each stand-in with version 0.0.1, so these three stop the resolve.
  `alsa_plugins_jll` works with 0.0.1 only because no package limits its version.
- **No code calls `SDL2_mixer` or `SDL2_gfx`.** No source file of projectured-julia or omnet-julia
  calls a `Mix_` function or a drawing function of `SDL2_gfx`. `SimpleDirectMediaLayer.init()`
  calls `Mix_OpenAudio`, but no code calls `init()`. Only `SimpleDirectMediaLayer` names the two
  packages.
- **The Julia runtime holds libuv.** `libjulia-internal` exports 307 `uv_` functions, so
  `lib/libuv.so.2.0.0` is a second copy. Only `LibUV_jll` names that file, and no manifest of a
  build holds `LibUV_jll`.
- **Julia unwinds only its own process.** `libjulia-internal` links `libunwind.so.8`. Only
  `libunwind-coredump`, `libunwind-ptrace` and `libunwind-setjmp` link `libunwind-x86_64`
  (`libunwind-generic.so` points to it). These four are for a program that unwinds another process.
- **Julia opens some libraries only at their first use**, for example `libdSFMT` for a
  `MersenneTwister`. So a list of links and of the libraries of one start can not prove that a
  library is unused.
- **What a run reads beside the libraries.** A distribution takes the licence texts from
  `share/licenses/` of each artifact folder (`_collect_artifact_licences` in `LicenceTexts.jl`).
  `libX11` reads `share/X11/`, and alsa reads `share/alsa/`. Of the JLL packages that stay, only
  `libsamplerate_jll` names a program in `bin/` (`sndfile_resample`).
- **Where a build ends.** Each kind of build, linked, plain, trimmed and reactive, passes through
  `compile!()` in `build_executable` of `source/tool/builder/Executable.jl`, and then
  `bundle_fonts!`. A full reactive build removes the output folder and copies everything again
  (`create_app`). A rebuild of an edit writes only the new part of the image and leaves the
  artifact folders as they are.
- **The checks of a distribution.** `collect_missing_libraries` finds each library that a bundled
  file links and that the bundle does not hold. `check_relocation` starts the copy with the
  checkout hidden.
- **The builders that use the default.** projectured-julia (`projectured`), omnet-julia
  (`omnet_ide`, `omnet_run` and its other binaries), and inet-julia
  (`source/tool/build/Build.jl`).

## Decisions

Each decision is proposed by the assistant.

1. **Six stand-ins in `PROJECTURED_STAND_INS`:** `Libtiff_jll`, `libwebp_jll`, `JpegTurbo_jll`,
   `libpng_jll`, `SDL2_mixer_jll` and `SDL2_gfx_jll`, beside `alsa_plugins_jll`. They keep no
   dependency, because no library that stays links one of their libraries. Each binary of the
   three repositories gets them. Rejected: stand-ins for `LERC_jll` and `Giflib_jll` too, which
   would be empty packages that nothing names. Rejected: a list for each binary, which each build
   function would have to remember.
2. **A stand-in names who may name it.** `StandIn` gets the keyword `named_by`: the packages that
   name the JLL and use none of its libraries. After the resolve of the app package, the build
   stops when another package names a stand-in. The error names that package and the stand-in, and
   says that the binary must pass a `stand_ins` list without it. The app package itself does not
   count. The values:
   - `alsa_plugins_jll`: `SDL2_jll`, `SimpleDirectMediaLayer`.
   - The four image-format packages: `SDL2_image_jll`.
   - `SDL2_mixer_jll` and `SDL2_gfx_jll`: `SimpleDirectMediaLayer`.

   Rejected: the build drops the stand-in and resolves again, which hides why a binary grows.
   Rejected: no check, with which a binary that holds `Cairo_jll` builds and then can not start.
   A binary that plays sound, or that draws with `SDL2_gfx`, passes its own list, as now.
3. **One new step after the compile:** `remove_unread_files!(output)`, called in
   `build_executable` right after `compile!()`. So it holds for each kind of build. In a rebuild
   of an edit it finds nothing to remove. It writes one line to the log with the count and the
   size of what it removed. Rejected: a call in each compile function, four places of which one can
   be forgotten. Rejected: only in `build_distribution`, because then the developer build stays
   large and shows a missing file only in a distribution.
4. **What item 1 removes in each artifact folder:** `include/`, each `.a` and `.la` file,
   `lib/pkgconfig/`, `lib/cmake/`, `share/pkgconfig/`, `share/aclocal/`, `share/man/`, `man/`,
   `share/doc/`, `share/gtk-doc/`, `share/info/`, `logs/`, and each file in `bin/`. A file stays
   when a product of a JLL of the build names it: a library, a program or a file product, in a
   wrapper of the exact version that the manifest names. All other files stay, among them
   `share/licenses/`, `share/X11/`, `share/alsa/` and `share/locale/`. Rejected: keep only the
   products, which drops data that a library reads by its path, such as the locale data of X11,
   with no error in the build. Rejected: a list of files for each JLL, which changes with each
   version.
5. **What item 4 removes in `lib/`, on Linux:** a fixed list, `UNUSED_RUNTIME_LIBRARIES`, with the
   reason of each entry: `libunwind-coredump`, `libunwind-ptrace`, `libunwind-setjmp`,
   `libunwind-x86_64` and `libunwind-generic`, because Julia unwinds only its own process; `libuv`,
   because the runtime holds it. Each file and each link whose name starts with `<entry>.so`
   goes, so no link points to nothing. `libuv` stays when the manifest holds `LibUV_jll`.
   Rejected: a rule that removes each library that nothing links and that one start does not open,
   because Julia opens some libraries only at their first use.
6. **No option keeps the files.** No binary reads headers, static libraries, manuals or the listed
   libraries. Rejected: a command-line option to keep them, which no caller needs.
7. **Each stand-in claims a version.** `StandIn` gets the keyword `version`, with no default. The
   value is the version of the package that the stand-in replaces, in the manifest of
   `omnet_ide` of 2026-11-23: `alsa_plugins_jll` 1.2.13, `Libtiff_jll` 4.4.0, `libwebp_jll`
   1.4.0, `JpegTurbo_jll` 3.2.1, `libpng_jll` 1.6.59, `SDL2_mixer_jll` 2.8.1 and `SDL2_gfx_jll`
   1.0.4. Rejected: a version only where a dependent limits it, which breaks when a new version of
   a dependent adds a limit. The plan
   [the-developer-environments-hold-no-cairo.md](the-developer-environments-hold-no-cairo.md) needs
   `version` and `named_by` too. The plan that runs first adds both keywords.

## Steps

Each step is one commit with its tests, in a worktree of each repository that it changes, made
with `julia-worktree new`. The tests of omnet-julia run in a scratch copy of `environment/build`
whose paths go to the two worktrees. Mark each step done here. A step lands on `main` only with
the word of the owner.

1. [ ] **Items 2 and 3: six more stand-ins, and the check of who names them** (decisions 1, 2, 7).
   - projectured-julia: `named_by` and `version` in `StandIn` (`AppPackage.jl`), if they are not
     there yet; the check after the resolve in `build_executable`, and the list in
     `ProjecturedProgram.jl`. `builder.md` says what a stand-in names, which version it claims,
     and when a build stops.
   - Test `test/tool/builder/BuilderTest.jl`: the default list holds seven stand-ins, each with
     `named_by` and `version`. The written stand-in package claims its version. The check of a small written manifest stops, with the package in the error, when a
     package outside `named_by` names a stand-in, and passes when only the app package and
     `named_by` name it.
   - omnet-julia `test/build.jl`: the app package of `omnet_ide` (`compile = false`) holds the
     seven stand-ins.
2. [ ] **Items 1 and 4: the build removes the files that no run reads** (decisions 3 to 6).
   - projectured-julia: `remove_unread_files!` and `UNUSED_RUNTIME_LIBRARIES`, the call in
     `build_executable`, and a section in `builder.md`.
   - Test `test/tool/builder/BuilderTest.jl`, on a bundle folder that the test writes: an artifact
     folder with `include/`, a `.a` file, a library and its links, `share/licenses/`, `share/X11/`,
     a program that a product names and one that no product names; and `lib/` with the parts of
     `libunwind` and `libuv` and their links. The test checks each file that goes and each file
     that stays, and that no link points to nothing. A second call removes nothing.
3. [ ] **Whole builds and the record.**
   - Each binary of the three repositories writes and resolves its app package
     (`compile = false`), so the check of step 1 runs for each one: `projectured`, each binary of
     omnet-julia and each binary of inet-julia.
   - `bin/build_omnet_ide --distribution` and the distribution of `projectured`. Their own checks
     run: no library is missing, and the copy starts with the checkout hidden.
   - The IDE starts with `SDL_VIDEODRIVER=offscreen` and a scratch home folder, draws its window,
     and writes a picture of it with `IMG_SavePNG`. It maps the same libraries as on 2026-11-23,
     less the removed ones.
   - Record here: the size of the artifact folders, of the bundle without the image and the store,
     and of the archive, before and after, measured as in "What the bundle holds now".

## The rule of measurement

- A size and a count need no idle machine and no word of the owner. This plan measures no time.
- Every run goes through `/home/projectured/workspace/bin/bounded-run`. A whole build of
  `omnet_ide` takes about 45 minutes and needs a cap of 20 to 28 GB.

## Landing

- Step 1 changes the default of each binary that the shared builder builds, in projectured-julia,
  omnet-julia and inet-julia. Each binary then needs a whole build once, because its manifest
  changes.
- When a step lands, its worktree, its depot `/var/tmp/<worktree>-depot` and its branch go in the
  same step.

## Not in this plan

OpenBLAS (34 MB), which a product of two matrices of floats calls; `libgfortran`, `libgomp` and
`libquadmath`, which `CompilerSupportLibraries_jll` opens at each start and needs; MbedTLS, whose
package calls its library when it starts; the second copy of the image, `lib/julia/sys.so`, in the
reactive developer build; the warning at the start of the IDE that 498 of the 3186 recorded calls
of `ProjecturedJulia` no longer resolve; `libgmpxx` and `libxcb-dbe` (60 KB); the extension
libraries of xcb; `Pkg` and `LibGit2`, which the old `SDL2_image_jll` 2.6.2 names.
