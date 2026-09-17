# The application and its build

**Status (2026-09-17): IN PROGRESS.** Step 0 is done, Step 1 is done except
for the two command palette entries, and Step 2 is done. The work is on the branch
`application-and-build`, in the worktree `workspace/projectured-julia-application`.
This plan was split from [documentation-rewrite.md](documentation-rewrite.md) on
2026-09-17. The owner decided every question of §2; none is open.

**Goal:** ProjecturEd is an application. One command and one binary open any
number of files, in every supported format, in a window with the AI assistant.
One general builder, `ProjecturedBuilder`, makes the binaries of
projectured-julia and of omnet-julia.

**Repositories:** projectured-julia (the application, the builder, the build
environment) and omnet-julia (Step 6 only: it calls the shared builder). The
plan changes no sealed file.

**Relation to other plans:** `documentation-rewrite.md` needs Steps 1 to 5 of
this plan. Its README quick start names the application command, and its
Step 11 attaches the binary to a GitHub release. The `--assistant` and
`--model` options of this plan use the backends of Step 1 of
`documentation-rewrite.md` (decisions D5 and D6 there).

**Process:** work in a sibling git worktree in `workspace/`. Commit each step
with explicit paths. Mark each part done here, and write down each decision
that the work makes.

## 1. The request

> for the question, yes, we already have a build system, but it should be
> perhaps generalize a bit. take a look at how omnet-julia builds binaries and
> copy what can be applied from there

The answers to the questions of the first design, 2026-09-17:

> for 2, we can have both using command line arguments to select
> for 3, move and call the environment build not tool, makes more sense
> for 4, should
>
> put the build thing into a separate plan from the documentation plan

## 2. Decisions

The numbers are the same as in `documentation-rewrite.md`.

### 2.1 Decided

| # | Question | Decision |
| --- | --- | --- |
| D18 | An application entry point before the posts | Yes. One command and one binary open any number of files, in every supported format, in one window with the assistant. |
| D20 | Which window is the application: the pane program (`source/pane/`) or the `Workbench` (`source/workbench/`)? | Both. A command-line option selects the window. |
| D21 | Copy the generic half of the omnet builder into `ProjecturedBuilder`, or move it? | Move it. `ProjecturedBuilder` holds the generic builder. omnet-julia keeps its program functions and its front end, and it calls the shared builder. |
| D22 | A binary with the posts | Yes. A Linux x86-64 archive in a GitHub release, after its relocation test passes. The owner approves the release. |
| D23 | The name of the build environment | `environment/build`, not `environment/tool`. |
| D24 | Which window opens when the command line names none? | The pane program. |
| D25 | Does omnet-julia rename its `environment/tool` to `environment/build` too? | Yes, in Step 6, so that both repositories use one name. |

The answers of 2026-09-17 to the two open questions:

> for 1, the pane program
> for 2, yes

No question is open.

## 3. What exists

The facts come from a read-only comparison of the two builds on 2026-09-17. The
full report is section J of
[documentation-rewrite-survey.md](documentation-rewrite-survey.md).

**projectured-julia**

