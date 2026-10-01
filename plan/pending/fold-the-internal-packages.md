# Fold the internal packages

**Status: a draft for discussion. Nothing is decided below the goal.**

## 1. Goal

Register only the packages that a user adds: the domains, the backends, the
model adapters and a few core packages. Fold the other packages of the
development repository into those. The maintainers of General asked for it on
2026-09-30 (Part R of
[release-the-binary-and-the-packages.md](release-the-binary-and-the-packages.md)),
and the owner decided the same day to fold in the development repository, not
only in the release copy (R28). The packages, their tests and their
documentation are then the same in both.

## 2. Facts (2026-09-30, branch `release-plan`)

- **66 release packages in 13 dependency levels.** `ProjecturedKernel` is used
  by 63 of them. `ProjecturedSubstrateTest` tests 30 of them as one group, "the
  substrate": the kernel, 27 internal packages, and the backends `Pdf` and
  `Console`.
- **The source of a slice names modules, not packages.** A file of
  `source/json/` says `using ..SyntaxModule`. Only the entry file of a package,
  `package/<Name>/src/<Name>.jl`, names packages: it `using`s the packages
  below it and binds each of their submodules as a `const`, so `..SyntaxModule`
  resolves. **So a fold changes the `Project.toml` files and the entry files,
  and not the code of the slices.**
- **What else names a package:**
  - the `Project.toml` of the test and example packages and of `environment/all`;
  - the static guards: `test/suite/tree.jl`, the layering guard of each
    package, and `DOMAIN_EDGES` in `test/projectured/PackageGraphTest.jl`;
  - tests and examples that `using` a package;
  - the documents that name packages; the documents of each slice in
    `documentation/package/<slice>/` stay;
  - the release generator: `PROJECTURED_PACKAGE_ASSETS` and the exclusions;
  - the downstream repositories, which `using` some packages directly.
- **The application is not in a release package.** `run_application_command`
  is in `example/projectured/Application.jl`, part of `ProjecturedExample`,
  and the release leaves out every `*Example` package. The binary carries it; a
  user of a registry does not get it.
- **Parallel precompilation** gets less parallel with fewer packages. The
  maintainers say that this is no reason for an entry in the registry. The cost
  is to be measured, not argued.

## 3. A first grouping (mine, for discussion)

| Group | Packages | Why |
| --- | --- | --- |
| `ProjecturedKernel`, as it is | Kernel | The base of every domain, audited and sealed file by file. |
| One core package, name open | Collection, Component, Serialization, Style, Domain, Focus, Plot, Primitive, Projection, Versioning, Dragging, Graphics, Layout, Screen, Text, Clipboard, Tooltip, Widget, Natural, Pane, Reflection, Inspector, Syntax, Fault, FileFormat, GestureHelp, GestureLog | The internals. A domain uses many of them together, and no user adds one alone. |
| The application, in the umbrella `Projectured` | Conversation, Assistant, Shell, Help, Log, Statistics, Undo, and the application of `ProjecturedExample` | The parts of the window, which no domain uses. With them, a user of the registry can start the application too. |
| Backends, as they are | Console, Pdf, Sdl, Web, Video, Tulip, Odbc | A user picks one; several bring a native library. |
| Model adapters, as they are | Anthropic, Ollama, OpenRouter, and Mcp (open) | A user picks one. |
| Domains, as they are | Json, Yaml, Xml, Markdown, Rst, Book, Math, Julia, Sql, Database, FileSystem, Graph, Chart, SequenceChart, DbCatalog, Formula, Fsm, Process, DataFrames | What a user adds. |

The result is about 32 packages instead of 66, in about 6 dependency levels.

## 3b. The folder shape (the owner, 2026-09-30)

The top-level layout stays: `source/`, `test/`, `example/`. The slices of a
folded package go into one folder of that package's name, in each of them:

```
source/kernel/                  as today
source/<name>/collection/       ← source/collection/
source/<name>/style/            ← source/style/
source/<name>/syntax/           ← source/syntax/
…                               the 27 slices of the package of internals
source/projectured/<slice>/     the parts of the application, in the umbrella
source/json/, source/sql/, …    the domains, backends and adapters, as today
test/<name>/style/, example/<name>/style/, …   the same, for the tests and examples
package/Projectured<Name>/      one package folder: Project.toml and the entry file
```

