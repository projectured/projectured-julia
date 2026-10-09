# Set up and start

> **Kind:** procedure · **Status:** current · **Stands on:** [concepts.md](../design/concepts.md)

What you need, how to start the application, and how to open the same views from a Julia session. It also says what a first start costs and what to do when a load fails.

## What you need

- **Julia 1.12 or later.** The code uses what Julia 1.12 adds, such as the `gc_safe` option of `@ccall`, and the packages are linked by `[sources]` path entries. The environment of this repository is resolved with 1.13.
- **SDL2 and SDL_ttf**, for the native window. On Debian or Ubuntu: `apt install libsdl2-2.0-0 libsdl2-ttf-2.0-0`.
- **Ollama with a pulled model**, or an `ANTHROPIC_API_KEY`, for the assistant. [assistant-guide.md](assistant-guide.md) says which model and how to pull it. Without either, everything else works.

To use the packages in a project of your own, without the source, add them from the registry `ProjecturedRegistry`: [own-project-guide.md](own-project-guide.md) says how. This guide runs the application from a clone of the source.

## Start the application

```sh
git clone https://github.com/projectured/AutoIntegration.jl auto-integration
git clone https://github.com/projectured/AgentClientProtocol.jl agent-client-protocol
git clone https://github.com/projectured/ClaudeCodeACP.jl claude-code-acp
git clone https://github.com/projectured/ModelContextProtocol.jl model-context-protocol
git clone https://github.com/projectured/projectured-julia
cd projectured-julia
bin/projectured
```

The four folders go beside `projectured-julia`, because the packages and `environment/all` name them by those folders: `auto-integration` the umbrella, `agent-client-protocol` and `claude-code-acp` the package `ProjecturedACP`, and `model-context-protocol`, the fork of the MCP package, the package `ProjecturedMCP`.

A worktree of this repository beside it, such as `../projectured-julia-<name>`, reaches the same folders. A worktree in `.claude/worktrees/<name>/` does not: its relative paths end in `.claude/worktrees/`, so it needs a link of the same name there for each folder, which git ignores:

```sh
for folder in auto-integration agent-client-protocol claude-code-acp model-context-protocol; do
    ln -s "$(realpath ..)/$folder" .claude/worktrees/$folder
done
```

The window has the Files pane on the left, the open files in the middle, and the assistant on the right. A double click in the Files pane opens a file. Files named on the command line open at once:

```sh
bin/projectured notes.md data.json
bin/projectured --help            # every option
```

**The first start compiles the code**, which takes some minutes and much memory. Later starts read the compiled cache and take seconds. `bin/build_projectured` makes a binary that starts in well under a second; [build-guide.md](build-guide.md) says what that costs.

## Start a session instead

A session is what you want while you work on ProjecturEd itself, or to open a value of your own program.

```sh
julia --project=environment/all
```

```julia
using Projectured, ProjecturedExample, ProjecturedSDL

run_example()                           # the JSON example
run_example("widget")                   # the widget forms
run_example("json"; shell = true)       # the same example inside a WidgetShell
run_value_viewer(my_value)              # a window on any value of your own
```

Press **Escape** to close the window.

`environment/all` holds every package of the repository. `using Projectured` gives the essential names (`display_in_editor`, `run_editor!` and the few others most programs call) and loads AutoIntegration, which loads an installed domain or integration when its triggers are loaded; `using ProjecturedAll` gives the names of every package in one namespace, as the tests and the examples use them. A program of your own uses the packages by path instead; [own-project-guide.md](own-project-guide.md) says how.

## Look at a view without a window

An image or a PDF of an example needs no window:

```julia
write_example_image("json", "/tmp/snapshot.png")
write_example_pdf("json", "/tmp/snapshot.pdf")     # vector PDF, with selectable text
```

For the **text of a document**, in the notation of its domain, ask the document:

```julia
document = parse_natural_text(:json, "{\"name\": \"Alice\"}")
println(print_natural_text(document))
```

That writes the document in its own notation, over as many lines as the notation
takes.

`print_object` answers the **structure** of any Julia value as a string — the
type names, the fields and the elements — which is what you want while you debug
a document. It answers the string rather than writing it, so a script prints it
itself:

```julia
println(print_object(document))
println(print_object(my_struct; include_selection = false))
```

`print_example("json")` writes the same structure for the whole output of an
example, down to each graphics primitive and each font. It runs to thousands of
lines, and it is the tool for a projection that draws the wrong thing.

## When a load fails

- **Pkg cannot find a package.** Run `using Pkg; Pkg.resolve()` in `environment/all`. `instantiate` alone does not see a dependency that appeared inside a package the manifest already lists.
- **The window opens black, or no text is drawn.** SDL_ttf is missing, or the fonts are not where the style package looks for them. `asset/font/` holds them.
- **The first start seems stuck.** It is compiling. The terminal names each package as it finishes.
- **A test fails after a pull.** [testing-guide.md](testing-guide.md) says which test covers what you changed. Run that one first.

## Run the tests

```julia
using ProjecturedTest
test_json()          # one domain
test_kernel()        # the kernel
test_all()           # everything, about 47 minutes
```

[testing-guide.md](testing-guide.md) lists the test of each package and what each helper checks.

## For an AI client

The editor can serve an MCP client at `http://127.0.0.1:9876/mcp`, with the same tools that the assistant in the window uses. [mcp-guide.md](mcp-guide.md) says how to start it and how to connect a client.
