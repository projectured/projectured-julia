# Release the binary and the packages

Status: pending, 2026-09-29. Nothing is built, generated, tagged or published
yet.

Two routes give ProjecturEd to other users. Each route serves a different
user:

- **Part A, the binary archive**, is for a user who runs the editor. That user
  needs no Julia.
- **Part B, the packages in a registry of our own**, is for a Julia programmer
  who uses the packages in a program.

Neither route changes the structure of the repository.

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

- **Most fonts have no licence text.** `asset/font/` holds licence text for
  Lucide (ISC) and Noto Emoji (OFL) only. DejaVu, Liberation, Inconsolata and
  Ubuntu have their own licences, and the OFL needs its text beside the font.
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

- **General is probably closed to these packages.** AutoMerge in General checks
  for an OSI-approved licence, and `LICENCE-PD` is not one. This is a belief,
  not a checked fact. It is also all or nothing: a package in General can not
  depend on a package outside General.
- **A user must name General when adding our registry.** Pkg adds General by
  itself only when no registry is installed yet. A user who adds our registry
  first can have no General, and then `SDL2_jll` does not resolve.
- **Discovery is weaker than in General.** `pkg> add ProjecturedJson` fails
  until the user adds our registry, and search in JuliaHub does not show the
  packages. The non-commercial licence and the minutes of the first compile are
  larger filters than the one extra line.
- **A registry entry names a tree by its hash.** Pkg must find that tree in the
  release repository forever. So the history of the release repository is never
  rewritten.
- **The generated copy and the repository can drift.** A new path that leaves a
  slice works in the checkout and fails in the copy. The generator must find
  such a path and stop (B2).
- **`projectured/projectured` is a redirect now (R9).** The Lisp original was
  renamed to `projectured/projectured-lisp`, which is archived, and GitHub
  sends the old name there (checked on 2026-09-29: `301` to
  `projectured-lisp`). A new repository under the old name ends the redirect.
  Then these links reach the Julia release copy instead of the Lisp original:
  - **Quicklisp.** `quicklisp-projects/projects/projectured/source.txt` says
    `branched-git https://github.com/projectured/projectured.git quicklisp`.
    The release copy has no `quicklisp` branch, so the Quicklisp build of the
    Lisp original fails and the project can leave the Quicklisp dist.
  - **This repository.** `CLAUDE.md` line 3 names
    `github.com/projectured/projectured` as the original, and
    `documentation/guide/new-domain-guide.md` uses it in three examples.
  - **The Lisp README.** Its clone command and its wiki links use the old
    name. The repository is archived, so a change there needs the owner to
    unarchive it first.

## 4. Decisions

### 4.1 Open

| # | Question | Recommendation (mine, not decided) |
| --- | --- | --- |
None.

### 4.2 Decided

The owner decided these on 2026-09-29.

| # | Question | Decision |
| --- | --- | --- |
| R0 | Which route? | The binary archive first. No change to the repository structure. |
| R1 | Is the deferral of 2026-09-20 lifted? | Yes. Part A goes to the release, Step A7 included. The owner still approves Step A7 before it runs. |
| R3 | What to do about x264, x265 and fdk-aac? | Wait for the licence check of Step A2. Nothing is chosen until it reports. If the answer is "remove them", look for a way that changes no structure, for example a JLL preference that points `SDL2_jll` at a build without sound plugins. |
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
| R15 | Rename `LICENCE-PD`? | No. It stays as it is. |
| R9 | Where does the release copy live? | In `projectured/projectured`. §3.3 says what this name costs, and Step B6 handles it. |
| R10 | The name and place of the registry? | `projectured/ProjecturedRegistry`, made with `LocalRegistry.jl`. |
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

- [ ] `test_builder()` in `environment/all`. It compiles nothing.
- [ ] `bin/build_projectured --no-compile`. It writes the package of the binary
      in about a second.
- [ ] `bin/projectured --help`, and one start of `bin/projectured` with two
      files. This is the program that the build compiles.
- [ ] The grep of §2.1 for private names in `documentation/` and `asset/web/`
      again, on the release commit.

### Step A2: the licence check (gate)

- [ ] The license-compliance-officer reads `build/app/projectured/Manifest.toml`
      and `asset/font/`, and lists for each item: its licence, whether the
      archive may carry it, and which text must go with it. It also says which
      texts each package folder of Part B must carry.
- [ ] The owner decides R3 from that list.
- [ ] Add the licence texts that are missing to `asset/font/`. New files only;
      no folder moves.
- [ ] If the archive must name more licences, extend `PROJECTURED_LICENCES` or
      the `README` text in `source/builder/`, with a test in
      `test/builder/BuilderTest.jl`.

### Step A3: the faults the owner wants fixed (R6)

- [ ] `SIGTERM` stops the application with no backtrace.
- [ ] The window has a `WM_NAME` (and `_NET_WM_NAME`) of `ProjecturEd`.
- [ ] One commit per fault, each with the narrowest test.

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

- [ ] The relocation test and the program check pass.
- [ ] Record in this plan: the wall time, the peak memory, the bundle size, the
      archive size and the SHA-256 digest that the build prints.
- [ ] Write the digest to `<archive>.sha256`, beside the archive.

### Step A5: test the archive as a user gets it

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

- [ ] Copy `ProjecturedKernel` to a release layout: `Project.toml` without
      `[sources]`, `src/ProjecturedKernel.jl` with the include prefix
      `../source/`, and `source/kernel/`. Make it a git repository.
- [ ] Make a registry with `LocalRegistry.create_registry`, and `register` the
      package in it.
