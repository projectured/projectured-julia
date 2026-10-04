# Fragment of `TextModule`.
#
# Reference → TextBlock projections. Two projections render a `Reference`
# (the linked-list path defined in `ReferenceModule`) as a `TextBlock`
# document:
#
# - `ReferenceToText` — a single colored line, the same compact shape as
#   `Base.show` but rendered with color-coded tokens.
# - `ReferenceToHumanReadableText` — a multi-line narrative read in
#   reverse order (innermost step first), one phrase per line, with each
#   step described in English and tagged with the Julia type of the value
#   the step is applied to.
#
# Both projections produce a `TextBlock` whose `selection` is always
# `nothing`; v1 does not map sub-selections between Reference steps and
# TextBlock spans.
# ── shared helpers ────────────────────────────────────────────────────────

_tok(content::AbstractString, font::StyleFont, color::StyleColor) =
    TextString(content, font, color)

function _ordinal(n::Integer)
    n < 0 && return string(n)
    last_two = n % 100
    if 11 <= last_two <= 13
        return string(n, "th")
    end
    suffix = (n % 10 == 1) ? "st" :
             (n % 10 == 2) ? "nd" :
             (n % 10 == 3) ? "rd" : "th"
    string(n, suffix)
end

_projection_name(p) = string(nameof(typeof(p)))

# Short, unqualified name of a type (e.g. `NedParam`, `CellVector`) — far more
# readable than the fully-qualified `Catalog.NedModule.NedParam`.
function _short_type(t)
    try
        string(nameof(t))
    catch
        string(t)
    end
end

# Indefinite article for a type name, chosen by its leading letter.
_article(name::AbstractString) =
    (!isempty(name) && lowercase(first(name)) in ('a', 'e', 'i', 'o', 'u')) ? "an " : "a "

# ─────────────────────────────────────────────────────────────────────────
# ReferenceToText (short form)
# ─────────────────────────────────────────────────────────────────────────

"""
    ReferenceToText(; font=…, style=…)

Projection that renders a `Reference` as a single-line, color-coded
`TextBlock`. Mirrors the shape of `Base.show` for references but each
token (delimiter, name, index, type) is a separate `TextString` span
with its own color.

`font` is the font of every token, and `style` holds the values of a
[`ReferenceTheme`](@ref) as one `NamedTuple`; both default to the default theme. A
builder gives `get_reference_style(theme, :font)` and
`make_theme_values_field(ReferenceTheme, theme)` to follow a theme.
"""
@projection UntrackedCell struct ReferenceToText
    font::StyleFont = get_reference_style(nothing, :font)
    style::NamedTuple = get_theme_defaults(ReferenceTheme)
end

map_reference_forward(::ReferenceToText, ::SimpleIoMap, _) = nothing
map_reference_backward(::ReferenceToText, ::SimpleIoMap, _) = nothing

# Append the colored token spans for a single step to `spans`. `t` is the
# values of the `ReferenceTheme` the projection prints with, read once per
# print.
function _emit_step_short!(spans::Vector{TextDocument}, t, font, step::FieldReferenceStep)
    push!(spans, _tok(".", font, t.punctuation_color))
    push!(spans, _tok(step.name, font, t.name_color))
end

function _emit_step_short!(spans::Vector{TextDocument}, t, font, step::RangeReferenceStep)
    if is_element_reference_step(step)
        push!(spans, _tok("[", font, t.punctuation_color))
        push!(spans, _tok(string(step.start + 1), font, t.index_color))
        push!(spans, _tok("]", font, t.punctuation_color))
    elseif is_position_reference_step(step)
        push!(spans, _tok("{", font, t.punctuation_color))
        push!(spans, _tok(string(step.start), font, t.index_color))
        push!(spans, _tok("}", font, t.punctuation_color))
    else
        push!(spans, _tok("{", font, t.punctuation_color))
        push!(spans, _tok(string(step.start), font, t.index_color))
        push!(spans, _tok(":", font, t.punctuation_color))
        push!(spans, _tok(string(step.stop), font, t.index_color))
        push!(spans, _tok("}", font, t.punctuation_color))
    end
end

function _emit_step_short!(spans::Vector{TextDocument}, t, font, step::TypeReferenceStep)
    push!(spans, _tok("::", font, t.punctuation_color))
    push!(spans, _tok(_short_type(step.type), font, t.type_color))
end

function _emit_step_short!(spans::Vector{TextDocument}, t, font, step::PointReferenceStep)
    push!(spans, _tok("@(", font, t.punctuation_color))
    push!(spans, _tok(string(step.x), font, t.index_color))
    push!(spans, _tok(",", font, t.punctuation_color))
    push!(spans, _tok(string(step.y), font, t.index_color))
    push!(spans, _tok(")", font, t.punctuation_color))
end

