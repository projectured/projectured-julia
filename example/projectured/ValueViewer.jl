# ──────────────────────────────────────────────────────────────────────────
# A window on any Julia value.
#
# Every other entry point of this package opens a document that somebody wrote
# a projection for. This one takes the value a person already has — a struct, a
# dictionary, a vector, an object of a running program — and shows it without a
# projection of its own.
#
# **The reflected shadow, not the value itself.** A reflection walks the value
# one level at a time, so an object that is large, that refers to itself, or
# that a task still writes, costs what is on the screen and no more. A chevron
# opens the next level. `NaturalToGraphics` draws the value itself instead, and
# `tree = false` asks for that; it is the flat view, and it reads every field it
# reaches.
# ──────────────────────────────────────────────────────────────────────────

"""
    make_value_viewer(value; tree = true, depth = 1, elements = 20,
                      measure = measure_truetype_text) -> (document, projection)

The document and the projection of a window on `value`.

- `tree` — the reflected tree, which opens one level at a time. `false` draws
  the value itself through [`NaturalToGraphics`](@ref), which reads every field
  it reaches.
- `depth` and `elements` — how much of the value the first frame holds: the
  levels below the root, and the elements of one collection. A chevron asks for
  the next level.
"""
function make_value_viewer(value; tree::Bool = true, depth::Integer = 1,
                           elements::Integer = 20, measure = measure_truetype_text)
    tree || return (value, NaturalToGraphics(measure = measure))
    document = reflect_document(value, DepthPolicy(depth = Int(depth),
                                                   elements = Int(elements)))
    projection = ChainingProjection(ReflectionToWidget(),
                                    WidgetToGraphics(font_ubuntu_monospace_regular_20;
                                                     measure = measure))
    (document, projection)
end

"""
    run_value_viewer(value; tree = true, depth = 1, elements = 20, name = "value",
                     backend = nothing, width = nothing, height = nothing,
                     mcp = false) -> Nothing

Open a window on any Julia value, and return when the window closes.

```julia
run_value_viewer(Dict("a" => 1, "b" => [1, 2, 3]))   # a tree, one level at a time
run_value_viewer(my_struct; tree = false)            # the flat view of the value
run_value_viewer(editor; depth = 2)                  # two levels of a running object
```

The keywords of [`make_value_viewer`](@ref) say how much of the value the first
frame holds. `backend`, `width` and `height` are those of every other window of
this package, and `mcp` starts the MCP server beside it.
"""
function run_value_viewer(value; tree::Bool = true, depth::Integer = 1,
                          elements::Integer = 20, name::AbstractString = "value",
                          backend = nothing, width = nothing, height = nothing,
                          mcp::Bool = false)
    document, projection = make_value_viewer(value; tree = tree, depth = depth,
                                             elements = elements)
    backend === nothing && (backend = default_backend())
    if width === nothing || height === nothing
        screen_width, screen_height = get_display_size(backend)
        width = something(width, screen_width)
        height = something(height, screen_height)
    end
    _run_window_scene(Any[document], Any[projection], String[String(name)];
                      width = width, height = height, backend = backend,
                      compose = (p, b) -> _multi_window_projection(p), mcp = mcp)
end
