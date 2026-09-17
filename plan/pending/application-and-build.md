# The application and its build

**Status (2026-09-17): IN PROGRESS.** Step 0 is done, and Step 1 is done except
for the two command palette entries. The work is on the branch
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

`ProjecturedBuilder` holds the generic builder that moves from omnet-julia
(D21):

| File | Holds |
| --- | --- |
| `Root.jl` | Finds a package directory by name. The calling repository gives its package roots, so the builder names no repository. |
| `Preference.jl` | Build-time preferences of the generated package. |
| `Usage.jl` | The option table of a binary: its `--help` text and its refusal of an unknown option. |
| `AppPackage.jl` | Writes a fresh app package: the packages, the `julia_main` expression, the workload, the usage, the log level. It does not write a file again when only a time stamp changes. |
| `Executable.jl` | Compiles with `create_app`: `incremental`, `cpu_target`, fonts, assets, the build report, `strip_bundle!`. Prelink and the custom launcher are options that are off by default. |
| `Distribution.jl` | A full build, a copy under `/var/tmp`, a start with an empty depot, and an archive with a checksum and a short README. |

- `environment/build` holds `ProjecturedBuilder` (by `[sources]`) and the
  released PackageCompiler (D23). No other environment holds PackageCompiler.
  The reactive rebuild needs the patched PackageCompiler, so it stays out of
  this plan.
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

### Step 2: the generic builder in projectured (builder slice)

- [ ] Copy the six generic files, `launcher.c` and the generic tests of
      `test/build.jl` into the builder slice and its test folder. omnet-julia
      keeps its own copy until Step 6.
- [ ] Remove the simulator names. Give `Root.jl` the package roots as an
      argument.
- [ ] Give `ProjecturedBuilder` the dependencies that the files need: `Dates`,
      `Pkg`, `Preferences`, `SHA`, `TOML`.
- [ ] Make `environment/build` (D23).
- [ ] Test: the builder tests, which compile nothing.

### Step 3: the projectured targets and the front end

- [ ] One function for each binary, with its option table.
- [ ] The generated app package replaces the fixed `ProjecturedExecutable`.
      Update `package-rules.md` and `test_package_graph()`.
- [ ] The front end `build_binary.jl`, with `--help`.
- [ ] Test: the builder tests; `test_package_graph()`; a dry run that writes
      the app package and compiles nothing.

### Step 4: the first build

- [ ] Ask the owner, then build the application with one process and a memory
      cap.
- [ ] Start the binary with a file of each format and each `--window`.
- [ ] Record the size and the start time of the build report in this plan.

### Step 5: the distribution build and the release

- [ ] A distribution build. The relocation test must pass.
- [ ] D22: the owner approves the GitHub release. The documentation plan
      attaches the archive in its Step 11.

### Step 6: omnet-julia uses the shared builder

- [ ] Land Steps 2 and 3 on projectured's `main` first. A change in a
      projectured worktree is not visible to omnet-julia.
- [ ] `OmnetBuilder` keeps `Program.jl`, the front end and the simulator parts,
      and calls `ProjecturedBuilder` for the rest. Delete its copies of the
      generic files. Move the generic tests out of its `test/build.jl`.
- [ ] D25: rename `environment/tool` to `environment/build`, and update the
      commands in its README and guides.
- [ ] Test: omnet's `test/build.jl`. Then, with the owner's approval, one
      omnet build.

### Step 7: the documentation of the build

- [ ] Turn `documentation/package/executable/README.md` into
      `documentation/guide/build-guide.md`: the targets, the front end, the
      options, the distribution build, the memory warning.
- [ ] Cross-link it with `static-compilation-guide.md`.
- [ ] Tell `documentation-rewrite.md` that its Step 4 can name the command.
- [ ] Move this plan to `plan/done/`.

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
