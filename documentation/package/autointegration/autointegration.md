# AutoIntegration

> **Kind:** design · **Status:** current · **Stands on:** [package-rules.md](../../rule/package-rules.md), [own-project-guide.md](../../guide/own-project-guide.md)

`AutoIntegration` loads an installed package when the packages that it names as its triggers are loaded, as the settings of the environment of the user choose. `using Projectured` loads it. It is a generic package of its own repository, [projectured/AutoIntegration.jl](https://github.com/projectured/AutoIntegration.jl), whose README says how the mechanism works. This document says how ProjecturEd uses it and why ProjecturEd installs and loads its packages in this way.

## Why it is so

ProjecturEd joins many packages of other authors. Now it joins six: SimpleDirectMediaLayer, DataFrames, FFMPEG, ODBC, Tulip and ModelContextProtocol. Later it can join dozens, for example a plot library, a file format or a database driver. Each join is one small package, an integration, such as `ProjecturedSDL` or `ProjecturedDataFrames`.

Pkg has no optional dependencies. `add` installs all of `[deps]`, and it never installs a `[weakdeps]` entry. So an integration that must work after `add` and `using` alone holds its third-party package in `[deps]`. That makes it a package of its own, which the user adds by name. An install is always explicit, and a package installs only what it needs.

A package extension can not serve both ways of use. An extension lives in its parent package, and Pkg does not install its triggers.

- An extension of the umbrella can load only what the umbrella installs. So the umbrella would install every integration and every third-party package.
- An extension inside the integration makes `add ProjecturedODBC` install no ODBC. Then `using ProjecturedODBC` alone fails.

Users want different things. One user wants the integrations to load by themselves. Another user names each package, because an automatic load costs time and memory and can surprise. With dozens of integrations, one switch for all is too coarse. So the setting is per package, in the environment of the user, and the package gives the default.

To install and to load are two steps. An install never changes what loads. Only a `using` line and the settings of the user change it.

## The triggers of the packages of ProjecturEd

A package declares its triggers in a table of its `Project.toml`:

```toml
[auto-integration]
default = "auto"

[auto-integration.triggers]
Projectured = "92922de3-b970-4d9a-8b2a-9d6f361397b5"
SimpleDirectMediaLayer = "98e33af6-2ee5-5afd-9e75-cbc738b767c4"
```

| Packages | Triggers | Default |
| --- | --- | --- |
| the 18 domains, `ProjecturedConsole`, `ProjecturedPDF`, `ProjecturedOllama`, `ProjecturedAnthropic`, `ProjecturedOpenRouter` | `Projectured` | auto |
| `ProjecturedSDL` | `Projectured`, `SimpleDirectMediaLayer` | auto |
| `ProjecturedDataFrames` | `Projectured`, `DataFrames` | auto |
| `ProjecturedVideo` | `Projectured`, `FFMPEG` | auto |
| `ProjecturedODBC` | `Projectured`, `ODBC` | auto |
| `ProjecturedTulip` | `Projectured`, `Tulip` | auto |
| `ProjecturedMCP` | `Projectured`, `ModelContextProtocol` | auto |

`ProjecturedWeb` declares no table: a loaded web backend becomes the default backend when SDL is absent, so it loads only by name. `test_packages_declare_triggers()` checks the table. A new domain declares the trigger `Projectured` with the default `auto` ([domain-inventory.md](../../design/domain-inventory.md)).

## The setting of the user

The file `LocalPreferences.toml` beside the `Project.toml` of an environment holds the state of each package:

```toml
[AutoIntegration]
ProjecturedSDL = "auto"
ProjecturedDataFrames = "manual"
```

`"auto"` loads the package when its triggers are loaded. `"manual"` loads it only when a `using` line names it. A package with no entry has its default. `set_auto_integration!` writes the same entry. A `using` line in `Main` reaches only the packages that the user added, and `add Projectured` adds AutoIntegration only as a dependency, so a user who calls the function adds AutoIntegration by name:

```
pkg> add AutoIntegration

julia> using AutoIntegration
julia> set_auto_integration!("ProjecturedDataFrames", :manual)   # from the next load
```

A package that AutoIntegration loads binds no name in `Main`. To write `SdlBackend()`, a user writes `using ProjecturedSDL`.

## How it fits

`Projectured` depends on `AutoIntegration` and `ProjecturedPlatform`, loads both, and re-exports the names of `ProjecturedPlatform.EssentialsModule` ([essentials.md](../platform/essentials/essentials.md)). The integrations do not depend on AutoIntegration: `using ProjecturedSDL` alone never loads it.

The repository of AutoIntegration sits beside this one. `package/Projectured/Project.toml` and `environment/all` name it by the folder `../../../auto-integration`, as a sibling checkout. The release of ProjecturEd does not copy it: the registry holds it as a package of its own, and the released `Projectured` depends on it there.

`ProjecturedIntegrations` is the other way to load every integration. It depends on the six integrations and loads each one with an ordinary package extension when the package that it joins is loaded. It loads an integration that the user sets to `"manual"` too: it means "load all".

## Tests

The repository of AutoIntegration holds the tests of the mechanism, with small scratch packages. Here, `test_umbrella_loads_integrations()` and `test_integrations_load_with_extensions()` of `ProjecturedTest` run the cases of a user with the real packages, and `test_packages_declare_triggers()` checks the tables.
