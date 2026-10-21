# Fragment of `TooltipModule` — what a part says about itself, by the meaning of
# each piece, so that one drawing gives every tooltip the same look.

"""
    TooltipNote(; title = nothing, keys = Any[], text = nothing, facts = Pair[],
                  hint = nothing, tone = :plain)

What a part says about itself when the pointer rests on it, by the meaning of
each piece. An author writes what the part is; the natural projection draws every
note the same way, with the texts and the colors of the [`TooltipTheme`](@ref).

- `title`: the name of the part, as a person sees it. It is not a sentence.
- `keys`: the keys that do what the part does: each a `GesturePattern`, drawn
  as key caps after the title, or a string such as `"Ctrl+click"`.
- `text`: what the part does, or what it shows: a string, or any document, such
  as a page of prose or a table.
- `facts`: what the part does not show, each a `name => value` pair: a path, a
  count, a time, a value with its unit. A value is a string or any document.
- `hint`: another gesture on the part, or why a command is off: a string.
- `tone`: `:plain`, `:warning` or `:error`. A warning and an error draw a mark
  of their color before the title.

Each piece that is `nothing` or empty draws nothing.

# Example

    TooltipNote(; title = "Refresh", keys = [KeyDownPattern(:f5; modifiers = Symbol[])],
                text = "Read the frame again.", facts = ["Rows" => "12480"])
"""
@document struct TooltipNote
    title::Any = nothing
    keys::Any = Any[]
    text::Any = nothing
    facts::Any = Pair[]
    hint::Any = nothing
    tone::Symbol = :plain
end
