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
- **With `filesystem` in the platform (the owner's move), and change 3 of F9:**
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
| F1 | Does the kernel stay a package of its own, or does it join the core package? | Of its own: it is the smallest base, and its seals are per file. |
| F2 | The name of the package of the internals. | **Decided:** `ProjecturedPlatform`, in `source/platform/`. |
| F3 | Where the parts of the application go. | **Decided:** the platform. |
| F4 | `Pdf` and `Console`. | **Decided:** in `source/backend/`, packages of their own. |
| F5 | `Mcp`. | **Decided:** in `source/adapter/`, a package of its own. |
| F6 | `Plot`: the core, or the chart domains? | The core: `Chart`, `SequenceChart` and `Statistics` all use it. |
| F7 | The test packages follow the packages: one test package for each registered package. | Yes: `ProjecturedSubstrateTest` becomes the test package of the core. |
| F8 | The order against the rename of R29 (acronyms in capitals; deferred by the owner) and the local registry of R27. | Decide this grouping first, and rename only the packages that stay, so that no package is renamed and then folded. The fold itself can come after the first release to the local registry: it changes no name that a user types. |
| F9 | The cycle: the platform named two domains. With `filesystem` in the platform, only Statistics is left: it uses `Chart` in `FramePlotToChart.jl` and in the line of `FrameStatisticsModule.jl` that registers it. | Open. Mine: `FramePlotToChart.jl` and its registration move to the `Chart` domain; the frame statistics then have a chart view when `Chart` is loaded, which the application always does. The other way: `chart` joins the platform too, but a chart is what a user adds. |
| S3 | For R30 (a `test/runtests.jl` in each package of the release): the test harness of `ProjecturedKernelTest` (`test_printer`, `test_reader`, the walkers) serves the tests of every package, and a registered test can use only registered packages. Where does it go? | A package extension of the kernel on `Test`: it loads only when a test loads `Test`. The other ways: a registered package of test tools, or a copy in each package. |
| S6 | The downstream repositories name internal packages 1,005 times in 128 files (omnet-julia 935 in 122, inet-julia 70 in 6). | One mechanical change in each, in the same landing. |
| S7 | Do the documents of the slices follow: `documentation/package/<name>/<slice>/`? | Yes, the same shape in every folder. |
| S8 | The rules and guards that name the shape `source/<slice>/` (`naming-rules.md`, `test/suite/tree.jl`, the layering guards) learn the level `source/<package>/<slice>/`. | Part of the same change. |

## 5. Steps

Not yet written. They follow the answers of section 4.
