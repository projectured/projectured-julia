# AutoIntegrations: install what you add, load what you choose

## 1. Goal

The owner, 2026-10-02:

> We remove all ext packages and all automatic loading now. Only keep manual
> loading. […] We write a separate package AutoIntegrations which would use a
> package loading hook to load additional packages depending on what the user's
> environment specifies […] the state could be :auto, :manual, or unspecified,
> which means that the AX package itself would specify whether it auto loads or
> not. […] using ProjecturedSDL, ProjecturedDataFrames, then display_in_editor
> works. Alternatively […] using Projectured (which implies ProjecturedPlatform
> and ProjecturedKernel and AutoIntegrations) and depending on the state of the
> user environment settings for AutoIntegrations, it will or will not load the
> ProjecturedDataFrames and ProjecturedSDL packages. The installation is an
> entirely separate thing from the using. […] can we also add a
> ProjecturedIntegrations package which would use the ordinary package extension
> mechanism to automatically load the ProjecturedSDL and ProjecturedDataFrames
> package? This package has to be installed manually and it brings with itself
> all integration packages.

The owner, 2026-10-03:

> Trigger for ProjecturedSDL: Projectured and SimpleDirectMediaLayer.
> AutoIntegration lives in this repository.

The requirements, in short:

- **R1, install is explicit.** `add X` installs X and its `[deps]`, and nothing
  more.
- **R2, the manual way.** `using ProjecturedSDL, ProjecturedDataFrames` works
  with no `Projectured`. It loads the packages that it names and their
  dependencies, and nothing more.
- **R3, the automatic way.** `using Projectured` loads the kernel, the platform
  and AutoIntegrations. AutoIntegrations loads an installed integration when its
  triggers are loaded and its state is `auto`.
- **R4, one setting for each package.** The environment of the user sets the
  state of a package to `auto` or `manual`. With no setting, the package's own
  default applies.
- **R5, all at once.** `ProjecturedIntegrations` installs every integration and
  loads each one with an ordinary package extension.
- **R6, minimal.** No package installs or loads when nothing needs it.

## 2. Facts (2026-10-03)

- **`main` (`a00d19122`) loads by itself.** The umbrella has six extensions,
  `[weakdeps]` on 34 packages, and a loader in `Base.package_callbacks` for 22
  packages (`_INSTALLED_PACKAGES`: the console, PDF, 17 domains, 3 model
  adapters). `load_installed_package!` of the domain slice serves only them. The
  tests are `test/projectured/IntegrationLoadingTest.jl` and
  `test/platform/document/InstalledPackageTest.jl`.
- **The six extensions load nothing for a new user.** Pkg never installs a
  `[weakdeps]` entry, so the integration is absent. A test in an empty depot
  showed it on 2026-10-02. On the owner's machine it worked, because `@v1.13`
  held the integrations.
- **The integrations have hard dependencies on `main`:**

  | Package | Third-party `[deps]` | ProjecturEd `[deps]` |
  | --- | --- | --- |
  | `ProjecturedSDL` | SimpleDirectMediaLayer, SDL2_jll, Xorg_libX11_jll | kernel, platform |
  | `ProjecturedDataFrames` | DataFrames | kernel, platform |
  | `ProjecturedVideo` | FFMPEG | kernel, platform, SDL |
  | `ProjecturedODBC` | ODBC, DBInterface, Tables | kernel, platform, SQL, Database, DBCatalog |
  | `ProjecturedTulip` | Tulip, MathOptInterface | platform |
  | `ProjecturedMCP` | ModelContextProtocol | kernel |

- **`julia-112` (`6c47fb276`) is not landed.** It raises the promise to Julia
  1.12 and writes the front page README of `Projectured.jl`
  (`_format_projectured_release_overview`). The branch `auto-integrations`
  starts from it.
- **Design B is superseded.** The branch `integration-shells` (`66ef4a556`),
  omnet `integration-shells` (`69486bf2`) and inet `integration-shells`
  (`cb972dc`) hold it. The private release on GitHub is design B:
  `Projectured.jl` `6358e8a`, `ProjecturedRegistry` `97b7db8`.
- **`display_in_editor` is a name of `ProjecturedPlatform`.**
  `ProjecturedSDL` and `ProjecturedDataFrames` do not export it.
- **The release keeps a new table.** `_write_release_project` copies every
  table of a `Project.toml` except `[sources]`.
- **The facts of the hook:**
  - Julia calls `Base.package_callbacks` after a load. A `Base.require` inside
    the callback works; the umbrella loader on `main` does it.
  - An `__init__` that loads a package of its own load fails with
    `ConcurrencyViolationError`.
  - `Base.require(::Base.PkgId)` binds no name in `Main`.
  - A `using X` in `Main` finds `X` only among the direct dependencies of the
    environments of the load path.
- **No downstream code loads the umbrella.** omnet-julia and inet-julia use
  `ProjecturedAll`.