function _emit_step_short!(spans::Vector{TextDocument}, t, font, step::ProjectionReferenceStep)
    push!(spans, _tok("<", font, t.punctuation_color))
    push!(spans, _tok(_projection_name(step.projection), font, t.projection_color))
    if !(step.output_path isa EmptyReference)
        push!(spans, _tok(": ", font, t.punctuation_color))
        _emit_path_short!(spans, t, font, step.output_path)
    end
    push!(spans, _tok(">", font, t.punctuation_color))
end

# Fallback for unknown step subtypes — surface them in red rather than throw.
function _emit_step_short!(spans::Vector{TextDocument}, t, font, step::ReferenceStep)
    push!(spans, _tok(string(step), font, t.unknown_color))
end

# Emit the folded `::Type` that a node carries (the type the step descends from).
function _emit_type_short!(spans::Vector{TextDocument}, t, font, T)
    push!(spans, _tok("::", font, t.punctuation_color))
    push!(spans, _tok(_short_type(T), font, t.type_color))
end

function _emit_path_short!(spans::Vector{TextDocument}, t, font, path::ConcreteReference)
    path.type === nothing || _emit_type_short!(spans, t, font, path.type)
    _emit_step_short!(spans, t, font, get_reference_head(path))
    tail = get_reference_tail(path)
    if tail isa EmptyReference
        tail.type === nothing || _emit_type_short!(spans, t, font, tail.type)
    else
        _emit_path_short!(spans, t, font, tail)
    end
end

_emit_path_short!(::Vector{TextDocument}, t, font, ::EmptyReference) = nothing

function _short_text(p::ReferenceToText, ref)
    t = unwrap_cell(p.style)
    font = p.font
    spans = TextDocument[]
    if ref === nothing
        push!(spans, _tok("(no selection)", font, t.punctuation_color))
    elseif ref isa EmptyReference
        # Whole-element selection: show its folded type if known, else ∅.
        ref.type === nothing ? push!(spans, _tok("∅", font, t.punctuation_color)) :
                               _emit_type_short!(spans, t, font, ref.type)
    else
        _emit_path_short!(spans, t, font, ref)
    end
    TextBlock(spans...)
end

print_document(p::ReferenceToText, recursion, ::Nothing, ctx) =
    SimpleIoMap(p, nothing, _short_text(p, nothing))

print_document(p::ReferenceToText, recursion, ref::EmptyReference, ctx) =
    SimpleIoMap(p, ref, _short_text(p, ref))

print_document(p::ReferenceToText, recursion, ref::ConcreteReference, ctx) =
    SimpleIoMap(p, ref, _short_text(p, ref))

# ─────────────────────────────────────────────────────────────────────────
# ReferenceToHumanReadableText (long form)
# ─────────────────────────────────────────────────────────────────────────

"""
    ReferenceToHumanReadableText(; document, font=…, style=…)

Projection that renders a `Reference` as a multi-line narrative
`TextBlock`. One phrase per line, in **reverse order** (innermost step
first), with each phrase shaped as
`the <step-description> of the <parent-type>` where `<parent-type>` is
the Julia type name of the value the step is applied to.

The `document` field is the document the reference points into; it is
needed to derive each step's parent type via `evaluate_reference`. The
document is captured at construction time — reactive callers should
rebuild the projection inside a `Cell` keyed on the document if they
need live updates.

`font` is the font of every line, and `style` holds the values of a
[`ReferenceTheme`](@ref) as one `NamedTuple`; both default to the default theme.
"""
@projection UntrackedCell struct ReferenceToHumanReadableText
    document::Any
    font::StyleFont = get_reference_style(nothing, :font)
    style::NamedTuple = get_theme_defaults(ReferenceTheme)
end

map_reference_forward(::ReferenceToHumanReadableText, ::SimpleIoMap, _) = nothing
map_reference_backward(::ReferenceToHumanReadableText, ::SimpleIoMap, _) = nothing

function _parent_type_name(document, prefix::Reference)
    document === nothing && return "?"
    try
        _short_type(typeof(evaluate_reference(document, prefix)))
    catch
        "?"
    end
end

function _emit_type_tail!(line::Vector{TextDocument}, t, font,
                          document, prefix::Reference, parent_type)
    name = parent_type !== nothing ? _short_type(parent_type) :
                                     _parent_type_name(document, prefix)
    push!(line, _tok(" of ", font, t.punctuation_color))
    push!(line, _tok(_article(name), font, t.punctuation_color))
    color = name == "?" ? t.unknown_color : t.type_color
    push!(line, _tok(name, font, color))
end

# Build the leading "the <description>" spans for a single navigation step.
# The type tail (" of a <Type>") is appended by `_walk_long!`, which knows the
# parent type. Returns `Vector{TextDocument}`.
function _phrase_for(t, font, step::FieldReferenceStep)
    line = TextDocument[]
    push!(line, _tok("the ", font, t.punctuation_color))
    push!(line, _tok(step.name, font, t.name_color))
    line
end

