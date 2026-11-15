# Architecture review: Packages, environments, build, tests, examples, tools

Commit 3a9b4fae4. Reviewer area key: packages-build-test.

## Scope

Paths: `package/` (117 folders), `environment/`, `tool/`, `test/` (structure, `test/suite`, shared helpers), `example/` (structure and registries), `source/tool/{builder,precompile}`, `source/{all,projectured,integrations}`, `bin/`, `build/`, `.github/workflows/CI.yml`.

Read in full, about 5 500 lines:

- Rules and designs: `documentation/design/concepts.md`, `documentation/design/architecture-decisions.md`, `documentation/rule/package-rules.md`, `documentation/design/compile-ahead.md`, and the sections PAR-ONE-WAY-TO-EDIT, PAR-LOWEST-PACKAGE, PAR-PARALLEL-TRIADS, PAR-PACKAGE-CHAIN and PAR-NO-TEST-DOUBLES-IN-MAIN of `documentation/rule/architecture-invariants.md`.
- Package entry files and project files: `Projectured`, `ProjecturedAll`, `ProjecturedREPL`, `ProjecturedIntegrations`, `ProjecturedKernel`, `ProjecturedPlatform`, `ProjecturedJSON`, `ProjecturedJSONTest`, `ProjecturedJSONExample`, `ProjecturedExample`, `ProjecturedKernelTest`, `ProjecturedPrecompile`, `ProjecturedBuilder`, `ProjecturedBuild`; `source/all`, `source/projectured`, `source/integrations`; the three `environment/*/Project.toml`.
- The compile-ahead tool: `PrecompileModule.jl`, `PrecompilePreferences.jl`, `PrecompilePackage.jl`, `PrecompileFailure.jl`; `BuilderModule.jl`.
- Tests: `test/projectured/ProjecturedSuite.jl`, `test/projectured/PackageGraphTest.jl`, `test/suite/tree.jl`, three `*Suite.jl` files, two per-domain test files, `.github/workflows/CI.yml`.
- Examples: `example/kernel/Harness.jl`, `example/kernel/BackendHeadless.jl`, `example/projectured/Precompile.jl`, `example/projectured/ExampleWorkload.jl`.
- Scripts: `bin/projectured`, `bin/build_projectured`, `tool/build-binary.jl`, `tool/record-rebuild-calls.jl`, `tool/survey-arguments.jl`, `tool/juliac-trim/README.md`; `source/kernel/playback/Playback.jl`.

Sampled (heads, outlines by `grep`, and counts over all files): the other 103 package entry files and 105 project files (compared by hash and by count), `test/platform/PlatformSuite.jl`, `test/kernel/layering/CheckLayering.jl`, the other five scripts of `test/suite`, `test/projectured/editor/ExampleSweeps.jl`, `example/projectured/{DomainExamples,ProjecturedExamples,Catalog,FileEditor}.jl`, `example/platform/PlatformExamples.jl`, `source/platform/application/ApplicationWorkload.jl`, `source/platform/display/DisplayWorkload.jl`, `source/backend/video/{VideoRecording,VideoBackend}.jl`, the builder files `ProjecturedProgram.jl`, `PackageRelease.jl`, `Executable.jl`, `LinkedExecutable.jl`, `ReactiveBuild.jl`, `PrecompileRecording.jl`, the scripts of `tool/video` and `tool/assistant`, the guides `build-guide.md` and `testing-guide.md`. The builder (5 200 lines) is the part that I read least: I state nothing about its inside.

I ran no Julia. Every count below comes from `grep`, `wc`, `find` and `awk` over the tree at the commit.

## State

The package model is sound. The five kinds of package, the one direction of the dependencies, the split of `source/`, `test/`, `example/`, `package/` and `environment/`, and the rule that a third-party dependency makes a package of its own are all stated, and static guards check them. Compile ahead has one mechanism, the macro `@compile_ahead` with two preferences, and the binary reuses it. The generic test drivers (`test_printer`, `test_reader`, `test_repl`, the navigation walks) take any document and projection, which is the right shape.

The main weakness is that the model is kept by hand and not by a mechanism. A package is a name and an include list, but each of 88 entry files also carries a copy of the same binding loop, and about a dozen files repeat the list of the packages. The guards then check the copies against each other. The copies drift: the CI matrix misses three test packages, `test_all()` calls 28 of the 39 package suites, and nine test suites are called by no aggregator.

The second weakness is that there is no one way to drive an editor with scripted input. A test, a video, a compile-ahead workload, a playback and a tool script each have their own driver, and most tests imitate the editor loop by hand with a stand-in for the editor. This goes against the first principle that a person, the assistant and a test make the same operations in the same way. It is the largest finding, and it reaches into the kernel and the platform.

The examples have the same fault at a smaller size: three registries kept by hand, the examples of a domain declared in the umbrella, and the question "which sweep applies to this example" answered by lists of names inside the sweeps.

## Inventory

### A. The 117 packages by kind

| Kind | Count | Which |
| --- | ---: | --- |
| main: engine | 2 | `ProjecturedKernel`, `ProjecturedPlatform` |
| main: domain | 21 | JSON, YAML, XML, Markdown, RST, Book, Math, Julia, SQL, Database, Graph, Chart, SequenceChart, DBCatalog, Formula, FSM, Process, Git, Pivot, Workflow, Research |
| main: backend | 5 | Console, PDF, SDL, Web, Video |
| main: adapter | 10 | ACP, Anthropic, Ollama, OpenRouter, MCP, LanguageServer, DataFrames, ODBC, Tulip, Adaptagrams |
| aggregate | 3 | `Projectured` (umbrella), `ProjecturedAll` (flat namespace), `ProjecturedIntegrations` |
| tool | 2 | `ProjecturedPrecompile`, `ProjecturedBuilder` |
| leaf | 3 | `ProjecturedREPL`, `ProjecturedBuild`, `ProjecturedBench` |
| example (`…Example`) | 31 | one per stem that has examples, and the umbrella `ProjecturedExample` |
| test (`…Test`) | 40 | one per stem that has a suite, and the umbrella `ProjecturedTest` |

### B. What repeats in each package

