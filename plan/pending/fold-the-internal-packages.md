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

## 3b. The folder shape (the owner, 2026-09-30: the folders change with the packages)

The code of each package moves into its package folder: `source/<slice>/`,
`test/<slice>/` and `example/<slice>/` go under `package/<Name>/`. Then each
package folder holds all that it reads, and **the development repository is
the repository that is registered**: no release copy, no generator of package
repositories, and the CI of the repository is the CI of the registered
packages, as the maintainers ask.

```
package/
├── ProjecturedKernel/
│   ├── Project.toml, README.md, LICENSE
│   ├── src/ProjecturedKernel.jl, src/cell/ …      ← source/kernel/
│   ├── test/runtests.jl, test/ …                  ← test/kernel/
│   └── example/ …                                 ← example/kernel/
├── ProjecturedToolkit/                            (the name is F2)
│   ├── src/ProjecturedToolkit.jl
│   ├── src/collection/, src/syntax/, … 27 slices  ← source/<slice>/
│   ├── test/ …, example/ …                        ← test/<slice>/, example/<slice>/
│   └── asset/font/                                ← asset/font/
├── ProjecturedJson/
│   ├── src/ …, test/ …, example/ …                ← source/json/, test/json/, example/json/
└── … 33 packages
documentation/      one Documenter site (stays at the root)
test/suite/         the static guards of the repository (stay at the root)
environment/, plan/, tool/, bin/
```

The `*Test` and `*Example` packages go: their content moves into `test/` and
`example/` of each package. The size of the move: 492 files of `source/`, 360
of `test/`, 147 of `example/`, with `git mv`; 92 documents and 131 entry files
name those paths.

## 4. Open questions

| # | Question | Recommendation (mine, not decided) |
| --- | --- | --- |
| F1 | Does the kernel stay a package of its own, or does it join the core package? | Of its own: it is the smallest base, and its seals are per file. |
| F2 | The name of the package of the 27 internals. | Not `ProjecturedCore`: the owner finds that it sounds like the kernel (2026-09-30). Candidates: `ProjecturedToolkit` (what it is for a user: the documents, projections and widgets to build views with); `ProjecturedSubstrate` (the name of the layer in `system-anatomy.md` and of its test package, but jargon to a user); `ProjecturedStandard` (a standard library of documents and projections). Mine: `ProjecturedToolkit`. |
| F3 | Do the parts of the application go into the umbrella, or into a package of their own? | The umbrella, so that `using Projectured` gives the application. |
| F4 | `Pdf` and `Console` are in the substrate today. Backends of their own? | Yes: a user picks a backend. |
| F5 | `Mcp`: an adapter of its own, or part of the umbrella? | Open: it has no dependency but the kernel, and the binary uses it. |
| F6 | `Plot`: the core, or the chart domains? | The core: `Chart`, `SequenceChart` and `Statistics` all use it. |
| F7 | The test packages follow the packages: one test package for each registered package. | Yes: `ProjecturedSubstrateTest` becomes the test package of the core. |
| F8 | The order against the rename of R29 (acronyms in capitals; deferred by the owner) and the local registry of R27. | Decide this grouping first, and rename only the packages that stay, so that no package is renamed and then folded. The fold itself can come after the first release to the local registry: it changes no name that a user types. |
| S1 | Where the package folders live: `package/` as today, `lib/` (the convention of SciML), or the root. | `package/`, as today. |
| S2 | Where the examples go: `example/` in each package, which the tests include and `using` does not load, or into `test/`. | `example/` in each package. The gallery and the application go to the umbrella. |
| S3 | The test harness of `ProjecturedKernelTest` (`test_printer`, `test_reader`, the walkers) serves the tests of every package, and a registered test can use only registered packages. Where does it go? | A package extension of the kernel on `Test`: it loads only when a test loads `Test`. The other ways: a registered package of test tools, or a copy in each package. |
| S4 | The 54 sealed files of the kernel move from `source/kernel/` to `package/ProjecturedKernel/src/`. Their text does not change, but `SEALING.md` says that no sealed file changes without the owner's permission for that file. | The owner gives the permission for the move alone, once, for all of them. |
| S5 | The fonts: the toolkit reads them, and so does `ProjecturedWeb`. | The toolkit holds them; `ProjecturedWeb` reads them through `pkgdir(ProjecturedToolkit)`. |
| S6 | The downstream repositories name internal packages 1,005 times in 128 files (omnet-julia 935 in 122, inet-julia 70 in 6). | One mechanical change in each, in the same landing. |

## 5. Steps

Not yet written. They follow the answers of section 4.
