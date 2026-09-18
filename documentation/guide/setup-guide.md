# Set up and start

> **Kind:** procedure · **Status:** current · **Stands on:** [concepts.md](../design/concepts.md)

What you need, how to start the application, and how to open the same views from a Julia session. It also says what a first start costs and what to do when a load fails.

## What you need

- **Julia 1.11 or later.** The packages are linked by `[sources]` path entries, which Julia 1.11 is the first to read. The environment of this repository is resolved with 1.13.
- **SDL2 and SDL_ttf**, for the native window. On Debian or Ubuntu: `apt install libsdl2-2.0-0 libsdl2-ttf-2.0-0`.
- **Ollama with a pulled model**, or an `ANTHROPIC_API_KEY`, for the assistant. [assistant-guide.md](assistant-guide.md) says which model and how to pull it. Without either, everything else works.

## Start the application

```sh
git clone https://github.com/projectured/projectured-julia
cd projectured-julia
bin/projectured
```

The window has the file navigator on the left, the open files in the middle, and the assistant on the right. A double click in the navigator opens a file. Files named on the command line open at once:

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
using Projectured, ProjecturedExample, ProjecturedSdl

run_example()                           # the JSON example
run_example("widget")                   # the widget forms
run_example("json"; workbench = true)   # the same example in the workbench shell
run_value_viewer(my_value)              # a window on any value of your own
```

Press **Escape** to close the window.

`environment/all` holds every package of the repository. A program of your own uses the packages by path instead; [own-project-guide.md](own-project-guide.md) says how.

## Look at a view without a window

```julia
print_example()                      # the JSON example as text, on the terminal
print_example("syntax")
write_example_image("json", "/tmp/snapshot.png")
write_example_pdf("json", "/tmp/snapshot.pdf")     # vector PDF, with selectable text
```

`print_object` shows any Julia value as structured text:

```julia
print_object(editor.document)
print_object(my_struct; include_selection = false)
```

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
