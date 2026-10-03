# AutoIntegrations

> **Kind:** design · **Status:** current · **Stands on:** [package-rules.md](../../rule/package-rules.md), [own-project-guide.md](../../guide/own-project-guide.md)

`AutoIntegrations` loads an installed package when the packages that it names as its triggers are loaded, as the settings of the environment of the user choose. `using Projectured` loads it. It names no ProjecturEd package: each package declares its own triggers. This document says how it works and why ProjecturEd installs and loads its packages in this way.

## Why it is so

ProjecturEd joins many packages of other authors. Now it joins six: SimpleDirectMediaLayer, DataFrames, FFMPEG, ODBC, Tulip and ModelContextProtocol. Later it can join dozens, for example a plot library, a file format or a database driver. Each join is one small package, an integration, such as `ProjecturedSDL` or `ProjecturedDataFrames`.

Pkg has no optional dependencies. `add` installs all of `[deps]`, and it never installs a `[weakdeps]` entry. So an integration that must work after `add` and `using` alone holds its third-party package in `[deps]`. That makes it a package of its own, which the user adds by name. An install is always explicit, and a package installs only what it needs.

A package extension can not serve both ways of use. An extension lives in its parent package, and Pkg does not install its triggers.

- An extension of the umbrella can load only what the umbrella installs. So the umbrella would install every integration and every third-party package.
- An extension inside the integration makes `add ProjecturedODBC` install no ODBC. Then `using ProjecturedODBC` alone fails.

Users want different things. One user wants the integrations to load by themselves. Another user names each package, because an automatic load costs time and memory and can surprise. With dozens of integrations, one switch for all is too coarse. So the setting is per package, in the environment of the user, and the package gives the default.

To install and to load are two steps. An install never changes what loads. Only a `using` line and the settings of the user change it.

## How it works

### A package declares its triggers

A package takes part with a table in its `Project.toml`. Each trigger is a package name with its uuid, as in `[weakdeps]`. A trigger need not be a dependency: `ProjecturedSDL` does not depend on `Projectured`.

```toml
[auto-integration]
default = "auto"

[auto-integration.triggers]
Projectured = "92922de3-b970-4d9a-8b2a-9d6f361397b5"
SimpleDirectMediaLayer = "98e33af6-2ee5-5afd-9e75-cbc738b767c4"
```

`default` is `"auto"` or `"manual"`. A table with no `default` gives `"manual"`. A package with no table never loads by AutoIntegrations. Pkg keeps a table that it does not know through `add`, `develop` and `resolve`, and the release copies it.

The packages of this repository declare:

| Packages | Triggers | Default |
| --- | --- | --- |
| the 17 domains, `ProjecturedConsole`, `ProjecturedPDF`, `ProjecturedOllama`, `ProjecturedAnthropic`, `ProjecturedOpenRouter` | `Projectured` | auto |
| `ProjecturedSDL` | `Projectured`, `SimpleDirectMediaLayer` | auto |
| `ProjecturedDataFrames` | `Projectured`, `DataFrames` | auto |
| `ProjecturedVideo` | `Projectured`, `FFMPEG` | auto |
| `ProjecturedODBC` | `Projectured`, `ODBC` | auto |
| `ProjecturedTulip` | `Projectured`, `Tulip` | auto |
| `ProjecturedMCP` | `Projectured`, `ModelContextProtocol` | auto |

`ProjecturedWeb` declares no table: a loaded web backend becomes the default backend when SDL is absent, so it loads only by name. `test_packages_declare_triggers()` checks the table.

### The user sets the state

The file `LocalPreferences.toml` beside the `Project.toml` of an environment holds the setting:

```toml
[AutoIntegrations]
ProjecturedSDL = "auto"
ProjecturedDataFrames = "manual"
```

`"auto"` loads the package when its triggers are loaded. `"manual"` loads it only when a `using` line names it. A package with no entry has the state of its default. The first environment of the load path that has an entry decides, so the active project comes first. `set_auto_integration!(name, state)` writes the file of the active project, with the state `:auto`, `:manual` or `nothing`; `nothing` removes the entry.

