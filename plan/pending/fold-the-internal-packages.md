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

## 5. Steps (a draft for the owner's review)

Each step is a commit or a few, on a branch in a worktree, and the suites of
the change pass after each step. Nothing lands on `main` before the last step,
and the downstream repositories land in the same landing.

- [ ] **Step 0, the baseline.** Measure the precompilation and the load of
      `environment/all` and the time of each CI job, for the comparison of
      Step 9. Generate the table of the allowed edges between the 35 slices
      from today's `Project.toml` files (S8), and a guard that checks the code
      against it. The guard passes on today's code.
- [ ] **Step 1, the frame times (F9).** With `julia-rename.jl`: `FramePlot` →
      `FrameTimeSeries`, and the other names of F9. `FrameTimeSeriesToChart.jl`
      and its registration move to `source/chart/`; `ProjecturedStatistics`
      loses its dependency on `ProjecturedChart`, and `ProjecturedChart` gains
      one on `ProjecturedStatistics`.
- [ ] **Step 2, the folders.** First `source/domain/` (the slice of the domain
      protocol) moves to `source/platform/domain/`. Then each slice moves to
      `source/<group>/<slice>/`, and the same in `test/`, `example/` and
      `documentation/package/`. The packages do not change in this step: the
      entry files change only their include paths. **The commits of the move
      hold only moves**, so git sees each file as a rename and the open
      branches can rebase onto them; the paths in the entry files, the guards,
      `naming-rules.md` and the documents change in the commits after.
- [ ] **Step 3, the fold.** `package/ProjecturedPlatform/`: a `Project.toml`
      with the outside dependencies of the 35 packages, and an entry file that
      includes the 35 slice modules in the order of the table of Step 0. The
      domains, backends, adapters and the umbrella use `ProjecturedKernel` and
      `ProjecturedPlatform` in place of the internal packages. The 35 internal
      package folders go. `environment/all` follows. The guard of Step 0
      becomes the layering guard of the platform.
- [ ] **Step 3b, the aggregate modules (the owner, 2026-09-30).** `KernelModule`
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
- [ ] **Step 4, the test and example packages (F7).** `ProjecturedPlatformTest`
      and `ProjecturedPlatformExample`; the CI matrix (28 jobs); the testing
      guide.
- [ ] **Step 5, the application (F10).** `run_application_command` and what it
      needs move from `ProjecturedExample` to the umbrella; the builder of the
      binary follows.
- [ ] **Step 6, the words.** The docstrings of `conversation` and `filesystem`
      stop calling them domains; `system-anatomy.md` and the other documents
      describe the kernel, the platform, the domains, the backends and the
      adapters.
- [ ] **Step 7, the release copy.** The list of the release packages, the
      assets (the fonts go with `ProjecturedPlatform`), the exclusions
      (`source/tool/`), and the test helpers of S3.
- [ ] **Step 8, downstream (S6).** The script of the package names in
      omnet-julia and inet-julia, and their `Project.toml` files, on branches
      of their own; their suites pass against the branch of this plan.
- [ ] **Step 9, the check and the landing.** The CI-like run from a fresh clone
      (`/var/tmp/release-plan/ci3/`), the times of Step 0 again, then the
      landing of this repository and the downstream ones together, with the
      owner's word.

**Risk: the open branches.** Step 2 moves about 1,000 files. Each branch of
another session that is open then must rebase onto it. The pure-move commits
keep that to a rename that git follows; a branch that adds a new file in an old
folder must move that file itself.
