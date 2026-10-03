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
| `Projectured` | ProjecturedKernel, ProjecturedPlatform, AutoIntegrations | the user | yes |
| `AutoIntegrations` | Preferences, TOML | `Projectured` | yes |
| `ProjecturedSDL`, … (the six) | as on `main`, table in section 2 | the user, or AutoIntegrations | yes |
| `ProjecturedIntegrations` | Projectured and the six | the user | yes |
| `ProjecturedAll` | decision D3 | the tests, the examples, the REPL | decision D3 |

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
third-party package of the extension on `main`. The defaults are my
recommendation: the user installed the integration and loaded the package that
it joins.

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

AutoIntegrations reads the file with Preferences.jl, which merges the files of
the load path, with the active project first. One function writes the file of
the active project: `set_auto_integration!(name, state)`, with the state
`:auto`, `:manual` or `nothing`. `nothing` removes the entry. The name of the
function is my recommendation.

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

`Projectured` depends on the kernel, the platform and AutoIntegrations, and
loads AutoIntegrations. It has no hook, no extension and no `[weakdeps]` of its
own. It re-exports the names of the kernel and the platform, as now.

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

### 4.7 What goes away

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
- `PROJECTURED_PACKAGE_READMES` gets entries for `AutoIntegrations` and
  `ProjecturedIntegrations`, and the sentence of `Projectured` changes.

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
| `documentation/README.md` | the new document |
| `plan/pending/release-the-binary-and-the-packages.md` | the items of Part R that this plan changes |

## 7. Steps

- [ ] **Step 1, AutoIntegrations.** The package, its test package, and tests
      with scratch packages in temporary environments that name no ProjecturEd
      package. Check that Pkg keeps `[auto-integration]` through `add`,
      `develop` and `resolve`, and that LocalRegistry `register` accepts it.
- [ ] **Step 2, the declarations.** The table in the six integrations, and in
      the packages of decision D2.
- [ ] **Step 3, the umbrella.** Remove what section 4.7 names. `Projectured`
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
- [ ] **Step 4, `ProjecturedIntegrations`.** The package and its six
      extensions, and a test case:
      `using ProjecturedIntegrations, DataFrames` loads `ProjecturedDataFrames`.
- [ ] **Step 5, decisions D3 and D4.** `ProjecturedAll`, and the names of the
      manual line.
- [ ] **Step 6, the release.** The README texts of section 5, the entries of
      `PROJECTURED_PACKAGE_READMES`, the release copy of a package with no
      slice folder, and the release tests.
- [ ] **Step 7, the guards.** The naming guard, the package graph and the tree
      guard accept `AutoIntegrations`.
- [ ] **Step 8, the documentation.** Section 6.
- [ ] **Step 9, downstream.** omnet-julia and inet-julia precompile. I expect
      no change, because they do not load the umbrella.
- [ ] **Step 10, the check.** A new user in an empty depot, from a local
      registry, for the manual way, the automatic way, the setting and
      `ProjecturedIntegrations`. The suites of the changed packages,
      `test_builder()` and `test_repository()`.
- [ ] **Step 11, cleanup, after the owner's word.** The branch
      `integration-shells`, its worktree and the two downstream branches. A
      new private release from the new head, with the commands for the owner.

## 8. Open decisions

Each recommendation is mine, not a decision.

- **D1, which packages are candidates.**
  - (a) The direct dependencies of the active project only.
  - (b) The direct dependencies of each environment of the load path.
  - (c) Each package of the manifests of the load path.

  I recommend (b). It is the set that a `using` line in `Main` can reach, so
  AutoIntegrations loads nothing that the user could not name. (a) misses a
  package that the user installed in the shared environment, for example
  `@v1.13`. (c)
  loads packages that the user did not add, which breaks R1.
- **D2, the domains, the console, PDF and the model adapters.** On `main` the
  umbrella loads them when they are installed.
  - (a) Each declares `[auto-integration]` with the trigger `Projectured` and
    the default `auto`.
  - (b) They load only by name.

  I recommend (a). A user who installed `ProjecturedJSON` and wrote
  `using Projectured` expects a window to open JSON, and the setting can turn
  it off. `ProjecturedWeb` gets no table, because a loaded web backend becomes
  the default backend when SDL is absent.
- **D3, `ProjecturedAll`.** The owner wrote "ProjecturedAll brings in all
  components". Now it holds the kernel, the platform, the console, PDF and the
  17 domains, and no integration. `package-rules.md` says that this is
  deliberate, so that `using ProjecturedAll` loads no ODBC driver manager and
  no solver.
  - (a) `ProjecturedAll` depends on every package, the six integrations
    included. Each environment that uses it (the examples, the REPL, the bench,
    `ProjecturedTest`, omnet, inet) installs and loads all of them. The rule
    in `package-rules.md` changes.
  - (b) `ProjecturedAll` stays as it is. For a user, "all" is
    `ProjecturedIntegrations`.

  The owner's text reads as (a). I recommend (b), because of the load time of
  each test and each example. Please confirm which one.
- **D4, the names of the manual line.** `using ProjecturedSDL,
  ProjecturedDataFrames` does not make `display_in_editor` visible, because it
  is a name of `ProjecturedPlatform`.
  - (a) Each integration re-exports the exported names of
    `ProjecturedPlatform`.
  - (b) Each integration re-exports a short list: `display_in_editor`,
    `run_editor!` and some more.
  - (c) The manual line names the platform:
    `using ProjecturedPlatform, ProjecturedSDL, ProjecturedDataFrames`.

  I recommend (a). It gives the owner's line as written, and two integrations
  that re-export the same binding do not conflict.
- **D5, the form of the triggers.** A table of names and uuids, as in section
  4.2, or a list of names. I recommend the table: it says exactly which
  package, as `[weakdeps]` does.
- **D6, does `ProjecturedIntegrations` re-export `Projectured`?** I recommend
  yes, so one `using ProjecturedIntegrations` line is enough.
- **D7, where AutoIntegrations lives.**
  - (a) The code in `package/AutoIntegrations/src/AutoIntegrations.jl`, and
    its document in `documentation/package/autointegrations/`.
  - (b) The code in a slice folder such as `source/tool/autointegrations/`.

  I recommend (a). The package names no ProjecturEd package, so it can later
  move to its own repository and to General.
- **D8, the name.** The owner wrote `AutoIntegrations` on 2026-10-02 and
  `AutoIntegration` on 2026-10-03. This plan uses `AutoIntegrations`.
- **D9, the default when a table has no `default`.** I recommend `"manual"`,
  because of R6.
- **D10, the order of the landings.** I recommend that `julia-112` lands
  first. It is complete, and this branch starts from it.