function _phrase_for(t, font, step::RangeReferenceStep)
    line = TextDocument[]
    push!(line, _tok("the ", font, t.punctuation_color))
    if is_element_reference_step(step)
        push!(line, _tok(_ordinal(step.start + 1), font, t.index_color))
        push!(line, _tok(" element", font, t.punctuation_color))
    elseif is_position_reference_step(step)
        push!(line, _tok(_ordinal(step.start), font, t.index_color))
        push!(line, _tok(" position", font, t.punctuation_color))
    else
        push!(line, _tok("range ", font, t.punctuation_color))
        push!(line, _tok(string(step.start), font, t.index_color))
        push!(line, _tok(" to ", font, t.punctuation_color))
        push!(line, _tok(string(step.stop), font, t.index_color))
    end
    line
end


function _phrase_for(t, font, step::PointReferenceStep)
    line = TextDocument[]
    push!(line, _tok("the pixel at (", font, t.punctuation_color))
    push!(line, _tok(string(step.x), font, t.index_color))
    push!(line, _tok(", ", font, t.punctuation_color))
    push!(line, _tok(string(step.y), font, t.index_color))
    push!(line, _tok(")", font, t.punctuation_color))
    line
end

function _phrase_for_projection(t, font, step::ProjectionReferenceStep)
    line = TextDocument[]
    push!(line, _tok("inside the ", font, t.punctuation_color))
    push!(line, _tok(_projection_name(step.projection), font, t.projection_color))
    push!(line, _tok(" projection", font, t.punctuation_color))
    line
end

# Fallback for unknown step subtypes — surface them in red.
function _phrase_for(t, font, step::ReferenceStep)
    TextDocument[_tok(string(step), font, t.unknown_color)]
end

# Walk a path front-to-back, appending one line per step to `lines`.
# `prefix` is the path leading up to but not including the current step,
# used for the parent-type lookup. `document` is the document the prefix
# is evaluated against (the outer document at the top level, or the
# projection's output at nested levels — for nested levels we pass
# `nothing` since the projection's output is not addressable here, which
# yields "?" tails inside nested projection paths).
# A `TypeReferenceStep` is not a line: it supplies the parent type of the
# navigation step that follows it. A canonical reference holds no such step, since
# its types sit on its nodes. When no type step precedes a step, the parent type
# falls back to `evaluate_reference(document, prefix)`, so every path reads
# correctly. `prefix` is the path up to but not including the step.
function _walk_long!(lines::Vector{Vector{TextDocument}},
                     t, font,
                     path::ConcreteReference,
                     document, prefix::Reference, parent_type)
    step = get_reference_head(path)
    new_prefix = extend_reference(prefix, step)
    tail = get_reference_tail(path)
    if step isa TypeReferenceStep
        # Checkpoint: emit no line; carry its type to the next nav step.
        tail isa EmptyReference || _walk_long!(lines, t, font, tail, document, new_prefix, step.type)
        return
    end
    if step isa ProjectionReferenceStep
        if !(step.output_path isa EmptyReference)
            _walk_long!(lines, t, font, step.output_path, nothing, EmptyReference(), nothing)
        end
        line = _phrase_for_projection(t, font, step)
    else
        line = _phrase_for(t, font, step)
    end
    _emit_type_tail!(line, t, font, document, prefix, parent_type)
    push!(lines, line)
    tail isa EmptyReference || _walk_long!(lines, t, font, tail, document, new_prefix, nothing)
end

_walk_long!(::Vector{Vector{TextDocument}}, t, font,
            ::EmptyReference, _, ::Reference, _) = nothing

function _long_text(p::ReferenceToHumanReadableText, ref)
    t = unwrap_cell(p.style)
    font = p.font
    if ref === nothing
        return TextBlock(_tok("no selection", font, t.punctuation_color))
    elseif ref isa EmptyReference
        type_name = p.document === nothing ? "document" : _short_type(typeof(p.document))
        type_color = p.document === nothing ? t.punctuation_color : t.type_color
        return TextBlock(
            _tok("the whole ", font, t.punctuation_color),
            _tok(type_name, font, type_color),
        )
    end
    lines = Vector{Vector{TextDocument}}()
    _walk_long!(lines, t, font, ref, p.document, EmptyReference(), nothing)
    reverse!(lines)
    spans = TextDocument[]
    for (i, line) in enumerate(lines)
        append!(spans, line)
        if i < length(lines)
            # "which is" connects each node to its role in its parent (the line
            # below it), so the rows read as one sentence.
            push!(spans, _tok(" which is", t.aside_font, t.punctuation_color))
            push!(spans, TextNewline(font=font))
        end
    end
    TextBlock(spans...)
end

print_document(p::ReferenceToHumanReadableText, recursion, ::Nothing, ctx) =
    SimpleIoMap(p, nothing, _long_text(p, nothing))

print_document(p::ReferenceToHumanReadableText, recursion, ref::EmptyReference, ctx) =
    SimpleIoMap(p, ref, _long_text(p, ref))

print_document(p::ReferenceToHumanReadableText, recursion, ref::ConcreteReference, ctx) =
    SimpleIoMap(p, ref, _long_text(p, ref))