- **No file of this change is sealed.** `SEALING.md` does not name
  `Projectured.jl`, `Domain.jl` or `DomainModule.jl`.

## 3. Why it is so

This section goes into the design document of AutoIntegrations (step 8), and a
short form goes into the README.

- **ProjecturEd joins many packages of other authors.** Now it joins six:
  SimpleDirectMediaLayer, DataFrames, FFMPEG, ODBC, Tulip and
  ModelContextProtocol. Later it can join dozens, for example a plot library, a
  file format or a database driver. Each join is one small package, an
  integration.
- **Pkg has no optional dependencies.** `add` installs all of `[deps]`, and
  never a `[weakdeps]` entry. So an integration that must work after `add` and
  `using` alone holds its third-party package in `[deps]`. That makes it a
  package of its own, which the user adds by name.
- **A package extension can not serve both ways.** An extension lives in its
  parent package, and Pkg does not install its triggers.
  - An extension of the umbrella can load only what the umbrella installs. So
    the umbrella installs every integration and every third-party package. That
    breaks R1 and R6.
  - An extension inside the integration makes `add ProjecturedODBC` install no
    ODBC. Then `using ProjecturedODBC` alone fails. That breaks R2.
- **Users want different things.** One user wants the integrations to load by
  themselves. Another user names each package, because an automatic load costs
  time and memory and can surprise. With dozens of integrations, one switch for
  all is too coarse. So the setting is per package, in the environment of the
  user, and the package gives the default.
- **Install and use are two steps.** An install never changes what loads. Only
  a `using` line, and the settings of the user, change it.
- **AutoIntegrations names no ProjecturEd package.** Each package declares its
  own triggers. A package of another project can use the same mechanism.

## 4. The design

### 4.1 The packages

| Package | `[deps]` | Who loads it | Released |
| --- | --- | --- | --- |
| `Projectured` | ProjecturedPlatform, AutoIntegrations | the user | yes |
| `AutoIntegrations` | TOML | `Projectured` | yes |
| `ProjecturedSDL`, … (the six) | as on `main`, table in section 2 | the user, or AutoIntegrations | yes |
| `ProjecturedIntegrations` | Projectured and the six | the user | yes |
| `ProjecturedPlatform.EssentialsModule`, a slice of the platform, not a package (section 9.6) | — | the integrations, the backends, `Projectured` | with the platform |
| `ProjecturedAll` | each package with no third-party dependency | the tests, the examples, the REPL, a user who wants all | yes |

### 4.2 A package declares its triggers

The `Project.toml` of an integration holds one more table:

```toml
[auto-integration]
default = "auto"

[auto-integration.triggers]
Projectured = "92922de3-b970-4d9a-8b2a-9d6f361397b5"
SimpleDirectMediaLayer = "98e33af6-2ee5-5afd-9e75-cbc738b767c4"
```

- `triggers` names each package that must be loaded, with its uuid, as
  `[weakdeps]` does. A trigger need not be a dependency: `ProjecturedSDL` does
  not depend on `Projectured`.
- `default` is `"auto"` or `"manual"`. Without it, the default is `"manual"`
  (decision D9).
- A package with no table is never loaded by AutoIntegrations.

The six integrations:

| Package | Triggers | Default |
| --- | --- | --- |
| `ProjecturedSDL` | Projectured, SimpleDirectMediaLayer | auto |
| `ProjecturedDataFrames` | Projectured, DataFrames | auto |
| `ProjecturedVideo` | Projectured, FFMPEG | auto |
| `ProjecturedODBC` | Projectured, ODBC | auto |
| `ProjecturedTulip` | Projectured, Tulip | auto |
| `ProjecturedMCP` | Projectured, ModelContextProtocol | auto |

The owner gave the triggers of SDL. The others follow the same form, with the
third-party package of the extension on `main`. The default is `auto`, because
the user installed the integration and loaded the package that it joins.

The domains, the console, PDF and the three model adapters declare the trigger
`Projectured` and the default `auto`. So `using Projectured` opens each domain
that the user installed, and the setting can turn it off. `ProjecturedWeb` has
no table, because a loaded web backend becomes the default backend when SDL is
absent.

### 4.3 The user sets the state

The file `LocalPreferences.toml` beside the `Project.toml` of an environment
holds the setting:

```toml
[AutoIntegrations]
ProjecturedSDL = "auto"
ProjecturedDataFrames = "manual"
```

- `"auto"` loads the package when its triggers are loaded.
- `"manual"` loads it only when a `using` line names it.
- No entry gives the default of the package.

AutoIntegrations reads the file itself, with the TOML standard library
(section 9.1). The first environment of the load path that has an entry
decides, so the active project comes first. One function writes the file of the
active project: `set_auto_integration!(name, state)`, with the state `:auto`,
`:manual` or `nothing`. `nothing` removes the entry.

