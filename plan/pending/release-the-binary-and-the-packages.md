# Release the binary and the packages

Status: pending, 2026-09-29. Nothing is built, generated, tagged or published
yet.

Two routes give ProjecturEd to other users. Each route serves a different
user:

- **Part A, the binary archive**, is for a user who runs the editor. That user
  needs no Julia.
- **Part B, the packages in the General registry**, is for a Julia programmer
  who uses the packages in a program.

Neither route changes the structure of the repository. **Part L**, the change
of the licence to MPL-2.0 (R21), comes before the publication of either.

## 1. The request

The owner, 2026-09-29: other users must be able to install ProjecturEd. The
owner first chose the binary archive, with one constraint:

> I would like to do route 1, but don't want to change the repository structure

Then the owner asked about `pkg> add` with the URL of the repository. A test
showed that this form fails (§2.2). `pkg> develop` works, but the owner does not
want it:

> I don't really like the develop route, is there a better way to do it with
> minimal modifications?

The answer is Part B: a script generates a self-contained copy of the packages
for each release, and a registry of our own serves that copy. The repository
keeps its structure. Then the owner said:

> update the plan for this

## 2. What exists

### 2.1 For the binary

- **The builder** ([build-guide.md](../../documentation/guide/build-guide.md)).
  `bin/build_projectured --distribution` compiles a fresh image for several
  processor families. It copies the bundle to `/var/tmp`, tests the copy with
  the checkout and the depot hidden under `bwrap`, and writes
  `build/projectured-<version>-linux-x86_64.tar.gz` with a `README` and the two
  licence files.
- **The tests of a copy.** The relocation test starts the copy with an empty
  depot. The program check starts it with `--backend=web --mcp
  --assistant=none` and reads the web client, a font and the guide list.
- **One distribution build passed, on 2026-09-17**
  ([application-and-build.md](../done/application-and-build.md) Step 5): 25
  minutes, about 14 GB of resident memory at the peak, a bundle of 1558 MB, and
  an archive of 437 MB. That archive was deleted.
- **The owner deferred the release on 2026-09-20.** The window was too rough to
  ship. [documentation-rewrite.md](documentation-rewrite.md) Step 11 still
  holds the release item (D22). The owner lifted the deferral on 2026-09-29
  (R1).
- **The version** is `0.1.0`. `BuildContext` gives it as the default, and every
  `Project.toml` has it.
- **The bundled guides are clean.** On 2026-09-29, no file in `documentation/`
  or `asset/web/` names a private project.
- **The prerequisites are on this machine.** `bwrap`, `curl` and `podman` are
  installed, and ports 8080 and 9876 are free.

### 2.2 For the packages: what Pkg does with this repository

A test on 2026-09-29, with Julia 1.13.0, a scratch depot, the committed `main`
as the source, and no compile:

| Case | Command | Result |
| --- | --- | --- |
| A | `add <url>` | Fails. The repository root has no `Project.toml`. |
| B | `add <url>:package/ProjecturedKernel` | Resolves, but Pkg installs only `Project.toml` and `src/`. `source/` is not there, so the first `include` fails. |
| C | `add <url>:package/Projectured` | Fails. Pkg ignores `[sources]` of a package that it adds by URL, and the sibling packages are in no registry. |
| D | `develop <url>:package/Projectured` | Works. Pkg clones the full repository to `~/.julia/dev/projectured-julia` and follows `[sources]` to every sibling. |
| E | then `develop <url>:package/ProjecturedSdl` | Works, and uses the same clone. |

So `add` needs each package folder to be complete, and it needs a registry for
the siblings. D works, but it gives no versions, and `pkg> up` does not update
it. The owner rejected D.

### 2.3 For the packages: what a release copy must hold

A scan on 2026-09-29:

- **The application needs 83 packages**: the closure of `ProjecturedExample`,
  `ProjecturedSdl`, `ProjecturedWeb` and `ProjecturedMcp`. That closure holds
  the umbrella `Projectured` and 22 example packages, and no `*Test` package.
  The other 46 packages stay out: the test packages, and `ProjecturedTulip`,
  `ProjecturedOdbc`, `ProjecturedAdaptagrams`, `ProjecturedRepl`,
  `ProjecturedBuilder`, `ProjecturedVideo` with their examples.
- **Each package includes its code from one slice**, with lines of the form
  `include("../../../source/<slice>/…")` in `package/<X>/src/<X>.jl`. No slice
  belongs to two packages.
- **No code in the 83 packages uses `pkgdir` or `pathof`.** The three packages
  with a `_PKG_DIR` path into `example/` are not in the set.
- **Four paths leave a slice.** If the copy puts each folder at the same
  relative place, three of them work with no change:

