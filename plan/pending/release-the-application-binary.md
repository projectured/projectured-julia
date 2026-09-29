# Release the application binary

Status: pending, 2026-09-29. Nothing is built, tagged or published yet.

## 1. The request

The owner, 2026-09-29: other users must be able to install ProjecturEd. Of the
two routes (a binary archive, or `pkg> add` from a registry), the owner chose
the binary archive, with one constraint:

> I would like to do route 1, but don't want to change the repository structure

So the packages stay where they are, and `source/` stays where it is. The
archive holds a compiled bundle, so the layout of the checkout does not matter
to the user who unpacks it.

The route through a registry is not in this plan. It needs each package folder
to be complete, the run-time files inside the packages, `[compat]` bounds, and a
registry of our own. That is a structural change.

## 2. What exists

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

## 3. Facts that the release must handle

- **Libraries with other licences come in through SDL.** `ProjecturedSdl` →
  `SDL2_jll` → `alsa_plugins_jll` → `FFMPEG_jll` brings `x264_jll`,
  `x265_jll`, `libfdk_aac_jll`, `LAME_jll`, `Opus_jll` and `libvorbis_jll`
  into `build/app/projectured/Manifest.toml`. x264 and x265 are GPL-2.0. The
  licence of fdk-aac is not compatible with the GPL. The application plays no
  sound. An archive that holds all three can be an archive that nobody can
  legally give to others. This is a gate for the release.
- **Most fonts have no licence text.** `asset/font/` holds licence text for
  Lucide (ISC) and Noto Emoji (OFL) only. DejaVu, Liberation, Inconsolata and
  Ubuntu have their own licences, and the OFL needs its text beside the font.
- **The archive carries only `LICENCE-PD` and `LICENCE-COMMERCIAL`**
  (`PROJECTURED_LICENCES`). The licences of Julia and of each JLL artifact are
  not named in the `README`.
- **Three faults from the first build are still open** (application-and-build.md
  Step 4): `--build-info` shows the time of the last write of the generated
  module, the window has no `WM_NAME`, and `SIGTERM` prints a backtrace with
  exit code 15.
- **Linux x86-64 only.** The relocation test uses `bwrap`, which is Linux-only.
  macOS and Windows need a build on that system, and that is not in this plan.

## 4. Decisions

### 4.1 Open

| # | Question | Recommendation (mine, not decided) |
| --- | --- | --- |
| R2 | Which plan owns the release: this one, or documentation-rewrite.md Step 11? | This plan. Step 11 then says "see release-the-application-binary.md", so only one place has the item. |
| R4 | Version and tag: `0.1.0` and `v0.1.0`? | Yes. It is the version the code already holds. |
| R6 | Fix the three open faults of §3 before the release, or ship with them? | Fix the `SIGTERM` backtrace and `WM_NAME`, because a user sees both. The `--build-info` time can wait. |

### 4.2 Decided

The owner decided these on 2026-09-29.

| # | Question | Decision |
| --- | --- | --- |
| R0 | Which route? | The binary archive. No change to the repository structure. |
| R1 | Is the deferral of 2026-09-20 lifted? | Yes. This plan goes to the release, Step 7 included. The owner still approves Step 7 before it runs. |
| R3 | What to do about x264, x265 and fdk-aac? | Wait for the licence check of Step 2. Nothing is chosen until it reports. If the answer is "remove them", look for a way that changes no structure, for example a JLL preference that points `SDL2_jll` at a build without sound plugins. |
| R5 | Is the repository public? | Yes: <https://github.com/projectured/projectured-julia>. A GitHub release there reaches every user. |
| R7 | Build from the main checkout, or from a worktree? | A worktree at the release commit. Then the archive matches the tag, and no uncommitted change of another session goes in. The cost is one full compile of the cache for that worktree. |

## 5. Steps

Every step that changes a tracked file runs in a worktree, with a commit per
step. Nothing lands on `main` and nothing is pushed without the owner's word.
The build of Step 4 runs in a worktree at the release commit (R7), after the
commits of Steps 2 and 3 are on `main`.

### Step 1: check that the builder still works, with no compile

- [ ] `test_builder()` in `environment/all`. It compiles nothing.
- [ ] `bin/build_projectured --no-compile`. It writes the package of the binary
      in about a second.
- [ ] `bin/projectured --help`, and one start of `bin/projectured` with two
      files. This is the program that the build compiles.
- [ ] The grep of §2 for private names in `documentation/` and `asset/web/`
      again, on the release commit.

### Step 2: the licence check of the bundle (gate)

- [ ] The license-compliance-officer reads `build/app/projectured/Manifest.toml`
      and `asset/font/`, and lists for each item: its licence, whether the
      archive may carry it, and which text must go with it.
- [ ] The owner decides R3 from that list.
- [ ] Add the licence texts that are missing to `asset/font/`. New files only;
      no folder moves.
- [ ] If the archive must name more licences, extend `PROJECTURED_LICENCES` or
      the `README` text in `source/builder/`, with a test in
      `test/builder/BuilderTest.jl`.

### Step 3: the faults the owner wants fixed (R6)

- [ ] One commit per fault, each with the narrowest test.

### Step 4: the distribution build

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

### Step 5: test the archive as a user gets it

- [ ] Unpack the archive under `/var/tmp`, far from the checkout. Start it with
      a window on this machine (`DISPLAY=:0`), and open a JSON, a Markdown and a
      Julia file. The owner looks at the window before Step 7.
- [ ] In `podman` containers of two or three distributions (for example
      Debian 12, Ubuntu 22.04 and Fedora), unpack the archive and run
      `--build-info`. Then start `--backend=web --assistant=none` and read the
      web client with `curl`. A library that fails to load shows a gap in the
      requirements of the `README`.
- [ ] If a container needs a system package, add it to
      `PROJECTURED_REQUIREMENTS` and build again.

### Step 6: the guides name the download

- [ ] [setup-guide.md](../../documentation/guide/setup-guide.md): a section
      "Download the application" before "Start the application": the link to
      the release, the unpack command, `bin/projectured`, and the requirements.
- [ ] `README.md`: the quick start names the download first.
- [ ] The web site (`projectured.github.io`, another repository) gets a link
      only if the owner asks for it.

### Step 7: publish (the owner only)

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
- [ ] After the release: download the asset from GitHub and run Step 5 once on
      that copy.

### Step 8: close

- [ ] Update documentation-rewrite.md Step 11 (R2).
- [ ] Move this plan to `plan/done/`.