### 4.4 The hook

1. `__init__` does nothing in a process that writes a cache file
   (`jl_generating_output`). So no cache file depends on what one user
   installed. In other processes, it adds one callback to
   `Base.package_callbacks`.
2. On its first call, the callback finds the candidates. A candidate is a
   direct dependency of an environment of the load path that has the table
   `[auto-integration]` (decision D1). It reads the `Project.toml` of each
   package beside the path that `Base.locate_package` gives, and keeps the
   result for the session.
3. On each call, it loads each candidate that is not loaded, whose state is
   `auto`, and whose triggers are all loaded. It loads with
   `Base.require(::PkgId)`, so no name goes into `Main`.
4. It repeats step 3 until a pass loads nothing, because a loaded integration
   can be the trigger of another.
5. A flag stops a second call while one call runs, because a `require` inside
   the callback calls the callbacks again.
6. If a load fails, it writes a `@warn` with the name of the package and the
   error. The `using` line of the user goes on.
7. It needs no special case for triggers that loaded before AutoIntegrations.
   The first callback, after the load of `Projectured`, sees them.

### 4.5 `Projectured`

`Projectured` depends on `ProjecturedPlatform` and AutoIntegrations, and loads
both. The kernel loads as a dependency of the platform. It has no hook, no
extension and no `[weakdeps]` of its own.

- It re-exports the names of `ProjecturedPlatform.EssentialsModule` (section
  4.7), and no other name.
- It does not export `set_auto_integration!`. A user who changes a setting
  writes `using AutoIntegrations`.
- It binds no submodule of the kernel or the platform. `ProjecturedPlatform`
  binds them, so `ProjecturedPlatform.EditorModule` works.

### 4.6 `ProjecturedIntegrations`

```toml
[deps]
Projectured = "…"
ProjecturedSDL = "…"
ProjecturedDataFrames = "…"
ProjecturedVideo = "…"
ProjecturedODBC = "…"
ProjecturedTulip = "…"
ProjecturedMCP = "…"

[weakdeps]
SimpleDirectMediaLayer = "…"
DataFrames = "…"
FFMPEG = "…"
ODBC = "…"
Tulip = "…"
ModelContextProtocol = "…"

[extensions]
ProjecturedIntegrationsSimpleDirectMediaLayerExt = "SimpleDirectMediaLayer"
ProjecturedIntegrationsDataFramesExt = "DataFrames"
ProjecturedIntegrationsFFMPEGExt = "FFMPEG"
ProjecturedIntegrationsODBCExt = "ODBC"
ProjecturedIntegrationsTulipExt = "Tulip"
ProjecturedIntegrationsModelContextProtocolExt = "ModelContextProtocol"
```

- `add ProjecturedIntegrations` installs every integration and every
  third-party package that they join. The owner accepted this for this package.
- Each extension holds one line, for example `import ProjecturedSDL`. An
  extension can load a dependency of its parent.
- Only the `using ProjecturedIntegrations` line of the user loads the package.
  So a session that does not name it never switches its extensions on.
- `ProjecturedIntegrations` means "load all". An integration set to `manual`
  for AutoIntegrations still loads through the extension. The documents say so.

### 4.7 The names that a user calls

The owner, 2026-10-03:

> I don't think it's a good idea to re-export all names from the platform,
> there are so many and most users only a handful. There should be a package
> which contains the most useful names, those can be re-exported.

- The kernel exports 577 names, and the platform exports 2999 (2026-10-03).
- A new slice of the platform, `EssentialsModule` in
  `source/platform/essentials/`, holds no code of its own. It exports a short
  list of names of the kernel and the platform (section 9.6).
- The list comes from the guides. It holds the names that show a value, and
  the names that open a window on a document, as the own-project guide does:

  | Names | Slice | What they do |
  | --- | --- | --- |
  | `display_in_editor`, `close_display_editor!`, `refresh_display_editor!`, `EditorDisplay` | platform, display | show a value in a window |
  | `run_editor!`, `build_editor`, `Editor` | kernel, editor | open an editor on a document |
  | `parse_natural_text`, `NaturalToGraphics`, `FontFileMeasure` | platform, natural and style | make a document from text, and draw it |
  | `print_document`, `write_image` | kernel, projection and backend | a view with no window, and an image file |

- `ProjecturedPlatform` does not export the five names of the kernel in this
  list. Only the flat namespace of the umbrella makes them visible now.
- Each integration and each backend (`ProjecturedConsole`, `ProjecturedPDF`,
  `ProjecturedWeb`) re-exports the names of `ProjecturedPlatform.EssentialsModule`.
  `Projectured` does the same. A user who writes a projection names
  `ProjecturedPlatform`.
- So `using ProjecturedSDL, ProjecturedDataFrames` makes `display_in_editor`
  visible.
