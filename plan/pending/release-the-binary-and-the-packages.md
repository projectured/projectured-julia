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
  - "Repo URL ends with `/PackageName.jl.git`." **AutoMerge does not apply
    this rule to a package in a subdirectory** (`AutoMerge/src/guidelines.jl`
    of RegistryCI: "we do not apply this check if the package is a
    subdirectory package"), and the README of General says that a new package
    in a subdirectory "will be handled by AutoMerge like any other package".
    Found on 2026-09-30; the reading of 2026-09-29 took the guideline list
    alone and missed the exception. So one release repository with a
    subdirectory for each package passes this rule too.
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
- **General has a policy for code made with an LLM** (its README, read on
  2026-09-30). Code made with the help of a tool such as Claude Code is
  welcome, but a person who maintains it must understand all of it; a
  "vibe-coded" package is refused. It asks: say so, with details, in the
  README; review the generated code by hand; keep the README short; run the
  tests in CI and track the coverage; build the documentation in CI where it
  fits. And it asks that a message about a registration be the owner's own
  words, not the output of an LLM. **The repository has no CI workflow, and its
  README does not say how the code was made.**
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
| R9 | Where does the release copy live? | In one repository, `projectured/Projectured.jl`, with one folder for each package (the owner, 2026-10-01; R23). The owner created it on 2026-10-01, private and empty; it becomes public when the release copy stands on its own (Part R). Not `projectured/projectured`: that name is the redirect to the Lisp original (§3.3). |
| R10 | The name and place of the registry? | First the owner's own registry, `ProjecturedRegistry`, in the repository `projectured/ProjecturedRegistry` (the owner, 2026-10-01; R27). It is private while `Projectured.jl` is private. The General registry later (R21), with R34. Steps B1 and B4 tested a registry of the same name, made with `LocalRegistry.jl`. |
| R21 | The licence of the repository and of the packages? | **MPL-2.0** (the owner, 2026-09-29). Other people may build and sell products on ProjecturEd with packages of their own; their changes to the files of ProjecturEd stay MPL and public when they distribute them; the owner can use those changes in his own closed products with no contributor licence agreement. It is OSI-approved, so the packages can go into General. It replaces `LICENCE-PD` and `LICENCE-COMMERCIAL`, and it makes R15 moot. Part L does the change. |
| R22 | Seven pairs of our names fail the name rule of General. Rename, or ask for manual merges? | Manual merges (the owner, 2026-09-29). |
| R24 | Do the other two authors agree to MPL-2.0 for their commits? | Yes (the owner, 2026-09-29: "I know them well and they agreed"). Keep their agreement in writing with the release records. |
| R25 | Guard against a version that skips one? | Yes (the owner, 2026-09-29). Done: `build_package_release!` takes `registry`, and `build_projectured_package_release!` checks General (commit after `c0dcdc1e1`). |
| R23 | One release repository with 65 subdirectories, or one repository for each package? | One release repository with a folder for each package, `projectured/Projectured.jl` (the owner, 2026-10-01: "I choose the single projectured/Projectured.jl repository"). The maintainers of General accept it: "generated copies are fine" in the subdirectories of one repository, "but that repo has to stand on its own" (Part R). AutoMerge does not apply the URL rule to a package in a subdirectory (§3.3). The decision of 2026-09-29, one repository for each package, is in the generator (commit `6571ceed9`); the generator must go back to one repository (Part R). |
| R26 | Without the port, which engine does `ProjecturedGraph` use when none is registered? | A new force-directed engine, written from the textbook algorithm and not from the port (the owner, 2026-09-29: option 3). Part G. |
| R19 | The ten files in `source/graph/cpp/` port the layout engine of OMNeT++, whose headers name OpenSim Ltd. and Andras Varga and the Academic Public License. | Move them out of this repository, into the private downstream repository that uses them (the owner, 2026-09-29). R26 holds what `ProjecturedGraph` uses in their place. The MIT function in `source/domain/Domain.jl` keeps its notice in one comment. |
| R35 | Which Julia do the packages promise? | Julia 1.12 (the owner, 2026-10-02, options B and B1). The CI of the first release on Julia 1.11 failed in four jobs: `@ccall gc_safe=true` of the SDL backend needs Julia 1.12, and the `world` keyword of `unsorted_names` in the completion by reflection of the platform needs Julia 1.13 (a sweep of every job on 1.12 showed it; the first reading said 1.12). `gc_safe` stays: a collection on another thread goes on while SDL waits. The completion reads the names without `world` on 1.12 (`_collect_module_names`), and checks each one in its world with `isdefinedglobal`, which 1.12 has. The other way, B2, was to promise 1.13. After the fix, every job of the release workflow on Julia 1.12 (`/var/tmp/r31/job.sh`) passes except the faults of `main`: `RoutedChangeTest.jl:199` (kernel), `PointerShapeTest.jl:58` (SDL, no cursor with the offscreen driver) and the known faults of `test_integration()`. Step B4 had checked only `ProjecturedJSON` on 1.11. The other way was a 1.11 path in both places, which makes SDL worse on 1.11 and needs its tests for as long as 1.11 is promised. The first release, `0.1.0` with `julia = "1.11"`, was private and is replaced by a new first commit and a new registry. |
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

**Deferred.** The owner, 2026-10-06: the binary is not part of the first release.
The first release is the packages, 0.1.0 in `ProjecturedRegistry`. The steps of
Part A wait for a later release.

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
- [x] The owner decides R3a, R17, R18 and R19 from that list. Decided on
      2026-09-29; the answers are in the table of decisions.
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
      unless the user set it (commit `212029014`). The binary carries the
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
      2026-09-30** (commit `fe3eabbcc`, `--distribution --filter-stdlibs`),
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
- [x] Record in this plan: the wall time, the peak memory, the bundle size, the
      archive size and the SHA-256 digest that the build prints. **The release
      candidate of 2026-09-30** (commit `8f098d469`, `bin/build_projectured
      --distribution`): with the stand-in and its two kept JLLs, Liberation
      2.1.5, Julia's own `libstdc++` (GCC 15.2.0, `GLIBC_2.17`), the licence
      texts and the source archive. Bundle 1,174 MB; archive 317.4 MB,
      SHA-256 `dc86af797f3de453e6f9512700738e7acc7f94206e12baea261a4bdff4ad3f8b`;
      source archive `projectured-0.1.0-sources.tar`, 131 MB. About 13 minutes
      with warm caches; the peak memory was not measured. The relocation test,
      the program check and the check of missing libraries passed.
- [ ] Write the digest to `<archive>.sha256`, beside the archive. At Step A7,
      from the archive that is published.

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
- [x] In `podman` containers of two or three distributions (for example
      Debian 12, Ubuntu 22.04 and Fedora), unpack the archive and run
      `--build-info`. Then start `--backend=web --assistant=none` and read the
      web client with `curl`. A library that fails to load shows a gap in the
      requirements of the `README`. Done with the release candidate
      (`/var/tmp/release-plan/a5/containers.sh`, no network in the container,
      a bash socket in place of `curl`): Debian 12 (glibc 2.36), Ubuntu 22.04
      (2.35) and Fedora 41 (2.40) all answer `--build-info`, serve the web
      client (HTTP 200) within 2 s, end on `SIGTERM` with 143 and no output, and
      carry the licence index and a README that names the source archive.
- [x] If a container needs a system package, add it to
      `PROJECTURED_REQUIREMENTS` and build again. None needed: the first run
      found two missing libraries, which the bundle now carries (above).

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

- [x] `README.md` and [setup-guide.md](../../documentation/guide/setup-guide.md):
      the install line. Done on 2026-10-03, with the two lines of
      `ProjecturedRegistry`, because the registry comes before General; the
      README has the two ways to start and a table of which repository is which,
      as the front page of `Projectured.jl` has. With General (R21) it needs no registry line:

      ```julia
      pkg> add Projectured ProjecturedSDL
      ```

- [x] [own-project-guide.md](../../documentation/guide/own-project-guide.md):
      the registry first (done on 2026-10-03; `ProjecturedExample` is "from a
      clone of the source only", although the registry holds it as a support
      package of the tests); the clone with `[sources]` stays for a contributor.
      The table "Which package to load" must not send a registry user to
      `ProjecturedExample` or `run_value_viewer`, because the registry does
      not hold them (R16). For the application, it names the binary.
- [x] The guides say: update all Projectured packages together (R11). Done on
      2026-10-03: the README and the own-project guide.
- [x] [build-guide.md](../../documentation/guide/build-guide.md): a section on
      how to make a package release: generate, commit, register, push. Done on
      2026-09-29 (commit `abe2c9557`), with the release copy in
      [builder.md](../../documentation/package/builder/builder.md).

### Step B6: publish the packages (the owner only)

The commands, to run after the owner approves. The agent states them and
stops.

A local registry comes first (R27), with the steps at the end of Part R. This
step registers in General later, from the same release repository.

- [x] Part L is done, and R23 has an answer from the maintainers of General.
- [x] Make the release repository of R9, `projectured/Projectured.jl`.
      Done by the owner on 2026-10-01, private and empty.
- [ ] Make the release repository public, and install the Registrator app of
      JuliaRegistries for it.
- [ ] Generate the release for `v0.1.0` into a clone of the release repository
      (`build_projectured_package_release!`), commit, and push.
- [ ] Register in General, one dependency level at a time (§3.3): a comment
      `@JuliaRegistrator register` on the release commit of each package of the
      level. The next level starts when General has merged the level below it.
- [ ] In an empty depot, run the install line of Step B5, and
      `using Projectured, ProjecturedSDL`.

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
      it does not know is refused. Done (commit `0990e7003`): 99 assertions in
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
      `35defbe51` of this repository and the second commit downstream (its test
      asserts the resolution by size), together. G3 (`c7a156547`) lands with
      them or after them, never before the move downstream.

      Checked against `release-plan` at `35defbe51`: the moved tests pass (111)
      with only the drawing package loaded, after `import ProjecturedAdaptagrams`
      with no shim (103 of 109 before the fix), and with the example package
      loaded; `resolve_layout_engine(DeferredLayout(), n)` gives the
      force-directed engine at 5 and 19 vertices and the spring embedder at 20
      and 25, and a layout records that name. Against the old `main` the second
      commit downstream fails 5 of 111, which is why it waits for `35defbe51`.
      Not run: the whole presentation suite downstream.

Facts of G4 (2026-09-29):

- **Where the port went**: a slice of the package downstream that draws the
  topology, not a package of its own; the rules there ask for a package only for
  a new third-party dependency. The ten files are the same code; only their
  first line and three comments changed (checked here with `diff` against
  `0990e7003`). An engine there chooses between the two by the vertex count, as
  the rule of 20 did, and its `__init__` registers it.
- **Same pictures**: the three topologies there (57, 7 and 3 vertices) drew
  byte for byte as before. The moved tests pass (109), and the C++ reference
  programs, built again, print the numbers that the tests assert.
- **Two faults on this side, found there and fixed here** (commit `35defbe51`):
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

- [x] R19: the port in `source/graph/cpp/` leaves this repository (Part G), and
      the MIT function in `source/domain/Domain.jl` gets its notice. The notice
      is done (commit `004075bff`): the MIT text of Julia, beside the two
      functions that come from `InteractiveUtils.subtypes`. The move is G3
      (`c7a156547`), which lands only in the order of Part G.
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

**Landed on `main` on 2026-09-30**, at the owner's word, so that the licence is
present before R23 is asked. `main` had 168 new commits; the branch rebased onto
them with no conflict. Three rules of the new `main` asked for three changes: a
`using`, not an `import`, for `Xorg_libX11_jll`, which `ProjecturedSdl` does not
extend; the layout guide names "the layouters of a C++ network simulator", not
the private product; and `SourceOffer` takes each argument after the version by
keyword. The lines that the branch adds fit in 90 characters, except four
`@testset` titles, which the macro keeps on one line. On the rebased branch:
builder 225, package release 45 and 490, meaning search 69, kernel layering 10,
graph 371, process 304, fsm 154 and SDL 785 pass. The downstream move landed
first, and its test after this. The commits that this plan cites are the ones on
`main`; the builds of Steps A4 and A5 ran on the same commits before the rebase,
and Step A4 builds again at the release commit (R7). On the same day, at the
owner's word, `main` (`4aa98d9c5`) and the site change went to GitHub together;
GitHub shows the licence as MPL-2.0, and projectured.org names it.

MPL-2.0 does not need a notice in each source file: its Exhibit A allows the
notice in "a LICENSE file in a relevant directory", and each package folder
has one.

## Part P: the LLM policy of General

The owner, on 2026-09-30: "Fix the llm policy, add statement to readme, add CI
too." §3.3 lists what the policy asks. Part P comes before Step B6, because the
maintainers of General read the repository when they review the first
registration.

### Step P1: the statement in the README

- [x] A section "How the code is made" in `README.md`, short, with the facts
      that the repository shows: the Lisp original, written by hand from 2013;
      the Julia port since 2026-05-26, most of it written by Claude Code under
      the direction of the author; the design and the decisions in
      `documentation/rule/` and `plan/`; the guards, the tests and CI; the
      kernel files that the author sealed after a review (`SEALING.md`: 52 of
      128 on 2026-09-30).
- [x] The owner checks each sentence about the author's own work. Only the
      owner knows how much of the code that is not sealed was read by hand, and
      the policy asks for that fact. The owner, on 2026-09-30: the seal of a
      file reads all its types and the interface of each public function, not
      the implementation of every function; outside the sealed files, only the
      parts of interest. The README says so. The policy asks that a person
      understands all the generated code, so the maintainers of General can
      ask about it.

### Step P2: what CI sees

- [x] Each of the 33 test packages in its own environment, in a fresh clone
      of this branch: `Pkg.instantiate()` with the network, then the suite of
      the package without it (`unshare -rn`, so no test reaches a local model
      server), with `SDL_VIDEODRIVER=offscreen`. The umbrella runs its 66
      integration parts, each in its own testset. Scripts and logs:
      `/var/tmp/release-plan/ci/`.

      **Result on `fefa3eed3` (2026-09-30).** The instantiate of a test package
      takes seconds when the depot holds its dependencies; `environment/all`
      took 5 minutes. Five test packages name siblings that their `[sources]`
      do not list (`ProjecturedTest`, `ProjecturedSdlTest`,
      `ProjecturedTulipTest`, `ProjecturedVideoTest`, `ProjecturedOdbcTest`), so
      they load through `environment/all`, as the testing guide says.

      | Suite | Result |
      | --- | --- |
      | 27 of the 32 per-package suites | pass (Kernel 2, Anthropic 1, OpenRouter 1, Yaml 2 `@test_broken`) |
      | SDL (offscreen driver), Tulip, Video, ODBC | pass: 785, 14, 41, 41 |
      | Substrate | 3 fail, 4 errors: the split-pane drag and the anchor point, known on `main` |
      | Conversation | 1 fail: the layering guard, known on `main` |
      | Umbrella, 66 parts in 70 minutes | 13 parts fail, below |

      The umbrella parts that fail: `test_arguments` (6) and `test_exports` (2),
      the guards; `test_position_navigations_complete` (449, all in the `text`
      examples); `test_mouse_clicks` (10: charts, sequence charts, the
      conversation); `test_typeins` (6), `test_text_navigation_invariants_all`
      (6), `test_assistant_mvp` (4), `test_projections` (3 and 2 errors, the
      split pane again), `test_position_navigations` (3), `test_catalog_coverage`
      (2), `test_catalog_typeins` (2), `test_application` (2 errors) and
      `test_json_content_clicks_clean_all` (1 error: it calls
      `test_json_content_clicks_clean`, which no file defines).

      Two failures came from the first setup and went away: a new network
      namespace has its loopback down (Anthropic), and `unshare -r` runs the
      test as root, which reads a folder of mode `000` (FileSystem). The run
      uses a second user namespace that maps the own user ID back, with the
      loopback up.

      **Every failure is on `main`.** The 11 umbrella parts that fail, run
      again on `main` (`c33824ca2`) in its own `environment/all`, with no
      namespace and the normal SDL driver, give the same counts, part by part.
      Plans that already hold some of them: `kernel-audit-fixes.md` (the anchor
      point, the split pane, `insert_elements!` and `delete_elements!`) and
      `export-block-rule.md` (`HelpModule`).

### Step P3: the workflow

- [x] `.github/workflows/CI.yml`, on a push to `main`, on a pull request, and
      by hand; not for a push that changes only `plan/` or Markdown.
  - A job for the static guards: each `test/suite/*.jl` alone, with no
    environment. They take seconds.
  - A job for each test package, in its own environment, on the latest release
    of Julia. The umbrella is split if one job takes too long (P2 gives the
    times).
  - Coverage: `--code-coverage=@.` for the code of this repository only,
    `julia-actions/julia-processcoverage`, and an upload to Codecov that does
    not fail the job while no token exists.

### Step P4: CI passes

- [ ] Each failure that P2 finds is fixed, or marked `@test_broken` with a
      `# @broken:` comment, as the testing guide says. The owner decides which,
      for each failure. **The owner chose on 2026-09-30:** fix the two faults of
      one line (the import of `test_json_content_clicks_clean`, and the
      `import` in `ConversationModule.jl`); mark each other failing test
      `@test_broken` with its reason and the plan that owns it; put
      `HelpModule` on the list of the export guard of modules that are not
      migrated (`export-block-rule.md` owns it); and fix the six argument
      violations in their files.

      Done: the two faults of one line (`a0581e9ee`, `3676cae25`). `HelpModule`
      is fixed, not listed: its block exported the five types that `@document`
      and `@projection` already export, and `export-block-rule.md` does not
      name it (`5a63c873f`). `visit` in `example/kernel/CallSite.jl` names its
      index and caller (`c4a82279b`).

      Open: the other five argument violations are the open questions of the
      kernel audit plan: POLICY-3 with L18-3 (`Tool`) and L22-1
      (`insert_elements!`, `delete_elements!`), and N-3 (`start_application!`,
      `FixedMeasure`), which asks the same question. The owner, on
      2026-09-30: they are settled and made in the kernel audit plan, not here.
      Until that lands, the guard job of CI fails on these five; the umbrella
      job does not run the guards.

      The markers (`561eb023f`, `5c3436089`), each with a `# @broken:` reason
      and only on the failing examples: the anchor point and the split pane
      (citing `kernel-audit-fixes.md`); the `text` example of the complete
      navigation (449 positions); three seeds of the position navigation; ten
      mouse-click examples ("no cursor found"); the collapsed navigator of
      `test_application`; the size of the assistant card; the Backspace at the
      start of a string and the two bare text atoms of the type-in; the three
      JSON examples of the text navigation invariants, with a new gate
      `:moved_right` / `:moved_left` in the round-trip driver. The catalog
      coverage lists its 22 document types with no atom in `_NO_ATOM`, the set
      that the file keeps for that, and marks only `isempty(gap)`, so a new
      type with no atom still fails. Checked part by part: 0 failures, 0
      errors, no unexpected pass.

      **The final check (2026-09-30, on the branch before the second rebase onto
      `main`, a fresh clone, as CI runs it):** all 33 test jobs pass. `test_integration()`: 1,059,125 pass,
      1,605 broken, 0 fail, 0 error, in 69 minutes after 5 minutes of
      instantiate. Substrate: 86,907 pass, 8 broken. Of the five guards, only
      the argument guard fails, on the five violations above.

      **After the second rebase onto `main`** (76 new commits, among them the
      DataFrames packages): the new test package got a job of its own (34 jobs,
      `7bbeca00d`), and the check ran again from a fresh clone. 33 of 34 jobs
      pass. The umbrella had 3 new failures, from the new commits of `main`:
      `DataFrameView` has a printer and no atom, and the mouse clicks of
      `chart` and `sequencechart_pair` find no cursor, as the ten marked
      before. They are marked in the same lists (`a5f4c9936`); checked: 0
      failures, 0 errors, no unexpected pass. The two mouse clicks are
      regressions of that day, which the session that made them can look at. The umbrella now exports `test_documents`
      and `test_projections`, which the testing guide calls (`dbe31d96b`).

### Step P5: the owner's steps

- [ ] Sign in to Codecov with GitHub, turn on the repository, and add the
      token as the secret `CODECOV_TOKEN`.
- [ ] Land and push; read the first run.

### Open

- The policy asks for the documentation to be built in CI "where appropriate".
  The documentation is Markdown that GitHub shows as it is, so there is nothing
  to build now.
- The policy asks for a short README. `README.md` has 145 lines; the owner
  judges whether that is short.

## Part R: the answer of the maintainers of General (2026-09-30)

The owner asked in `#pkg-registration`. A maintainer read the repository and
answered in two messages. This part holds what they ask for, and the decisions
that follow. It comes before Step B6; Step B6 waits for it.

### What they ask for

- **CI on the repository that the packages are registered from**, with GitHub
  Actions, running the tests of every package, with tracked coverage. "A hard
  requirement". The CI of Part P runs on the development repository, so it is
  not that CI; the release repository needs its own.
- **Generated copies are fine** as packages in the subdirectories of one
  published repository, "but that repo has to stand on its own". This answers
  R23: one release repository.
- **Each registered package has** a working `test/runtests.jl`, because
  `Pkg.test` and PkgEval run each package alone and do not find the
  `Projectured*Test` packages; a short README; a copy of the licence; and
  `[compat]` for Julia and for every dependency, the siblings too. (They
  counted 59 of 70 packages with no `[compat]` in the development repository;
  the release copy writes it.)
- **Not registered:** the `*Test` and `*Example` packages and
  `ProjecturedBench`. The release already leaves them out.
- **Names:** similar pairs such as `ProjecturedSdl` and `ProjecturedSql` are no
  problem; they override the name rule routinely. This answers R22. But they
  want acronyms in capitals: `ProjecturedJSON`, `ProjecturedSQL`,
  `ProjecturedSDL`, `ProjecturedXML`, `ProjecturedYAML`, `ProjecturedPDF`,
  `ProjecturedMCP`, `ProjecturedODBC`, and so on. The written guidelines
  (`NAMING_GUIDELINES.md`) do not say so in words: rule 9 asks for upper camel
  case, and rule 1 asks to avoid acronyms. The capitals are the convention of
  the ecosystem (`JSON.jl`, `YAML.jl`, `ODBC.jl`). Rule 2, "avoid using `Julia`
  in your package name", can also touch `ProjecturedJulia`.
- **Fewer packages.** Packages such as `ProjecturedFocus`,
  `ProjecturedDragging`, `ProjecturedTooltip` and `ProjecturedGestureLog` look
  like internals that no one outside the project depends on, and parallel
  compilation is no reason for an entry in the registry. Fold them into the
  kernel or the umbrella, and register only what a user adds: the domains, the
  backends, and a few core packages.
- **Documentation:** one Documenter site for the whole project is fine. It must
  be written for people, which means much manual work.
- **Order:** when all of this is in place and CI passes, register from the
  bottom up, one dependency level at a time.
- **A local registry first.** The second message: they are "not super thrilled"
  by the registration of many packages at once, and second the advice to grow
  the project in a local registry until it is mature. It is no rule. Each
  package has its own cost of upkeep, and more monolithic frameworks tend to
  work better; the wait for hundreds of CI runs is a cost too.
- **Code made with an LLM.** "I've reviewed every line of code" is no longer
  the measure they look for. They look for "I've iterated over this over a
  long period of time and put considerable thought and effort into guiding the
  design", together with the highest standards of best practice of the Julia
  ecosystem: testing, documentation and so on.

### Open decisions

| # | Question | Recommendation (mine, not decided) |
| --- | --- | --- |
| R27 | Register in a local registry first, or go on toward General now? | The local registry first, as the maintainers advise. `LocalRegistry.jl` and the release copy do it today (Step B4 proved it), with no review and no wait. General later, when the rest of this part is done. |
| R28 | Which packages does a user add, and where are the internals folded: in the development repository, or only in the release copy? | Decide the set first: the domains, the backends, the assistant adapters, the umbrella, and a small core. Fold in the development repository, not only in the copy, so that the packages, their tests and their documentation are the same in both. This is a design of its own, with its own plan. |
| R29 | Acronyms in capitals, in the development repository too? | Yes, and before the first registration anywhere, the local registry too: a new name is a new package for each user. `julia-rename.jl` does the code; the folders, the documents and the downstream repositories follow. |
| R30 | How does each package get its `test/runtests.jl`? | The release copy writes it from the suite of the package's test package, and copies the test helpers and examples that the suite needs into `test/`, because a test may use only registered packages. |
| R31 | The CI of the release repository. | The release copy writes a workflow that runs `Pkg.test` for each package with coverage. The CI of Part P stays as the check of the development repository. |
| R32 | The Documenter site: where it lives, and what it holds. | Open. The guides in `documentation/` are the start; the API pages come from the docstrings. |
| R33 | Does the README statement change, after the second message? | Say what is true in their terms: the design came from long iteration and the owner's guidance, and the tests, CI and documentation follow the practice of the ecosystem. The owner writes it. |

**The owner's answers, 2026-09-30:** R27 yes, the local registry first. R29
yes in principle, but deferred (the owner, later the same day): the rename
comes only if the registration needs it. R28 yes, fold in the development repository; the design is its own
plan, [fold-the-internal-packages.md](fold-the-internal-packages.md). R33 yes:
the statement is in the owner's words, and it names the plans behind the work
in round numbers (more than 400 plans; a typical plan revised several times,
the larger ones dozens of times; about half of the more than 4,000 commits
change a plan). The owner reviewed the draft: the Lisp version is the owner's alone, and the
seals go beyond the kernel in time (only kernel files are sealed today).

### What changes in the other parts

- R22 and R23 have their answers above. R23: one release repository,
  `projectured/Projectured.jl` (the owner, 2026-10-01: "I choose the single
  projectured/Projectured.jl repository"). The owner created it the same day,
  private and empty.
- Step B6 and the install lines of Step B5 wait for R27, R28 and R29.
- **R28 and R29 are done (2026-10-01).** The fold put the internal packages
  into `ProjecturedPlatform` ([fold-the-internal-packages.md](../done/fold-the-internal-packages.md)),
  and the twelve packages with an acronym have it in capitals
  (`ProjecturedJSON`, `ProjecturedSQL`, `ProjecturedSDL`, …; the owner: "Let's
  do the package renames now"; [acronyms-in-package-names.md](../done/acronyms-in-package-names.md)).
  Steps B5 and B6 now wait for R27 alone.
- Part P stays: it is the CI of the development repository, and the release
  tests of R30 come from its suites.

### The work toward the local registry (R27)

- [x] The plan names the one release repository: R9, R23 and Step B6.
- [x] The generator writes one repository with a folder for each package, the
      form that Step B4 tested. Done on 2026-10-01:
      [one-release-repository.md](../done/one-release-repository.md).
- [x] R30: each registered package has its `test/runtests.jl`. The plan:
      [release-tests-for-each-package.md](../done/release-tests-for-each-package.md).
      Done on 2026-10-01: the release copy gives each package its test folder,
      and all 32 pass their tests as installed packages.
- [x] R31: the release repository has its CI workflow. Done on 2026-10-02:
      [release-repository-ci.md](../done/release-repository-ci.md). One job for
      each package on Julia 1.11; a job develops the folders that its test needs.
- [x] Each registered package has a short README. Done on 2026-10-02:
      [release-package-readmes.md](../done/release-package-readmes.md).
- [x] The full test of Step B4 again, with a local registry on this machine.
      Done on 2026-10-02 with `/var/tmp/b4r/run.sh`, from the branch of the
      READMEs (`5fd84f1e1`), in empty depots:
      - The 32 packages generated and registered in a local registry named
        `ProjecturedRegistry`, all `0.1.0`.
      - `add Projectured ProjecturedJSON ProjecturedSDL`: 134 packages, 5 of
        ours; `using Projectured, ProjecturedSDL` in 0.9 s after the compile,
        and the umbrella loads `ProjecturedJSON`; the fonts come from the
        installed `ProjecturedPlatform`; a real window drew 40 frames.
      - `Pkg.test("ProjecturedJSON")` on the installed package: 225 of 225. It
        installs the released siblings that its support packages need, so it
        needs the registries; offline it can not find `ProjecturedPDF`.
      - `add Projectured ProjecturedJSON ProjecturedWeb ProjecturedMCP`: the web
        client, a font and the guide list over HTTP and MCP, from the installed
        packages.
      - A second release, one comment in the JSON domain: only
        `ProjecturedJSON` became `0.1.1`, and `Pkg.update()` downloaded only it.
      - Julia 1.11.9: `add Projectured ProjecturedJSON`, and `JsonString`
        works.
- [x] The owner makes the repository of the local registry,
      `projectured/ProjecturedRegistry` (R10). Done on 2026-10-01, private and
      empty. Its content, `Registry.toml` with the uuid of the registry, comes
      from `LocalRegistry.create_registry` in the test of the item above.
- [x] The release under the design of AutoIntegrations, private, on
      2026-10-03: [auto-integrations.md](../done/auto-integrations.md). The
      registry holds AutoIntegrations from its own repository and 89 packages:
      34 at the root of `Projectured.jl`, 32 test packages in `test/` and 23
      example packages in `example/`. Each package with tests has a workflow
      and a badge of its own, which runs when a folder that its test develops
      changes.
- [x] **Until the first announcement, each release overwrites both
      repositories as a fresh 0.1.0** (the owner, 2026-10-03: "until the first
      announcement of the registry we can always nuke the existing versions and
      overwrite it, there's no reason to keep the old versions, nobody uses them
      yet"). A new registry keeps the name, the uuid, the URL and the README of
      `ProjecturedRegistry`, and every entry of a package of another repository
      (AutoIntegrations, AutoPrecompile) as it is registered; then the release
      registers in its order, and both repositories are pushed with `--force`.
      An overwrite on 2026-10-03 dropped AutoPrecompile, which another session
      had registered, because it kept only AutoIntegrations; the entry came back
      unchanged from the replaced registry commit.
      After the force-push, each workflow of `Projectured.jl` starts by hand
      (`gh workflow run <Package>.yml --ref main`): a fresh history is one root
      commit, which starts no workflow that has a path filter.
      The owner, 2026-10-06: the release that passes the tests is the 0.1.0
      release, and it is not overwritten again. A later change is a new
      version, so `/var/tmp/release-overwrite.sh` is not used for it.
- [x] Before the announcement, the full suites: each test package in its own
      environment, `test_integration()`, and each failure compared with `main`.
      The owner, 2026-10-04: they wait until the owner lands the other work of
      the first release. The owner, 2026-10-06: the tests of the release decide
      it. The 32 workflows of the release run each test package in its own
      environment from the registry, and the umbrella runs `test_integration()`.
      Before the last overwrite, the umbrella of `main` failed one test:
      `McpLog` had a printer and no catalog atom, and `e09801237` lists it in
      `_NO_ATOM` with the other logs.
- [x] **The 0.1.0 release**, 2026-10-06: `Projectured.jl` `5b8284f8`, "ProjecturEd
      0.1.0, from projectured-julia e09801237", 89 packages, and
      `ProjecturedRegistry` `077f625`, which keeps AutoIntegration and
      AutoPrecompile as they are registered. The 32 workflows pass. The ways of
      the front page pass as a new user types them, on Julia 1.12.7 and 1.13.1.
- [x] The owner pushes the release copy and the registry, and makes both
      repositories public. Done by 2026-10-05: Projectured.jl, ProjecturedRegistry,
      AutoIntegration.jl and AutoPrecompile.jl are public.
- [x] The ways of the front page, as a new user types them, 2026-10-05: a fresh
      `HOME` with no git credentials, an empty depot, a new environment for each
      way, and the window offscreen, on Julia 1.12.7 and 1.13.0. Each way adds,
      loads and shows the data frame: `using Projectured` with the integrations,
      each package by name, `ProjecturedIntegrations`, and AutoPrecompile, which
      starts its build in the background. The setting `"manual"` keeps
      ProjecturedDataFrames out of the session. `pkg> add AutoPrecompile` failed
      while its repository was private, and it works since the owner made it
      public. The front page then shows the way of `Projectured` first, and its
      references are links.
- [x] The build guide names `ProjecturedRegistry` where it says `<registry>`.
      Done on 2026-10-02 with the READMEs.

**R34, open: the move from `ProjecturedRegistry` to General.** AutoMerge
accepts only 0.0.1, 0.1.0 or X.0.0 (1.0.0, 2.0.0, …) as the first version of a
new package, and each later version must not skip one (RegistryCI,
`meets_standard_initial_version_number` and `meets_sequential_version_number`,
read on 2026-10-01). Each release in `ProjecturedRegistry` gives a changed
package the next patch version (0.1.1, 0.1.2, …). If a person has both
registries, the same version of a package must have the same tree in both. So
the first version in General is 1.0.0 (or the next X.0.0), or General takes the
versions of `ProjecturedRegistry` one by one from 0.1.0, or a maintainer merges
by hand. The decision belongs to the move, not to now.

## Step C: close

- [x] Update documentation-rewrite.md Step 11 (R2). Done on 2026-09-29: its
      D22 item points here.
- [ ] Move this plan to `plan/done/`.