| What | Copies | Kept equal by | Evidence |
| --- | ---: | --- | --- |
| `version = "0.1.0"` | 117 | nobody; the release computes the version of a package from its content | `grep '^version'`, [PackageRelease.jl:477](../../../source/tool/builder/PackageRelease.jl#L477) |
| `[deps]` line of a `Projectured*` package | 806 of 922 `[deps]` lines | `test_package_graph()` computes the set from the source and compares | [PackageGraphTest.jl:218](../../../test/projectured/PackageGraphTest.jl#L218), [PackageGraphTest.jl:342](../../../test/projectured/PackageGraphTest.jl#L342) |
| `[sources]` line `Name = {path = "../Name"}` | 784 of 788 | nobody; 22 `Projectured*` dependencies in 6 packages have no line | counts by `awk` |
| `[compat]` section | 17 of 117 | the release writes the bounds from a manifest | [PackageRelease.jl:108](../../../source/tool/builder/PackageRelease.jl#L108) |
| `[auto-integration]` table | 33 | `test_packages_declare_triggers()` | [IntegrationLoadingTest.jl:181](../../../test/projectured/IntegrationLoadingTest.jl#L181) |
| binding loop `for _src in …` | 88 entry files, 4 texts (51 + 35 + 1 + 1) | nobody | [ProjecturedJSON.jl:22](../../../package/ProjecturedJSON/src/ProjecturedJSON.jl#L22), [ProjecturedJSONTest.jl:26](../../../package/ProjecturedJSONTest/src/ProjecturedJSONTest.jl#L26) |
| `const _SOURCES = (…)`, the dependencies again | 53 | nobody | [ProjecturedJSONTest.jl:24](../../../package/ProjecturedJSONTest/src/ProjecturedJSONTest.jl#L24) |
| re-export loop of the names of the slice module | 29 | nobody | [ProjecturedJSON.jl:38](../../../package/ProjecturedJSON/src/ProjecturedJSON.jl#L38) |
| `run_natural_rows_workload(M)` and `run_file_workload(M.T)` | 17 entry files hold the first line, 13 of them also the second | two guards that find the need by a regular expression | [PackageGraphTest.jl:421](../../../test/projectured/PackageGraphTest.jl#L421), [PackageGraphTest.jl:437](../../../test/projectured/PackageGraphTest.jl#L437) |
| `test_<slice>_layering()` with the same body | 39 suite files | the naming guard demands the function | [YamlSuite.jl:6](../../../test/domain/yaml/YamlSuite.jl#L6), [naming.jl:223](../../../test/suite/naming.jl#L223) |
| `include(…)` of a test file | 637 lines (557 in `package/*Test/src`, 80 in `ProjecturedSuite.jl`) | nothing checks that an aggregator calls the suite of the file | `grep -c '^include('` over `package/*Test/src` and `test/projectured/ProjecturedSuite.jl` |
| hand `export` of example factories | 646 lines in the example packages | nobody; the umbrella re-exports by a loop and by hand | [ProjecturedExample.jl:40](../../../package/ProjecturedExample/src/ProjecturedExample.jl#L40), [ProjecturedExample.jl:204](../../../package/ProjecturedExample/src/ProjecturedExample.jl#L204) |

### C. The places that write the list of the packages

| Place | Entries | Derived or by hand |
| --- | ---: | --- |
| `package/` folder | 117 | the truth |
| [environment/all/Project.toml](../../../environment/all/Project.toml) | 117 twice (`[deps]`, `[sources]`) | by hand |
| [package/ProjecturedAll/src/ProjecturedAll.jl:15](../../../package/ProjecturedAll/src/ProjecturedAll.jl#L15) | 25 imports | by hand |
| [source/all/ProjecturedAll.jl:1](../../../source/all/ProjecturedAll.jl#L1) | 25 in `_SOURCES` | by hand |
| `package/ProjecturedAll/Project.toml` | 25 twice | by hand |
| [package/ProjecturedBuild/src/ProjecturedBuild.jl:14](../../../package/ProjecturedBuild/src/ProjecturedBuild.jl#L14) and its project file | 31 imports, 32 twice | by hand |
| [ProjecturedProgram.jl:279](../../../source/tool/builder/ProjecturedProgram.jl#L279) `PROJECTURED_APPLICATION_IMPORTS` | 23 | by hand |
| [ProjecturedExample.jl:8](../../../package/ProjecturedExample/src/ProjecturedExample.jl#L8) and [:40](../../../package/ProjecturedExample/src/ProjecturedExample.jl#L40) | 24 `using`, 25 in the loop | by hand |
| [ProjecturedSuite.jl:17](../../../test/projectured/ProjecturedSuite.jl#L17), [:44](../../../test/projectured/ProjecturedSuite.jl#L44), [:476](../../../test/projectured/ProjecturedSuite.jl#L476) | 36 `using`, 23 in the loop, 28 calls in `test_all()` | by hand |
| [CI.yml:57](../../../.github/workflows/CI.yml#L57) | 38 rows `{package, run}`: 36 test packages, and `ProjecturedTest` twice | by hand |
| [PackageGraphTest.jl:21](../../../test/projectured/PackageGraphTest.jl#L21) `DOMAIN_EDGES` | 21 | by hand (a rule table) |
| [ProjecturedProgram.jl:760](../../../source/tool/builder/ProjecturedProgram.jl#L760) the test of a released package | `<Name>Test`, `test_<name>()` | **derived from the name** |
| `PrecompileRecording.jl` `record_repository_calls!` | each package of the repository | **derived from the folder** |

### D. The ways that code is loaded

| Way | Who uses it | What it loads |
| --- | --- | --- |
| `using Projectured` | a user | the platform, the kernel and AutoIntegration, which loads each installed package whose triggers are loaded |
| `using ProjecturedSDL`, … by name | a user | that package and what it depends on |
| `using ProjecturedIntegrations` | a user who wants all | the umbrella, and six integrations by six package extensions |
| `using ProjecturedAll` | tests, examples, the REPL leaf, downstream | 25 packages in one flat namespace, by the loop of `source/all` |
| `using ProjecturedREPL` (`jp`) | a developer | `ProjecturedAll`, `ProjecturedExample`, `ProjecturedSDL`, `ProjecturedTest` |
| `using ProjecturedExample` / `ProjecturedTest` | a developer, CI | the umbrella of the examples / of the tests |
| `ProjecturedBuild` and `build/app/<name>` | the binary | 31 packages named by hand; the build writes a small package that loads it |
| `bin/projectured` | a developer | the same program from the checkout, through `prepare_program_start!` |
| `julia --project=package/<X>Test` | CI, a developer | one test package in its own environment |

### E. The environments

| Environment | Holds | Manifest in git |
| --- | --- | --- |
| `environment/all` | every package and the third-party packages | yes |
| `environment/build` | `ProjecturedBuilder` and the fork of PackageCompiler | no |
| `environment/readme-data-frame` | the session of the README, for the measurement | yes |
| each `package/<X>` | itself, when CI or a person activates it | no (the tree guard forbids it) |
| `build/app/<name>` | the package of a binary, written by a build | not in git |

### F. The ways to drive an editor with scripted input

"Real loop" means that the input passes through the frame of the editor, `run_frame!` of [EditorLoop.jl:66](../../../source/kernel/editor/EditorLoop.jl#L66), with its fault barrier, its inbox and its history.

| Driver | Place | Real loop | Finds its target in what the window drew | Form of the script | Users |
| --- | --- | --- | --- | --- | --- |
| `run_application_workload`, `run_workload_steps!` with `WorkloadStep` | [ApplicationWorkload.jl:46](../../../source/platform/application/ApplicationWorkload.jl#L46), [:214](../../../source/platform/application/ApplicationWorkload.jl#L214) | yes | yes: `DrawnText`, `DrawnPart` | typed steps: click, key, typing, wait | the workloads; 2 test files |
| `run_display_workload` with `WorkloadBackend(events)` | [DisplayWorkload.jl:16](../../../source/platform/display/DisplayWorkload.jl#L16) | yes | no, fixed pixels | `Vector{Event}` | the workloads of three packages |
| `send_workload_inputs!` | [DisplayWorkload.jl:39](../../../source/platform/display/DisplayWorkload.jl#L39), [SdlWorkload.jl:38](../../../source/backend/sdl/SdlWorkload.jl#L38) | yes | — | `Vector{WindowInput}`, one method per backend (2) | the driver of row 1 |
| `HeadlessBackend` with `push_event!` | [BackendHeadless.jl:21](example/kernel/BackendHeadless.jl#L21), [:129](example/kernel/BackendHeadless.jl#L129) | yes, when the test runs frames | no | one event at a time | 118 test files |
| `VideoBackend(timeline, window_id)` | [VideoBackend.jl:84](../../../source/backend/video/VideoBackend.jl#L84) | yes | no, pixels | named tuples `(event, hold)` | `record_application_video` |
| `record_video(document, projection; gestures)` | [VideoRecording.jl:71](../../../source/backend/video/VideoRecording.jl#L71), [:157](../../../source/backend/video/VideoRecording.jl#L157) | **no**: its own loop and the stand-in `_VideoEditor` | no | named tuples `(event \| operation \| await, hold)` | examples, `LiveExample`, tool scripts |
| `play_live!(editor, timeline)` | [Playback.jl:71](../../../source/kernel/playback/Playback.jl#L71), [:40](../../../source/kernel/playback/Playback.jl#L40) | the three stages, in a loop of its own; it calls `read_intent` itself | no | the same named tuples | `LiveExample` |
| `_drive_workload_example!` | [ExampleWorkload.jl:26](example/projectured/ExampleWorkload.jl#L26) | a real `Editor`, stages called by hand | no | a fixed list of events | the workload of `ProjecturedExample` |
| `warm_file_editor` | [FileEditor.jl:213](example/projectured/FileEditor.jl#L213) | no | no | a fixed list | no caller |
| `walk_repl_loop`, `walk_reader_events`, `explore_selections` | [ReplTest.jl:27](../../../test/kernel/editor/ReplTest.jl#L27), [:18](../../../test/kernel/editor/ReplTest.jl#L18) | **no**: stand-in `_ReplEditor` | no | a fixed battery of events | every example sweep |
| local helpers `press!`, `_press!`, `click`, … | for example [PaneRenameTest.jl:14](../../../test/platform/projection/PaneRenameTest.jl#L14), [InsertionInTabTest.jl:43](../../../test/projectured/editor/InsertionInTabTest.jl#L43) | **no** | some, each in its own way | calls | 198 test files call `read_intent` (1 116 calls); 51 stand-in editor types; 132 calls `evaluate_operation((document = …,), op)` in 35 files |
| the scripts of `tool/video` | [record_settings.jl:18](../../../tool/video/record_settings.jl#L18), [:36](../../../tool/video/record_settings.jl#L36) | through the video recorders | no: more than 60 pixel pairs | named tuples; `glide`, `click`, `key`, `pause`, `move` defined again in 5 scripts | 13 scripts |

### G. The registries of the examples

| List | Place | Entries | Built |
| --- | --- | ---: | --- |
| `const X_example = Example(…)` | 202 declarations under `example/` | 202 | by hand |
| `examples` (the global one) | [ProjecturedExamples.jl:1](example/projectured/ProjecturedExamples.jl#L1) | 142 | by hand, not a join of the two below |
| `platform_examples` | [PlatformExamples.jl:143](example/platform/PlatformExamples.jl#L143) | 104 (95 names and two sub-lists of 4 and 5) | by hand; 30 are not in `examples` |
| `domain_examples` | [DomainExamples.jl:185](example/projectured/DomainExamples.jl#L185), in the umbrella | 83 | by hand; 15 are not in `examples` |
| `odbc_examples`, `tulip_examples`, `adaptagrams_examples`, `live_examples` | the example package of each | — | by hand, in the package that owns them |
| `platform_atomic_documents`, `domain_atomic_documents` | [PlatformExamples.jl:249](example/platform/PlatformExamples.jl#L249), [DomainExamples.jl:278](example/projectured/DomainExamples.jl#L278) | — | by hand |
| `BRIDGES`, the projections that the generated catalog may chain | [Catalog.jl:34](example/projectured/Catalog.jl#L34) | 11 | by hand |
| `WIDGET_EXAMPLES` | [widget-images.jl:23](../../../tool/widget-images.jl#L23) | 45 names | by hand |

### H. The static guards

| Guard | File | Lines | Reads source with | Exception form | Runs alone |
| --- | --- | ---: | --- | --- | --- |
| tree | `test/suite/tree.jl` | 292 | directory entries, regular expressions | none | yes |
| naming | `test/suite/naming.jl` | 566 | `Base.JuliaSyntax`, regular expressions | tables `_ALLOWED`, `_MANY_METHODS` | yes |
| arguments | `test/suite/arguments.jl` | 390 | `Meta.parseall` | comment `# @optional:`, list `ARGUMENT_PROTOCOL`, `PORT_FOLDERS` | yes |
| exports | `test/suite/exports.jl` | 380 | `Meta.parseall` | lists `EXPORT_UNMIGRATED`, `EXPORT_REEXPORTING` | yes |
| documentation | `test/suite/documentation.jl` | 369 | regular expressions on Markdown | `_PHRASE_EXCEPTIONS` | yes |
| style | `test/suite/style.jl` | 208 | regular expressions per line | comment `# @style:`, `STYLE_EXEMPT_FILES` | yes |
| layering, slice edges | `test/kernel/layering/CheckLayering.jl` | 1 300 | `Meta.parse` | `exempt_files`, `unmigrated_files`, `extra_aliases` | no, 39 callers |
| package graph | `test/projectured/PackageGraphTest.jl` | 453 | regular expressions | `_LEAVES`, `_FIRST_WINDOW_PACKAGES` | no |
| export collisions | `test/projectured/ExportCollisionTest.jl` | 156 | the loaded modules | — | no |
| report of the audit | `tool/survey-interface.jl` | 150 | `Meta.parseall` | — | yes |

The nine files hold 25 calls of `walkdir`. Each has its own list of roots. Six have the same eight-line `@testset` wrapper in [ProjecturedSuite.jl:305](../../../test/projectured/ProjecturedSuite.jl#L305) to [:439](../../../test/projectured/ProjecturedSuite.jl#L439).

### I. Compile ahead

| Mechanism | Place | Role |
| --- | --- | --- |
| `@compile_ahead` at `"recorded"` | [PrecompilePackage.jl:110](../../../source/tool/precompile/PrecompilePackage.jl#L110) | a package compiles the lines of its `precompile/*.txt`; 31 packages hold the folder |
| `@compile_ahead` at `"live"` | [PrecompilePackage.jl:59](../../../source/tool/precompile/PrecompilePackage.jl#L59) | a package runs its workload |
| the recording | [PrecompileRecording.jl:279](../../../source/tool/precompile/PrecompileRecording.jl#L279), [:293](../../../source/tool/precompile/PrecompileRecording.jl#L293), [:322](../../../source/tool/precompile/PrecompileRecording.jl#L322) | one package, the repository, or an application |
| the recording of the builder itself | [tool/record-rebuild-calls.jl](../../../tool/record-rebuild-calls.jl) | a script, because a build can not run as a workload |
| the system image of a binary | [Executable.jl:436](../../../source/tool/builder/Executable.jl#L436) | PackageCompiler; the packages compile by the same preference |
| the linked executable and its prelink | [LinkedExecutable.jl:105](../../../source/tool/builder/LinkedExecutable.jl#L105), [:215](../../../source/tool/builder/LinkedExecutable.jl#L215) | a faster start of the binary |
| the reactive build | [ReactiveBuild.jl:365](../../../source/tool/builder/ReactiveBuild.jl#L365) | a rebuild in seconds, on the fork |
| `juliac --trim` | `tool/juliac-trim/` | a probe; nothing ships from it |
| the workload bodies | `run_display_workload`, `run_natural_rows_workload`, `run_window_workload`, `run_file_workload`, `run_sdl_window_workload`, `run_example_workload`, `warm_application` | what a package or the binary runs |

### J. The scripts of `tool/` and `bin/`

| Script | Lines | Job | Overlap |
| --- | ---: | --- | --- |
| `bin/projectured` | 63 | run the program from the checkout | — |
| `bin/build_projectured` | 39 | `tool/build-binary.jl projectured` under its own name | a wrapper |
| `tool/build-binary.jl` | 20 | the shell front end of `run_build_command` | — |
| `tool/record-rebuild-calls.jl` | 29 | record the calls of a rebuild | row 4 of table I |
| `tool/measure-compile-ahead.jl` | 136 | the measurements of the design | uses `ProjecturedPrecompile` |
| `tool/check-release-as-new-user.jl` | 149 | install and load as a new user | — |
| `tool/survey-arguments.jl` | 14 | the report of the argument guard | a wrapper |
| `tool/survey-interface.jl` | 150 | exported names that no test or guide names | its own file walker and parser, as each guard |
| `tool/widget-images.jl` | 123 | draw the widget examples and compare | its own list of example names |
| `tool/video/*.jl` | 13 scripts | record a feature video | the same helpers defined again in 5 scripts |
| `tool/assistant/rehearsal.jl`, `warm_session.jl` | 805, 59 | the fast loop of the assistant | drives the window by operations, without frames |
| `tool/search/*.jl`, `tool/juliac-trim/*` | — | experiments | — |

## Findings

### PB-1 An editor is driven by scripted input in eight ways, and most tests imitate the loop by hand

- **Kind:** several-ways · **Value:** high · **Effort:** large · **Confidence:** high
- **Principle:** First principle 3 (a person, the assistant and a test make the same operations) and 7 (one mechanism); PAR-ONE-WAY-TO-EDIT; PAR-LOWEST-PACKAGE.
- **Today:** Table F lists the drivers. Only one of them drives the window as a person does: `run_workload_steps!` of the platform takes typed steps (`WorkloadClick`, `WorkloadKey`, `WorkloadTyping`, `WorkloadWait`), finds each target in what the window drew (`DrawnText("Save")`, `DrawnPart(predicate)`), gives the inputs through the backend, and waits until the window is quiet ([ApplicationWorkload.jl:214](../../../source/platform/application/ApplicationWorkload.jl#L214)). It sits in the application slice under the name of compile ahead, and 2 test files use it. The other drivers:
  - `record_video` prints one projection and runs its own loop: `read_intent` at [VideoRecording.jl:157](../../../source/backend/video/VideoRecording.jl#L157), then `evaluate_operation` on `_VideoEditor`, a stand-in for the editor that shipped code defines ([VideoRecording.jl:9](../../../source/backend/video/VideoRecording.jl#L9)). The file of the second recorder says so: `VideoBackend` exists "rather than one bare projection printed by hand, the way `record_video` does it" ([VideoBackend.jl:4](../../../source/backend/video/VideoBackend.jl#L4)). So a video has two recorders.
  - `play_live!` of the kernel has a third loop and calls `read_intent` itself ([Playback.jl:40](../../../source/kernel/playback/Playback.jl#L40)).
  - Three backends without a device carry scripted input, each with its own queue: `WorkloadBackend` (platform), `HeadlessBackend` (example package of the kernel) and `VideoBackend`. `send_workload_inputs!` has one method per backend that can take a workload (2 today).
  - The generic test drivers use the stand-in `_ReplEditor` ([ReplTest.jl:18](../../../test/kernel/editor/ReplTest.jl#L18)). 198 test files call `read_intent` directly (1 116 calls). Tests define 51 stand-in editor types and call `evaluate_operation((document = x,), op)` with a named tuple 132 times.
  - Five scripts of `tool/video` define `glide`, `click`, `key`, `pause` and `move` again and address the window by more than 60 pixel pairs such as `SETTINGS_BUTTON = (334, 52)` ([record_settings.jl:18](../../../tool/video/record_settings.jl#L18)).
- **Example:**

  ```julia
  # Today, test/platform/projection/PaneRenameTest.jl: one of more than 100 local drivers.
  mutable struct _PaneRenameMockEditor
      document::Any
  end
  function _press!(editor, event)
      proj = _chain()
      iomap = print_document(proj, editor.document)
      op = read_intent(proj, iomap, event)
      op === nothing || evaluate_operation(editor, op)
      op
  end

  # Today, tool/video/record_settings.jl: the same click, by a pixel.
  click(SETTINGS_BUTTON)                       # (334, 52)

  # Today, the platform workload: the same click, by what the window draws.
  WorkloadClick(DrawnText("Settings"))

  # After (names are proposals): one script, one runner, any backend.
  editor = make_editor(document, projection; backend = DeviceLessBackend())
  run_script!(editor, [Click(DrawnText("Rename")), Typing("notes"), Key(:return)])
  @test get_pane_tab_title_string(tab) == "notes"
  run_script!(make_editor(document, projection; backend = VideoBackend(…)), steps)   # the video of the same steps
  ```
- **Problem:** A test that reads and evaluates by hand does not pass the fault barrier, the rooting of the operation, the inbox or the history of the editor, so it does not test what a person gets. A stand-in editor has only the fields that the test author thought of, so an operation that reads another field of the editor can not be tested this way. A video script breaks when a layout change moves a button by a pixel. A new backend must add its own method of `send_workload_inputs!` before a workload can run on it. Every new test file writes its own `press!`.
- **Proposal:** Make the typed steps and their targets one value type that knows no widget and no application, in the lowest package that can find a drawn part (the screen or graphics slice of the platform; the kernel for the steps that need no target). One runner gives the inputs of a step to the editor at the place where the input of a device enters the read stage, runs frames, and waits until the window is quiet. The script is then independent of the backend. A backend without a device becomes one real backend of the platform that reads every drawn part; the scripted part is the script, not the backend. A step may also carry an operation, as a timeline entry does today, so a script by operations (PAR-ONE-WAY-TO-EDIT) and a script by gestures share the runner. The test packages get one shared helper over a real `Editor` from `make_editor`.
- **What goes away:** the loop of `record_video` and `_VideoEditor`; the loop of `play_live!` and `_timeline_operation` (about 100 lines of `Playback.jl`); `_drive_workload_example!`; `warm_file_editor`; one of `WorkloadBackend` and `HeadlessBackend`; the per-backend `send_workload_inputs!`; `_ReplEditor`, 51 stand-in editor types and more than 100 local `press!`, `click` and key helpers in the tests; the helper block of 5 video scripts and their pixel constants.
- **What stays:** every test, with the same assertions; the video of a bare projection (a script on an editor with no window wrapper) and of the whole application; live playback at a wall-clock pace (a pace option of the runner on a real backend); `timed_await` (a wait step); the workloads of compile ahead; the generic sweeps over the examples.
- **Risk and open questions:** (1) Where the scripted input enters: a device, a feed, or the backend seam. This needs the owner, because it adds or moves a mechanism in the kernel. (2) A unit test of one reader may rightly call `read_intent` alone; the proposal is about tests that imitate the editor, not about every call. A count of how many of the 198 files are of which kind is still to make. (3) PAR-NO-TEST-DOUBLES-IN-MAIN sends `HeadlessBackend` to an example package while compile ahead needs the same thing in shipped code; the rule must say that a backend without a device is a real backend. (4) The frame of a real editor costs more than a hand loop; the sweeps over 142 examples may need the measurement first. (5) `Playback.jl` is in the kernel inventory of `SEALING.md` (not sealed today).
- **Related plans:** `plan/pending/feature-video-screenplays.md` (pending, writes more scripts in the pixel form); `plan/pending/live-example-construction.md` (in progress, adds one more stand-in, `_ConstructEditor`); `plan/pending/a-fast-loop-for-the-assistant.md` (pending, a driver "with no loop and no frames"); `plan/pending/packages-compose-by-seams.md` (in progress, gives `make_editor` and `build_editor`, which the runner would use); `plan/pending/kernel-audit-fixes.md` (pending; three open questions for the owner cover three of the drivers: L23-5, playback as a source of input around `run_editor!`; L23-4, one declared form of a timeline entry; L22-31 part 2, `walk_repl_loop` through a real `Editor`). None unifies all the drivers. Other areas: kernel editor and playback, backends, platform application, the test suites of every domain.
- **Check:** confirmed-with-corrections. I opened each cited file and counted again: 198 test files call `read_intent` (1 117 matches), 52 `…Editor` structs in the tests (two of them are no stand-in), 132 calls of `evaluate_operation` with a named tuple in 35 files, 118 test files with `HeadlessBackend`, 53 pixel constants and the helper block in 5 of the 14 video scripts. The loops of `record_video`, `play_live!` and `_drive_workload_example!` are as cited. Corrections:
  1. "Most tests" is too strong. 198 of 676 test files call `read_intent`, and 112 test files already run `run_frame!` on a real `Editor`.
  2. The report missed `plan/pending/kernel-audit-fixes.md`. Three parts of this finding stand there as open questions for the owner, each with a recommendation: L23-5 (playback becomes a source of input around `run_editor!`), L23-4 (one declared form of a timeline entry for `record_video`, `VideoBackend` and `play_live!`) and L22-31 part 2 (`walk_repl_loop` through a real `Editor` and `run_frame!`). These three parts are covered by that plan.
  3. "Every test, with the same assertions" does not hold for the sweep over the examples. The plan states that through the real read stage an Escape that no reader takes quits, and that the zoom keys and the pairing of press and release change what each example reports. The sweep needs a new baseline of its broken records.
  4. `run_workload_steps!` waits 0.25 s of wall time before each step (`_QUIET_WINDOW_SECONDS`, [ApplicationWorkload.jl:152](../../../source/platform/application/ApplicationWorkload.jl#L152)). A runner for tests needs a mode that runs frames until nothing waits, or the 1 100 gestures of the tests cost minutes.
  5. The tests make the same operations through the same readers; what they skip is the frame. So first principle 3 is bent, not broken. The frame is still worth it: the plan records that a stand-in hides the faults of IO map reuse.

  New in this finding and in no plan: the typed steps as the one form of a script, one backend without a device in place of `WorkloadBackend` and `HeadlessBackend`, the 51 stand-in editors of the tests, and the pixel scripts of `tool/video`. A unit test of one reader keeps its direct call of `read_intent`. No feature is lost when points 3 and 4 are solved. Value stays high; the move of the tests is the large part and can come after the driver.

### PB-2 The list of the packages is written by hand in about twelve places, and the copies have drifted

- **Kind:** repeated-by-hand · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** First principle 7 (a missing case gets its row in the generic mechanism) and 11; PAR-PARALLEL-TRIADS.
- **Today:** Table C. The folder `package/` and the `[deps]` of each `Project.toml` are the truth, and Julia needs them. Beside them, the same lists stand in the import list and in `_SOURCES` of `ProjecturedAll`, in `ProjecturedBuild`, in `PROJECTURED_APPLICATION_IMPORTS`, in the umbrellas of the examples and of the tests (a `using` list and a loop list each), in the body of `test_all()`, in the CI matrix and in `environment/all`. What I checked of the drift:
  - The CI matrix has no row for `ProjecturedACPTest`, `ProjecturedPivotTest` and `ProjecturedPrecompileTest` ([CI.yml:57](../../../.github/workflows/CI.yml#L57)).
  - `test_all()` calls 28 of the 39 package suites; it does not call `test_builder`, `test_console`, `test_mcp`, `test_odbc`, `test_openrouter`, `test_pdf`, `test_precompile`, `test_sdl`, `test_tulip`, `test_video`, `test_web` ([ProjecturedSuite.jl:476](../../../test/projectured/ProjecturedSuite.jl#L476)). Its docstring says "the twenty domain test packages"; the table of the domains has 21.
  - `ProjecturedTest` does not load `ProjecturedBuilderTest`, `ProjecturedOpenRouterTest` and `ProjecturedPrecompileTest`.
  - 784 `[sources]` lines repeat the `[deps]` line above them as `Name = {path = "../Name"}`; 22 such lines are missing in 6 packages (`ProjecturedTest`, `ProjecturedREPL`, `ProjecturedAdaptagrams`, and the example packages of ODBC, Tulip and Adaptagrams), so these resolve only inside `environment/all`. For the opt-in example packages this is a stated choice, not drift ("it resolves through the root env (no [sources])", `package/ProjecturedODBCExample/Project.toml:6`).
  - The guard `test_package_graph()` already computes the `Projectured*` packages that the source of a package names (`_named_packages`, [PackageGraphTest.jl:218](../../../test/projectured/PackageGraphTest.jl#L218)) and then only compares the set with `[deps]`.
  - Two places do derive: the release finds the suite of a package as `<Name>Test` and `test_<name>()` ([ProjecturedProgram.jl:760](../../../source/tool/builder/ProjecturedProgram.jl#L760)), and the recording walks the folder.
- **Example:**

  ```julia
  # Today: a new domain ProjecturedTOML needs an edit in each of these.
  #   package/ProjecturedAll/Project.toml               2 lines
  #   package/ProjecturedAll/src/ProjecturedAll.jl      import ProjecturedTOML
  #   source/all/ProjecturedAll.jl                      _SOURCES
  #   package/ProjecturedBuild/{src,Project.toml}       3 lines
  #   source/tool/builder/ProjecturedProgram.jl         PROJECTURED_APPLICATION_IMPORTS, the README row
  #   package/ProjecturedExample/{src,Project.toml}     using, the loop list, 2 lines
  #   test/projectured/ProjecturedSuite.jl              using, the loop list, test_toml() in test_all()
  #   package/ProjecturedTest/Project.toml              2 lines
  #   .github/workflows/CI.yml                          one matrix row
  #   environment/all/Project.toml                      6 lines
  #   test/projectured/PackageGraphTest.jl              DOMAIN_EDGES (a rule: stays by hand)

  # After (names are proposals).
  const _SOURCES = load_declared_dependencies(@__MODULE__)     # the [deps] of this package, in load order
  test_all() = (run_guards(); foreach(run_package_suite, collect_test_packages()); test_integration())
  ```
- **Problem:** A new package is a search for a dozen lists, and a miss is silent: a suite that is in no list is not run. The lists of `ProjecturedAll`, `ProjecturedBuild` and the builder say three times which packages make the product. The next domain repeats all of it.
- **Proposal:** Keep two facts by hand: the folder of the package, and the rule tables (`DOMAIN_EDGES`, the leaves). Derive the rest.
  1. An aggregate package (`ProjecturedAll`, `ProjecturedBuild`, the two umbrellas) reads its own `[deps]` once, at the top of its entry file, and imports and binds what it finds. The `using` list, `_SOURCES` and the loop list are then one call.
  2. `test_all()` and the CI matrix take the test packages from the folder and the suite name from the stem, as the release already does. A package that must stay out says so in one table with the reason.
  3. One small tool writes the `Projectured*` lines of `[deps]` and every `[sources]` line of all 117 project files from what the source names, with the function that the guard has. The guard then asserts that the files are in step with the tool. `environment/all` is written by the same tool.
- **What goes away:** about 10 hand lists of 23 to 36 names; the 28 calls of `test_all()`; the 36 rows of CI as text; hand upkeep of about 1 600 lines of `[deps]` and `[sources]`; the builder constant `PROJECTURED_APPLICATION_IMPORTS` (the imports of `ProjecturedBuild` are the same list).
- **What stays:** every package and its `Project.toml` as Pkg needs it; the rule that `ProjecturedAll` holds no third-party dependency (a filter by the kind of package, checked by the guard); a suite that needs a database or a display stays out by a named exception; the release copy.
- **Risk and open questions:** A `Core.eval` of `import` in a loop at the top of an entry file works during precompilation (the binding loop does the same today), but the load order of the aggregate must stay a dependency order, so the reader must sort. Whether a Julia workspace (`[workspace]` in a root project file) could replace the `[sources]` lines is not checked here. The CI matrix can come from a job that lists the folder, or stay a file that a guard compares with the folder; the second is smaller.
- **Related plans:** `plan/pending/package-convention-repl-leaves.md` (in progress; sets the kinds and the leaf rule, not the lists); `plan/done/mechanize-umbrella-reexports.md` (done; replaced 846 hand lines of one umbrella by a loop, the same idea one level lower); `plan/pending/release-the-binary-and-the-packages.md` (first release done; keeps the repository layout).
- **Check:** confirmed-with-corrections. Counted again: 117 packages and 40 test packages; the CI matrix has 38 rows (36 test packages, and `ProjecturedTest` twice) and no row for ACP, Pivot and Precompile; `test_all()` names 28 of the 39 suites; `ProjecturedTest` loads 36 of the 39; 806 `Projectured*` lines of `[deps]`, 788 `[sources]` lines, 22 missing in 6 packages. The lists of `ProjecturedAll`, `ProjecturedBuild` and the builder are as cited. Corrections:
  1. The drift is worse than stated in one place. CI runs `test_integration` and `test_repository`, not `test_all()`, so `test_acp()`, `test_pivot()` and `test_precompile()` run in no CI job. `test_integration` calls 2 of the 23 functions of `test_sdl()` and 1 of the 7 of `test_video()`, so `test_all()` is not the full suite that its docstring says.
  2. "A miss is silent" holds only for the lists with no guard. `test_package_graph()` keeps each import list equal to `[deps]` ([PackageGraphTest.jl:342](../../../test/projectured/PackageGraphTest.jl#L342)), `test_builder()` keeps `PROJECTURED_APPLICATION_IMPORTS` equal to the dependencies of `ProjecturedAll` (`test/tool/builder/BuilderTest.jl:160`), and `documentation/design/domain-inventory.md:128` lists the steps for a new domain. The lists with no guard are the CI matrix, the body of `test_all()`, the loads of `ProjecturedTest`, and the question whether a new domain is in `ProjecturedAll` at all.
  3. Steps 1 and 3 of the proposal are circular for the four aggregates: the entry file would read `[deps]`, and the tool would write `[deps]` from what the source names. So the `[deps]` of an aggregate stays the one list by hand, or follows from the kind of a package, which no file declares today. A new domain still edits about five project files; the "After" is smaller than drawn.

  No feature is lost. Value: medium (was high). Guards hold half of the lists today, and a guard that compares the CI matrix and `test_all()` with the folder closes the gap of point 1 at a small cost; the derivation is the cleaner end state.

### PB-3 An example is declared in up to six places, and its sweeps are chosen by lists of names

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** PAR-LOWEST-PACKAGE ("for a test or example, the fixture determines the home"); first principle 5 (domains are independent) and 7.
- **Today:** The type `Example` is a name, a function that makes the document and a function that makes the projection ([Harness.jl:15](example/kernel/Harness.jl#L15)).
  - The factory of a JSON example is in the JSON example package, and that package exports it by hand ([ProjecturedJSONExample.jl:48](../../../package/ProjecturedJSONExample/src/ProjecturedJSONExample.jl#L48)). The `Example` value `json_example` is in the umbrella ([DomainExamples.jl:9](example/projectured/DomainExamples.jl#L9)), with the examples of all 21 domains. So `test_printer(json_example)` needs the two umbrellas: `ProjecturedExample` holds the value and loads every domain, Anthropic and Ollama (not SDL, Video, ODBC or Tulip), and `ProjecturedTest` holds the `Example` method of `test_printer` and loads the test packages of SDL, Video, ODBC and Tulip.
  - Four packages do own their list: the platform, ODBC, Tulip and Adaptagrams (table G).
  - The global list `examples` is a third hand list. 45 examples of the two lists below it are not in it. Seven comments say why for about ten of them ("deliberately kept OUT": an endless list, a stateful document, no caret, a slow computation), each because one sweep does not apply; for the others I found no stated reason.
  - For the examples that are in the list, the sweeps decide by name: `startswith(example.name, "widget")`, `endswith(example.name, "_widget")`, `startswith(example.name, "workflow")` and a list of about 40 names in `test_position_navigations` ([ExampleSweeps.jl:228](../../../test/projectured/editor/ExampleSweeps.jl#L228), [:246](../../../test/projectured/editor/ExampleSweeps.jl#L246)); the same prefix test stands at [:357](../../../test/projectured/editor/ExampleSweeps.jl#L357), [:470](../../../test/projectured/editor/ExampleSweeps.jl#L470) and [:556](../../../test/projectured/editor/ExampleSweeps.jl#L556).
  - The type has a field for this, `terminal` ("the single pivot the discovered catalog uses to decide which tests apply", [Harness.jl:38](example/kernel/Harness.jl#L38)), but only the generated examples set it.
  - "Which examples are widget examples" has four answers: the prefix test in the sweeps, in the screenshots ([ProjecturedExamples.jl:194](example/projectured/ProjecturedExamples.jl#L194)), in a test, and the hand list `WIDGET_EXAMPLES` of a tool ([widget-images.jl:23](../../../tool/widget-images.jl#L23)).
  - The lookup by name, `findfirst(ex -> ex.name == name, examples)`, is written six times ([ProjecturedExamples.jl:95](example/projectured/ProjecturedExamples.jl#L95) to [:148](example/projectured/ProjecturedExamples.jl#L148)).
- **Example:**

  ```julia
  # Today: a new example of the JSON domain.
  #   example/domain/json/JsonDocumentExample.jl          the factory
  #   package/ProjecturedJSONExample/src/…                export make_json_sorted_document_example
  #   example/projectured/DomainExamples.jl               const json_sorted_example = Example("json_sorted", …)
  #   example/projectured/DomainExamples.jl               the entry in domain_examples
  #   example/projectured/ProjecturedExamples.jl          the entry in examples, or a comment why not
  #   package/ProjecturedExample/src/ProjecturedExample.jl  export json_sorted_example
  #   test/projectured/editor/ExampleSweeps.jl            its name in each skip list that applies

  # After (names are proposals): the JSON example package owns its examples and says what applies.
  const json_examples = Example[
      Example("json", make_json_document_example, make_json_projection_example),
      Example("json_sorted", make_json_document_example, make_json_sorted_projection_example),
  ]
  Example("lazy", make_lazy_document_example, make_lazy_projection_example; endless = true)
  Example("widget_card", …; caret = false)          # no sweep that needs a caret
  # The umbrella joins the lists of the loaded example packages; a sweep filters by the property.
  ```
- **Problem:** A domain can not test its own example in its own environment. An example that is kept out of `examples` is also out of `run_example("name")`, out of the screenshots and out of the workload, though only one sweep was the reason. A new widget example works in the sweeps only because its name starts with `widget`. The umbrella must be edited for every example of every domain.
- **Proposal:** Each example package holds the `Example` values of its own domain in one list with a fixed name pattern, as four packages do today. The umbrella keeps only the examples whose fixture joins several domains, and builds the global registry by joining the lists of the packages it loads. An example states the properties that the sweeps need (it has no caret; it is endless; it is stateful; it is slow), and each sweep filters by a property. Every example is then in the one registry. The exports of an example package come from its list and its factories by the rule that the main packages use, not from 646 hand lines.
- **What goes away:** `domain_examples` and the hand list `examples` as separate lists; the exclusion from the registry as the way to skip a sweep; the name tests and the name list in the sweeps (about 60 lines); `WIDGET_EXAMPLES`; five of the six lookups; most of the 646 hand export lines and the 266 export statements of `ProjecturedExample.jl`.
- **What stays:** every example and its name; `run_example("json")`; the sweeps and their `@test_broken` records (a broken example is a different thing from a sweep that does not apply); the generated catalog and its `domain/name/variant` names; the cross-domain examples in the umbrella.
- **Risk and open questions:** The done plan `split-domain-into-per-domain-packages.md` kept the registry whole because a split "would have reordered the registry and put the catalog comparison out of use"; that was a reason of the migration, and an explicit order of the packages keeps the order. The set of properties must be small; four seem enough for the reasons that the seven comments give today. The 35 or so examples that are out of the registry with no comment need a look each. The list `BRIDGES` of the catalog ([Catalog.jl:34](example/projectured/Catalog.jl#L34)) is a second table of "which projection takes a domain to syntax", beside the natural notation of the platform; a file of the same folder warns against exactly that ([Precompile.jl:18](example/projectured/Precompile.jl#L18)). That part belongs to the area of the natural notation.
- **Related plans:** `plan/pending/packages-compose-by-seams.md` step 8 (open: the 14 keywords of `make_example_editor` become wrappers; it does not touch the registries); `plan/pending/live-example-construction.md` (in progress; a new sweep over the examples); `plan/pending/test-suite-green.md` (in progress; the broken records).
- **Check:** confirmed-with-corrections. Counted again: 202 `Example` constants (104 in `PlatformExamples.jl`, 86 in `DomainExamples.jl`), 142 names in `examples`, 83 in `domain_examples`, 6 lookups by name, and the name tests at the cited lines of `ExampleSweeps.jl`. PAR-LOWEST-PACKAGE supports the move: the fixture of `json_example` names only the JSON example package. The done plan says that the registry "stayed whole, against the plan", and gives the order as the one reason. Corrections:
  1. Which umbrella loads SDL, Video, ODBC and Tulip (corrected above).
  2. `examples` is one curated order that mixes the tiers: JSON, YAML and XML, then the text and widget examples of the platform, then the domains again. `run_example(examples)` shows that order. A join of the lists of the packages changes it, so the order needs a key, or the umbrella keeps one ordered list of names.
  3. The skip lists of the sweeps do not record properties of an example. Their comments say that Ctrl+Home seeds no selection in a widget container, which is a limit of the keyboard routing (the deferred plan `tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md` is about that reach). `caret = false` on a widget example would be a false statement: the shown text of a widget takes a caret and a selection (settled: widget text is read-only, with its mouse and key selection). A property must name what the sweep needs, for example "Ctrl+Home seeds a selection", or the sweep must measure it and skip. Endless, stateful and slow are real properties of an example.

  With points 2 and 3 no feature is lost. Value stays medium.

### PB-4 The entry file of a package repeats one loop in 88 files, and a guard demands two workload lines that the method table knows

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** First principle 7; `package-rules.md` ("a package is a name and an include list").
- **Today:** A source file names a module of a lower package as a sibling, `using ..SyntaxModule`. So the entry file of each package binds every submodule of the packages below as a constant, with a loop. 88 entry files hold that loop in four texts: 35 bind only, 51 also import every exported name (the flat namespace of the test and example files), and two files hold a form of their own, one of them the example umbrella ([ProjecturedJSON.jl:22](../../../package/ProjecturedJSON/src/ProjecturedJSON.jl#L22), [ProjecturedJSONExample.jl:27](../../../package/ProjecturedJSONExample/src/ProjecturedJSONExample.jl#L27)). The platform, the umbrella of the tests and `source/all` hold three more forms ([ProjecturedPlatform.jl:21](../../../package/ProjecturedPlatform/src/ProjecturedPlatform.jl#L21), [source/all/ProjecturedAll.jl:18](../../../source/all/ProjecturedAll.jl#L18)). The done plan that introduced the loop names the copies of its guard that had to be relaxed: the umbrella, the example package, the test package and the code runner of the kernel.
  Around the loop, each file repeats its dependencies a third time (`using`, then `_SOURCES`; 53 files), a loop that exports the names of its slice module (29 files), and, for a domain, two workload lines (17 entry files hold `run_natural_rows_workload`, and 13 of them also `run_file_workload`). Two guards find by a regular expression over the source whether a package needs these lines, and fail when the entry file does not hold them ([PackageGraphTest.jl:421](../../../test/projectured/PackageGraphTest.jl#L421), [:437](../../../test/projectured/PackageGraphTest.jl#L437)). The platform already reads the same fact from the method table: `collect_workload_file_types()` lists each type with a method of `make_workload_file` ([DisplayWorkload.jl:239](../../../source/platform/display/DisplayWorkload.jl#L239)). Because a loop makes the bindings, the layering guard can not read them, so each of 38 suite files passes them as `extra_aliases` ([JsonSuite.jl:8](../../../test/domain/json/JsonSuite.jl#L8)).
- **Example:**

  ```julia
  # Today: package/ProjecturedJSON/src/ProjecturedJSON.jl, 51 lines; the same 13 lines in 35 files.
  using ProjecturedKernel
  using ProjecturedPlatform
  for _src in (ProjecturedKernel, ProjecturedPlatform)
      for _n in names(_src; all = true)
          isdefined(_src, _n) || continue
          _m = getfield(_src, _n)
          (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
          Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
      end
  end
  include("../../../source/domain/json/JsonModule.jl")
  using .JsonModule
  for _n in names(JsonModule)
      _n === :JsonModule || Core.eval(@__MODULE__, Expr(:export, _n))
  end
  @compile_ahead begin
      run_natural_rows_workload(JsonModule)
      run_file_workload(JsonModule.JsonFile)
  end

  # After (names are proposals).
  @bind_dependencies                                   # the loop, once; reads [deps] of this package
  include("../../../source/domain/json/JsonModule.jl")
  @export_module JsonModule
  @compile_ahead run_domain_workload(JsonModule)       # its rows, and each workload file that the module defines
  ```
- **Problem:** A fix of the loop is 88 edits; the plan that made the loop records four places where the guard of the loop was wrong. A new domain copies 40 lines that carry no fact of the domain. The two workload guards check a hand copy of a fact that the code can read.
- **Proposal:** One definition of the binding, in the lowest package that every package with source loads (the kernel, or a small package beside `ProjecturedPrecompile`), with two modes: bind the modules, or also import the exported names. It reads the dependencies from the project file of the calling package, so `_SOURCES` goes away with PB-2. One definition of the re-export. One function `run_domain_workload(module)` that runs the registrations of the module and the file workload of each type whose `make_workload_file` method the module defines. The layering guard learns the one macro and needs no `extra_aliases`.
- **What goes away:** about 1 100 lines of loops in 88 files; 53 `_SOURCES` tuples; 29 re-export loops; the workload lines of 17 entry files; two guards of `PackageGraphTest.jl` (about 30 lines); the `extra_aliases` argument and its 38 call sites.
- **What stays:** the include list of each package, which is its real content; `using ..XxxModule` in every source file (PAR-QUALIFIED-EXTENSION is not touched); the flat namespace of the test and example files; one `@compile_ahead` per entry file, with a workload of its own where a package needs one.
- **Risk and open questions:** The other shape is to remove the need: a domain file names `ProjecturedPlatform.SyntaxModule` and no binding exists. The done plan rejected it "for now" because of the size of the diff, which has no weight under first principle 11; but it changes PAR-QUALIFIED-EXTENSION, so it is the owner's choice. A macro that reads `Project.toml` must register the file with `include_dependency`, so that a new dependency builds the package again. `run_natural_rows_workload` on a module with no rows only runs its initializers and builds one projection ([DisplayWorkload.jl:179](../../../source/platform/display/DisplayWorkload.jl#L179)); I did not measure that cost.
- **Related plans:** `plan/done/split-domain-into-per-domain-packages.md` (done; chose the loop and named the alternative); `plan/done/mechanize-umbrella-reexports.md` (done); `plan/pending/packages-compose-by-seams.md` (in progress; its decision C7 keeps the registrations in `__init__` for now, which is why `run_natural_rows_workload` exists).
- **Check:** confirmed-with-corrections. Counted again, the loop by the hash of its text: 88 entry files, 4 texts (51 + 35 + 1 + 1); `_SOURCES` in 53 entry files; the re-export loop in 29; `run_natural_rows_workload` in 17 entry files and `run_file_workload` in 13 of them; `extra_aliases` in 38 suite files (counts corrected above). No plan in `plan/pending` or `plan/tentative` covers the loop. The rule of the two workload lines stands in `documentation/rule/package-rules.md:50`, the two guards read it by a regular expression, and `collect_workload_file_types()` shows that the method table holds the same fact. Corrections to the proposal:
  1. "The layering guard learns the one macro and needs no `extra_aliases`" needs more than said: a static guard would have to find the submodules of every package below from their source. The cheap form is one generic function that measures the set from the loaded package; it removes the 38 copies too (see PB-5).
  2. Only 38 entry files load `ProjecturedPrecompile` today. A macro in a package of the tool kind is one new dependency for about 50 test and example packages. A macro in the kernel is in direct reach of 85 of the 88 packages that hold the loop, but it puts package plumbing into the kernel. The home is a choice for the owner.

  No feature is lost: the include list, `using ..XxxModule` and one `@compile_ahead` per entry file stay. Value stays medium.

### PB-5 A test is registered three times by hand, and the contract tests of a domain are copies

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** First principle 7; PAR-PARALLEL-TRIADS ("registering … means editing the package's entry module").
- **Today:** A new test file needs an `include` line in the entry file of its test package (557 such lines, and 80 more in `ProjecturedSuite.jl`), a call in the aggregator of the suite file, and a name in an `export` statement (159 `export` lines in the suite files, 222 in all test files). Nothing checks the second step. Of 819 test functions without arguments, 9 that I checked one by one are called by no aggregator, for example `test_command_palette`, `test_gesture_log`, `test_marker_vocabulary` and `test_syntax_tree_selection` ([CommandPaletteTest.jl:20](../../../test/projectured/projection/CommandPaletteTest.jl#L20), [MarkerVocabularyTest.jl:39](../../../test/projectured/serializer/MarkerVocabularyTest.jl#L39)); the guide names one of them, `test_recursion_contracts`, as opt-in. Each of 39 suite files defines `test_<slice>_layering()` with the same 12 lines ([YamlSuite.jl:6](../../../test/domain/yaml/YamlSuite.jl#L6), [OllamaSuite.jl:6](../../../test/adapter/ollama/OllamaSuite.jl#L6)), and the naming guard demands that function by name ([naming.jl:223](../../../test/suite/naming.jl#L223)).
  The generic drivers show the other way: `test_printer(example)` serves every domain. But the tests of what every domain must do are copies with the names changed: 17 files `*ThemeTest.jl` of the domains and one adapter (24 with the 7 of the platform) and 4 files `*FileNoteTest.jl`. I compared two pairs: the JSON and YAML theme tests differ in the sample text and one field name, and the JSON and YAML file note tests differ in the sample and the type names; the YAML copy still says "a JSON file" in its test set title ([YamlFileNoteTest.jl:16](../../../test/domain/yaml/document/YamlFileNoteTest.jl#L16)). Each copy carries its own helpers under a prefix (`_jfn_`, `_yfn_`), because the test packages share one namespace in the umbrella.
- **Example:**

  ```julia
  # Today: test/domain/yaml/YamlSuite.jl, and the same in 38 other files.
  function test_yaml_layering()
      main = get_package_source_root(ProjecturedYAML)
      check_layering(main, pathof(ProjecturedYAML); name = "yaml",
                     extra_aliases = Set{Symbol}(n for n in names(ProjecturedYAML; all = true) if …))
  end
  function test_yaml()
      @testset "ProjecturedYAML" begin
          test_yaml_layering(); test_yaml_parser(); test_yaml_file_note(); test_yaml_theme()
      end
  end
  export test_yaml, test_yaml_layering, test_yaml_parser, test_yaml_theme, test_yaml_file_note

  # After (names are proposals).
  @test_package ProjecturedYAML                 # includes test/domain/yaml/**, defines test_yaml() over its suites
  test_file_note(YamlFile, "a.yaml", "users:\n  - name: Alice\nmy key: 2\n";
                 container = YamlSequence)      # one contract in the platform test package, one row per domain
  ```
- **Problem:** A suite that nobody calls passes forever. The next domain copies a theme test and a file note test and renames 20 names. A change of the contract (what a file note says) is an edit of four files.
- **Proposal:** The test package finds the files of its folder, as the layering guard already asserts for source that every file on disk is reached. A suite marks itself (a macro at its definition, with `optin = true` for a slow one or one that needs a database), and the aggregator of the package is the list of the marked suites, so "defined and never run" can not happen in silence. `test_<slice>_layering()` is one generic function of the kernel test package that takes the package. A test of a contract that every domain meets is one function in the lowest test package that can state it, with a row of data per domain; the test package of the domain calls it with its row.
- **What goes away:** 637 include lines; the hand aggregators and their export statements; 39 copies of the layering function; the bodies of about 20 copied contract tests; the helper prefixes.
- **What stays:** one test package per stem and its own environment; `test_json()` and every single `test_*` name that a person runs at the prompt; opt-in suites; the tests that are special to a domain.
- **Risk and open questions:** I compared 2 of the 17 theme tests and 2 of the 4 file note tests; the others differ in length (23 to 68 lines), so some check more than the common contract. The include order of test files matters in at least one place ("after the file above", [ProjecturedSuite.jl:173](../../../test/projectured/ProjecturedSuite.jl#L173)); a found order must be stable or the files must not depend on each other. That the theme tests are copies points at a theme mechanism that each domain repeats; that part belongs to the area of the domains.
- **Related plans:** `plan/pending/test-suite-green.md` (in progress; the failing tests, not the structure); `plan/pending/naming-rule-violations.md` (pending; names).
- **Check:** weakened. The facts hold (counts corrected above): 557 `include` lines in `package/*Test/src` and 80 in `ProjecturedSuite.jl`; 39 layering functions with one body; `test_command_palette`, `test_gesture_log`, `test_marker_vocabulary`, `test_syntax_tree_selection` and `test_recursion_contracts` have no caller, though `ProjecturedSuite.jl` includes the file of each. The JSON and YAML theme tests differ in three lines, the two file note tests in the sample and the names. The proposal is larger than the fault, and one part loses something:
  1. A guard of about 30 lines ("each test function with no argument is called by an aggregator, or stands in a table of opt-in suites with its reason") closes the gap. A marker on 819 functions is not needed for it.
  2. A test package that finds its files loses the include order that some files need ([ProjecturedSuite.jl:173](../../../test/projectured/ProjecturedSuite.jl#L173)), and a new test file in a running session: today the new `include` line brings it in through Revise, and a folder that is read at load time does not.
  3. The copied contract tests are small: 4 files of about 40 lines and 17 files of 23 to 68 lines. They are copies because each domain repeats the theme code itself, so the larger gain is in the domains, as the report says.

  What holds: one generic layering function in the kernel test package (39 copies go), the guard of point 1, and one contract function with a row per domain. Value: medium for these three parts; the discovery of the files should be dropped.

### PB-6 The static guards share a shape but no code

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** First principle 7.
- **Today:** Table H. Six guards of `test/suite` answer `X_violations(root) -> Vector{String}` and can run alone, which is a good common shape. Beyond that each stands alone. Each walks the tree itself (25 `walkdir` calls in nine files) from its own list of roots ([arguments.jl:30](../../../test/suite/arguments.jl#L30), [exports.jl:23](../../../test/suite/exports.jl#L23), [style.jl:32](../../../test/suite/style.jl#L32)). They read Julia source in three ways: `Meta.parseall`, `Base.JuliaSyntax` and regular expressions per line. Exceptions have five forms: a comment `# @optional:`, a comment `# @style:`, a set of file names, a set of function names, a keyword argument. Each has its own main block, and the test wrapper is the same eight lines six times ([ProjecturedSuite.jl:305](../../../test/projectured/ProjecturedSuite.jl#L305), [:431](../../../test/projectured/ProjecturedSuite.jl#L431)). The guard that protects the guards, `guard_root_violations` ("every directory a guard walks exists"), names two of the nine files ([tree.jl:244](../../../test/suite/tree.jl#L244)). The `test_*` wrappers of the six guards live only in `ProjecturedTest`, the package that loads everything, while the layering guard lives in the kernel test package. `tool/survey-interface.jl` is a tenth walker with its own parser.
- **Example:**

  ```julia
  # Today: six times, one per guard.
  function test_style()
      @testset "style" begin
          root = normpath(joinpath(@__DIR__, "..", ".."))
          for violation in style_violations(root)
              @test violation == ""
          end
          @test isempty(style_violations(root))
      end
  end

  # After (names are proposals): a rule is a function of one parsed index of the repository.
  const GUARDS = [:tree => tree_violations, :naming => naming_violations, :style => style_violations, …]
  index = read_source_index(root)                     # walks once, parses each file once, reads each `# @name: reason` marker
  test_guards() = foreach(guard -> run_guard(guard, index), GUARDS)
  ```
- **Problem:** A new rule copies a walker, a parser choice and an exception form. A moved folder must be fixed in each list of roots, and the guard that would notice covers two files. A rule that reads the syntax tree and a rule that reads lines can disagree on what is code and what is a comment.
- **Proposal:** One guard module with no dependency (so it still runs with a bare Julia): one index of the files, read once; one parse of each Julia file; one marker form `# @<rule>: <reason>` and one table form for an exception with its reason; one runner and one test wrapper over a table of rules. Each rule keeps its logic. The walk roots are one constant, so `guard_root_violations` covers every rule. The layering guard and the package graph guard become rules of the same module.
- **What goes away:** 20 or more of the 25 walks; the six wrappers; the per-file main blocks; the hand list inside `guard_root_violations`; the second parser of `tool/survey-interface.jl`.
- **What stays:** every rule and every exception that stands today; `julia test/suite/<rule>.jl` with no environment (a file per rule can stay as a three-line entry); the CI job that runs the guards without a package.
- **Risk and open questions:** `ProjecturedTest` includes `test/suite/*.jl`, and `test_package_graph()` asserts that a package declares exactly what its source names, which is why `tree.jl` reads TOML keys by a regular expression ([tree.jl:19](../../../test/suite/tree.jl#L19)); a guard module must keep that property or become a package of its own. `Base.JuliaSyntax` is the parser of the Julia in use; one parser for all rules ties them to it.
- **Related plans:** `plan/pending/export-block-rule.md`, `plan/pending/naming-rule-violations.md`, `plan/pending/kernel-audit-fixes.md` (each adds or uses a guard; none joins them).
- **Check:** weakened. The counts hold: 25 `walkdir` calls in 9 files, six main blocks, six wrappers of one shape, and `guard_root_violations` names 2 guards while its docstring says "every guard in this repository that walks the tree is named here". The difference is smaller than stated:
  1. The three ways to read source follow from what each rule reads. The style guard reads lines and comments, the documentation guard reads Markdown, the tree guard reads directory entries, the package graph guard reads `Project.toml` files and `using` lines, the argument and export guards read signatures as `Expr`, and the naming guard needs the positions that `Base.JuliaSyntax` gives. "One parse of each Julia file" serves five of the ten rows of table H (naming, arguments, exports, layering, the survey); the other five read text that a parse drops, or files that are no Julia.
  2. The exception forms are two, not five: a marker comment at the place (`# @style:`, `# @optional:`, as `# @broken:` in a test) and a table with a reason for a whole file or name. Both fit their case.
  3. The layering guard and the export collision guard read the loaded package (`extra_aliases`, the loaded modules). They can not join a module with no dependency, which the proposal asks for, before PB-4 changes how the bindings are made.
  4. What the guards truly share is the walk, the wrapper and the main block: about 150 of 2 200 lines. A source index is a framework for six rules.

  What holds: one constant of the walk roots, so that `guard_root_violations` covers every guard, and one wrapper `run_guard(name, violations)`. Every rule and the run of each file with a bare Julia stay. Value: low (was medium).

### PB-7 Parts of earlier compile-ahead and file-editor schemes are still exported

- **Kind:** redundant · **Value:** low · **Effort:** small · **Confidence:** high
- **Principle:** First principle 11; `compile-ahead.md` ("one mechanism").
- **Today:** `warm_file_editor` has no caller and is exported twice ([FileEditor.jl:213](example/projectured/FileEditor.jl#L213), [ProjecturedExample.jl:286](../../../package/ProjecturedExample/src/ProjecturedExample.jl#L286)). The file around it defines `EditorDomain`, the table `EDITOR_DOMAINS`, `build_file_editor` and `run_file_editor`: a file editor with its own table of how each domain makes, loads and saves a document. No test, tool or script calls any of them; the platform opens a file by its file format slice. `precompile_atoms` and `precompile_atom_parsers` compile nothing for a package of this repository; two tests use them to count the atoms that print and parse ([Precompile.jl:25](example/projectured/Precompile.jl#L25), `CatalogCoverageTest.jl:72`). (Corrected by the check: the downstream repository omnet-julia calls `precompile_atoms` in its precompile workload, `demo/Precompile.jl:87`, so there the name says what the call is for.) `environment/all/LocalPreferences.toml` sets `[ProjecturedREPL] workload = "recorded"` (corrected by the check: git ignores this file, `.gitignore:42`, so it is a file of this machine and no part of the repository); the mechanism reads only `precompile_calls` and `precompile_failure` ([PrecompilePreferences.jl:50](../../../source/tool/precompile/PrecompilePreferences.jl#L50)), and `ProjecturedREPL` has no `@compile_ahead`. The workload of the binary is named `warm_application` ([ApplicationWorkload.jl:649](../../../source/platform/application/ApplicationWorkload.jl#L649)) beside six functions named `run_…_workload`.
- **Example:**

  ```julia
  # Today
  export EditorDomain, EDITOR_DOMAINS, editor_domain, build_file_editor, run_file_editor, warm_file_editor
  renders(a) = precompile_atoms([a]) == 1          # a test

  # After
  # FileEditor.jl is gone; the application opens a file.
  renders(a) = count_printed_atoms([a]) == 1       # a name for what the function answers
  ```
- **Problem:** A reader finds two ways to open a file in an editor and two vocabularies for compile ahead, and must find out that one of each is dead.
- **Proposal:** Remove `FileEditor.jl` and its exports (243 lines), or move what a caller still needs behind `build_editor`. Give the two atom walks the name of what they answer. Remove the dead preference. Name the workload of the binary as the others.
- **What goes away:** `EditorDomain`, `EDITOR_DOMAINS`, `EXTENSION_DOMAINS`, `build_file_editor`, `run_file_editor`, `warm_file_editor`; one preference line.
- **What stays:** opening a file in the application; the coverage tests of the catalog; the workload of the binary.
- **Risk and open questions:** A downstream repository may call `run_file_editor` or `precompile_atoms`; the docstring of the second names a downstream caller. I did not search the other repositories.
- **Related plans:** `plan/pending/packages-compose-by-seams.md` step 11 (open; lists `FileEditor` among "the other callers" to move to the new run function); `plan/pending/faster-executable-startup.md` (in progress; still describes `warm_file_editor` as the warm-up of the binary, which is stale).
- **Check:** weakened. Two of the five facts do not hold, and one removal is not a dead-code removal:
  1. `environment/all/LocalPreferences.toml` is ignored by git (`.gitignore:42`). The dead preference is a file of this machine, not of the repository.
  2. `precompile_atoms` has a caller that compiles: the precompile workload of omnet-julia (`demo/Precompile.jl:87`, imported in `OmnetPresentationExample.jl:41`), which the docstring names. The name `count_printed_atoms` would be wrong for that caller.
  3. `warm_file_editor` is dead: no caller in projectured-julia, omnet-julia and inet-julia. This part holds, with the stale text of `faster-executable-startup.md`.
  4. `EditorDomain`, `EDITOR_DOMAINS`, `build_file_editor` and `run_file_editor` have no caller in the three repositories. But `run_file_editor` is an exported entry for a person at the prompt (one bare window of one domain on a file, without the Files pane and the assistant), and step 11 of `packages-compose-by-seams.md` keeps `FileEditor` and moves it to the new run function. Its removal would lose that entry, so it is a question for the owner inside that plan.
  5. `warm_application` beside six `run_…_workload` names is a naming point, and a rename reaches the downstream repositories.

  Value: low. What is left is the removal of `warm_file_editor` and the question of point 4.

## Covered by plans

- The 14 keywords of `make_example_editor` and the wrapper documents of the gallery: `plan/pending/packages-compose-by-seams.md`, step 8, open.
- The builder writes a `main` that names its backend packages by a table: the same plan, step 10, open.
- The registrations in `__init__` (`register_natural_…!`) that force `run_natural_rows_workload` and `run_module_initializers!`: the same plan, decision C7, "a later plan moves the other eight natural register functions to seams".
- `ProjecturedTest` as an optional slice and the weak dependencies of two downstream example packages: `plan/pending/package-convention-repl-leaves.md`, steps 13 and 16.
- The known failing sweeps and their `@test_broken` records: `plan/pending/test-suite-green.md`.
- The binary archive and the move to the General registry: `plan/pending/release-the-binary-and-the-packages.md`, Part A and B6.
- The start time of the binary beyond precompilation: `plan/pending/faster-executable-startup.md`, tiers 0, 1, 3 and 4.
- The slice edges and the layers of the source tree as a declared table: `plan/tentative/from-scratch-structure.md` (tentative; `PLATFORM_SLICE_EDGES` already does this for the platform).

## Examined and sound

- The five top-level folders and "a package is a name and an include list": decided in `plan/done/repository-tree.md`, shared with two other repositories, and held by `test/suite/tree.jl`. The cost, a release copy that moves `source/` under `src/` ([PackageRelease.jl:108](../../../source/tool/builder/PackageRelease.jl#L108)), follows from the owner's wish not to change the layout.
- One mechanism for compile ahead: `@compile_ahead`, two preferences, a recording per package, and the binary uses the same preference. The linked executable, the reactive build and `juliac --trim` solve other problems (start time, rebuild time, an experiment) and do not overlap with it.
- `ProjecturedIntegrations` with six package extensions beside AutoIntegration: the owner asked for exactly this package and mechanism (`plan/done/auto-integrations.md`, requirement R5), and the settled decisions allow it.
- `Projectured` (essential names and AutoIntegration) and `ProjecturedAll` (flat namespace, no third-party dependency) are two aggregates with two jobs, by decision D3 of the same plan.
- A third-party dependency makes a stem of its own, and no domain has one: stated in `package-rules.md` and visible in the project files that I sampled.
- The leaf rule (nothing depends on `ProjecturedREPL`, `ProjecturedBuild`, `ProjecturedBench`) and the reason for it, measured in `package-convention-repl-leaves.md`.
- One test package per stem, each runnable in its own environment without SDL or a database: CI does this for 36 of them.
- The generic test drivers and walkers take `(label, document, projection)` and know no domain; the gesture presets live one package higher. This is the right split; PB-1 is about what they drive, not about their shape.
- `DOMAIN_EDGES` and `PLATFORM_SLICE_EDGES` as hand tables: they are rules, not copies, so a new edge is a deliberate edit.
- `environment/build` apart from `environment/all`: PackageCompiler stays out of every session.
- `bin/projectured` runs the same `julia_main` as the binary, by one build function with `compile = false`: one program, not an imitation.
- `tool/survey-arguments.jl` and `bin/build_projectured` are thin wrappers of one implementation each.

## Check of the report

A second reader tried to refute each finding at commit 3a9b4fae4: opened the cited files, counted again with `grep`, searched `documentation/` and the plan folders for a stated reason or a covering plan, and looked for a feature that each proposal would lose. No Julia ran. The corrections stand in place above, and each finding has a **Check** item.

| Id | Verdict | Value after the check | Main correction |
| --- | --- | --- | --- |
| PB-1 | confirmed-with-corrections | high | Three parts are open questions of `plan/pending/kernel-audit-fixes.md` (L23-5, L23-4, L22-31 part 2). The sweep over the examples reports differently through the real loop. The workload runner waits 0.25 s before each step, which a test runner can not. "Most tests" is 198 of 676 files. |
| PB-2 | confirmed-with-corrections | medium (was high) | Guards already keep half of the lists equal. CI runs `test_acp()`, `test_pivot()` and `test_precompile()` in no job. Steps 1 and 3 of the proposal are circular for the aggregates. The 22 missing `[sources]` lines are a stated choice. |
| PB-3 | confirmed-with-corrections | medium | The skip lists record a limit of the keyboard routing, not a property "no caret". The registry has a curated order across the tiers. `ProjecturedExample` does not load SDL, Video, ODBC or Tulip. |
| PB-4 | confirmed-with-corrections | medium | Counts: 4 texts (51 + 35 + 1 + 1), `_SOURCES` in 53 files, `run_file_workload` in 13. A static layering guard with no `extra_aliases` needs more than the proposal says. |
| PB-5 | weakened | medium | A small guard closes the gap of the suites that nobody calls. The discovery of test files loses the include order and a new file in a running session. The copied contract tests are small. |
| PB-6 | weakened | low (was medium) | The ways to read source follow from what each rule reads. The exception forms are two. The shared part is about 150 of 2 200 lines. Two guards need the loaded package. |
| PB-7 | weakened | low | `LocalPreferences.toml` is not in git. `precompile_atoms` compiles for a downstream caller. `FileEditor` is kept by step 11 of `packages-compose-by-seams.md`. Only `warm_file_editor` is dead. |

Seen during the check and not in the report: 46 places in 30 files of `source/` (37 of them in the platform) branch on `editor isa Editor` to answer for no editor or for a stand-in (for example `source/platform/log/MessageLogDocument.jl:121`), and `documentation/package/platform/domain/domain.md:61` documents what "a mock editor that is not an `Editor`" gets. When the tests of PB-1 drive a real `Editor`, the stand-in half of these branches has no user.