AutoIntegrations reads the file itself, with the TOML standard library. Julia gives the preferences of a package only to an environment that names the package in `[deps]` or `[extras]`, and the environment of the user names `Projectured`, not AutoIntegrations. So Preferences.jl would not see the table.

### The candidates

A candidate is a direct dependency of an environment of the load path that declares the table. That is the set that a `using` line in `Main` can reach, so AutoIntegrations loads nothing that the user did not install by name. A folder of packages, such as `@stdlib`, gives no candidate.

AutoIntegrations reads the `Project.toml` of each direct dependency beside the path that `Base.locate_package` gives. It keeps the candidates with the times of change of the project files and of the manifests beside them, so an `add`, an `update` or an `activate` in the session gives new candidates at the next load. It reads the state of a candidate again each time, only when the triggers of the candidate are loaded.

### The hook

`__init__` adds one callback to `Base.package_callbacks`. In a process that writes a cache file, it adds nothing, so no cache file depends on what one user installed.

Julia calls the callback after each load of a package. The callback does nothing while a load is in progress. Julia calls the callback of a dependency while the package that imports it still loads: `import Projectured, ProjecturedSDL` loads SimpleDirectMediaLayer inside the load of `ProjecturedSDL`. A candidate loaded then could need the package in progress and load it a second time, which Julia stops with `ConcurrencyViolationError`. Julia calls the callback of the outer package after its load ends, and that callback does the work.

The callback loads each candidate that is not loaded, whose triggers are all loaded and whose state is `"auto"`, with `Base.require(::Base.PkgId)`. It repeats until a pass loads nothing, because a loaded package can be the trigger of another. A flag stops a second call while one call runs, because a load inside the callback calls the callbacks again.

A loaded candidate binds no name in `Main`. To write `SdlBackend()`, a user writes `using ProjecturedSDL`. If a candidate fails to load, a warning names it, the `using` line of the user goes on, and the session does not try the candidate again.

## How it fits

The code is one file, `package/AutoIntegrations/src/AutoIntegrations.jl`, and it depends on the TOML standard library alone. It names no ProjecturEd package, so it can move to a repository of its own. `test_autointegrations_layering()` checks that.

`Projectured` depends on `AutoIntegrations` and `ProjecturedEssentials`, and loads both. The integrations do not depend on AutoIntegrations: `using ProjecturedSDL` alone never loads it.

`ProjecturedIntegrations` is the other way to load every integration. It depends on the six integrations and loads each one with an ordinary package extension when the package that it joins is loaded. It loads an integration that the user sets to `"manual"` too: it means "load all".

## Usage

```
pkg> add Projectured ProjecturedSDL ProjecturedDataFrames DataFrames SimpleDirectMediaLayer

julia> using Projectured, DataFrames, SimpleDirectMediaLayer    # loads ProjecturedSDL and ProjecturedDataFrames

pkg> add AutoIntegrations

julia> using AutoIntegrations
julia> set_auto_integration!("ProjecturedDataFrames", :manual)  # from the next load
```

A `using` line in `Main` reaches only the packages that the user added, and `add Projectured` adds AutoIntegrations only as a dependency. So a user who calls `set_auto_integration!` adds AutoIntegrations by name. A user who edits `LocalPreferences.toml` needs no add.

## Tests

`AutoIntegrationsTest` builds small scratch packages in a scratch environment, and runs each case in a new Julia process that sees only that environment and the standard library: `test_automatic_load()` and `test_set_auto_integration()`. `test_umbrella_loads_integrations()` and `test_integrations_load_with_extensions()` of `ProjecturedTest` run the cases of a user with the real packages.

## Limits

- A setting applies from the next load of a package. AutoIntegrations does not unload a package that is set to `"manual"` after it loaded.
- The callback reads `Base.package_locks` under `Base.require_lock` to know whether a load is in progress. That is a name of Julia that is not public.