The release copy stays as it is today: it copies `source/<name>/**` into the
package folder of the release.

## 3c. The owner's decisions (2026-09-30)

- **The package of the internals is `ProjecturedPlatform`**, in
  `source/platform/`.
- **The groups of `source/`:** `source/kernel/`, `source/platform/`,
  `source/domain/`, `source/backend/`, and `source/adapter/` for the other
  connections to programs and services outside ProjecturEd. The backends stay
  a group of their own, because they are essential, not like the other
  adapters.
- **The parts of the application go into the platform**, not into the
  umbrella: assistant, conversation, shell, help, log, statistics, undo.

| Group | Slices |
| --- | --- |
| `source/kernel/` | kernel |
| `source/platform/` (35) | collection, component, serialization, style, domain, focus, plot, primitive, projection, versioning, dragging, graphics, layout, screen, text, clipboard, tooltip, widget, natural, pane, reflection, inspector, syntax, fault, fileformat, filesystem, gesturehelp, gesturelog, assistant, conversation, shell, help, log, statistics, undo |
| `source/domain/` (17) | json, yaml, xml, markdown, rst, book, math, julia, sql, database, graph, chart, sequencechart, dbcatalog, formula, fsm, process |
| `source/backend/` (5) | console, pdf, sdl, web, video |
| `source/adapter/` (8) | anthropic, ollama, openrouter, mcp, odbc, tulip, adaptagrams, dataframes |
| `source/tool/` (2), proposed | builder, repl: developer tools that no release carries |
| `source/projectured/` | the umbrella, as today |

More decisions of the owner, the same day: `dataframes` is an adapter, as its
docstring says (it owns a third-party dependency). No third folder level inside
the platform for now. `conversation` stays in the platform, and its docstring,
which calls it "the conversation domain", changes with the move: the assistant
is a capability of the platform. `filesystem` is in the platform too (the owner,
later the same day): the window's explorer and file dialog use it, and it
depends on no domain. Its docstring ("The file-system domain.") changes with the
move, as the one of `conversation` does.

`source/domain/` exists today as the slice of the domain protocol
(`DomainModule`); that slice moves to `source/platform/domain/` first.
`test/substrate/` and `example/substrate/` become `test/platform/` and
`example/platform/`; `test/suite/` and `test/bench/` stay.

## 3d. The check of the cycles (2026-09-30)

A scan of each `Project.toml` and of each module reference in `source/`, mapped
to the packages of 3c (`fold_graph.py` in the session scratchpad; it skips
docstrings, and a name that a `using` brings is checked by hand):

- **Today's code:** one cycle, `Platform → FileSystem, Chart → Platform`
  (F9). A mention of `OdbcModule` in the docstring of `DatabaseModule` is
  prose, not a dependency.