- [ ] In an empty depot: add General and the local registry, `add
      ProjecturedKernel`, and `using ProjecturedKernel`.
- [ ] Do the same for `ProjecturedJson`, which brings 16 siblings. This proves
      that the siblings resolve through the registry.
- [ ] Record what worked and what did not in this plan, before Step B2.

### Step B2: the generator

A new function in the builder, for example
`build_package_release(context; packages, version, output)`. The name follows
[naming-rules.md](../../documentation/rule/naming-rules.md); read it before
the name is final. For each package of the registry set (R16), the function:

- [ ] copies `Project.toml` and `src/`, and the slice of `source/` that the
      entry file includes;
- [ ] changes the prefix `../../../source/` to `../source/` in the entry file,
      and nothing else in the code;
- [ ] copies the folders of the table in §2.3 to their places;
- [ ] copies `LICENCE-PD`, `LICENCE-COMMERCIAL`, and the texts that Step A2
      names, into the package folder;
- [ ] removes `[sources]`, and sets `version` and `[compat]` by the rules of
      R11 and by R13;
- [ ] keeps the last registered `Project.toml` of a package whose content did
      not change, and registers no new version of it (R11, rules 1 and 2);
- [ ] scans the copy for an `include`, an `@__DIR__` path or a `joinpath` with
      `..` that leaves the package folder, and stops with the file and the line
      when it finds one.

- [ ] A test in `test/builder/BuilderTest.jl` that compiles nothing: generate
      two small packages, check the layout, the rewritten include, the
      `[compat]`, the licence files, and that the scan stops on a path that
      leaves a package. Then change one of the two and generate again: only
      that one gets a new version, and the other keeps its tree.

### Step B3: the meaning folder of an installed package

- [ ] Check [SEALING.md](../../SEALING.md) for `tool/MeaningSearch.jl` again
      before the edit.
- [ ] In `_get_default_meaning_folder`, use the cache folder of the user also
      when the checkout folder is not writable. A Julia session in a checkout
      keeps `build/meaning/`.
- [ ] The narrowest test of the meaning search.

### Step B4: the full test of the release copy

Warning: give each Julia process a memory cap of 8 GB and a timeout, and read
`free -g` first. The first `using` of the application compiles for minutes.

- [ ] Generate the 65 packages of the registry set under `/var/tmp`, commit them to a local
      git repository, and register them in a local registry.
- [ ] In an empty depot: add General and the local registry.
- [ ] `add ProjecturedJson ProjecturedSdl`, then `using`, and open one window
      with a JSON document. The fonts must come from
      `ProjecturedStyle/asset/font`.
- [ ] In a new environment, `add Projectured ProjecturedWeb ProjecturedMcp`,
      and open a document with `run_window_editor(…; backend = WebBackend(),
      mcp = true)`. The web client must come from `ProjecturedWeb/asset/web`.
      The MCP tool `read_resource` with `resource://guides` must list the
      guides from `ProjecturedKernel/documentation`.
- [ ] A second release: change one file in one slice, generate again, and
      register. Only that package gets a new version. `pkg> up` in the test
      depot takes it and downloads nothing else.
- [ ] Repeat the `add` and the `using` of `ProjecturedJson` on Julia 1.11 and
      1.12 through `juliaup`. The oldest version that passes sets the Julia
      bound of R13.

### Step B5: the guides name the registry

- [ ] `README.md` and [setup-guide.md](../../documentation/guide/setup-guide.md):
      the install line, with General named:

      ```sh
      julia -e 'using Pkg; Pkg.Registry.add("General"); Pkg.Registry.add(url="https://github.com/projectured/ProjecturedRegistry"); Pkg.add(["ProjecturedJson", "ProjecturedSdl"])'
      ```

- [ ] [own-project-guide.md](../../documentation/guide/own-project-guide.md):
      the registry first; the clone with `[sources]` stays for a contributor.
      The table "Which package to load" must not send a registry user to
      `ProjecturedExample` or `run_value_viewer`, because the registry does
      not hold them (R16). For the application, it names the binary.
- [ ] The guides say: update all Projectured packages together (R11).
- [ ] [build-guide.md](../../documentation/guide/build-guide.md): a section on
      how to make a package release: generate, commit, register, push.

### Step B6: publish the packages (the owner only)

The commands, to run after the owner approves. The agent states them and
stops.

Before `projectured/projectured` exists, move the links that use the old name
(§3.3). The new repository ends the redirect, and every link that is not moved
then reaches the release copy.

- [ ] Quicklisp: a pull request to `quicklisp/quicklisp-projects` that changes
      `projects/projectured/source.txt` to
      `https://github.com/projectured/projectured-lisp.git`. The owner sends it,
      or decides that the Lisp original can leave Quicklisp.
- [ ] This repository: `CLAUDE.md` line 3 names
      `github.com/projectured/projectured-lisp` for the original, and the three
      examples in `new-domain-guide.md` get a URL that stays right.
- [ ] The Lisp README: the owner decides whether to unarchive it and change
      its links.
- [ ] Make the two GitHub repositories of R9 and R10.
- [ ] Generate the release copy for `v0.1.0`, commit it to the release
      repository with the tag `v0.1.0`, and push.
- [ ] `register` the 65 packages of the registry set in `ProjecturedRegistry`, with the URL of
      the release repository, and push the registry.
- [ ] In an empty depot, run the install line of Step B5 against GitHub, and
      `using ProjecturedJson, ProjecturedSdl`.

## Step C: close

- [x] Update documentation-rewrite.md Step 11 (R2). Done on 2026-09-29: its
      D22 item points here.
- [ ] Move this plan to `plan/done/`.