- Two packages that re-export the same binding do not conflict in `Main`.
- A test checks that each name of the list is defined and exported. The design
  document of the package lists the names and says what each one does.

### 4.8 What goes away

- `package/Projectured/ext/`, six files, and the tables `[weakdeps]` and
  `[extensions]` of `package/Projectured/Project.toml`.
- `_INSTALLED_PACKAGES` and `__init__` in `source/projectured/Projectured.jl`.
- `load_installed_package!` in `source/platform/domain/Domain.jl`, its export in
  `DomainModule.jl`, `test/platform/document/InstalledPackageTest.jl`, and its
  line in `documentation/package/platform/domain/domain.md`.
- The cases of the umbrella extensions in `IntegrationLoadingTest.jl`. Step 3
  writes the new cases.

## 5. The README of `Projectured.jl`

`_format_projectured_release_overview` writes the front page. The parts
"Install" and "Use" replace the part "Install" of `julia-112`. The text is for
a Julia user who does not know ProjecturEd.

````markdown
## Install

The packages are in the registry `ProjecturedRegistry`. Add General too, for the
packages that they depend on. If General is there already, the line does
nothing.

```
pkg> registry add General
pkg> registry add https://github.com/projectured/ProjecturedRegistry
```

Each package installs only what it needs. Add each package that you use by its
name. A `using` line reaches only the packages that you added, so add the
packages of other authors that you load too.

## Use

To install and to load are two different steps. You can load in two ways.

### Name each package

```
pkg> add ProjecturedSDL ProjecturedDataFrames DataFrames

julia> using DataFrames, ProjecturedSDL, ProjecturedDataFrames
julia> display_in_editor(DataFrame(n = 1:100_000, square = (1:100_000) .^ 2))
```

`ProjecturedSDL` installs SimpleDirectMediaLayer, and `ProjecturedDataFrames`
installs DataFrames. The session loads the packages that you name and the
packages that they depend on. Nothing else loads.

### Let `Projectured` load the integrations

```
pkg> add Projectured ProjecturedSDL ProjecturedDataFrames DataFrames SimpleDirectMediaLayer

julia> using Projectured, DataFrames, SimpleDirectMediaLayer
julia> display_in_editor(DataFrame(n = 1:100_000, square = (1:100_000) .^ 2))
```

`using Projectured` loads the kernel, the platform and AutoIntegrations.
AutoIntegrations loads an integration that you installed when all its triggers
are loaded. The order of the `using` lines does not matter.

| Integration | It joins | It loads when these are loaded |
| --- | --- | --- |
| `ProjecturedSDL` | SimpleDirectMediaLayer: native windows | Projectured, SimpleDirectMediaLayer |
| `ProjecturedDataFrames` | DataFrames: a table of a data frame | Projectured, DataFrames |
| `ProjecturedVideo` | FFMPEG: a video of a session | Projectured, FFMPEG |
| `ProjecturedODBC` | ODBC: a live database | Projectured, ODBC |
| `ProjecturedTulip` | Tulip: a constraint layout | Projectured, Tulip |
| `ProjecturedMCP` | ModelContextProtocol: an external assistant | Projectured, ModelContextProtocol |

An integration that loads in this way puts no name into `Main`. To write
`SdlBackend()`, add `using ProjecturedSDL`.

### Choose for each integration

Each integration says if it loads by itself. You can change it for each
package in the file `LocalPreferences.toml` beside the `Project.toml` of your
environment:

```toml
[AutoIntegrations]
ProjecturedSDL = "auto"
ProjecturedDataFrames = "manual"
```

`"auto"` loads the integration when its triggers are loaded. `"manual"` loads
it only when you name it. A package with no line keeps its own default. This
call writes the same line:

```
pkg> add AutoIntegrations

julia> using AutoIntegrations
julia> set_auto_integration!("ProjecturedDataFrames", :manual)
```

### Load all integrations

```
pkg> add ProjecturedIntegrations DataFrames SimpleDirectMediaLayer

julia> using ProjecturedIntegrations, DataFrames, SimpleDirectMediaLayer
```

`ProjecturedIntegrations` installs every integration and every package that
they join. It loads an integration when the package that it joins is loaded.
Use it when you want all of them and do not want to choose.

### Why there are so many packages

ProjecturEd joins many packages of other authors, and each join is one small
package. Pkg installs all dependencies of a package and has no optional ones.
So each integration is its own package, and you install only the ones that you
add. Some users want the integrations to load by themselves, and some users
name each package. The setting for each package lets you choose.
````

The README of each released package changes too
(`_format_projectured_package_readme`):

- The install line adds the package alone, for example `pkg> add ProjecturedSDL`.
- An integration gives its triggers and its default. The generator reads them
  from the table `[auto-integration]` of the package, so the triggers have one
  source.