| Path | Where the copy puts the folder |
| --- | --- |
| [Font.jl:104](../../source/style/Font.jl#L104) `../../asset/font` | `ProjecturedStyle/asset/font` |
| [Web.jl:77](../../source/web/Web.jl#L77) `../../asset/<name>` | `ProjecturedWeb/asset/web` and `ProjecturedWeb/asset/font` |
| [Documentation.jl:58](../../source/kernel/tool/Documentation.jl#L58) `../../../documentation` | `ProjecturedKernel/documentation` |
| [MeaningSearch.jl:22](../../source/kernel/tool/MeaningSearch.jl#L22) `../../../build/meaning` | This path is a write. Pkg installs a package read-only, so this path needs one code change (B3). The file is not sealed. |

- **What a single `add` brings with it.** Pkg installs each registered package
  with its dependencies only:

| `add` | Projectured packages | Other packages |
| --- | --- | --- |
| `ProjecturedKernel` | 1 | none |
| `ProjecturedSdl` | 9 | `SDL2_jll`, `SimpleDirectMediaLayer` |
| `ProjecturedJson` | 17 | none |
| `ProjecturedJson ProjecturedSdl` | 18 | the two SDL packages |
| `Projectured` | 56 | none |
| the full application | 83 | also `HTTP`, `JSON3`, `ModelContextProtocol` |

### 2.4 For the packages: the set of R12

A scan on 2026-09-29. The rule of R12 (no example package, no test package)
gives 69 packages. It holds seven packages that the application does not need:
`ProjecturedTulip`, `ProjecturedOdbc`, `ProjecturedVideo`,
`ProjecturedAdaptagrams`, `ProjecturedBench`, `ProjecturedBuilder` and
`ProjecturedRepl`. Four of them can not go in as they are:

| Package | Why not |
| --- | --- |
| `ProjecturedBench` | It depends on `ProjecturedExample`, which R12 leaves out. Its entry file includes files from `_BENCH_DIR`, outside its slice. |
| `ProjecturedRepl` | It depends on `ProjecturedExample` and `ProjecturedTest`, which R12 leaves out. `Repl.jl:78` includes `../../asset/precompile/`. |
| `ProjecturedBuilder` | `Executable.jl:415` reads `../../asset/font`, and `BuildContext` looks for the root of a checkout. It is a tool of this repository. |
| `ProjecturedAdaptagrams` | `deps/build.jl` compiles a C++ shim on the machine of the user, and `Adaptagrams.jl:14` reads `package/ProjecturedAdaptagrams/deps`. It needs a JLL first. |

The rule also leaves out `ProjecturedExample`, which depends on the 22
per-domain example packages. So the registry gives no application, no gallery
and no `run_value_viewer`.
[own-project-guide.md](../../documentation/guide/own-project-guide.md) names
`run_value_viewer` now.

`ProjecturedTulip`, `ProjecturedOdbc` and `ProjecturedVideo` have no path that
leaves their slice. They bring `Tulip` with `MathOptInterface`, `ODBC` with
`DBInterface` and `Tables`, and `FFMPEG` from General.

## 3. Facts that the release must handle

### 3.1 Both routes

- **Most fonts had no licence text.** `asset/font/` held licence text for
  Lucide (ISC) and Noto Emoji (OFL) only. Step A2 found the licence of each
  family: DejaVu 2.37 is Bitstream Vera (its text is also inside each font
  file), Inconsolata is OFL-1.1, Ubuntu is the Ubuntu Font Licence 1.0, and
  **Liberation 1.07.3 is GPL-2 with a font exception, not OFL** (only
  Liberation 2.x is OFL). A GPL-2 font needs its source, or a written offer,
  beside it (R17).
- **`LICENCE-PD` asks for its notice in every copy.** The archive carries it.
  Pkg installs only the folder of a package, so each package folder of the
  release copy must carry it too.

### 3.2 The binary

- **Libraries with other licences come in through SDL.** `ProjecturedSdl` →
  `SDL2_jll` → `alsa_plugins_jll` → `FFMPEG_jll` brings `x264_jll`,
  `x265_jll`, `libfdk_aac_jll`, `LAME_jll`, `Opus_jll` and `libvorbis_jll`
  into `build/app/projectured/Manifest.toml`. x264 and x265 are GPL-2.0. The
  licence of fdk-aac is not compatible with the GPL. The application plays no
  sound. An archive that holds all three can be an archive that nobody can
  legally give to others. This is a gate for the release of the binary.
  The package route does not give these libraries to anyone: Pkg downloads
  them from the Julia package servers, not from us.
- **The archive carries only `LICENCE-PD` and `LICENCE-COMMERCIAL`**
  (`PROJECTURED_LICENCES`). The licences of Julia and of each JLL artifact are
  not named in the `README`.
- **Three faults from the first build are still open** (application-and-build.md
  Step 4): `--build-info` shows the time of the last write of the generated
  module, the window has no `WM_NAME`, and `SIGTERM` prints a backtrace with
  exit code 15.
- **Linux x86-64 only.** The relocation test uses `bwrap`, which is Linux-only.
  macOS and Windows need a build on that system, and that is not in this plan.

### 3.3 The packages

- **General needs an OSI-approved licence**, "located in the top-level
  directory" of the package. `LICENCE-PD` is not one; MPL-2.0 is (R21). The
  release copy already puts the licence files into each package folder. A
  package in General can not depend on a package outside General, so all 65 go
  in together or none.
- **The AutoMerge rules of General** (the guidelines of RegistryCI, read on
  2026-09-29) that matter here:
  - "Repo URL ends with `/PackageName.jl.git`." Only `Projectured` meets it in
    `projectured/Projectured.jl`. **The first version of each of the other 64
    needs a manual merge** by the maintainers of General. The rules for a new
    version do not have this one.
  - "The package should be installable" and "loadable". AutoMerge tests a new
    package against General, so a package goes in only after its siblings are
    in. **The 65 packages form 13 dependency levels** (1, 9, 4, 2, 2, 6, 7, 4,
    4, 11, 8, 5 and 2 packages), and the first registration goes level by
    level. I think General also waits some days before it merges a new
    package; the page did not say.
  - The Damerau–Levenshtein distance of a new name to every existing name must
    be at least 3 (2 in lower case), and a visual distance must pass too.
    **Seven pairs of our own names fail it**: `ProjecturedSdl`/`ProjecturedSql`
    (1), `ProjecturedFsm`/`ProjecturedRst`, `ProjecturedJulia`/`ProjecturedTulip`,
    `ProjecturedPdf`/`ProjecturedSdl`, `ProjecturedSdl`/`ProjecturedXml`,
    `ProjecturedSql`/`ProjecturedXml` and `ProjecturedXml`/`ProjecturedYaml`
    (2 each). The second of each pair fails when the first is already in. No
    name comes close to one of the 14,233 names in General. The visual distance
    was not computed.
  - A new version "should be a standard increment and not skip versions". A
    version that the release repository committed and General never took makes
    the next version skip it (R25).
  - `[compat]` must bound every dependency and Julia from above. The caret
    bounds of the release copy do.
- **A registry entry names a tree by its hash.** Pkg must find that tree in the
  release repository forever. So the history of the release repository is never
  rewritten.
- **The generated copy and the repository can drift.** A new path that leaves a
  slice works in the checkout and fails in the copy. The generator must find
  such a path and stop (B2).
- **`projectured/projectured` must stay free (R9).** The Lisp original was
  renamed to `projectured/projectured-lisp`, which is archived, and GitHub
  sends the old name there (checked on 2026-09-29: `301` to
  `projectured-lisp`). A new repository under the old name ends the redirect.
  Quicklisp builds the Lisp original through the old name
  (`branched-git https://github.com/projectured/projectured.git quicklisp`),
  and `CLAUDE.md` and `new-domain-guide.md` use it for the original too.

## 4. Decisions

### 4.1 Open

| # | Question | Recommendation (mine, not decided) |
| --- | --- | --- |
| R3a | Which way removes the sound chain from the binary? | A stand-in for `alsa_plugins_jll` in the build environment of the binary: the same name and uuid, no dependencies (the owner, 2026-09-29). It removes 58 of the 99 JLLs and 462 of the 577 MB of artifacts, FFmpeg with `--enable-nonfree` among them. The binary only: with `Pkg.add` the JLLs come from the Julia package servers, not from us. |
| R17 | Liberation 1.07.3 is GPL-2. | Switch Sans, Serif and Mono to Liberation 2.x (OFL-1.1, the same metrics), and remove Sans Narrow, which no code uses and which 2.x does not have (the owner, 2026-09-29). **Both routes**: `ProjecturedStyle` and `ProjecturedWeb` carry `asset/font/`, so it comes before B6 too. |
| R18 | The source of the LGPL and GPL libraries that stay in the binary. | First `--filter-stdlibs`, which should leave out `libgit2` and 7-Zip because no package of the application needs Pkg or LibGit2; then a source archive of exactly the versions that remain, in the same GitHub release (the owner, 2026-09-29). The binary only. |
| R23 | One release repository with 65 subdirectories, or one repository for each package? | Open: the owner asked whether one repository for each package makes the registration automatic. It makes the URL rule pass, so the first version of about 61 packages merges with no maintainer. But the name rule still stops 4 or more of them, the first registration still goes one dependency level at a time with 3 days of waiting for each new package (13 levels), and 65 repositories must then be kept and pushed at each release. My view: one repository, and a word first in `#pkg-registration` on the Julia Slack, which the README of General names for a review by a person. |
| R20 | The guides live in `ProjecturedKernel` (§2.3), so each change to a guide gives the kernel a new version, and Julia compiles every package above it again after `pkg> up`. A change to a licence text gives all 65 a new version. Accept that, or give the guides a package of their own later? | Accept it now. The kernel changes in most releases anyway, and a package of its own for the guides is a change of structure. |

### 4.2 Decided

The owner decided these on 2026-09-29.

| # | Question | Decision |
| --- | --- | --- |
| R0 | Which route? | The binary archive first. No change to the repository structure. |
| R1 | Is the deferral of 2026-09-20 lifted? | Yes. Part A goes to the release, Step A7 included. The owner still approves Step A7 before it runs. |
| R3 | What to do about x264, x265 and fdk-aac? | Wait for the licence check of Step A2. Nothing is chosen until it reports. If the answer is "remove them", look for a way that changes no structure, for example a JLL preference that points `SDL2_jll` at a build without sound plugins. The check reported on 2026-09-29; R3a holds the choice. |
| R5 | Is the repository public? | Yes: <https://github.com/projectured/projectured-julia>. A GitHub release there reaches every user. |
| R7 | Build from the main checkout, or from a worktree? | A worktree at the release commit. Then the archive matches the tag, and no uncommitted change of another session goes in. The cost is one full compile of the cache for that worktree. |
| R8 | How does a Julia programmer install the packages? | Through a generated release copy and a registry of our own (Part B). Not `pkg> develop`: the owner does not want it. Not a move of `source/` into the packages: that changes the structure. |
| R2 | Which plan owns the release? | This plan. documentation-rewrite.md Step 11 points here. |
| R4 | Version and tag? | `0.1.0` and `v0.1.0`. The first registration gives every package `0.1.0`. |
| R6 | Which open faults of §3.2 to fix before the release? | The `SIGTERM` backtrace and `WM_NAME`. The `--build-info` time can wait. |
| R11 | One version for all packages, or one per package? | One per package. A package that did not change gets no new version, so a user does not download it again. The rules of R11 below say how. |
| R12 | Which packages go in the registry? | Every package that is not an example package and not a test package: 69. R16 takes four out, so the registry set is 65 packages. |
| R13 | The `[compat]` bounds? | The siblings: a caret bound from the version of the sibling in the release that changed the package (R11, rule 3). Every other package: a caret bound from its version in `environment/all/Manifest.toml`. Julia: the oldest version that passes Step B4. |
| R14 | A `projectured` command through Pkg apps? | Later. |
| R15 | Rename `LICENCE-PD`? | No. It stays as it is. Moot since R21: the file goes. |
| R9 | Where does the release copy live? | In one repository per package, `projectured/<Name>.jl` (R23). Not `projectured/projectured`: that name is the redirect to the Lisp original (§3.3). The umbrella's own repository is then `projectured/Projectured.jl`. |
| R10 | The name and place of the registry? | The General registry (changed on 2026-09-29 by R21). Before that: `projectured/ProjecturedRegistry`, made with `LocalRegistry.jl`, which Step B4 still uses as a local stand-in for General. |
| R21 | The licence of the repository and of the packages? | **MPL-2.0** (the owner, 2026-09-29). Other people may build and sell products on ProjecturEd with packages of their own; their changes to the files of ProjecturEd stay MPL and public when they distribute them; the owner can use those changes in his own closed products with no contributor licence agreement. It is OSI-approved, so the packages can go into General. It replaces `LICENCE-PD` and `LICENCE-COMMERCIAL`, and it makes R15 moot. Part L does the change. |
| R22 | Seven pairs of our names fail the name rule of General. Rename, or ask for manual merges? | Manual merges (the owner, 2026-09-29). |
| R24 | Do the other two authors agree to MPL-2.0 for their commits? | Yes (the owner, 2026-09-29: "I know them well and they agreed"). Keep their agreement in writing with the release records. |
| R25 | Guard against a version that skips one? | Yes (the owner, 2026-09-29). Done: `build_package_release!` takes `registry`, and `build_projectured_package_release!` checks General (commit after `507ef1c06`). |
| R23 | One release repository with 65 subdirectories, or one repository for each package? | One repository for each package, `projectured/<Name>.jl` (the owner, 2026-09-29). Then the URL rule of General passes for every package; the name rule still needs a manual merge for at least 4 (R22); the first registration still goes one level at a time, with 3 days of waiting for each new package. Done in the generator (commit `92b4fa717`). |
| R26 | Without the port, which engine does `ProjecturedGraph` use when none is registered? | A new force-directed engine, written from the textbook algorithm and not from the port (the owner, 2026-09-29: option 3). Part G. |
| R19 | The ten files in `source/graph/cpp/` port the layout engine of OMNeT++, whose headers name OpenSim Ltd. and Andras Varga and the Academic Public License. | Move them out of this repository, into the private downstream repository that uses them (the owner, 2026-09-29). R26 holds what `ProjecturedGraph` uses in their place. The MIT function in `source/domain/Domain.jl` keeps its notice in one comment. |
| R16 | What to do with the four packages of §2.4 that can not go in as they are? | Skip them: `ProjecturedBench`, `ProjecturedRepl`, `ProjecturedBuilder` and `ProjecturedAdaptagrams`. `ProjecturedExample` and the other example packages stay out by R12, so the registry gives no application; the binary gives it. The registry set is 65 packages. |

**The rules of R11.** The owner chose one version per package. These rules
are the design of the agent (2026-09-29), for Step B2:

1. A package gets a new version only when its content changed: its slice of
   `source/`, a folder that the generator copies into it, or the list of its
   dependencies. The generator compares the new tree with the tree of the last
   registered version.
2. A package that did not change keeps its last registered `Project.toml` as
   it is, `[compat]` included. Without this rule, a change in the kernel gives
   a new `[compat]`, and so a new version, to every package above it.
3. A package that changed gets a patch step (`0.1.0` → `0.1.1`). Its bounds on
   the siblings become caret bounds from their versions in this release.
4. The versions live in the release copy and in the registry only. The
   `Project.toml` files of this repository keep `0.1.0`, so a release changes
   nothing in this repository.

What follows from the rules:

- The newest version of every package is always the set that the release
  tested, so `pkg> up` always gives a tested set.
- A user who holds one package back can get a combination that no release
  tested. The guides tell the user to update all Projectured packages
  together.
- No new version means no new download. But Julia compiles a package again
  when one of its dependencies changed. The kernel is below every package, so
  a change in the kernel still compiles almost everything again.

## 5. Steps

Every step that changes a tracked file runs in a worktree, with a commit per
step. Nothing lands on `main` and nothing is pushed without the owner's word.
The build of Step A4 runs in a worktree at the release commit (R7), after the
commits of Steps A2 and A3 are on `main`.

Part A and Part B do not wait for each other, except that Step A2 (the licence
check) also decides the licence texts that Part B copies.

## Part A: the binary

### Step A1: check that the builder still works, with no compile

- [x] `test_builder()`. It compiles nothing. Done on 2026-09-29: 167 of 167
      pass. It needs only the builder, so it runs without the test umbrella:
      `julia --project=environment/build -e 'using ProjecturedBuilder, Test;
      include("test/builder/BuilderTest.jl"); test_builder()'`.
- [x] `bin/build_projectured --no-compile`. It writes the package of the binary
      in about a second. Done on 2026-09-29: exit 0.
- [x] `bin/projectured --help`, and one start of `bin/projectured` with two
      files. This is the program that the build compiles. Done in Step A3 on
      2026-09-29: `--help` prints the usage, and a start with a JSON and a
      Markdown file opens the window.
- [ ] The grep of §2.1 for private names in `documentation/` and `asset/web/`
      again, on the release commit. On 2026-09-29, on the branch: no hit.

### Step A2: the licence check (gate)

- [x] The license-compliance-officer reads `build/app/projectured/Manifest.toml`
      and `asset/font/`, and lists for each item: its licence, whether the
      archive may carry it, and which text must go with it. It also says which
      texts each package folder of Part B must carry.
- [ ] The owner decides R3a, R17, R18 and R19 from that list.
- [x] Add the licence texts that are missing to `asset/font/`. New files only;
      no folder moves. Done for three on 2026-09-29: `DejaVu-Bitstream-Vera.txt`,
      `Inconsolata-OFL.txt`, `Ubuntu-UFL.txt`. Liberation after R17, below.

**R18, done on 2026-09-30.** `build_source_archive` (`source/builder/SourceArchive.jl`)
writes `<name>-<version>-sources.tar` beside the binary archive: for each
`SourceOffer`, the tarball of its authors, downloaded once into
`build/source-cache` and checked against a SHA-256 that a download verified,
the patches its build applies, and a README with the JLL, the recipe at its
Yggdrasil commit and a note. It first checks that each JLL carries the version
of its offer (stdlib, manifest, or `VERSION` for Julia) and stops otherwise, so
an upgrade can not ship the wrong source. `PROJECTURED_SOURCE_OFFERS` holds
seven parts, researched and verified on 2026-09-30: alsa-lib 1.2.15.3, GMP 6.3.0
(two patches), MPFR 4.2.2, GCC 15.2.0 (the runtime libraries; their banner says
15.2.0), libgit2 at `0060d9cf`, 7-Zip 26.02 (which `p7zip_jll` 17.8.2 builds)
and Julia 1.13.0. The archive of this release: 131 MB, 2.8 s from the cache.
Two limits, which its README says: GitHub does not promise the bytes of the
archive of a git revision (libgit2), and the patches that Yggdrasil applies to
GCC itself are named by their recipe, not pinned to a commit.
`build_projectured_distribution` builds it after the bundle and before the
archive, and the README of the archive names it. `test_builder()` 217.

**R3a, done on 2026-09-29.** `write_app_package` and `build_executable` take
`stand_ins`, `"<name>" => "<uuid>"` of JLLs that a binary must not carry. The
builder writes a package of the same name and uuid under `stand_in/` of the app
package, with no dependency and with the three bindings that a user of a JLL
reads (`artifact_dir`, `PATH_list`, `LIBPATH_list`, all empty), and lists it in
`[deps]` and `[sources]`. The build record names each one. `JLLWrappers`
reads `PATH_list` and `LIBPATH_list` of a dependency only when they exist, and
SimpleDirectMediaLayer reads `artifact_dir`; nothing else is read.
`PROJECTURED_STAND_INS` names `alsa_plugins_jll`. The resolved environment of
the binary then holds 42 JLLs instead of 99 (41 and the stand-in, as the
licence check predicted): no FFmpeg, x264, x265, fdk-aac, PulseAudio, GSL or
BerkeleyDB; SDL2 and alsa stay. With the stand-in, `bin/projectured --help`
works, the web backend ends on `SIGTERM` with no backtrace, and a window with two
files opens with its title and quits on `SIGTERM`. `test_builder()` 181.

**R17, done on 2026-09-29.** Liberation Sans, Serif and Mono are version 2.1.5
from the release of their authors (`liberation-fonts-ttf-2.1.5.tar.gz`, SHA-256
`7191c669…25d0`), each file "Licensed under the SIL Open Font License, Version
1.1"; `Liberation-OFL.txt` holds the `LICENSE` of that release. The four files
of Sans Narrow are removed: no code used them, and 2.x has no such family. The
example `text_baseline`, rendered before and after, differs in 125 of 196,836
pixels, all inside the box of the one word in Liberation Serif Italic: the
glyphs changed a little, the layout did not move. `test_sdl()` 719,
`test_tool_views()` 19 (the inspectors draw their headings in Liberation Sans
Bold) and `test_hover_probe()` 8 pass.
- [x] The archive carries the third-party texts of the results below: extend
      `PROJECTURED_LICENCES`, the `README` text and the assets in
      `source/builder/`, with a test in `test/builder/BuilderTest.jl`. Done on
      2026-09-30, except the source archive of R18, which is its own step.

      `bundle_licence_texts!` (`source/builder/LicenceTexts.jl`) writes into
      `share/licenses/` of the copy that is archived: Julia's `LICENSE.md` and
      the `THIRDPARTY.md` of its tag; the texts of every standard-library JLL,
      from the `share/licenses/` of its artifact for this platform, which it
      downloads by the URL of `StdlibArtifacts.toml`, checks against its
      SHA-256, and caches in `build/licence-cache`; the licence files of every
      registered package of the manifest of the binary, from the depot; the
      MPL-2.0 text for `cert.pem`, whose JLL names no artifact
      (`PROJECTURED_EXTRA_TEXTS`); and a `README` that lists all of it, names the
      texts that each artifact carries itself, and holds the two credits
      (`PROJECTURED_CREDITS`: the IJG sentence, and the FreeType credit with
      2026, the year of the shipped FreeType 2.14.3). `build_distribution` calls
      it after the checks, and the README of the archive points to it. On the
      bundle of the test build: 23.5 s, 23 library folders, 54 packages, all
      with a licence file, 1.1 MB of texts, 187 MB of downloads in the cache.
      `test_builder()` 196.

Results of 2026-09-29. The evidence (the manifest list, the `LD_DEBUG` log of
a start, the `ffmpeg` build flags, the font name tables and the downloaded
texts) is in `/var/tmp/release-plan/licence/`.

- **The sound chain.** `SDL2_jll` 2.32.10 and `SimpleDirectMediaLayer` 0.5
  both run `using alsa_plugins_jll`, and its `__init__` loads `FFMPEG_jll` and
  `PulseAudio_jll`. FFmpeg 9.0 of the JLL is built with `--enable-gpl
  --enable-version3 --enable-nonfree` and fdk-aac, x264 and x265, and `ffmpeg
  -L` says: "This version of ffmpeg has nonfree parts compiled in. Therefore it
  is not legally redistributable." The chain also loads GSL, Readline and Gdbm
  (GPL-3), FFTW, obstack and BlueZ (GPL-2) and BerkeleyDB (AGPL-3) into the
  process of `projectured --help`. Every version of these JLLs in General has
  the same dependencies.
- **A JLL preference does not remove the chain.** It changes which file a
  library loads, but the `using` of the dependency stays, and PackageCompiler
  bundles the artifact of every package of the manifest.
- **What stays after a cut of `alsa_plugins_jll`** is permissive, with its text
  in the `share/licenses/` of each artifact, except the LGPL and GPL parts of
  R18. The archive must add: Julia's `LICENSE.md` and `THIRDPARTY.md`, the
  texts of `lib/julia`, `libexec` and `cert.pem` (MPL-2.0), the `LICENSE`
  files of the 25 Julia packages compiled into the image, and two credits in
  the `README` (the IJG sentence for libjpeg-turbo, the FreeType credit).
- **Part B needs no JLL text**, because Pkg downloads the JLLs from the Julia
  package servers. Each package folder carries `LICENCE-PD` and
  `LICENCE-COMMERCIAL`; `ProjecturedStyle` and `ProjecturedWeb` carry the font
  texts with `asset/font/`. R17 and R19 apply to Part B too.
- **`asset/web/` and `documentation/` hold no third-party content.**

### Step A3: the faults the owner wants fixed (R6)

- [x] `SIGTERM` stops the application with no backtrace.

      **The cause is the Julia runtime, not the application.** Every Julia
      process prints the stacks of all threads on `SIGTERM`: the signal
      listener of the runtime takes the signal with `sigwait` and treats it as
      fatal, with no setting to change that (`src/signals-unix.c` of 1.13.0,
      lines 1131 and 1154 to 1215). **The fix**, in the module that the builder
      writes for every binary: `julia_main` calls `_end_on_terminate!()` right
      after the log level. On Linux it sets `SIGTERM` to its default action and
      unblocks it on the main thread. Linux gives a signal sent to the process
      to the main thread first when that thread does not block it, so the
      kernel ends the process: exit status 143, no output. `atexit` hooks do
      not run; the application registers none. Checked on 2026-09-29: a plain
      Julia process with 1 and with 4 threads, and a program that the builder
      wrote with `compile = false`, all end with 143 and print nothing after
      their last line. `test_builder()`: 170 of 170.
- [x] The window has a `WM_NAME` (and `_NET_WM_NAME`) of `ProjecturEd`.

      **The cause is the libX11 JLL.** Its build names a locale folder that
      exists only on the build machine, and the JLL does not set `XLOCALEDIR`.
      Without the locale data `XSupportsLocale` is false, and SDL 2 then sets
      neither property (`xprop`: "not found"; `WM_CLASS` was there). With
      `XLOCALEDIR` pointing at `share/X11/locale` of the artifact, both
      properties were right. **The fix**: `ProjecturedSdl` names
      `Xorg_libX11_jll`, and its `__init__` sets `XLOCALEDIR` to that folder
      unless the user set it (commit `1cfea4acc`). The binary carries the
      artifact whole, so the fix holds there too.
- [x] One commit per fault, each with the narrowest test.

Checked on 2026-09-29 on the real application of the worktree (`bin/projectured`,
no `XLOCALEDIR` set):

- The window of a start with two files has `WM_NAME` and `_NET_WM_NAME` =
  "ProjecturEd".
- `SIGTERM` prints no backtrace in either backend, and the two end differently.
  With the web backend the process ends at once (status 15 through the
  `systemd-run` wrapper, 143 without it). With the SDL window the application
  quits normally, status 0: SDL puts its own `SIGTERM` handler in place when the
  handler is the default one, and it turns the signal into a quit event. The
  fix of `_end_on_terminate!` is what gives SDL that default.
- `test_native_window()` passes with 7, with a new assertion that `XLOCALEDIR`
  holds `locale.dir`, and `test_sdl_layering()` passes.

### Step A4: the distribution build

Warning: do not start the build while `free -g` shows less than 40 GB
available. The cap of 20 GB must stay under half of the available memory, and
other sessions use this machine.

```sh
free -g | sed -n 2p
mkdir -p /var/tmp/projectured-release
TMPDIR=/var/tmp/projectured-release JULIA_IMAGE_THREADS=2 JULIA_NUM_PRECOMPILE_TASKS=2 \
  systemd-run --user --scope -q -p MemoryMax=20G -p MemorySwapMax=0 \
  timeout 7200 nice -n 10 taskset -c 16-23 \
  julia --startup-file=no --project=environment/build \
    source/builder/build_binary.jl projectured --distribution \
  > /var/tmp/projectured-release/build.log 2>&1
```

- [x] The relocation test and the program check pass. **A test build, on
      2026-09-30** (commit `28ce34357`, `--distribution --filter-stdlibs`),
      with the stand-in of R3a and the fonts of R17, but not yet the licence
      texts of Julia and its libraries (A2) or the source archive (R18), so
      its archive is not the release one. About 22 minutes. Bundle 1,149 MB
      (1,558 on 2026-09-17), artifacts 99 MB (577), libraries 290 MB, archive
      306.3 MB (437), SHA-256 `583c2786…411c`. The copy started with no depot
      in 0.34 s, and the program check read the web client, the fonts and the
      guides from the bundle.

      **`--filter-stdlibs` did not shorten the list of R18.** It filters the
      standard libraries in the system image, but PackageCompiler copies the
      `lib/julia` of Julia whole: `libgit2`, `libssh2`, `libcurl`, OpenBLAS and
      the rest are all there, and `7z` in `libexec/julia`. So the source archive
      of R18 covers alsa, GMP, MPFR, the GCC runtime (`libgcc_s`, `libstdc++`,
      `libgfortran`, `libgomp`, `libatomic`, `libssp`, `libquadmath`),
      libgit2, 7-Zip and libjulia.

      **The test build carried the `libstdc++` of this machine**, found while
      the sources of R18 were checked: `libstdc++.so.6.0.35` of Ubuntu's GCC 16
      prerelease (`libstdc++6` 16-20260322), which needs `GLIBC_2.38`, so the
      archive would not start on Debian 12 or Ubuntu 22.04. PackageCompiler
      copies "the libstdc++ that is actually loaded by Julia", and Julia's
      loader loads the machine's own when it is newer. Julia's own is
      `libstdc++.so.6.0.34` of GCC 15.2.0, needs `GLIBC_2.17`, and is byte for
      byte the one of `CompilerSupportLibraries_jll` 1.5.5. **The fix**:
      `bin/build_projectured` starts every build with `JULIA_PROBE_LIBSTDCXX=0`
      (the switch of `cli/loader_lib.c`), and `build_distribution` refuses a
      bundle whose `libstdc++` is not Julia's own. A binary still probes on its
      user's machine and loads a newer system library when there is one.
      `test_builder()` 199.
- [ ] Record in this plan: the wall time, the peak memory, the bundle size, the
      archive size and the SHA-256 digest that the build prints.
- [ ] Write the digest to `<archive>.sha256`, beside the archive.

### Step A5: test the archive as a user gets it

**What the first container run found (2026-09-30).** The release candidate did
not start on Debian 12, Ubuntu 22.04 or Fedora 41: `libSDL2.so` needs
`libiconv.so.2` and `libsamplerate.so.0`, and `SDL2_jll` names neither JLL. The
tree of `alsa_plugins_jll` brought both, and the stand-in of R3a removed it. The
test of a copy on this machine passed, because this machine has
`/usr/local/lib/libiconv.so.2` and a system `libsamplerate.so.0`. Two changes:

- `StandIn(name, uuid; keeps)`: a stand-in keeps dependencies of the real one
  that the binary still needs, and loads them, so they load before `libSDL2`
  whatever the order of the packages. `alsa_plugins_jll` keeps
  `libsamplerate_jll` and `Libiconv_jll`.
- `collect_missing_libraries(bundle)`: every library that a file of the bundle
  needs (`readelf -d`, `NEEDED`) must be in the bundle or be one of
  `GLIBC_LIBRARIES`; `build_distribution` stops otherwise. On the failing
  bundle it names exactly the two libraries, in 0.3 s, so this class of fault
  shows at build time now. `test_builder()` 225.

- [ ] Unpack the archive under `/var/tmp`, far from the checkout. Start it with
      a window on this machine (`DISPLAY=:0`), and open a JSON, a Markdown and a
      Julia file. The owner looks at the window before Step A7.
- [ ] In `podman` containers of two or three distributions (for example
      Debian 12, Ubuntu 22.04 and Fedora), unpack the archive and run
      `--build-info`. Then start `--backend=web --assistant=none` and read the
      web client with `curl`. A library that fails to load shows a gap in the
      requirements of the `README`.
- [ ] If a container needs a system package, add it to
      `PROJECTURED_REQUIREMENTS` and build again.

### Step A6: the guides name the download

- [ ] [setup-guide.md](../../documentation/guide/setup-guide.md): a section
      "Download the application" before "Start the application": the link to
      the release, the unpack command, `bin/projectured`, and the requirements.
- [ ] `README.md`: the quick start names the download first.
- [ ] The web site (`projectured.github.io`, another repository) gets a link
      only if the owner asks for it.

### Step A7: publish the binary (the owner only)

The commands, to run after the owner approves. The agent states them and
stops.

```sh
git tag -a v0.1.0 -m "ProjecturEd 0.1.0"
git push origin v0.1.0
gh release create v0.1.0 \
  build/projectured-0.1.0-linux-x86_64.tar.gz \
  build/projectured-0.1.0-linux-x86_64.tar.gz.sha256 \
  --title "ProjecturEd 0.1.0" --notes-file /var/tmp/projectured-release/notes.md
```

- [ ] The release notes: what the application is, the requirements from the
      `README`, the digest, and the licence.
- [ ] After the release: download the asset from GitHub and run Step A5 once on
      that copy.

## Part B: the packages

### Step B1: prove the mechanism on a small scale

Before the generator covers every package of the registry set (R16), prove each part of the mechanism by hand,
under `/var/tmp`, with a memory cap and a timeout:

- [x] Copy `ProjecturedKernel` to a release layout: `Project.toml` without
      `[sources]`, `src/ProjecturedKernel.jl` with the include prefix
      `../source/`, and `source/kernel/`. Make it a git repository.
- [x] Make a registry with `LocalRegistry.create_registry`, and `register` the
      package in it.
- [x] In an empty depot: add the local registry, `add ProjecturedKernel`, and
      `using ProjecturedKernel`.
- [x] Do the same for `ProjecturedJson`, which brings 16 siblings. This proves
      that the siblings resolve through the registry.
- [x] Record what worked and what did not in this plan, before Step B2.

Results of 2026-09-29 (Julia 1.13.0, `LocalRegistry` 0.5.7). The prototype
scripts were `generate.jl`, `register.jl` and `user.jl` under
`/var/tmp/release-plan/b1/`.

- **Everything worked on the first real run.** A release copy of the closure
  of `ProjecturedJson` (17 packages, 18 MB) was committed to a git repository
  and registered in dependency order, with `repo = "file://…"`. In an empty
  depot that knew only this registry, `add ProjecturedKernel` and `add
  ProjecturedJson` resolved, and `using` loaded both. The 17 packages
  precompiled in 12 seconds.
- **The layout works as §2.3 says.** The kernel found its guides in
  `…/packages/ProjecturedKernel/<slug>/documentation`, and `ProjecturedStyle`
  found its 40 font files in `…/packages/ProjecturedStyle/<slug>/asset/font`.
- **An installed package folder holds only what the copy put there:**
  `LICENCE-COMMERCIAL LICENCE-PD Project.toml documentation source src` for the
  kernel.
- **The meaning folder resolves into the installed package**:
  `…/packages/ProjecturedKernel/<slug>/build/meaning`. So Step B3 is necessary.
- **Pkg makes the files read-only, not the folders**: `-r--r--r--` on each
  file, `drwxrwxr-x` on the package folder. A write to `build/meaning` would
  succeed, but it would change a folder that Pkg manages, and a shared depot
  can be read-only as a whole. §2.3 said "Pkg installs a package read-only";
  that is true of the files only.
- **A package with no dependency outside the registry needs no General.** Both
  test packages have none. The packages that bring `SDL2_jll` and the others do
  need it (§3.3).
- **`TOML.print` drops the comments of a `Project.toml`.** The copy does not
  need them.
- **The entry file of each of the 65 packages includes exactly one slice**, and
  each package folder holds only `Project.toml` and `src/<Name>.jl`. Eight of
  them have a `[compat]` section already, which the generator keeps and
  extends.

### Step B2: the generator

A new function in the builder, for example
`build_package_release(context; packages, version, output)`. The name follows
[naming-rules.md](../../documentation/rule/naming-rules.md); read it before
the name is final. For each package of the registry set (R16), the function:

- [x] copies `Project.toml` and `src/`, and the slice of `source/` that the
      entry file includes;
- [x] changes the prefix `../../../source/` to `../source/` in the entry file,
      and nothing else in the code;
- [x] copies the folders of the table in §2.3 to their places;
- [x] copies `LICENCE-PD` and `LICENCE-COMMERCIAL` into the package folder.
      The font texts that Step A2 names go with `asset/font/`, so they need no
      step of their own;
- [x] removes `[sources]`, and sets `version` and `[compat]` by the rules of
      R11 and by R13;
- [x] keeps the last registered `Project.toml` of a package whose content did
      not change, and registers no new version of it (R11, rules 1 and 2);
- [x] scans the copy for an `include`, an `@__DIR__` path or a `joinpath` with
      `..` that leaves the package folder, and stops with the file and the line
      when it finds one.

- [x] A test that compiles nothing: generate two small packages, check the
      layout, the rewritten include, the `[compat]`, the licence files, and
      that the scan stops on a path that leaves a package. Then change one of
      the two and generate again: only that one gets a new version, and the
      other keeps its tree.

What was built (2026-09-29):

- **The code.** [PackageRelease.jl](../../source/builder/PackageRelease.jl)
  holds the generic half: `build_package_release!(context; packages, output,
  assets, licences, manifest, julia_compat)` and the scan
  `collect_outside_paths(folder)`. [ProjecturedProgram.jl](../../source/builder/ProjecturedProgram.jl)
  holds the half of this repository: `PROJECTURED_RELEASE_EXCLUSIONS`,
  `PROJECTURED_PACKAGE_ASSETS`, `collect_projectured_release_packages(context)`
  and `build_projectured_package_release!(output)`.
- **The name takes `!`.** The function writes files, and the naming rules give
  `!` to an external side effect. `build_executable` and `build_distribution`
  beside it do not have it.
- **The layout of the release repository**: one folder per package at the
  root, `<Name>/`, and the licence files at the root too.
- **Where the last released version is read.** The working tree of the release
  repository holds it: the `Project.toml` of `<Name>/` is the last release of
  that package. The generator reads no registry.
- **The content that decides "changed"**: every file of the package folder, and
  the `Project.toml` without `version`, `[compat]` and `[sources]`. The
  generator writes the copy into a staging folder under `/var/tmp` first, and
  it replaces the released folder only when the content differs.
- **The bounds (R13) in practice.** A sibling: the exact version, as a caret
  (`"0.1.0"`). A package from a registry: its full version in
  `environment/all/Manifest.toml`, as a caret (`SimpleDirectMediaLayer =
  "0.5.0"`). A standard library: no bound. A bound in the source `[compat]`
  stays (`SDL2_jll = "2.32.10"`). Julia: `"1.11"` until Step B4 finds the
  oldest version that passes.
- **The scan reads the syntax tree** (`Meta.parseall`), not the text. So the
  docstring that says `@__DIR__` in `TrueType.jl` and the call `include(node)`
  in `PaneProgram.jl`, where `include` is a keyword argument, cause no false
  report. A `@__DIR__` outside `joinpath` is reported, because the scan can not
  follow it; none occurs in the 65 packages. A path inside the folder that
  names nothing is reported too, which catches an asset that the release
  forgot.
- **Registration stays out of the builder.** `LocalRegistry.jl` registers the
  packages in the order that the generator answers. The builder gets no new
  dependency; the procedure is in the build guide (Step B5).
- **The run on this repository**: 65 packages, 35 MB, all `:new` at `0.1.0`.
  A second run with no change: all 65 `:unchanged`, and no file written.
- **Changed after the review of 2026-09-29.** The code-reviewer found these
  faults, and each one is fixed:
  - `import TOML` in the test file broke `using ProjecturedTest`, which does
    not declare TOML. The test reaches it as `ProjecturedBuilder.TOML`, as
    `BuilderTest.jl` does.
  - An error in the middle of a run left the copy half-written, and the next
    run then called a package unchanged that was never registered. **Now** the
    generator writes and scans every package in the staging folder first, and
    `output` changes only when all passed. **And** it refuses a release
    repository with an uncommitted change, so the last release is always what
    the last commit holds.
  - The copy took every file in the folder, so a coverage file (`*.cov`) or an
    editor lock file could reach a user and change a version. **Now** it copies
    only the files that git tracks (`git ls-files`).
  - A JLL version carries a build suffix (`2.32.10+0`), and a `[compat]` entry
    with it is refused by Pkg. **Now** the bound drops the suffix.
  - The scan missed `joinpath(dirname(@__FILE__), …)`, `Base.include(module,
    path)`, `include(mapexpr, path)`, `include(joinpath("..", …))` and
    `Base.@__DIR__`. **Now** it follows them, and it reports a path through
    `pkgdir` or `pathof` and a `@__FILE__` it can not follow. None of these
    forms occurs in the 65 packages.
  - The digest had no length before each file, so two folders could give the
    same digest. A missing manifest gave no bounds in silence; now it stops.
  - `PROJECTURED_JULIA_COMPAT` (`"1.11"`) is the Julia bound of this
    repository, passed by `build_projectured_package_release!`.
- **The rule for the registration** that follows from the refusal: after a
  commit of the release repository, register every package whose version the
  registry does not hold yet, in the order that the generator answers. That
  makes a registration that was cut short safe to run again.
- **The tests**: [PackageReleaseTest.jl](../../test/builder/PackageReleaseTest.jl),
  `test_package_release()`, beside `test_builder()` in the umbrella suite. It
  passes with 34 assertions on a made git repository, and 490 on this
  repository: the release set is closed (every sibling that a released package
  depends on is released too), and a real run over the 65 packages passes the
  scan. `test_package_graph()` passes with 675, and the tree guard too. It
  runs alone with
  `julia --project=environment/build -e 'using ProjecturedBuilder, Test;
  include("test/builder/PackageReleaseTest.jl"); test_package_release()'`.
  `test_builder()` still passes with 167, and the naming guard passes.

### Step B3: the meaning folder of an installed package

- [x] Check [SEALING.md](../../SEALING.md) for `tool/MeaningSearch.jl` again
      before the edit. Done on 2026-09-29: `⬜`, not sealed.
- [x] In `_get_default_meaning_folder`, use the cache folder of the user also
      for an installed package. A Julia session in a checkout keeps
      `build/meaning/`.

      **Changed during the step: the test is `package/`, not writability.** B1
      showed that Pkg leaves the folder of an installed package writable, so a
      test of writability can not tell it from a checkout. The function now
      takes a second parameter, `root`, the folder three levels above the
      file. `root` is a checkout when it holds `package/`, the same marker that
      `BuildContext` uses. Everything else goes to the cache folder.
- [x] The narrowest test of the meaning search:
      `ProjecturedKernelTest.test_meaning_search()`, 69 of 69 pass. Two new
      assertions: a `root` without `package/` gives the cache folder, and a
      `root` with it gives `build/meaning`.

### Step B4: the full test of the release copy

Warning: give each Julia process a memory cap of 8 GB and a timeout, and read
`free -g` first. The first `using` of the application compiles for minutes.

- [x] Generate the 65 packages of the registry set under `/var/tmp`, commit them to a local
      git repository, and register them in a local registry.
- [x] In an empty depot: add General and the local registry.
- [x] `add Projectured ProjecturedSdl`, then `using`, and open one window
      with a JSON document. The fonts must come from
      `ProjecturedStyle/asset/font`.

      **Changed during the work: the umbrella, not `ProjecturedJson`.** A user
      can `using` only the packages that the environment names.
      `parse_natural_text` and `NaturalToGraphics` live in `ProjecturedNatural`,
      and `run_window_editor` in `ProjecturedScreen`. `add ProjecturedJson
      ProjecturedSdl` installs both, but names neither. `Projectured`
      re-exports every public name, so the install line of Step B5 names
      `Projectured ProjecturedSdl`, as the own-project guide does.
- [x] In a new environment, `add Projectured ProjecturedWeb ProjecturedMcp`,
      and open a document with `run_window_editor(…; backend = WebBackend(),
      mcp = true)`. The web client must come from `ProjecturedWeb/asset/web`.
      The MCP tool `read_resource` with `resource://guides` must list the
      guides from `ProjecturedKernel/documentation`.
Results of 2026-09-29, in an empty depot with General and a local registry of
the 65 packages (`/var/tmp/release-plan/b4/`):

- **The window.** `add Projectured ProjecturedSdl` installed 230 packages
  (ours and those of General, the JLLs included). After the precompile,
  `using` took 2.6 s. `_FONT_DIR` of `ProjecturedStyle` was
  `…/packages/ProjecturedStyle/<slug>/asset/font`, with 40 files. A headless
  print of a JSON document with `FontFileMeasure` worked, and a real window
  drew 40 frames.
- **The web backend and MCP.** `add Projectured ProjecturedWeb ProjecturedMcp`
  in a new environment: the web client page, `client.js`, the font list and a
  font file came over HTTP, and the MCP tool `read_resource` listed the guides
  (`design/concepts`) from `…/packages/ProjecturedKernel/<slug>/documentation`.

- [x] A second release: change one file in one slice, generate again, and
      register. Only that package gets a new version. `pkg> up` in the test
      depot takes it and downloads nothing else.
- [x] Repeat the `add` and the `using` of `ProjecturedJson` on Julia 1.11 and
      1.12 through `juliaup`. The oldest version that passes sets the Julia
      bound of R13.

Results of the later releases and of the Julia versions (2026-09-29). The
script is `/var/tmp/release-plan/b4/next-release.sh`; each release came from a
clone of the branch.

- **Release 2, the branch as committed.** Three packages had changed since the
  first copy: `ProjecturedKernel` (its guides and the meaning folder),
  `ProjecturedStyle` and `ProjecturedWeb` (the font texts). Each became
  `0.1.1`, and the other 62 kept `0.1.0`. `pkg> up` in the window environment
  downloaded `ProjecturedKernel` and `ProjecturedStyle` only; that environment
  does not hold `ProjecturedWeb`.
- **Release 3, one comment added to `source/json/JsonModule.jl`.** Only
  `ProjecturedJson` became `0.1.1`, and `pkg> up` downloaded only it.
- **Julia 1.11.9 and 1.12.7** (`juliaup add 1.11`, `juliaup add 1.12`; the
  default stays 1.13): in an empty depot with the local registry, `add
  ProjecturedJson` resolved and `using` loaded it on both. So the bound of R13
  stays `julia = "1.11"`. The umbrella and the backends were checked on 1.13
  only.

### Step B5: the guides name the registry

The install lines of the guides wait for Step B6: before it, they would name
a registry that does not exist. They land with the release, as the guides of
Step A6 do.

- [ ] `README.md` and [setup-guide.md](../../documentation/guide/setup-guide.md):
      the install line. With General (R21) it needs no registry line:

      ```julia
      pkg> add Projectured ProjecturedSdl
      ```

- [ ] [own-project-guide.md](../../documentation/guide/own-project-guide.md):
      the registry first; the clone with `[sources]` stays for a contributor.
      The table "Which package to load" must not send a registry user to
      `ProjecturedExample` or `run_value_viewer`, because the registry does
      not hold them (R16). For the application, it names the binary.
- [ ] The guides say: update all Projectured packages together (R11).
- [x] [build-guide.md](../../documentation/guide/build-guide.md): a section on
      how to make a package release: generate, commit, register, push. Done on
      2026-09-29 (commit `2310c84b0`), with the release copy in
      [builder.md](../../documentation/package/builder/builder.md).

### Step B6: publish the packages (the owner only)

The commands, to run after the owner approves. The agent states them and
stops.

- [ ] Part L is done, and R23 has an answer from the maintainers of General.
- [ ] Make the 65 GitHub repositories of R9, `projectured/<Name>.jl`, and
      install the Registrator app of JuliaRegistries for them.
- [ ] Generate the release for `v0.1.0` into a folder that holds a clone of
      each (`build_projectured_package_release!`), commit each, and push.
- [ ] Register in General, one dependency level at a time (§3.3): a comment
      `@JuliaRegistrator register` on the release commit of each package of the
      level. The next level starts when General has merged the level below it.
- [ ] In an empty depot, run the install line of Step B5, and
      `using Projectured, ProjecturedSdl`.

## Part G: a layout engine of our own, and the move of the port (R19, R26)

The ten files in `source/graph/cpp/` port the layout engine of OMNeT++. They
leave this repository for the private downstream repository that uses them
(R19). `ProjecturedGraph` then needs an engine of its own for a graph that no
package registered an engine for (R26).

### What exists (2026-09-29)

- **The interface** (`GraphLayoutEngine.jl`): `layout_graph(engine, graph,
  sizes, constraints; extent, border) -> (positions, routes)`, with shared
  helpers: `layout_vertices` (the order that makes a layout deterministic),
  `get_vertex_sizes`, `get_constraint_pins`, `get_constraint_clusters`,
  `get_straight_routes` and `get_extent_transform`. An engine places centres;
  the helpers do the rest.
- **The engines**: `GridEmbedding` (`:pin`, `:fixed_size`), and from the port
  `SpringEmbedderLayout` and `ForceDirectedLayout` (`:pin`, `:fixed_size`,
  `:cluster`). `make_pure_julia_layout_engine` picks one of the two ported ones
  by the vertex count (20).
- **The seam**: `register_layout_engine!(factory)`, which
  `ProjecturedAdaptagrams` already uses from its `__init__`.
- **Who uses the port**: here, `GraphLayoutChoice.jl`, the tests in
  `test/graph/projection/GraphProjectionTest.jl` (the sets up to line 420),
  `test/bench/graphlayoutbench.jl`, and `graph-layout.md` and `graph.md`. The
  downstream repository uses only `DeferredLayout`, so it keeps its pictures
  when it registers the port.

### The design

- **`FruchtermanReingoldLayout`**, in `source/graph/FruchtermanReingoldLayout.jl`:
  the force-directed algorithm of Fruchterman and Reingold (1991), written from
  its description. Edges attract with `d²/k`, every pair of vertices repels
  with `k²/d`, and a temperature that falls each round limits each step. `k`
  comes from the sizes of the boxes, so large cards get room.
- **Deterministic without a random generator**: the start places the vertices
  in the order of `layout_vertices` on a sunflower spiral (the golden angle),
  which breaks the symmetry that a grid start keeps.
- **Parts that are not connected** stay near each other by a weak pull to the
  centre, so no part flies off.
- **Boxes do not overlap**: after the simulation, a pass pushes each pair of
  overlapping boxes apart along the axis of the smaller overlap, until no pair
  overlaps or a bound of passes is reached.
- **Constraints**: `:pin` (the vertex does not move), `:fixed_size` (through
  `get_vertex_sizes`) and `:cluster` (a family moves as one body, each member
  at its own offset), the same kinds as the port.
- **`extent` and routes** through the shared helpers, as the other engines do.
- **`make_pure_julia_layout_engine`** answers `FruchtermanReingoldLayout()`
  for every size. The rule of 20 vertices belongs to the port and moves with it.
- **The downstream repository** gets the ten files, an engine that chooses
  between its two ported engines by the vertex count, and a
  `register_layout_engine!` call in its `__init__`, with the tests of the port.

### Steps

- [x] G1. `FruchtermanReingoldLayout` and its tests: every vertex placed, no
      two boxes overlap, an edge is shorter than the mean distance of two
      vertices without one, pins hold exactly, a cluster keeps its offsets, the
      same input gives the same output, an extent bounds it, and a constraint
      it does not know is refused. Done (commit `071225f08`): 99 assertions in
      `test/graph/projection/FruchtermanReingoldLayoutTest.jl`, all passing on
      the first run.
- [x] G2. The default: `make_pure_julia_layout_engine` answers the new engine;
      the tests that asked for the ported ones by default ask for it. Done in
      the same commit. `test_graph()` passed with 464.

Facts of G1 and G2 (2026-09-29):

- **The vertex count stays in the interface.** `ProjecturedAdaptagrams` extends
  `resolve_layout_engine(engine, vertex_count)`, and `GraphToGraphLayout`
  passes the count to name the engine that ran. An engine that decides by size,
  such as the one downstream, needs it too. Only the answer changed.
- **The offsets of a cluster are centre offsets**, as in the port: a member's
  centre is the body plus its offset, and a pin wins over a cluster.
- **Cost**, one run with other load on the machine, on the network graph of
  the benchmark (a chain plus a link every seventh vertex, 40 by 20 boxes):
  0.006 s at 10 vertices, 0.005 s at 60 and 0.13 s at 300, with no overlap. The
  document said 41 s at 300 for the ported force-directed engine.
- **The example `graph`**, rendered to an image with the new default: three
  cards, no overlap, straight edges between the nearest sides.
- [x] G3. The move, here: the ten files, their exports, their tests and the
      benchmark leave; the guides describe the new engine. Done on 2026-09-29:
      `source/graph/cpp/` and `test/graph/reference/` (the C++ programs that
      made the reference positions) are deleted, with 142 exports and
      `ADVANCED_LAYOUT_LIMIT`; the benchmark compares the grid with the new
      engine; `graph-layout.md`, `graph.md`, `process.md` and
      `code-quality-rules.md` describe what is here now. The comments that said
      "the original" now say OMNeT++. `test_graph()` 368 (464 less the 96 of
      the port), `test_process()` 304, `test_fsm()` 154, `test_package_graph()`
      675, and the naming and tree guards pass. **It lands on `main` only after
      G4**, or the downstream repository loses its layouts until G4 lands. The
      generated `asset/precompile/PrecompileStatements.jl` still names the two
      types; it skips an entry that no longer resolves.
- [x] G4. The move, downstream, in a worktree of that repository: the files,
      the choosing engine, the registration and the tests. Done on 2026-09-29
      by the lead of that repository, in two commits on its own branch (not
      merged, not pushed).

      **The landing order**: the first commit downstream (the move) works with
      both the old and the new `ProjecturedGraph`, so it lands first. Then
      `222b30517` of this repository and the second commit downstream (its test
      asserts the resolution by size), together. G3 (`047bfa23f`) lands with
      them or after them, never before the move downstream.

      Checked against `release-plan` at `222b30517`: the moved tests pass (111)
      with only the drawing package loaded, after `import ProjecturedAdaptagrams`
      with no shim (103 of 109 before the fix), and with the example package
      loaded; `resolve_layout_engine(DeferredLayout(), n)` gives the
      force-directed engine at 5 and 19 vertices and the spring embedder at 20
      and 25, and a layout records that name. Against the old `main` the second
      commit downstream fails 5 of 111, which is why it waits for `222b30517`.
      Not run: the whole presentation suite downstream.

Facts of G4 (2026-09-29):

- **Where the port went**: a slice of the package downstream that draws the
  topology, not a package of its own; the rules there ask for a package only for
  a new third-party dependency. The ten files are the same code; only their
  first line and three comments changed (checked here with `diff` against
  `071225f08`). An engine there chooses between the two by the vertex count, as
  the rule of 20 did, and its `__init__` registers it.
- **Same pictures**: the three topologies there (57, 7 and 3 vertices) drew
  byte for byte as before. The moved tests pass (109), and the C++ reference
  programs, built again, print the numbers that the tests assert.
- **Two faults on this side, found there and fixed here** (commit `222b30517`):
  - `ProjecturedAdaptagrams` registered from its `__init__` even without its
    shim, and so took the place of the engine registered before it and handed
    every layout to `FruchtermanReingoldLayout`. It registers now only when the
    shim is built. A shim built during a session is then used by
    `DeferredLayout` only after the next start.
  - `resolve_layout_engine(::DeferredLayout, n)` gave a registered engine no
    vertex count, so a layout recorded the name of the choice for 0 vertices.
    It now resolves the registered engine again with `n`, and it stops a
    factory that answers a `DeferredLayout`, which would loop.
  - `test_graph()` 371 with the three new assertions.

## Part L: the licence (R21)

It comes before Step A7 and Step B6, because both publish under the licence.

### Step L1: what must be settled first

- [ ] R19: the port in `source/graph/cpp/` leaves this repository (Part G), and
      the MIT function in `source/domain/Domain.jl` gets its notice. The notice
      is done (commit `fa12685a9`): the MIT text of Julia, beside the two
      functions that come from `InteractiveUtils.subtypes`.
- [x] R24: the two other authors agree to MPL-2.0 for their commits (the owner,
      2026-09-29).

### Step L2: the change

- [x] `LICENSE` at the root: the text of MPL-2.0, verbatim from
      <https://www.mozilla.org/media/MPL/2.0/index.txt> (16,726 bytes, SHA-256
      `3f3d9e00…9d04`; it differs from the Debian copy only in `https` in
      Exhibit A). `LICENCE-PD` and `LICENCE-COMMERCIAL` are removed.
- [x] `PROJECTURED_LICENCES` in the builder names `LICENSE`, so the archive,
      the release copy and each package folder carry it. The `README` of the
      archive says where the source is, which MPL-2.0 §3.2 asks of a program
      in executable form: `build_distribution` takes `source`, and
      `PROJECTURED_SOURCE` is the repository on GitHub, with the tag of the
      version. The README of each release repository names the licence.
      `test_builder()` 173, `test_package_release()` 45 + 490.
- [x] `README.md` and `CONTRIBUTING.md`: the licence is MPL-2.0, and a pull
      request offers its change under MPL-2.0. The overview presentation in
      `documentation/presentation/` too.
- [x] The web site (`projectured.github.io`, another repository) changes its
      licence sentence. The owner asked for it on 2026-09-29. Done on its
      branch `licence-mpl` (commit `0f4bd8c`, not merged, not pushed): the
      status section names MPL-2.0 and links `LICENSE` on `main` of this
      repository, so it goes live only with the licence change. The install
      section of the site still says "clone the repository" until Step B6.
- [x] `documentation-rewrite.md` D1a (a clause for `LICENCE-PD`) is moot; it
      says so there.

**The licence change lands on `main` and reaches GitHub together with the site
change**, and not before R3a, R17 and R18 are settled for any binary that is
published under it.

MPL-2.0 does not need a notice in each source file: its Exhibit A allows the
notice in "a LICENSE file in a relevant directory", and each package folder
has one.

## Step C: close

- [x] Update documentation-rewrite.md Step 11 (R2). Done on 2026-09-29: its
      D22 item points here.
- [ ] Move this plan to `plan/done/`.
