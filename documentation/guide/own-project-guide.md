# ProjecturEd in your own project

> **Kind:** procedure · **Status:** current · **Stands on:** [package-rules.md](../rule/package-rules.md)

How to use ProjecturEd from a project of your own: how to reach the packages, which package to load, and how to open a window from your code.

## Reach the packages

The packages are in the registry `ProjecturedRegistry`, not in the General registry. Add the registry once, with General for the packages that ProjecturEd depends on, then add each package that your program uses by name:

```
pkg> registry add General
pkg> registry add https://github.com/projectured/ProjecturedRegistry
pkg> add Projectured ProjecturedJSON ProjecturedSDL SimpleDirectMediaLayer
```

A `using` line reaches only the packages that you added: a package that another one installs as its dependency is not enough. Update all ProjecturEd packages together, with `pkg> update`, because each version of a package is made for the versions of the other packages of the same release. The [front page of Projectured.jl](https://github.com/projectured/Projectured.jl), where the released packages are, lists them.

### From a clone of the source

A contributor reaches the packages by path instead, the way this repository reaches its own packages.

1. Clone ProjecturEd beside your project, and AutoIntegration beside it, because the umbrella names that folder:

   ```sh
   git clone https://github.com/projectured/AutoIntegration.jl auto-integration
   git clone https://github.com/projectured/projectured-julia
   ```

2. Name the packages you load in the `Project.toml` of your project, and give each one a path in `[sources]`:

   ```toml
   [deps]
   Projectured = "…"
   ProjecturedJSON = "…"
   ProjecturedSDL = "…"

   [sources]
   Projectured = {path = "../projectured-julia/package/Projectured"}
   ProjecturedJSON = {path = "../projectured-julia/package/ProjecturedJSON"}
   ProjecturedSDL = {path = "../projectured-julia/package/ProjecturedSDL"}
   ```

   The uuid of each package is in its own `Project.toml`. Give a path for every ProjecturEd package you name, and for none that you do not: a package that you do not name is reached through the ones you do.

3. Resolve, and not `instantiate` alone. `Pkg.resolve()` sees a dependency that appeared inside a package your manifest already lists; `instantiate` does not.

## Which package to load

| Package | What you get |
| --- | --- |
| `Projectured` | the umbrella: the essential names, `ProjecturedPlatform.EssentialsModule` ([essentials.md](../package/platform/essentials/essentials.md)), and AutoIntegration to load an installed package when its triggers are loaded ([autointegration.md](../package/autointegration/autointegration.md)) |
| `ProjecturedSDL` | the native window |
| `ProjecturedWeb` | the browser backend |
| `ProjecturedExample` | from a clone of the source only: the examples, the gallery and `run_value_viewer` |
| one domain, for example `ProjecturedJSON` | the names of that domain, with the kernel and the platform below it |

The application, with its Files pane, its tabs and its assistant, is no package to load: it runs from a clone of the source (`bin/projectured`), or as a binary that `bin/build_projectured` builds ([build-guide.md](build-guide.md)).

`add Projectured` installs the kernel, the platform and `AutoIntegration`, and nothing more. Add each domain that your program shows, and the console or the PDF backend if you use one. AutoIntegration loads each one that you installed when `Projectured` is loaded, because a domain declares `Projectured` as its trigger with the default `auto` ([autointegration.md](../package/autointegration/autointegration.md)). The names of a domain stay in its package: to write `JsonString`, add `using ProjecturedJSON`.

A program that shows data of one domain can load that domain and a backend without the umbrella. [package-rules.md](../rule/package-rules.md) says what each kind of package may depend on.

## Load the integrations

An integration joins ProjecturEd to another package: `ProjecturedSDL` to `SimpleDirectMediaLayer`, `ProjecturedVideo` to `FFMPEG`, `ProjecturedDataFrames` to `DataFrames`, `ProjecturedODBC` to `ODBC`, `ProjecturedTulip` to `Tulip`, and `ProjecturedMCP` to `ModelContextProtocol`. Add the integrations that you want; `add Projectured` installs none of them.

### Name each package

A session that names each package loads only the packages it names and their dependencies:

```julia
using SimpleDirectMediaLayer, DataFrames, ProjecturedSDL, ProjecturedDataFrames
```

### Let AutoIntegration load them

`using Projectured` loads `AutoIntegration` too. AutoIntegration loads an installed integration when the packages it names as triggers are loaded, in either order:

```julia
using Projectured, SimpleDirectMediaLayer, DataFrames    # loads ProjecturedSDL and ProjecturedDataFrames
```

### Choose for each integration

Each integration gives its own default. Set the state of a package in the file `LocalPreferences.toml` beside the `Project.toml` of your project:

```toml
[AutoIntegration]
ProjecturedSDL = "auto"
ProjecturedDataFrames = "manual"
```

`"auto"` loads the package when its triggers are loaded; `"manual"` loads it only when a `using` line names it. `set_auto_integration!(name, state)` writes the same file:

```
pkg> add AutoIntegration

julia> using AutoIntegration
julia> set_auto_integration!("ProjecturedDataFrames", :manual)
```

[autointegration.md](../package/autointegration/autointegration.md) says how the hook finds its candidates and in which order it loads them.

### Load every integration

```julia
using ProjecturedIntegrations, SimpleDirectMediaLayer, DataFrames
```

`ProjecturedIntegrations` installs every integration and every package that it joins, and loads each one with a package extension when the package it joins is loaded. Use it when you want all of them and do not want to choose.

The model adapters `ProjecturedOllama`, `ProjecturedAnthropic` and `ProjecturedOpenRouter` declare the trigger `Projectured` alone, with no third-party package to join: AutoIntegration loads each one that you installed when `Projectured` is loaded, and a loaded adapter does nothing until you ask for it by name (`assistant = :ollama`). The web backend loads only when you name it, because a loaded web backend becomes the default backend when SDL is absent.

An integration that AutoIntegration loads puts no name into `Main`; the names of the integration stay in it. To write `SdlBackend()` yourself, add `using ProjecturedSDL`.

`Projectured` gives only the essential names, `ProjecturedPlatform.EssentialsModule` ([essentials.md](../package/platform/essentials/essentials.md)): `display_in_editor`, `run_editor!` and the few others that most programs call. A program that needs another name of the kernel or the platform writes `using ProjecturedPlatform`.

## Open a window from your code

An editor needs three things: a backend, a document and a projection.

```julia
using Projectured, ProjecturedSDL

document = parse_natural_text(:json, "{\"name\": \"Alice\"}")
projection = NaturalToGraphics(measure = FontFileMeasure())
run_editor!(document, projection; window = (; title = "My data"))
```

The JSON domain is installed (step 2), so AutoIntegration loads it when `Projectured` is loaded, because `ProjecturedJSON` declares the trigger `Projectured` with the default `auto`, and `parse_natural_text` reads `:json`. `run_editor!` puts the view in a window of the title you give, and returns when the window closes. SDL is the one loaded backend that draws windows, so the call needs no `backend`. `mcp = true` starts the MCP server beside it, so an external client can drive the same editor ([mcp-guide.md](mcp-guide.md)).

`NaturalToGraphics` is the general renderer: it draws a document of any domain, and a struct of your own through reflection. A projection you wrote yourself goes in its place.

For a value that has no projection of its own, [view-your-data-guide.md](view-your-data-guide.md) is shorter: `run_value_viewer(value)`.

That window has no menu bar, no clipboard and no F1 help: what a window has besides the document in it is a set of wrappers of `build_editor`, each a keyword, each from the slice of `ProjecturedPlatform` that owns the feature. [shell.md](../package/platform/shell/shell.md) says what each keyword adds and why the order is what it is.

## Another backend, and no screen at all

The same document and projection go to another backend with no other change:

```julia
using ProjecturedWeb
run_editor!(document, projection; backend = WebBackend(), window = (; title = "My data"))
```

With SDL and Web both loaded, the call must name its backend.

The browser then shows the same window at `http://127.0.0.1:8080`.

A test or a script needs no window. `print_document(projection, document)` answers an IO map, which is the view together with the record that maps it back to the data; `iomap.output` is the view itself, and `write_image` writes it to a file. [testing-guide.md](testing-guide.md) says which helper checks what.

## What to expect

- The first start of a session compiles the code, which takes minutes. A built binary starts in well under a second; [build-guide.md](build-guide.md) says how to make one.
- SDL2 and SDL_ttf must be installed for the native window.
- Undo is opt-in. Put an `UndoBuffer` around your document and `UndoBufferToAnyProjection` at the top of your projection, and `Ctrl+Z` takes a change back. Without one, a program that changes data of its own keeps its own way back.
