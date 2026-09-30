# ProjecturEd in your own project

> **Kind:** procedure · **Status:** current · **Stands on:** [package-rules.md](../rule/package-rules.md)

How to use ProjecturEd from a project of your own: which package to load, how to reach it while it is not in the General registry, and how to open a window from your code.

## Reach the packages

The packages are not in the General registry yet. A project reaches them by path, the way this repository reaches its own packages.

1. Clone ProjecturEd beside your project:

   ```sh
   git clone https://github.com/projectured/projectured-julia
   ```

2. Name the packages you load in the `Project.toml` of your project, and give each one a path in `[sources]`:

   ```toml
   [deps]
   Projectured = "…"
   ProjecturedSdl = "…"

   [sources]
   Projectured = {path = "../projectured-julia/package/Projectured"}
   ProjecturedSdl = {path = "../projectured-julia/package/ProjecturedSdl"}
   ```

   The uuid of each package is in its own `Project.toml`. Give a path for every ProjecturEd package you name, and for none that you do not: a package that you do not name is reached through the ones you do.

3. Resolve, and not `instantiate` alone. `Pkg.resolve()` sees a dependency that appeared inside a package your manifest already lists; `instantiate` does not.

## Which package to load

| Package | What you get |
| --- | --- |
| `Projectured` | the umbrella: the kernel, the substrate and every domain |
| `ProjecturedSdl` | the native window |
| `ProjecturedWeb` | the browser backend |
| `ProjecturedExample` | the examples, the gallery, `run_value_viewer` and the application |
| one domain, for example `ProjecturedJson` | that domain alone, with the kernel below it |

A program that shows data of one domain loads that domain and a backend. A program that shows anything loads the umbrella. [package-rules.md](../rule/package-rules.md) says what each kind of package may depend on.

## Open a window from your code

An editor needs three things: a backend, a document and a projection.

```julia
using Projectured, ProjecturedSdl

document = parse_natural_text(:json, "{\"name\": \"Alice\"}")
projection = NaturalToGraphics(measure = FontFileMeasure())
run_editor!(document, projection; window = (; title = "My data"))
```

`run_editor!` puts the view in a window of the title you give, and returns when the window closes. SDL is the one loaded backend that draws windows, so the call needs no `backend`. `mcp = true` starts the MCP server beside it, so an external client can drive the same editor ([mcp-guide.md](mcp-guide.md)).

`NaturalToGraphics` is the general renderer: it draws a document of any domain, and a struct of your own through reflection. A projection you wrote yourself goes in its place.

For a value that has no projection of its own, [view-your-data-guide.md](view-your-data-guide.md) is shorter: `run_value_viewer(value)`.

That window has no menu bar, no clipboard and no F1 help: what a window has besides the document in it comes from `ProjecturedShell`. `make_window_wrap(; …)` answers the fold to apply before the window opens. [shell.md](../package/platform/shell/shell.md) says what each keyword adds and why the order is what it is.

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
