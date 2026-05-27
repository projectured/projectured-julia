# Getting Started

This guide covers prerequisites, setup, and the REPL helpers you will use
every day. For the conceptual foundation (what projectional editing is, the
five core ideas, the key event walkthrough) see [the concepts guide](concepts.md).
For a guided tour of the examples see [the examples tour](examples-tour.md).

## Prerequisites

- Julia 1.10+
- SDL2 and SDL_ttf installed (for the SDL backend)
- Familiarity with Julia (modules, multiple dispatch, structs)

## Setup

```sh
git clone https://github.com/projectured/projectured-julia
cd projectured-julia
julia --project=.
```

```julia
julia> using Projectured, ProjecturedExample
```

## Opening examples

```julia
run_example()                        # JSON example (default)
run_example("widget")                # widget form example
run_example("json"; workbench=true)  # wrap any example in the IDE shell
run_example("json"; scrolling=true)  # wrap in a scrollable viewport
run_example("json"; caching=true)    # enable GraphicsCaching layer
```

Press **Escape** to close the SDL window.

## Inspecting output without a window

```julia
print_example()           # print the JSON example's output to stdout
print_example("syntax")   # print the syntax example
```

`print_example` runs `print_object` on the projection output — it chains
`ObjectToSyntax → SyntaxToText → TextToString` internally.

## Saving a screenshot

```julia
write_image_example("json", "/tmp/snapshot.bmp")
write_image_example("widget", "/tmp/w.bmp"; width=1200, height=800)
```

See [the graphics guide](document/graphics.md) for the `write_image` API.

## Inspecting document structure

`print_object` renders any Julia value as structured text:

```julia
print_object(editor.document)
print_object(my_struct; open_delimiter = "{", close_delimiter = "}")
print_object(doc; include_selection = false)
```

## Working with references

The `@reference` macro builds reference paths from a path-like DSL:

```julia
ref = @reference entries[1].value.value{3}
evaluate_reference(editor.document, ref)
```

See [the reference guide](editor/reference.md) for the full grammar
(`.field`, `[i]`, `{k}`, `[i, j]`, `.field(expr)`, `.point(x, y)`,
`.proj(p, sub)`).

## Running the test suite

```julia
using ProjecturedTest
test_all()          # full suite
test_printers()     # printer round-trips only
test_readers()      # reader round-trips only
test_selections()   # selection tests only
```

See [the testing guide](testing.md) for all per-layer helpers.

## For AI assistants using MCP

When `run!` is active the editor exposes an MCP server on port 9876.
Recommended workflow:

1. Read `resource://guides` to discover the documentation layout.
2. Read `resource://guide/getting-started`, then the topic guides
   relevant to the task — usually `reactive-cells`, `projection-system`,
   `editor/reference`, and the affected domain's guide.
3. Use `print_object(editor.document)` to see the live structure.
4. Build reference paths with `@reference` and apply changes with
   `replace_selection!`, `set_selection!`, or domain operations.

Do not guess names or signatures. Look them up via `resource://modules`,
`resource://classes`, and `resource://functions`.