- **With `filesystem` in the platform (the owner's move), and the move of F9:**
  no cycle. 33 packages, 32 of them released (`ProjecturedAdaptagrams` is not),
  in 5 levels:

| Level | Packages |
| --- | --- |
| 1 | Kernel |
| 2 | Platform, Database, Anthropic, Ollama, OpenRouter, Mcp |
| 3 | Json, Yaml, Xml, Markdown, Rst, Book, Math, Julia, Sql, Graph, Chart, SequenceChart, Console, Pdf, Sdl, Web, Tulip |
| 4 | DbCatalog, Formula, Fsm, Process, Video, Adaptagrams, DataFrames |
| 5 | Odbc, the umbrella `Projectured` |

## 4. Open questions

| # | Question | Recommendation (mine, not decided) |
| --- | --- | --- |
| F1 | Is the kernel a package of its own? | **Decided:** yes. omnet-julia uses the kernel alone (`environment/kernel`), and the seals are per file of `source/kernel/`, which does not move. |
| F2 | The name of the package of the internals. | **Decided:** `ProjecturedPlatform`, in `source/platform/`. |
| F3 | Where the parts of the application go. | **Decided:** the platform. |
| F4 | `Pdf` and `Console`. | **Decided:** in `source/backend/`, packages of their own. |
| F5 | `Mcp`. | **Decided:** in `source/adapter/`, a package of its own. |
| F6 | `Plot`: the core, or the chart domains? | The core: `Chart`, `SequenceChart` and `Statistics` all use it. |
| F7 | The test and example packages follow the packages. | **Decided:** `SubstrateTest`, `FaultTest`, `FileSystemTest`, `ConversationTest`, `HelpTest`, `ShellTest` and `UndoTest` become `ProjecturedPlatformTest`; `SubstrateExample`, `FaultExample`, `FileSystemExample` and `ConversationExample` become `ProjecturedPlatformExample`. The others stay. 34 test packages become 28, 26 example packages become 23; the folders are `test/platform/<slice>/` and `example/platform/<slice>/`. |
| F8 | The order against the rename of R29 (acronyms in capitals; deferred by the owner) and the local registry of R27. | Decide this grouping first, and rename only the packages that stay, so that no package is renamed and then folded. The fold itself can come after the first release to the local registry: it changes no name that a user types. |
| F9 | The cycle: the platform named two domains. With `filesystem` in the platform, only Statistics was left: it uses `Chart` in `FramePlotToChart.jl` and in the line of `FrameStatisticsModule.jl` that registers it. | **Decided (the owner, 2026-09-30):** the projection and its registration move to the `Chart` domain, and they get names that say what the data is. The document stays in the platform's statistics. No package extension (the owner does not want one). The renames, with `julia-rename.jl`, as part of the fold: `FramePlot` → `FrameTimeSeries`; `FramePlotToChart` → `FrameTimeSeriesToChart` (the file too); `get_session_frame_plot` → `get_session_frame_time_series`; `flush_frame_plot!` → `flush_frame_time_series!`; the title "Frame plot" → "Frame times"; the alias "frame plot" → "frame times"; the registry key `:frame_plot` → `:frame_time_series`. A session saved with a `FramePlot` does not load under the new name; the document starts empty after a load anyway. |
| F10 | Where the application program goes: `run_application_command` is in `ProjecturedExample`, which no release carries. | **Decided:** the umbrella `Projectured`, which alone depends on every domain. `using Projectured` then gives a user the application. |
| S3 | The test helpers for the release tests (R30). | **Decided:** the release copy copies the helper files into the `test/` of each package that needs them, as it copies the slices. No package extension. |
| S6 | The downstream repositories: omnet-julia names internal packages 935 times in 122 files (23 `Project.toml`), inet-julia 70 times in 6. | **Decided:** a script maps each old package name to `ProjecturedPlatform`, in the same landing as the fold. The umbrella's paths `Projectured.XModule` do not change. |
| S7 | The documentation folders. | **Decided:** the same groups, `documentation/package/<group>/<slice>/`; `llm/` goes to `documentation/package/kernel/llm/`. |
| S8 | The rules and guards; the edges between the slices of the platform. | **Decided:** `naming-rules.md` and `test/suite/tree.jl` learn `source/<group>/<slice>/`. Before the fold, a table of the allowed edges between the slices is generated from today's `Project.toml` files, and the layering guard of the platform checks it, so the rules between the slices stay as they are. |

## 4b. Facts found at the start of the work (2026-10-01, `main` at `e7962bdaa`)

- The owner landed the open branches, deleted `window-leave`, and keeps
  `history-substrate-scaffold` (37 commits, the last on 2026-08-01); that
  branch must rebase onto the moves of Step 2 when it is taken up again.
- **Three packages are new since the grouping:** `ProjecturedGestureTracking`
  (the click count, the key chord and the dwell, from the device events; it
  uses only the kernel), `ProjecturedMouseTargetTracking` (the part under the
  pointer, and its crossings; the kernel and graphics) and
  `ProjecturedDisplay` (a value shown in an editor beside the REPL; the kernel,
  natural, screen, style and widget). The two trackers go to the platform:
  `screen`, a slice of the platform, uses them. `display` goes to the platform
  too (the owner): it depends only on the kernel and on slices of the platform,
  and it is a capability, like the assistant. `ProjecturedDisplayTest` joins
  `ProjecturedPlatformTest` in Step 4. The platform then has 38 slices.
- `ProjecturedDataFrames` imports `display_in_editor`, `ProjecturedDisplay` and
  `close_data_frame_editor!` from `DataFramesModule`, which no longer defines
  them; Julia warns "undeclared at import time" while it compiles. This is on
  `main`, outside the fold.
- **The baseline run on `main` (`e7962bdaa`, CI-like, a fresh clone):** the
  argument guard (5, the kernel audit's) and the export guard (4, in
  `EventModule.jl` and `GestureModule.jl`) fail, and 15 test sites in 5 jobs:
  DataFrames (the scroll bar, `DataFrameViewTest.jl:191`), the kernel
  (`DocumentMacroTest.jl:275` and `:434`, `FrameDrainTest.jl:170`), the shell
  (a saved user interface, `WindowShellTest.jl:417`), the substrate
  (`WidgetTablePartsTest.jl:56`, `WidgetRoundTripTest.jl:121`) and the
  umbrella (the JSON string of `TableCellEditingTest.jl`, the catalog coverage
  with four new types, `UserInterfaceFileTest.jl:47`, `HistorySweepTest.jl:115`
  twice, and an unexpected pass of the JSON markers of
  `ClickRoundtripTest.jl:323`). All came with the landings; the fold is
  measured against this list, not against a clean run.
  `test_display()` also fails 8 times on `main` (not in the baseline run; run
  alone on its clone). **The check of Step 2** (`4a5e5bb7a`, CI-like) found
  these and two more: the package graph (`_source_dir`, mended in Step 3) and
  the release copy (the generator copied a whole group; mended in
  `446942db3`), so Step 2 adds no failure of its own.

## 5. Steps (a draft for the owner's review)

Each step is a commit or a few, on a branch in a worktree, and the suites of
the change pass after each step. Nothing lands on `main` before the last step,
and the downstream repositories land in the same landing.

- [x] **Step 0, the baseline.** Measure the precompilation and the load of
      `environment/all` and the time of each CI job, for the comparison of
      Step 9. Generate the table of the allowed edges between the 35 slices
      from today's `Project.toml` files (S8), and a guard that checks the code
      against it. The guard passes on today's code.
      Done: `check_slice_edges` and `slice_edge_errors` in
      `test/kernel/layering/CheckLayering.jl` (a unit test in
      `test_layering_checkers`); `PLATFORM_SLICE_EDGES` (37 slices, from the
      `[deps]` of their packages on `e7962bdaa`) and `test_platform_slice_edges`
      in the substrate suite, which `test_substrate` runs. It walks the entry
      file of each package whose source is a slice of the platform, and checks
      that the slices it reaches are exactly the rows. **The times before the
      fold** (`0bb7b7362`, a clone of its own, a depot whose `compiled` folder
      starts empty, `JULIA_NUM_PRECOMPILE_TASKS=3` on CPUs 28, 30 and 31, load
      average 7.8): the precompilation of `environment/all` 279 s, 309 compiled
      files, 513 MB; the load of `ProjecturedKernel` 0.03 s, of `ProjecturedJson`
      0.30 s, of `Projectured` 2.66 s (the median of three). The script is
      `/var/tmp/fold/compile0/measure.sh`. A first run was void: the worktree
      that it compiled was edited during the run.
- [x] **Step 1, the frame times (F9).** With `julia-rename.jl`: `FramePlot` →
      `FrameTimeSeries`, and the other names of F9. `FrameTimeSeriesToChart.jl`
      and its registration move to `source/chart/`; `ProjecturedStatistics`
      loses its dependency on `ProjecturedChart`, and `ProjecturedChart` gains
      one on `ProjecturedStatistics`.
      Done: the renames with `julia-rename.jl` (and the private
      `_get_frame_time_series_count`, `_is_frame_time_series_due`,
      `_SESSION_FRAME_TIME_SERIES`, and `_make_measurement_line` for the helper
      that makes one chart line); the prose, the labels ("Frame times") and
      the registry key by hand. `ProjecturedChart` gains `ProjecturedNatural`
      and `ProjecturedProjection` too (the registration uses
      `register_natural_graphics!` and `ChainingProjection`), and gets an
      `__init__`. `ProjecturedStatistics` also loses `ProjecturedProjection`,
      which only the moved registration used. The guard of the edges now also
      fails for a module that is neither a slice of the platform nor in the
      kernel (`below_files`). The table got the row of `display`. Tests: the
      edge guard, chart 354, the frame statistics feed 48, the tool views 19,
      the application 339 pass; the shell error and the four types without an
      atom of the catalog coverage are on `main` too (see 4b).
- [ ] **Step 2, the folders.** First `source/domain/` (the slice of the domain
      protocol) moves to `source/platform/domain/`. Then each slice moves to
      `source/<group>/<slice>/`, and the same in `test/`, `example/` and
      `documentation/package/`. The packages do not change in this step: the
      entry files change only their include paths. **The commits of the move
      hold only moves**, so git sees each file as a rename and the open
      branches can rebase onto them; the paths in the entry files, the guards,
      `naming-rules.md` and the documents change in the commits after.
      Done in two commits: `3a9944bea` holds only the 196 folder moves (803
      files, each an R100 rename), `2cbee1855` the paths. A script changed the
      paths from the repository root in one regex pass (so a new
      `source/domain/…` is not replaced again by the rule of the old slice
      `source/domain`), and wrote each relative link of a Markdown file again
      from the old place of its file and its target; 244 files. By hand: the
      nine files that count their depth with `@__DIR__` or a relative
      `include`, a path in `ShellSuite.jl` and `PackageGraphTest.jl`, the two
      includes of the builder tests in `ProjecturedSuite.jl`, the fixture that
      the documentation guard skips, the edge guard (it reads
      `source/platform/` now), and the texts that describe the shape with a
      placeholder (`source/<group>/<slice>/`, the README layout,
      `writing-rules.md`). **The names of the guides change** with the group:
      `documentation/package/domain/json/json.md` is `domain/json/json` for
      the assistant; the kernel guides keep their names, and no code or corpus
      names a guide of a slice. The static guards pass, but for the argument
      and export violations of `main`.
- [x] **Step 3, the fold.** `package/ProjecturedPlatform/`: a `Project.toml`
      with the outside dependencies of the 35 packages, and an entry file that
      includes the 35 slice modules in the order of the table of Step 0. The
      domains, backends, adapters and the umbrella use `ProjecturedKernel` and
      `ProjecturedPlatform` in place of the internal packages. The 35 internal
      package folders go. `environment/all` follows. The guard of Step 0
      becomes the layering guard of the platform.
      Done: `ProjecturedPlatform`, uuid `b21cb890-5227-4e91-ae0e-8ab4d844f9f7`,
      version 0.1.0; its entry file binds the kernel's modules with the loop of
      the domains, includes the 38 slices in a topological order of the table,
      holds the two `__init__` bodies of `ProjecturedNatural` and
      `ProjecturedSyntax`, and exports the three names of the display at the
      package level. A script (`fold_platform.py` in the session scratchpad)
      put `ProjecturedPlatform` in place of each of the 38 names in 214 files,
      and each `Project.toml` names it once; the repeated `using`/`import`
      lines and the tuples of the binding loops were merged and sorted. By
      hand: `PackageGraphTest.jl` (`FileSystem` and `Conversation` leave
      `DOMAIN_EDGES`; `SUBSTRATE` became `BELOW_THE_DOMAINS`, the platform, the
      console and the PDF backend; and `_source_dir` reads the includes, which
      also mends a gap of Step 2, where it found no folder for most packages
      and so checked less), the comment of the umbrella's re-export pass, the
      manifest of `environment/all` (the 38 entries out, the platform's in,
      then `Pkg.resolve`), the layering guard of the platform (the kernel's
      modules as aliases, because the loop binds them), and
      `ProjecturedDataFrames`, which imported and exported three names that its
      module no longer defines (the warnings on `main`). **Left for Step 6:**
      the prose that the name rule made wrong or awkward, which
      `git grep -n ProjecturedPlatform -- '*.jl'` lists in comments and
      docstrings (for example a list that now names the platform twice, or "it
      must not name `ProjecturedPlatform`"). Tests: the layering guard and the
      edge table of the platform, the package graph, the export collisions,
      JSON and DataFrames pass, but for the scroll bar of the baseline.
      `test_display()` fails 8 times on `main` too (`get_wrapped_document`
      not in scope of its test package): it joins the baseline.
- [x] **Step 3b, the aggregate modules (the owner, 2026-09-30).** `KernelModule`
      in the kernel and `PlatformModule` in the platform, each defined after
      the slices of its package, export every public name of those slices and
      the names of the slice modules. The code above the platform (the
      domains, backends, adapters and the umbrella) replaces its 12 to 18
      `using ..XxxModule` lines with `using ..KernelModule` and
      `using ..PlatformModule`; the binding loop of the entry files binds the
      two like the other submodules. The package modules `ProjecturedKernel`
      and `ProjecturedPlatform` export the same names, so a user writes
      `using ProjecturedKernel, ProjecturedPlatform`. Conditions: the slices of
      the kernel and the platform keep naming each module (the aggregate comes
      after them, and the table of S8 reads their `using` lines); `import
      ..XxxModule: f` for an extension stays (PAR-QUALIFIED-EXTENSION); the
      guard of shadowed extensions counts every name of an aggregate, and
      PAR-QUALIFIED-EXTENSION gets a sentence on the aggregates. The
      export-collision guard already keeps the aggregate unambiguous.
      Done: the aggregates are files of their own, `source/kernel/KernelModule.jl`
      and `source/platform/PlatformModule.jl`, each included last. In the entry
      file they would have made a second module in one file, which
      `walk_includes` refuses; as a file at the root of its group, the kernel's
      layer check leaves it alone, and it fits the naming rule of a slice
      module. `SEALING.md` lists `KernelModule.jl`, not sealed. Each builds its
      `using ..XxxModule` lines and its exports with a loop, so the naming
      guard counts the exports of its group for it (the check of shadowed
      extensions), and the edge guard skips the file at the root of the
      platform. 26 files above the platform lost 260 `using` lines. Two entry
      files that bind one module at a time (Console, PDF) bind the two
      aggregates too, and the 42 loops that give a test or an example package a
      flat namespace skip them, because an aggregate repeats what such a loop
      binds (it failed on `LlmModule` otherwise). `CodeExecution.jl` of the
      kernel is left as it is: its loop imports names, not modules. The rule
      has its paragraph in PAR-QUALIFIED-EXTENSION. Tests: the kernel's and the
      platform's layering guards, the edge table, the export collisions, the
      package graph, JSON, FSM, SQL, Graph and DataFrames pass; `using
      ProjecturedKernel, ProjecturedPlatform` gives a user the names.
- [x] **Step 4, the test and example packages (F7).** `ProjecturedPlatformTest`
      and `ProjecturedPlatformExample`; the CI matrix (28 jobs); the testing
      guide.
      Found: two of the four example packages can not join the platform's.
      `ProjecturedFaultExample` uses the umbrella and `ProjecturedExample`, and
      `ProjecturedConversationExample` uses four domains and their example
      packages; each of those uses the platform's example package, so either
      merge makes a cycle (the first try hit it as a load deadlock). They are
      examples of the application, and stay packages of their own. The eight
      test packages merge: no main package depends on a test package, so a test
      package may use a domain (the conversation and shell suites use JSON,
      Julia and XML). Each merged package is a submodule of the new one
      (`FaultTests`, …, `FileSystemExamples`), so the helpers of two of them do
      not collide, and the new package re-exports what each exports.
      Done: `ProjecturedPlatformTest` (the uuid of the substrate test package;
      `test/platform/PlatformSuite.jl` defines `test_platform()`, which runs the
      substrate's tests and then the seven merged suites, and
      `test_platform_layering()`); the seven suites lost their own layering
      guard, which now checked the whole platform seven times. CI has 28 jobs.
      `test_all()` calls `test_platform()` in place of five suites. Two more
      gaps of Step 2 came to light and are mended: the suite rule of the
      naming guard looked for `test/<slice>` and skipped every package when it
      found none (`c832fc48a`), and the report of slices without a guide read
      the group folders as slices. Tests: `test_platform()` 97,458 pass, the
      errors are the baseline's (`WidgetRoundTripTest.jl:121`,
      `WidgetTablePartsTest.jl:564`, `WindowShellTest.jl:417`); the package
      graph and the export collisions pass.
      **The CI-like check of Steps 1 to 4** (`dc5ffdec5`, a fresh clone, the 28
      jobs of `CI.yml`): the kernel and the umbrella have exactly the failure
      sites of the baseline; the merged test package did not instantiate in
      its own environment, because the merge kept the old path of a renamed
      `[sources]` entry (an `environment/all` run can not see that); mended in
      `36a176ac4`, after which every `[sources]` entry of every package names
      its own folder, and `test_platform()` in its own environment has only the
      three errors of the baseline. The eight display errors of `main` are
      gone: the display tests write `using ProjecturedKernel`, which now gives
      them `get_wrapped_document`.
- [ ] **Step 5, the application (F10).** `run_application_command` and what it
      needs move from `ProjecturedExample` to the umbrella; the builder of the
      binary follows.
      **Changed by the owner (2026-10-01): the application goes to the
      platform**, as a slice of its own, `source/platform/application/`, and
      names no domain. Facts that led there: the application asks for a model
      only by symbol through the seams of the kernel (`make_llm`,
      `make_agent_server`), so it compiles without an adapter; the four
      domains it named (JSON, XML, Julia, SQL) register their notation, so
      the natural renderer draws them; and an application that names no
      domain shows every domain a session loads, a downstream one too. What
      a user types: `using Projectured, ProjecturedSdl, ProjecturedOllama`.
      The parts:
      - [x] 5a. **The assistant's API is open to the domains** (the owner:
            "other domains can also extend the assistant API, add the
            registry"). A domain registers, when it loads, the names a model
            may use for its documents; `make_application_api` takes every
            registered entry. JSON registers the seven names that the
            application names now (`JsonArray` … `JsonNull`).
            Done: `register_assistant_api!(declaration)` and
            `get_assistant_api()` in the assistant slice
            (`AssistantApi.jl`); an entry is in the form that `declare_api!`
            takes, and an entry registered again is not added twice (a
            package calls it from `__init__`). JSON registers in its
            `__init__`; tests `test_assistant_api` (platform) and
            `test_json_assistant_api` (JSON).
      - [ ] 5b. **The chat rows** `conversation_draft_entry` and
            `conversation_widget_entry` move from the conversation example
            into the conversation slice, with the names of a product.
      - [ ] 5c. **The slice**: `Application.jl` and `DefaultBackend.jl` move to
            `source/platform/application/`; the four domain rows go, and the
            natural renderer draws those documents (the visible difference:
            long lines of a JSON or an XML file no longer wrap, because the
            natural renderer never wraps code). The platform gains
            `InteractiveUtils` (a standard library) for `default_backend`.
            `PLATFORM_SLICE_EDGES` gains the row of the slice.
      - [ ] 5d. **The warm-up** `warm_application` needs `ConsoleBackend` and
            three domains, so it goes to the umbrella, which only a build runs
            it from.
      - [ ] 5e. **The builder** builds the binary from `Projectured`, the two
            model adapters, `ProjecturedMcp` and the backends; the example tier
            leaves the binary.
      - [ ] 5f. The tests, the examples that call the application, and the
            documents follow.
- [x] **Step 6, the words.** The docstrings of `conversation` and `filesystem`
      stop calling them domains; `system-anatomy.md` and the other documents
      describe the kernel, the platform, the domains, the backends and the
      adapters.
      Done (`09cae7767`, 108 files, comments, docstrings and Markdown only:
      every changed `.jl` file parses to the same code without its
      docstrings). The domain inventory lists 17 domains; the conversation, the
      assistant and the file system are slices of the platform. The definition
      of a slice covers a package with no layer of its own. One consequence is
      written down where it applies: the platform registers the syntax fallback
      in its `__init__`, so every session that loads the platform can draw any
      document, and the tabs wrapper of the display is always there; before,
      both waited for `ProjecturedSyntax` and `ProjecturedPane` to load.
      Then the names (`f3e18063f`): `substrate_examples`,
      `substrate_atomic_documents` and `test_substrate_examples` are
      `platform_examples`, `platform_atomic_documents` and
      `test_platform_examples` (with `julia-rename.jl`), the file is
      `example/platform/PlatformExamples.jl`, and three faults the words pass
      found are mended: the `runtests.jl` of the platform test package loaded
      the old package, the loop of `ProjecturedTest` named the platform test
      package seven times, and the entries of `Pdf` and `Console` bound
      `StyleModule` five and two times (as on `main`). Tests: the platform
      examples (90,562 pass), the registries, the naming guard.
- [x] **Step 7, the release copy.** The list of the release packages, the
      assets (the fonts go with `ProjecturedPlatform`), the exclusions
      (`source/tool/`), and the test helpers of S3.
      Done: the release copy takes the common folder of what an entry file
      includes (`446942db3`), `PROJECTURED_PACKAGE_ASSETS` gives the fonts to
      `ProjecturedPlatform`, and `PROJECTURED_RELEASE_EXCLUSIONS` keeps the
      builder and the REPL leaf out. The builder tests pass. The test helpers
      of S3 are not a part of the fold: they belong to R30 of the release
      plan, which the release copy needs whether or not the fold lands.
- [ ] **Step 8, downstream (S6).** The script of the package names in
      omnet-julia and inet-julia, and their `Project.toml` files, on branches
      of their own; their suites pass against the branch of this plan.
      Done so far: branch `fold-follow` in both repositories (omnet-julia
      `c5fb4901`, inet-julia `8ea400c`), from their `main`. A script maps every
      old package name to the new one, writes each `Project.toml` with the new
      name once at the same relative path, joins the repeats in a `using`
      list, and makes `ProjecturedPane.ProjecturedWidget.WidgetModule` read
      `ProjecturedPlatform.WidgetModule`; it leaves `plan/`, the recorded
      measurements and `prototype/` alone. The prose that named several old
      packages, and the comments over the `[deps]` lines that went, are
      rewritten by hand. Both repositories precompile against a clone of this
      branch, every package, no error.
      **A consequence, and the owner's decision (2026-10-01).** The simulator
      used four slices of the platform (collection, primitive, serialization,
      domain: 4,007 lines, which depend on the kernel alone); after the fold
      `OmnetSimulator`, `OmnetLegacyFormat`, the runner and every inet-julia
      model package reach the whole platform (63,153 lines). No third-party
      package comes with it. The alternatives were a second small package
      under the platform for the four slices, or the four slices in the
      kernel (which breaks inet-julia's rule that the kernel has no `[deps]`).
      The owner accepted the larger closure. So the closure guards now say
      that no domain and no backend is reachable from a runner: the platform
      names no backend, so nothing in the image can open a window. The
      closures are 15 names for the omnet runner (17 on `main`), 9 for the
      campaign window (28), 22 for the interface (54) and 19 for the inet
      runner (21); the four guards pass with a walk that reads the packages of
      this branch.
      Of the recorded precompile statements of omnet-julia, 51% resolve (the
      list of inet-julia warns as well); the names they miss most are missing
      on `main` too (`ProjectionApiModule`,
      `PrinterContextModule`, `ProjecturedWorkbench`), so they must be recorded
      again whether or not the fold lands.
      **The suites against the baseline** (a scratch environment per run, the
      fold side on a clone of this branch, the `main` side on clones of the
      three `main` branches; no network, cores 24-27). omnet-julia
      `test/runtests.jl`: 12,343 pass, 42 fail, 83 errors on the fold; 12,325,
      44, 76 and 7 broken on `main`. The sites differ only where (a) a walk
      guard reads `ProjecturedPlatform` through the relative `[sources]` path,
      which reaches the main checkout of projectured-julia, where the package
      does not exist yet (the four closure guards, the NG and the
      co-simulation guards; each passes with a walk that reads this branch),
      (b) a timing ratio at `OmnetSimulatorTest/runtests.jl:2308`, which fails
      2 of 20 times on `main` and on the fold alike, and (c) the drift checks
      of the samples, which ran only where an `omnet-cpp` checkout sits beside
      the clone. inet-julia `test/suite/runtests.jl`: 20,104 pass and 12
      fail on the fold, 20,105 and 11 on `main`; the one more is
      `test/runner/closure.jl:75`, the runner guard, which reaches
      `OmnetSimulator` through the main checkout of omnet-julia and so sees
      the old names until omnet-julia lands. So the three repositories must
      land together, and their walk guards pass only after that.
- [ ] **Step 9, the check and the landing.** The CI-like run from a fresh clone
      (`/var/tmp/release-plan/ci3/`), the times of Step 0 again, then the
      landing of this repository and the downstream ones together, with the
      owner's word.

**Risk: the open branches.** Step 2 moves about 1,000 files. Each branch of
another session that is open then must rebase onto it. The pure-move commits
keep that to a rename that git follows; a branch that adds a new file in an old
folder must move that file itself.