- `PROJECTURED_PACKAGE_READMES` gets entries for `AutoIntegrations`,
  `ProjecturedIntegrations` and `ProjecturedAll`.
  `ProjecturedAll` leaves `PROJECTURED_RELEASE_EXCLUSIONS`, and the sentence of `Projectured` changes.

## 6. Documentation

| Document | Change |
| --- | --- |
| a new design document of AutoIntegrations (decision D7) | how the hook works, the table, the setting, and section 3 of this plan in full |
| `documentation/guide/own-project-guide.md` | the part "Two ways to load the integrations" becomes: install, the manual way, the automatic way, the setting, `ProjecturedIntegrations` |
| `documentation/rule/package-rules.md` | the umbrella, AutoIntegrations, `ProjecturedIntegrations`, and the rule on third-party dependencies (D3) |
| `documentation/rule/naming-rules.md` | the name `AutoIntegrations` breaks `Projectured<Slice>` because it is generic, and the example of an extension name |
| `documentation/design/system-anatomy.md` | the list and the graph of the packages |
| `documentation/design/domain-inventory.md` | a domain declares `[auto-integration]` (D2) in place of `_INSTALLED_PACKAGES` |
| `documentation/guide/new-domain-guide.md` | the same, if it names the umbrella list |
| `documentation/package/platform/domain/domain.md` | `load_installed_package!` goes |
| the documents of SDL, DataFrames, Video, ODBC, Tulip, MCP | the triggers and the default |
| the document of the builder | the README of a package and the front page |
| a new design document of `EssentialsModule`, `documentation/package/platform/essentials/essentials.md` | the list of names, what each one does, and which packages re-export them |
| `documentation/README.md` | the new documents |
| `plan/pending/release-the-binary-and-the-packages.md` | the items of Part R that this plan changes |

## 7. Steps

- [x] **Step 1, AutoIntegrations.** The package, its test package, and tests
      with scratch packages in temporary environments that name no ProjecturEd
      package. Check that Pkg keeps `[auto-integration]` through `add`,
      `develop` and `resolve`, and that LocalRegistry `register` accepts it.
      Done: `package/AutoIntegrations/src/AutoIntegrations.jl`, the test package
      `AutoIntegrationsTest` with `test/autointegrations/`. `test_autointegrations()`
      passes 20 of 20: the two triggers, the order of the `using` lines, a chain,
      a package that is no direct dependency, a package that fails to load, the
      states of `LocalPreferences.toml`, and `set_auto_integration!`.
      `Pkg.develop` keeps the table. The check of `register` moves to step 10,
      where the local registry is.
- [x] **Step 2, the declarations.** The table in the six integrations, and in
      the packages of decision D2. Done: 28 packages, each with the default
      `auto`: the six with `Projectured` and their third-party package, and the
      17 domains, the console, PDF and the three model adapters with
      `Projectured` alone. `ProjecturedWeb` has none.
- [x] **Step 3, the umbrella.** Remove what section 4.8 names. `Projectured`
      depends on AutoIntegrations. Rewrite `IntegrationLoadingTest.jl` with
      these cases, each in a scratch environment with
      `JULIA_LOAD_PATH=@:@stdlib`:
      1. `using DataFrames, ProjecturedSDL, ProjecturedDataFrames` loads them
         and their dependencies, and not AutoIntegrations.
      2. `using Projectured, DataFrames, SimpleDirectMediaLayer` loads both
         integrations, in each order.
      3. The same with `ProjecturedDataFrames = "manual"` loads only SDL.
      4. `using Projectured` alone loads no integration.
      5. An integration that is not installed does not load, and gives no
         warning.
      Done: `Projectured` depends on `ProjecturedEssentials` and
      AutoIntegrations, and re-exports the names of `ProjecturedEssentials`.
      `ProjecturedEssentials` came here from step 5, because the umbrella needs
      it; section 9.6 turned it into a slice of the platform. `load_installed_package!` and its test are gone. The cases 1 to 5 run
      in a scratch environment of a user (`Projectured`, `ProjecturedSDL`,
      `ProjecturedDataFrames`, `ProjecturedJSON`, DataFrames,
      SimpleDirectMediaLayer); one more case loads the other four triggers in
      `environment/all`. `test_packages_declare_triggers()` replaces
      `test_umbrella_names_every_package()`. 8 of 8 and 29 of 29.
- [x] **Step 4, `ProjecturedIntegrations`.** The package and its six
      extensions, and a test case:
      `using ProjecturedIntegrations, DataFrames` loads `ProjecturedDataFrames`.
      Done: the source of the package is in `source/integrations/`, its
      extensions in `package/ProjecturedIntegrations/ext/`.
      `test_integrations_load_with_extensions()` passes 3 of 3: the extension
      loads `ProjecturedDataFrames`, nothing loads without DataFrames, and a
      "manual" setting does not stop the extension.
