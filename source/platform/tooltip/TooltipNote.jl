# Fragment of `TooltipModule` — what a part says about itself, by the meaning of
# each piece, so that one drawing gives every tooltip the same look.

"""
    TooltipNote(; title = nothing, keys = Any[], code = nothing, text = nothing,
                  facts = Pair[], hint = nothing, tone = :plain)

What a part says about itself when the pointer rests on it, by the meaning of
each piece. An author writes what the part is; the natural projection draws every
note the same way, with the texts and the colors of the [`TooltipTheme`](@ref).

- `title`: the name of the part, as a person sees it. It is not a sentence. A
  string, or any document.
- `keys`: the keys that do what the part does: each a `GesturePattern`, drawn
  as key caps after the title, or a string such as `"Ctrl+click"`.
- `code`: a line of code, such as the signature of a function: a string, in the
  text of a value, which breaks at the edge of the window.
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
    code::Any = nothing
    text::Any = nothing
    facts::Any = Pair[]
    hint::Any = nothing
    tone::Symbol = :plain
end

"""
    find_bound_keys(type, description) -> Vector{GesturePattern}

The key patterns that the gesture table of the document type `type` binds to
the command `description`, for the `keys` of a note about a control that does
what that key does: the note then names the key that works, and a change of the
binding changes the note. A pointer gesture bound to the same command, such as
the back button of a mouse, is not a key, and the note leaves it out. Empty when
the table binds no key to `description`.
"""
find_bound_keys(type::Type, description::AbstractString) =
    GesturePattern[binding.pattern for binding in collect_document_gesture_bindings(type)
                   if binding.description == description && _is_key_pattern(binding.pattern)]

_is_key_pattern(::GesturePattern{<:Union{KeyDown,KeyPress}}) = true
_is_key_pattern(_) = false