| Fact | Where |
| --- | --- |
| A build starts only from a Julia session: `build_executable(make_workbench_app(SdlBackend))`. There is no shell front end. | [Builder.jl](../../source/builder/Builder.jl), [executable/README.md](../../documentation/package/executable/README.md) |
| A target is a `BuildSpec`. Two exist: `default_json_app` and `make_workbench_app`. | `Builder.jl:268`, `:277` |
| Every build compiles the one fixed package `ProjecturedExecutable`. Its `[deps]` always hold SDL, Anthropic, Ollama and PackageCompiler. `LOCAL_CORE_PACKAGES` names the same packages. | `Builder.jl:39`, [Project.toml](../../package/ProjecturedExecutable/Project.toml) |
| The build environment is the environment of `ProjecturedExecutable` itself: `_compile!` activates it and adds PackageCompiler to it. | `Builder.jl:215-249` |
| `_compile!` passes three keywords to `create_app`. There is no `incremental`, no font copy, no size or start-time report, and no test of the builder. | `Builder.jl:240` |
| The runtime already looks for fonts in `share/projectured/font` beside the binary. The build does not copy them there. | [TrueType.jl:101](../../source/style/TrueType.jl#L101) |
| One compiled `julia_main` serves every build. Build-time constants in the generated `AppConfig.jl` select its behaviour. It reads one file argument, `--backend`, `--help` and `--version`, and it returns 0 or 1. | [Executable.jl](../../source/executable/Executable.jl) `:53-183` |
| `run_file_editor` knows 4 formats (`EDITOR_DOMAINS`) and cannot save without the workbench. | [FileEditor.jl:56](../../example/projectured/FileEditor.jl#L56), `:166` |
| `read_document_file` and `write_document_file` know the 8 natural formats (json, xml, yaml, md, rst, math, jl, sql), `.pdoc` and `.pred`. | [DocumentFile.jl](../../source/fileformat/DocumentFile.jl) |
| A `WorkbenchEditor` tab saves with `Ctrl+S` and reloads with `Ctrl+O`. There is no "Save as", and no gesture opens a file. | [WorkbenchFile.jl](../../source/workbench/WorkbenchFile.jl) |
| `open_pane!(editor, document)` puts any document in a new tab of the pane program. | [PaneProgram.jl:266](../../source/pane/PaneProgram.jl#L266) |

**omnet-julia**

| Fact | Where |
| --- | --- |
| A build starts from a shell: `julia --project=environment/tool source/tool/build_binary.jl <what>`. The front end only dispatches; one option table gives the `--help` text and the refusal of an unknown option. | `source/tool/build_binary.jl` |
| One Julia function for each binary decides the name, the packages, the `julia_main` expression, the workload, the command-line usage, the fonts and the assets. | `source/build/Program.jl` |
| A generic `build_executable` writes a fresh app package with only the packages that the binary needs, and compiles it with `create_app`. | `source/build/AppPackage.jl`, `Executable.jl` |
| Each generated binary answers `--build-info`, `--help`, `--version` and `--log-level`, and refuses an option that its usage does not name. | `AppPackage.jl:122-199`, `Usage.jl` |
| `incremental = true` is the default. A measurement: 390 s and 741 MB, against 741 s and 736 MB for a full build. Only a distribution build is full. | `Executable.jl:293-309` |
| `bundle_fonts!` copies the fonts to `share/projectured/font`. `bundle_assets!` copies other files. | `Executable.jl:719-774` |
| `print_build_report!` prints the bundle size and the time that the binary takes to answer `--build-info`. | `Executable.jl:776-791` |
| `build_distribution` copies the bundle to `/var/tmp`, starts it with an empty `JULIA_DEPOT_PATH`, and makes an archive. | `Distribution.jl` |
| Optional: prelink with the special Julia of `julia-sysimage-prelink-wip` (the build logs and continues without it), a custom `launcher.c` (about 90 ms of start time), a reactive rebuild with a patched PackageCompiler. | `Executable.jl:393-412`, `launcher.c`, `Reactive.jl` |
| The generic files name no simulator package: `Root.jl`, `Preference.jl`, `Usage.jl`, `AppPackage.jl`, `Executable.jl`, `Distribution.jl`. `test/build.jl` tests them without a compile. | `source/build/`, `package/OmnetBuilder/` |
| Simulator parts: the program names, `-u Cmdenv`, the `-f` and `-c` options, the model packaging rule, the module union pin, the requirement texts. | `Program.jl`, `AppPackage.jl:140-150` |
| A `create_app` compile once died because another build used the memory. | `plan/done/build-programs.md:746` |

## 4. Design

### 4.1 The application

The command line of the binary:

```
projectured [files...] [--window pane|workbench] [--backend sdl|web]
            [--assistant ollama|anthropic|none] [--model NAME] [--mcp]
            [--log-level=LEVEL] [--help] [--version] [--build-info]
```

- One Julia function opens the application window with the files, and the
  binary calls it. A REPL user calls the same function. Name it by the naming
  rules, and put it where `package-rules.md` says.
- `--window` selects the window (D20). The default is the pane program (D24).
- The pane window: file tabs in split panes, a file navigator, and the
  assistant beside the tabs. A file tab is a document that a `PaneTab` holds.
  The `Ctrl+S` and `Ctrl+O` gestures of `WorkbenchFile.jl` move to it, so that
  both windows use one file tab.
- The workbench window: the existing `Workbench`, with one `WorkbenchEditor`
  tab for each file.
- A file opens in the format that its extension names, through the registry
  of `read_document_file`. `EDITOR_DOMAINS` goes away, or it reads that
  registry.
- In both windows, a file opens from the navigator and from the command
  palette. `Ctrl+S` saves a tab. "Save as" asks for a path with
  `WidgetInputDialog`.
- `--assistant` and `--model` select the backend and the model. They use the
  defaults of `documentation-rewrite.md` Step 1: Ollama, and the newest
  Claude model.
- `--mcp` starts the MCP server.
- The exit code is 0 when the program finishes, 1 for a bad command line, and
  2 for a failure. A failure prints one line on `stderr`.

### 4.2 The builder

**D31 (the owner, 2026-09-17: "move only the stable core").** omnet's
`build_executable` mixes the generic steps with reactive rebuilds, trimming,
sealing and prelinking, and its plain path links a custom launcher from an
object archive that only the patched PackageCompiler keeps. A public build must
work with the released PackageCompiler. So only the stable core moves to
`ProjecturedBuilder`. omnet's `OmnetBuilder` keeps the custom launcher, the
prelink, the reactive rebuild, the trim and the seal, as an extension that calls
the core.

The core, as fragments of the `ProjecturedBuilder` package in `source/builder/`:

| File | Holds |
| --- | --- |
| `BuildContext.jl` | `BuildContext`: the repository a build writes into (`build/app/`, `build/<name>/`), the folders to find packages in, the environment variable of the log level, the precompile statements file, and the version text. `get_package_directory(context, name)` and `get_package_uuid(directory)`. A caller makes the context, so the builder names no repository. |
| `Preference.jl` | `Preference`, `make_baked_preference`, `make_exposed_preferences` (omnet's `exposed`, with a verb-first name), `write_preferences`. |
| `Usage.jl` | `Usage`, `format_usage`, `format_version_line`, `collect_option_flags`. |
| `AppPackage.jl` | `write_app_package(context; name, packages, imports, init, main, workload, info, usage, log_level)` and `write_if_changed`. `imports` are packages the module imports but does not use, and `init` is Julia code at module level. omnet passes `OmnetSimulator` and its module-union pin through these two; the core names neither. |
| `Executable.jl` | `resolve_app_project`, `build_info`, `build_executable(context; …; compile_app = compile_app!)`, `compile_app!` (the plain `create_app` with PackageCompiler's own launcher), `bundle_fonts!`, `bundle_assets!`, `print_build_report!`, `get_smoke_flag`, `PORTABLE_CPU_TARGET`, `INCREMENTAL_MARK`. A caller passes its own `compile_app` to compile another way; omnet passes its launcher, prelink, reactive and trim step. |
| `Distribution.jl` | `build_distribution(context; …)`, `get_staging_root`, `check_relocation`, `write_readme`, `report_distribution`. |
| `ProjecturedProgram.jl` | The projectured binaries: `build_projectured_executable`, `build_projectured_distribution`, and the context of this repository. |

`BuildSpec` and `Builder.jl` stayed until Step 3 removed them. The two
`build_executable` methods differed in their first argument, so they lived
side by side for that time. `make_projectured_build_context` is in
`BuildContext.jl`, not in `ProjecturedProgram.jl`.

- `environment/build` holds `ProjecturedBuilder` (by `[sources]`) and the
  released PackageCompiler (D23). No other environment holds PackageCompiler.
  The reactive rebuild needs the patched PackageCompiler, so it stays in
  omnet-julia.
- `strip_bundle!` stays in omnet: it moves `lib/julia/sys.so` out of the
  bundle, which is right only when the image is linked into the executable.
- The application function stays in the example package for now, because its
  content projections use example factories. Moving it into product code is a
  later cleanup.
- One function for each projectured binary: the application, and the JSON
  file editor if it is still wanted. The shell front end `build_binary.jl`
  dispatches to them: `julia --project=environment/build <path>/build_binary.jl
  projectured`. Put the front end where `architecture-rules.md` says; the
  builder slice `source/builder/` is the first choice.
- `ProjecturedExecutable` stops being a fixed package with fixed `[deps]`. It
  becomes the template of the generated package, or it goes away. Update
  `package-rules.md` and `test_package_graph()` with it.
- The output layout is `build/<name>/{bin,lib,share}`.
- The moved code is public. Replace the simulator examples and measurements in
  its comments with ProjecturEd ones when they exist. Until then, keep the
  statement and drop the private sample name.

## 5. Steps

Before you run a build, read the process rules: one Julia process at a time, a
memory cap of 20 GB, a timeout, and output to a log file. A build uses much
memory. Do not start a build beside another build or a large Ollama model. A
timing needs an idle machine and the owner's approval.

### Step 0: the worktree and the baseline

- [x] Make the worktree `workspace/projectured-julia-application`
      (2026-09-17, from `main` at `14a533d1`).
- [x] Record the baseline. The regression set of Step 1 serves as the record:
      see "What the step measured" below. omnet-julia's `test/build.jl` waits
      for Step 2.

### Step 1: the application window (projectured; pane, workbench, fileformat, example slices)

- [x] The file tab: `WorkbenchEditor`, for both windows (D26).
- [x] Every format opens and saves: the 8 natural formats, `.pdoc`, `.pred`,
      `.txt` and a file without an extension (commit `1213e1e3`).
- [x] The pane window: file tabs, the navigator, the assistant. A file opens
      from the navigator with `open_pane!`.
- [x] The workbench window with the same file tabs.
- [ ] The command palette entries "Open file" and "Save as" (see "Open").
- [x] The function that opens the window: `run_application` in
      [Application.jl](../../example/projectured/Application.jl), with the
      options of §4.1 except the command line itself, which is Step 3.
- [x] Test without a window: `test_application()` in
      `test/projectured/editor/ApplicationTest.jl`. Both windows draw a file of
      each of the 11 kinds; `Ctrl+S` saves a changed file; a click, Enter and a
      double click in the navigator open a file beside the other files.

**Decisions of Step 1.**

- **D26. The file tab is `WorkbenchEditor`.** It already had the save and
  reload gestures and a projection that works alone, so both windows hold it
  and no new document type exists. `make_workbench_file_editor(path)` builds
  one. A move of the type to a lower slice is left for later.
- **D27. The navigator opens a file with an operation.** `FileSystemToWidget`
  takes `open_file`, a function from a path to an operation. Enter on a
  selected file and a double click on a file row return
  `OpenWorkspaceFileOperation(path)`. The workbench slice evaluates it: in a
  workbench it adds a tab to the editing page, and in a pane tree it calls
  `open_pane!`. The file is read at evaluation, so the reader stays pure. The
  workbench package depends on the pane package for this.
- **D28. `open_pane!` takes a `group`.** A file opened from the navigator goes to
  the group that holds files, never to the navigator's or the assistant's
  group. `pane_group_to_avoid` could not say this: it names one group, and
  omnet-julia already writes its method for `PaneTree`, so a second method in
  this repository would collide with it.
- **D29. The pane window starts with the focus inside the first file**, or inside
  the navigator when no file is open, so that the first key reaches a document.
- **D30. The application projection has F1 and the command palette**
  (`GestureHelpDecoratorProjection`, `make_command_palette_decorator_projection`),
  and the window scene gets the projection of the help window.

**Faults that Step 1 found and fixed.**

- A container that moves a click to a child rebuilt the `MousePress` without its
  click count, so a double click never reached a widget inside a container.
  15 calls in the widget, layout and graph slices keep the count now. The same
  edit first touched the sealed `kernel/gesture/GestureRecognizerModule.jl` and
  `inspector/HoverProbe.jl`; both changes were wrong and were reverted at once,
  so no sealed file changed.
- A click on a navigator row failed with "under-typed @reference" in the
  workbench's navigator mapping. The selection names a node of the computed
  file-system document, which is not part of the workspace. The workspace stage
  now writes that selection on the computed document and selects the workspace
  as a whole, and the navigator mapping has the missing type.
- `SaveWorkbenchEditorOperation`, `ReloadWorkbenchEditorOperation` and
  `OpenWorkspaceFileOperation` did not declare `operation_travels_unchanged`,
  so a reader between the tab and the window dropped them. In the pane window,
  `Ctrl+S` did nothing for this reason.

**A fault that Step 1 found and did not fix.** The XML printer indents the text
of an element, and the parser keeps that whitespace, so each save and load adds
blank space to the text. `test_workbench_file_keys` marks it `@test_broken`.
It contradicts the approved introduction ("comes back unchanged"), so it needs
a fix before the posts.

**Open in Step 1.** "Open file" and "Save as" from the command palette need a
path from the person. `WidgetInputDialog` shows a field and two buttons, but
nothing passes the field's value to an operation yet.

**What the step measured.** No timing. The screenshots of both windows with 11
open files were checked by eye.

**The regression check of Step 1**, run on the branch and, for the two sets that
do not pass, on a clean worktree at `14a533d1`
(`workspace/projectured-julia-application-base`):

| Test | Branch | Clean `14a533d1` |
| --- | --- | --- |
| `test_application` (new) | 50 pass | — |
| `test_workbench_file_keys` | 43 pass, 1 broken (the XML text) | — |
| `test_package_graph` | 727 pass, 3 fail | the same 3, at `PackageGraphTest.jl:284` |
| `test_workbench` | 143 pass, 3 fail, 2 errors | the same, at `AssistantMvpTest.jl:599, 643` and `WorkbenchTabClickTest.jl:119, 151, 152` |
| `test_split_pane_drag` | 24 pass, 3 fail, 2 errors | known on `main` |
| `test_click_roundtrips` | 42 pass, 2 broken | known markers |
| `test_naming`, `test_filesystem`, `test_graph`, 8 pane tests, 15 widget, table and layout tests | all pass | — |

The three failures of `test_package_graph` are the stale table of edges between
domains that the documentation survey found. They are not this plan's.

### Step 2: the generic builder in projectured (builder slice)

- [x] Port the stable core of §4.2 into the builder slice, from omnet's
      `source/build/`. omnet-julia keeps its own files until Step 6.
- [x] Remove the simulator names; pass what omnet needs through
      `BuildContext`, `imports`, `init` and `compile_app`.
- [x] Give `ProjecturedBuilder` the dependencies that the files need: `Dates`,
      `Pkg`, `Preferences`, `SHA`, `TOML`.
- [x] Make `environment/build` (D23).
- [x] Port the tests of omnet's `test/build.jl` that cover the core, into
      `test/builder/`. They compile nothing.
- [x] Test: `test_builder()`, `test_package_graph()`, `test_naming()`.

**What the step measured.** `test_builder()`: 73 pass. `test_package_graph()`:
727 pass, 3 fail — the same stale-edge failures the Step 1 baseline recorded, at
the same line, `PackageGraphTest.jl:284`. `test_naming()`: 1 pass. `test_tree()`:
1 pass. No new failure anywhere.

**Decisions of Step 2.**

- **`ProjecturedProgram.jl` did not land.** §4.2's table names it as a fragment
  that would hold "the projectured binaries", but Step 2 ports only the generic
  core — one function per projectured binary is Step 3's work, over the front
  end. Nothing in Step 2 needed it.
- **`bundle_fonts!` finds its own source directory, not `context.root`.** The
  fonts always live in projectured-julia's own `asset/font`, regardless of which
  repository's `BuildContext` calls it — that is where `ProjecturedStyle` is
  compiled from, whichever repository builds the binary. So it resolves its
  source path from `@__DIR__` (this fragment's own location under
  `source/builder/`), the same trick `Builder.jl` already used for
  `EXECUTABLE_DIR`/`SOURCE_DIR`, rather than from the context passed in.
  `bundle_assets!`, by contrast, takes the context and resolves under
  `context.root`, because an asset directory is specific to the repository that
  is building.
- **`get_package_directory` takes `context.package_roots`, a list, in place of
  omnet's hardcoded sibling-checkout fallback.** omnet's `Root.jl` tried
  `ROOT/package` and then `../projectured-julia/package` by name. The context
  generalizes this to an ordered list a caller builds however it likes — omnet's
  own context, in Step 6, lists both its own `package/` and projectured-julia's.
- **`build_info` gained an `extra_info` keyword instead of knowing about `trim`
  or `reactive`.** Those stay entirely in omnet's extension; the core's
  `build_info` appends whatever text a caller's own build step wants recorded,
  after everything it writes itself.
- **The `.gitignore` rule `build/` was anchored to `/build/`.** The unanchored
  pattern matches a directory named `build` at any depth, so it silently
  swallowed `environment/build/` the moment that directory was created — the
  comment beside the rule already said it meant only the repository root. Fixed
  as part of this step, since `environment/build/Project.toml` and its
  `Manifest.toml` could not otherwise be committed.
- **`environment/build`'s `Manifest.toml` resolved `PackageCompiler` v2.4.2**,
  freshly — `environment/all`'s `Manifest.toml` held no prior entry for it to
  match, since `Builder.jl`'s existing path only adds PackageCompiler to an app
  environment at compile time and never to `environment/all` itself.
- **Not ported, per D31 and the plan's explicit list**: `Trim.jl`/juliac
  trimming, `Reactive.jl` and the reactive rebuild, the prelink machinery and
  `launcher.c`, `link_executable!`, `strip_bundle!`, the object-archive
  keyword, and `Program.jl`'s simulator-specific build functions (module-union
  pin call site, `-u Cmdenv`, `-f`/`-c` options, the wrapper-fold system). All
  stay in `OmnetBuilder` for Step 6 to keep as an extension over the core.

### Step 3: the projectured targets and the front end

- [x] One function for each binary, with its option table.
      `source/builder/ProjecturedProgram.jl` holds `build_projectured_executable`
      and `build_projectured_distribution`. The JSON file editor binary is not
      made again: the application opens a JSON file.
- [x] The generated app package replaces the fixed `ProjecturedExecutable`.
      Update `package-rules.md` and `test_package_graph()`.
      Removed: `package/ProjecturedExecutable/`, `source/executable/`,
      `source/builder/Builder.jl` and its `BuildSpec`, and the `.gitignore`
      line of the generated `AppConfig.jl`. Changed: `package-rules.md`,
      `division-terminology.md`, `naming-rules.md`, `CONTRIBUTING.md`, and a
      comment in `example/projectured/Precompile.jl`.
- [x] The front end `build_binary.jl`, with `--help`.
      It is `source/builder/build_binary.jl`, with one binary, `projectured`.
- [x] Test: the builder tests; `test_package_graph()`; a dry run that writes
      the app package and compiles nothing.

Done on 2026-09-17. Results:

| Test | Result |
| --- | --- |
| `test_builder()` | 133 pass. New: the dry run of `build_projectured_executable`, the front end, and the wrap of the help text. |
| `test_application()` | 72 pass. |
| `test_package_graph()` | 604 pass, 3 fail. The 3 fails are the known ones (the domain edge table). The pass count was 727: one leaf fewer makes 236 in place of 357 in "nothing depends on a leaf", and one package fewer makes 126 in place of 128 in "every package declares exactly the packages it names". |
| `tree_violations`, `naming_violations` | none. |
| `build_binary.jl --help`, `build_binary.jl projectured --no-compile` | exit 0. The manifest of `environment/build` did not change. |

Decisions and facts of Step 3:

- **One option list.** `PROJECTURED_OPTIONS` in `ProjecturedBuilder` is the
  list that the `--help` text of the binary shows. `APPLICATION_OPTIONS` is
  gone. The example package can not depend on the builder, and the builder
  loads no program package, so `test_application()` compares the list with the
  keys of `parse_application_arguments`.
- **The default backend is the first backend of the build.** The parser gives
  `backend = nothing` when the command line names none, and
  `run_application_command` takes the first key of `backends`. A binary with
  one backend has no `--backend` line in its help, and its flag matcher
  refuses `--backend`.
- **The generated package is `ProjecturedApp`** under
  `build/app/projectured/`. It depends on `ProjecturedExample`,
  `ProjecturedMcp` (it defines `make_agent_server(:mcp, …)`), and one package
  for each backend: `ProjecturedSdl`, `ProjecturedWeb`. Its workload is
  `ProjecturedExample.warm_application()`.
- **`format_usage` wraps.** A description can hold `\n`, and a label wider than
  the column puts its description on the next line. Before this change,
  `--assistant=ollama|anthropic|none` ran into its description. The help text
  of `projectured` fits 80 columns, and a test checks that.
- **A test includes the front end.** `build_binary.jl` resolves the build
  environment and calls `exit` only when it is the program file
  (`IS_COMMAND`), so `test_builder()` includes it into a module and calls its
  parser.
- `build_projectured_distribution` refuses `compile = false`, and the front end
  refuses `--distribution` with `--no-compile`, `--no-incremental` or
  `--cpu-target`, because the distribution sets these.
- `make_projectured_build_context` finds the repository root as the first
  directory above the package that holds `CLAUDE.md` and `package/`.

### Step 4: the first build

- [x] Ask the owner, then build the application with one process and a memory
      cap. The owner approved it on 2026-09-17 ("yes").
- [x] Start the binary with a file of each format and each `--window`.
- [x] Record the size and the start time of the build report in this plan.

Done on 2026-09-17, with the stock Julia 1.13.0 and PackageCompiler 2.4.2:

```
JULIA_IMAGE_THREADS=2 systemd-run --user --scope -q -p MemoryMax=20G -p MemorySwapMax=0 \
  timeout 5400 nice -n 10 taskset -c 16-23 \
  julia --startup-file=no --project=environment/build source/builder/build_binary.jl projectured
```

The first try stopped in `Pkg.resolve`: `ProjecturedExample` gave no
`[sources]` path for `Projectured`, `ProjecturedAnthropic` and
`ProjecturedOllama`. `environment/all` gives these paths, but the generated
package has only its own. Commit `79881fe6` adds the three paths, and
`build_executable` now stops before it writes anything when a local dependency
in the tree has no path (`collect_missing_sources`). Other upper packages
(`ProjecturedTest`, `ProjecturedRepl`, the native example and test packages)
have the same gap. No build holds them, so they stay as they are.

| What | Value |
| --- | --- |
| Wall time of the build | 8 min 6 s (incremental, native). Other sessions used the machine, so this is not a measurement. |
| Bundle | 1413 MB (`du -sb`): 530 MB of artifacts, 290 MB of libraries, 37 fonts. |
| Start in the build report | 0.38 s to answer the smoke flag, one run on a busy machine. |
| `--help`, `--version`, `--build-info` | exit 0, correct text. |
| `--window=tiles`, `--backend=x11`, `--colour`, `--log-level=loud` | exit 1 with a message that names the fault. |
| `--window=pane` with 11 files (json, xml, yaml, md, rst, math, jl, sql, txt, a file without an extension, pdoc) | The window was there after about 1.1 s. It shows the navigator, 11 tabs, the JSON file in colour, and the assistant with its greeting. No warning in the log. |
| `--window=workbench` with the same files | The same, in the workbench layout with the console at the bottom. |

The binary shows only the first tab of each start. `test_application()`
checks that every format draws, in both windows, in a Julia session.

Faults that Step 4 found, still open:

- `--build-info` shows the time of the last write of the generated module,
  not the time of the build. `write_if_changed` ignores the time stamp, so a
  build that changes nothing else keeps the old time.
- `xprop` found no `WM_NAME` on the window of the binary. The code gives the
  title `ProjecturEd` to `SDL_CreateWindow`. Check `_NET_WM_NAME` the next
  time a window is open.
- The stop by `SIGTERM` prints a backtrace, and the exit code is 15.
- The large artifacts (x264, x265, libfdk_aac and the rest of FFMPEG) come in
  through the SDL backend: `ProjecturedSdl` → `SDL2_jll` →
  `alsa_plugins_jll` → `FFMPEG_jll`. The application plays no sound. If the
  archive must be smaller, look at this chain in Step 5.

### Step 5: the distribution build and the release

- [x] Make the binary read three more things from the bundle, as it reads the
      fonts from `share/projectured/font`. Each one is now a path relative to
      the source file, so a copy on another machine does not find it:
  - the web client, `asset/web` (`WebBackend` in `source/web/Web.jl`), and the
    fonts that the web backend sends;
  - the guides that the assistant reads, `documentation/`
    (`_guide_roots` in `source/kernel/tool/Documentation.jl`);
  - the folder of the meaning index, `build/meaning`
    (`_get_meaning_file` in `source/kernel/tool/MeaningSearch.jl`). This folder
    must be writable, so it goes to a user folder, not into the bundle.
- [x] A distribution build. The relocation test must pass. Start the copy with
      `--backend=web` too, because the relocation test does not open a window.

Decisions and facts of Step 5 (commit `a8b4ce34`):

- **A binary looks in its bundle first.** `share/projectured/` beside `bin/`
  exists only in a binary, so a Julia session reads the checkout as before.
  The fonts keep their own order (the compiled-in path first), because
  `StyleFont` carries a path.
  - The web backend: `get_web_asset_directory(name)` for `web` and `font`.
  - The guides: `_get_documentation_directory()` in `ToolModule`.
  - The meaning index: `_get_default_meaning_folder()`. A binary uses
    `$XDG_CACHE_HOME/projectured/meaning`, or `~/.cache/projectured/meaning`.
- **The build copies two folders:** `PROJECTURED_ASSETS` names `asset/web`
  (32 KB) and `documentation/` (1.1 MB, 61 Markdown files).
- **The copy is tested with the checkout hidden.** `check_relocation` and the
  program check run under `bwrap --dev-bind / / --die-with-parent --tmpfs
  <folder>`. `get_hidden_directories(context)` names the repository, the
  repository of each package folder, and `first(DEPOT_PATH)`. Without `bwrap`,
  the test stops with a message.
- **`build_distribution` takes a `check`.** `check_projectured_copy` starts
  the copy with `--backend=web --mcp --assistant=none`, reads `/`,
  `/client.js`, `/fonts.json` and one font from port 8080, and calls the MCP
  tool `read_resource` with `resource://guides` on port 9876. The list must
  name `editor-concepts`. The check needs `curl` and the two free ports.
- **The archive of this step is a test, not the release.** Four files in
  `documentation/` still name private projects (`README.md`,
  `package/graph/graph-layout.md`, `package/chart/chart.md`,
  `rule/code-quality-rules.md`), and the bundle carries `documentation/`.
  Build the release archive again after the documentation plan removes
  those names.
- [ ] D22: the owner approves the GitHub release. The documentation plan
      attaches the archive in its Step 11. Build the archive again for the
      release, after the documentation plan removes the private names (see
      below).

The distribution build of 2026-09-17:

```
JULIA_IMAGE_THREADS=2 systemd-run --user --scope -q -p MemoryMax=20G -p MemorySwapMax=0 \
  timeout 7200 nice -n 10 taskset -c 16-23 \
  julia --startup-file=no --project=environment/build source/builder/build_binary.jl projectured --distribution
```

| What | Value |
| --- | --- |
| Wall time | 25 min (a fresh image for the portable processor list). Another session used the machine. |
| Largest process | about 14 GB of resident memory, in the compile of the image. |
| Bundle | 1558 MB. |
| Archive | `build/projectured-0.1.0-linux-x86_64.tar.gz`, 437 MB. It holds `bin/`, `lib/`, `libexec/`, `share/` and a `README`. |
| Relocation test | passed: the copy answered `--build-info` in 0.4 s with the repository and `~/.julia` hidden. |
| Program check | passed: web client, font and guide list from the bundle. |

The first distribution build passed, but its check left the copy running on
ports 8080 and 9876. `kill` stopped `bwrap` only, and `--die-with-parent` did
not stop the program. With `--unshare-pid`, the kernel stops the program when
`bwrap` stops (tested with `sleep` and in `test_builder()`). The check now also
waits until both ports are free. The left process was stopped by hand, and the
distribution step ran again on the same bundle: it passed and left nothing.

The check can fail. On a copy of the bundle, with the checkout hidden:

| Case | Result |
| --- | --- |
| no `share/projectured/documentation` | fails: the guide list does not name `editor-concepts` |
| no `share/projectured/web` | fails: the copy serves no web client |
| no `share/projectured/font` | fails: the copy finds no font |
| no guides, checkout visible | passes, because the copy reads the checkout |
| everything | passes |

For the release README, still open: the address of the web window
(`http://127.0.0.1:8080`), the default Ollama model to pull, and the licence.

### Step 6: omnet-julia uses the shared builder

- [x] Land Steps 2 and 3 on projectured's `main` first. A change in a
      projectured worktree is not visible to omnet-julia.
- [x] `OmnetBuilder` keeps `Program.jl`, the front end and the simulator parts,
      and calls `ProjecturedBuilder` for the rest. Delete its copies of the
      generic files. Move the generic tests out of its `test/build.jl`.
- [x] D25: rename `environment/tool` to `environment/build`, and update the
      commands in its README and guides.
- [x] Test: omnet's `test/build.jl`.
- [x] With the owner's approval, one omnet build (2026-09-17). The owner
      approved it, and a subagent ran it.

`bin/build_omnet_run`, with the prelink Julia
(`workspace/julia-sysimage-prelink-wip`, 1.13.0-rc4) on the `PATH`, under
`systemd-run --scope -p MemoryMax=14G`:

| What | Value |
| --- | --- |
| Wall time | 3 min 53 s |
| Largest process | 9.3 GB, under the cap |
| Bundle | 632.6 MB; the executable answers in 0.01 s |
| Prelink | ran: "2 of 13600428 pointers on the list" |
| `--build-info` | `omnet_run, built … by ProjecturedBuilder`, the packages, the `main`, the workload, and the preference of the program |
| `--help` | the command line of the runner, with its exit codes |

So the shared builder writes and compiles a binary of the other repository,
with the launcher, the prelink and the preferences that only that repository
has. The script names `julia` without a path, so a build there must have the
prelink Julia first on the `PATH`.

Done on 2026-09-17, in the worktree `workspace/omnet-julia-build`, branch
`shared-builder`, commit `812a3928`. Not landed on omnet's `main` yet.

- `OmnetBuilder` depends on `ProjecturedBuilder` by a `[sources]` path to the
  sibling checkout, the way every other cross-repository dependency is named.
- `source/build/Context.jl` replaces `Root.jl`: `ROOT`, the context of the
  repository (`package_roots` are omnet's `package/` and then projectured's),
  and the one-argument `get_package_directory`.
- `AppPackage.jl`, `Preference.jl`, `Usage.jl` and `Distribution.jl` are
  deleted. `Executable.jl` keeps the launcher, the object archive, the link,
  the prelink, `strip_bundle!` and `_compile!`, and its `build_executable` is
  now a wrapper: it validates its own keywords, then calls the shared builder
  with a `compile_app` of its own — the trimmed build, the reactive rebuild,
  or the plain path with the launcher.
- **Two seams went into the core for this**: `precompile` (a trimmed build
  compiles no system image, so its resolve must precompile) and `after_write`
  (the reactive preparation writes the trace workload into the package and
  reads what the last build wrote, and both must happen when `compile = false`
  too). A first version put the reactive preparation in `compile_app`; omnet's
  own test caught that `compile = false` then wrote no trace workload.
- `test/build.jl` keeps what only omnet does: the prelink, the workload, what
  each binary holds, the trimmed build, the wrappers, the reactive build and
  the watch. The generic testsets are `test_builder()` in projectured.

| Test | Result |
| --- | --- |
| omnet `test/build.jl` with the prelink Julia, on the branch | 53 pass, 2 errors |
| the same on omnet's `main` | 124 pass, 2 errors |

Both runs error in the same two reactive tests, for the same reason: the
`[sources]` of the build environment names `workspace/package-compiler-reactive`,
which has no `collect_tracked_sources`. That is the state of that checkout, not
a fault of this change. The pass count differs because the generic testsets
moved to projectured, where `test_builder()` now has 152 assertions.

`bin/build_omnet_ide --help` answers from the renamed environment, and the
`bin/` scripts of both repositories ask the builder for the module name of the
generated package (`get_app_module_name`, which this step made public).

### Step 7: the documentation of the build

- [x] Turn `documentation/package/executable/README.md` into
      `documentation/guide/build-guide.md`: the targets, the front end, the
      options, the distribution build, the memory warning.
      The old file is removed: every line of it named code that is gone
      (`BuildSpec`, `ProjecturedExecutable`, the generated `AppConfig.jl`, the
      pre-move tree). `README.md` and `documentation/README.md` name the new
      guide.
- [x] Cross-link it with `static-compilation-guide.md`.
- [x] Tell `documentation-rewrite.md` that its Step 4 can name the command.
- [ ] Move this plan to `plan/done/`, when the release of Step 5 is out. That
      release belongs to Step 11 of `documentation-rewrite.md`, because the
      archive carries `documentation/` and must be built again after the
      private names leave it. Everything else in this plan is done.

**The owner asked for `bin/` scripts (2026-09-17), as omnet-julia has them:**

| Script | What it does |
| --- | --- |
| `bin/projectured` | runs the application from the checkout, with no build: it writes the package of the binary (`compile = false`) and starts its `julia_main`. |
| `bin/build_projectured` | builds the binary. It is `build_binary.jl` under a name of its own. |

`PROJECTURED_BUILD_WHAT` and `PROJECTURED_BUILD_COMMAND` tell the front end
which binary a script fixed and what to call itself, so `bin/build_projectured
--help` names that command and offers no choice of binary. Both scripts are
tested by hand (`--help` of each) and by `test_builder()` (the fixed binary in
the parser).

### Later, only if wanted

- Prelink with the special Julia.
- The custom launcher.
- The reactive rebuild, with the patched PackageCompiler.
- `cpu_target` for other processors, and builds for macOS and Windows.

## 6. Risks

- **A build runs out of memory.** One build at a time, a memory cap, no large
  model beside it.
- **Linux-only code.** The launcher, `strip_bundle!` and the link options assume
  Linux. The release is Linux x86-64 only, and the build guide says so.
- **Two copies of the builder for a while.** Steps 2 to 5 use the copy in
  projectured, and omnet-julia keeps its own until Step 6. Do Step 6 soon after
  Step 3, so that the copies do not drift.
- **The fonts or another file come from the checkout.** The relocation test of
  Step 5 catches this. Run it before every release.
- **The window option doubles the test work.** Both windows use one file tab
  and one open function, so most tests run once for each window with the same
  code.

## 7. Out of scope

- `juliac --trim`. It stays research (`static-compilation-guide.md`).
- Builds for macOS and Windows.
- The reactive rebuild.