- [x] **Step 5, the names.** `ProjecturedEssentials` and its test (a slice of
      the platform since section 9.6). The
      integrations, the backends and `Projectured` re-export its names.
      Done: the six integrations and the three backends depend on
      `ProjecturedEssentials` and re-export its names with one `export` that
      reads `names(ProjecturedEssentials)`, as the umbrella and
      `ProjecturedIntegrations` do. The export of the three display names in
      `ProjecturedDataFrames` went into it. `test_essential_names()` checks that
      the 11 packages export the 12 names with the same bindings (12 of 12), and
      the manual case of `test_umbrella_loads_integrations()` checks that
      `display_in_editor` is visible. This test found the fault of section 9.3.
- [x] **Step 6, the release.** The README texts of section 5, the entries of
      `PROJECTURED_PACKAGE_READMES`, the release copy of a package with no
      slice folder, and the release tests.
      Done: `ProjecturedAll` is released; `PROJECTURED_PACKAGE_READMES` has
      entries for `AutoIntegrations`, `ProjecturedEssentials`,
      `ProjecturedIntegrations` and `ProjecturedAll`. The README of a package
      installs it alone, and says when AutoIntegrations loads it, from the
      table of its `Project.toml`. The front page holds the text of section 5;
      its table of integrations comes from the same tables. The suite name of a
      released package drops the prefix with `chopprefix`, so
      `AutoIntegrationsTest` runs `test_autointegrations()`.
      `test_package_release()` passes 61 of 61 and 167 of 167. The two design
      documents of section 6 came here, because a README entry names its
      document and the test checks that it exists.
- [x] **Step 7, the guards.** The naming guard, the package graph and the tree
      guard accept `AutoIntegrations`.
      Done: the suite rule of the naming guard drops the prefix with
      `chopprefix`, so it reads `AutoIntegrationsTest` as the slice
      `autointegrations`. The package graph reads `ext/` too, where
      `ProjecturedIntegrations` names the integrations (380 of 380). The tree
      and documentation guards pass; the exports and arguments guards give the
      same findings as `julia-112`. The binary loads the platform, not the
      umbrella (section 9.5); `test_builder()` passes 473 of 473.
- [x] **Step 8, the documentation.** Section 6.
      Done: the two design documents (step 6 and section 9.6), and 25 files
      by a documentation agent that I reviewed: the guides, the rules, the
      anatomy, the package documents, the builder document, the index, and
      each code example that wrote `using Projectured` and used a name that
      is not essential (checked with Julia; `debugging-guide.md`,
      `application.md`, `editor.md`, `tulip.md` and two docstrings name
      `ProjecturedPlatform` now). The documentation guard passes; its two new
      soft lines are "wants" said of a user.
- [x] **Step 9, downstream.** omnet-julia and inet-julia precompile. I expect
      no change, because they do not load the umbrella.
      Done: scratch environments of both repositories against the packages of
      this worktree (`/var/tmp/down3/run.sh`): omnet-julia precompiles 108
      packages in 140 s, inet-julia 12 in 77 s, with no error. Neither loads
      the umbrella, so AutoIntegrations is not in their manifests.
- [x] **Step 10, the check.** A new user in an empty depot, from a local
      registry, for the manual way, the automatic way, the setting and
      `ProjecturedIntegrations`. The suites of the changed packages,
      `test_builder()` and `test_repository()`.
      Done, as a sample (the owner, 2026-10-03: "the complete long running
      tests should be done before the final publication of the registry and
      the module, make this development process fast by only testing minimal
      stuff that tells we are on the right track"):
      - the new user (`/var/tmp/b4a/run.sh`), on `5814b9df3`: 35 packages
        released and registered by LocalRegistry; the five cases pass,
        `display_in_editor` opens offscreen in the manual way, and
        `Pkg.test("AutoIntegrations")` of the released package passes;
      - the 10 test packages of the changed packages load;
      - `test_platform_layering()` (it found the `using` list of
        `EssentialsModule`, now a bare `using` of each owner),
        `test_platform_slice_edges()`, `test_console()` 140, `test_pdf()` 50,
        `test_autointegrations()` 22, `test_builder()` 473,
        `test_package_release()` 61 and 156, `test_package_graph()` 373, the
        four loading tests, and the naming, tree and documentation guards.
- [x] **Step 10c, the slice under `src/` (added by the owner, 2026-10-03).**
      The release copy puts `source/<path>` at `<package>/src/<path>`, and the
      include of the entry file names the path from `src/`, so
      `ProjecturedJSON/src/domain/json/JsonModule.jl`. `source/` and `src/`
      are both one folder below the root, so each file keeps its depth and a
      path from `@__DIR__` reaches the same folder; one rule serves every
      package. Done in `_write_package_content`; the coverage of the workflow
      reads `src` and `ext`. `test_package_release()` passes 62 of 62 and 156
      of 156, and `ProjecturedJSON` loads from a generated release with the
      kernel and the platform of the same release.
- [x] **Step 10d, AutoIntegrations in its own repository (the owner,
      2026-10-03).** `~/workspace/auto-integrations` (the owner renamed the
      folder from `AutoIntegrations.jl`), pushed as the
      repository `projectured/AutoIntegrations.jl` (`eed3a80`): the source
      unchanged, `test/runtests.jl` from the scratch-package tests
      (`Pkg.test()` passes 22 of 22), a README with the mechanism and the
      reasons, the MIT licence, and a CI workflow. In this repository the
      package, its test package and `test/autointegrations/` went away; the
      umbrella and `environment/all` name the sibling by `../../../auto-integrations`
      (section 9.7); the release does not copy it, and its front page links
      it. The graph (366), the loading tests (8, 3, 29) and the release test
      (62, 154) pass.
      The new-user check on `383cb9345` passes its five cases, with a local
      registry that holds AutoIntegrations from `~/workspace/auto-integrations`
      and the 34 released packages; `Pkg.test("AutoIntegrations")` runs the
      tests of the new repository.
- [ ] **Step 10b, before the publication.** The full suites: each package
      suite in its own environment as CI runs them, `test_integration()`, and
      the comparison with `main` for each failure.
- [x] **Step 10e, two gaps of the release (the owner, 2026-10-03).** The
      workflow of the release adds General and ProjecturedRegistry, because its
      jobs of `Projectured` and `ProjecturedIntegrations` resolve AutoIntegrations
      from ProjecturedRegistry, and Julia adds General by itself only when no
      registry is there. A package that the manifest reaches by path and that
      the repository does not hold, AutoIntegrations, gets the `[compat]` bound
      of the version that the manifest names. `test_package_release()` passes
      62 of 62 and 157 of 157. The first run of the release CI failed in all
      32 jobs: `ProjecturedRegistry` is private, and a job has no token for it.
      So a job adds AutoIntegrations from its public repository by URL, and no
      registry; General comes by itself.
- [x] **Step 10f, each test and example package once (the owner,
      2026-10-03).** The release copied the test package of each released
      package and every test or example package that it needs into its
      `test/support/`: 216 folders of 55 packages, 88 MB of 128 MB, 8195 of 9216
      files. The owner's requirements: no test or example package at the root
      of `Projectured.jl`, `Pkg.test` of an installed package works, and GitHub
      CI reaches them. Now each support package is released once, a test
      package in `test/<Name>/` and an example package in `example/<Name>/`,
      with a version and bounds as any package, and the registry holds it. A
      released package's `test/Project.toml` names its test package, and a job
      develops every folder that its test needs. A support package counts the
      files of its `test/` in its version, because a test package keeps its
      suite there. The release: 34 packages at the root, 32 in `test/`, 23 in
      `example/`, 49 MB and 1767 files. `test_package_release()` passes 67 of 67
      and 160 of 160.
- [ ] **Step 11, cleanup, after the owner's word.** The branch
      `integration-shells`, its worktree and the two downstream branches. A
      new private release from the new head, with the commands for the owner.

## 8. Decisions

The owner, 2026-10-03: "mostly agreed". The answers:

| Decision | Answer |
| --- | --- |
| D1, the candidates | the direct dependencies of each environment of the load path, the set that a `using` line in `Main` can reach |
| D2, the domains, the console, PDF, the model adapters | the trigger `Projectured`, the default `auto`; no table for `ProjecturedWeb` |
| D3, `ProjecturedIntegrations` and `ProjecturedAll` | `ProjecturedIntegrations` holds the six integrations only; `ProjecturedAll` holds no integration |
| D3a, the packages with HTTP | `ProjecturedAll` holds each package with no third-party dependency, as now; the model adapters and `ProjecturedWeb` stay out |
| D3b, release `ProjecturedAll` | yes: "most people will not use it, All in the name is scary enough" |
| D4, the names of the manual line | a package of the most useful names, which other packages re-export |
| D5, the form of the triggers | a table of names and uuids |
| D6, `ProjecturedIntegrations` re-exports `Projectured` | yes |
| D7, where AutoIntegrations lives | first `package/AutoIntegrations/`; then its own repository, `projectured/AutoIntegrations.jl`, MIT (D18) |
| D8, the name | `AutoIntegrations` |
| D9, no `default` in the table | `"manual"` |
| D10, the order | `julia-112` lands first |
| D11, the name of the package of the names | `ProjecturedEssentials`, then no package: the slice `ProjecturedPlatform.EssentialsModule` (D17) |
| D12, who re-exports the names | the six integrations and the backends `ProjecturedConsole`, `ProjecturedPDF`, `ProjecturedWeb` |
| D13, the names of `Projectured` | only the essential names |
| D14, the list | all names of section 4.7 stay: "you can keep them" |
| D15, `Projectured` exports `set_auto_integration!` | no |
| D16, `Projectured` binds the submodules | no |
| D17, a package or a module for the essential names | a module of the platform: the owner agreed, 2026-10-03 |
| D18, AutoIntegrations in its own repository | yes, MIT, private on GitHub first, registered in ProjecturedRegistry first (the owner, 2026-10-03) |

No decision is open.

## 9. Decisions made during the work

### 9.1 AutoIntegrations reads `LocalPreferences.toml` itself

Julia gives the preferences of a package only to an environment that names the
package in `[deps]` or `[extras]` (`collect_preferences` in `base/loading.jl`:
"we only allow actual dependencies to have preferences set"). The environment
of the user names `Projectured`, not AutoIntegrations, so Preferences.jl would
not see a table `[AutoIntegrations]` that the user writes. So AutoIntegrations
reads the first of `JuliaLocalPreferences.toml` and `LocalPreferences.toml`
beside each project of the load path, as Julia finds them, and
`set_auto_integration!` writes the file of the active project. It depends on the
TOML standard library alone.

### 9.2 The candidates are read again when a file changes

The candidates come from the project files of the load path and the manifests
beside them. AutoIntegrations keeps them with the times of change of these
files, so an `add`, an `update` or an `activate` in the session gives new
candidates at the next load of a package. It reads the state of a candidate
again each time, only when the triggers of the candidate are loaded.

### 9.3 The callback waits while a package loads

`import Projectured, ProjecturedSDL` loads SimpleDirectMediaLayer inside the
load of `ProjecturedSDL`. Julia calls the callback of SimpleDirectMediaLayer
while `ProjecturedSDL` is still in `Base.package_locks`, so AutoIntegrations
found `ProjecturedSDL` ready and loaded it a second time:
`ConcurrencyViolationError("deadlock detected in loading ProjecturedSDL using
ProjecturedSDL")`. A candidate that needs a package in progress, as Video needs
SDL, fails the same way. Julia calls the callback of the outer package after
`end_loading`, so the callback now does nothing while `Base.package_locks` holds
a package, and the callback after the outermost load does the work. The scratch
package `GlueNeedsB` reproduces it in `test_automatic_load()`: it imports one of
its triggers. A scratch package that names a dependency but does not import it
does not reproduce it, because Julia loads only what the code imports.

### 9.4 `ProjecturedMCP` loads the platform

`ProjecturedMCP` depended on the kernel alone. It re-exports the essential
names (D12), which are a slice of the platform, so it depends on the platform
and `using ProjecturedMCP` loads the platform too. An MCP server
drives an editor, which needs the platform in each real use.

### 9.5 The binary loads the platform, not the umbrella

The binary called `Projectured.run_application_command` and
`Projectured.warm_application`, which the flat namespace of the umbrella gave.
The umbrella now gives only the essential names. A binary holds a fixed set of
packages and imports its domains by name, so AutoIntegrations has no part in
it: it loads `ProjecturedPlatform` in place of `Projectured`, and calls the two
functions through it.

### 9.6 The essential names are a module of the platform

The owner asked whether the essential names need a package of their own, since
no user installs it or names it in a `using` line. They do not: each package
that re-exports them depends on the platform, `ProjecturedMCP` too after
section 9.4, and the names include names of the platform, so the kernel can not
hold them. A package costs a registry entry, a README, a version and a test job,
and gives the user nothing. So the package `ProjecturedEssentials`, which steps
3 and 5 made, became the slice `EssentialsModule` of the platform
(`source/platform/essentials/`, edges to display, natural and style). Each
re-exporter writes `using ProjecturedPlatform.EssentialsModule`, and
`Projectured` depends on the platform and AutoIntegrations, as the owner first
described it. The package graph passes 373 of 373 with one package fewer; the
loading tests and `test_essential_names()` pass.

### 9.7 The sibling checkout of AutoIntegrations

`package/Projectured/Project.toml` and `environment/all` name AutoIntegrations by
`path = "../../../auto-integrations"`, the folder beside the repository, as
omnet-julia names projectured-julia. The repository on GitHub keeps the name
`AutoIntegrations.jl`, so a clone names the folder:
`git clone https://github.com/projectured/AutoIntegrations.jl auto-integrations`.

From a worktree in `.claude/worktrees/` the same path ends in
`.claude/worktrees/auto-integrations`, so a symlink there, which git ignores,
points at the checkout. The worktree of this branch is therefore
`.claude/worktrees/auto-integrations-branch`. Pkg follows the symlink and writes
the path from the real folder, six levels up, into the manifest and into the
`[sources]` of `environment/all`; the tracked files keep
`../../../auto-integrations`, which works in the main checkout and, through the
symlink, in a worktree. `_make_scratch_environment` of the loading tests makes
each relative path of the manifest absolute.

The dev CI checks out `projectured/AutoIntegrations.jl` and moves it beside the
repository, in the two jobs that use `environment/all`. The owner made the
repository public, so the CI and a public clone of projectured-julia reach it
with no token.
