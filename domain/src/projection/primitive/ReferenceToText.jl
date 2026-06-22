"""
    ReferenceToTextModule

Reference → TextText projections. Two projections render a `Reference`
(the linked-list path defined in `ReferenceModule`) as a `TextText`
document:

- `ReferenceToText` — a single colored line, the same compact shape as
  `Base.show` but rendered with color-coded tokens.
- `ReferenceToHumanReadableText` — a multi-line narrative read in
  reverse order (innermost step first), one phrase per line, with each
  step described in English and tagged with the Julia type of the value
  the step is applied to.

Both projections produce a `TextText` whose `selection` is always
`nothing`; v1 does not map sub-selections between Reference steps and
TextText spans.
"""
module ReferenceToTextModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ReferenceModule: Reference, ReferencePath, EmptyReferencePath, ConcreteReferencePath,
                          ReferenceStep, RangeReference, FieldReference, ProjectionReference,
                          PointReference, TypeReference, FunctionReference,
                          is_element_reference, is_position_reference,
                          head, tail, evaluate_reference, append_reference
import ..TextModule: TextDocument, TextText, TextString, TextNewline
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_default,
                      color_solarized_gray, color_solarized_cyan,
                      color_solarized_magenta, color_solarized_orange,
                      color_solarized_green, color_solarized_yellow,
                      color_solarized_red
import ..IoMapModule: SimpleIoMap

export ReferenceToText, ReferenceToHumanReadableText

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

# ─────────────────────────────────────────────────────────────────────────
# ReferenceToText (short form)
# ─────────────────────────────────────────────────────────────────────────

"""
    ReferenceToText(; font=font_ubuntu_monospace_regular_24)

Projection that renders a `Reference` as a single-line, color-coded
`TextText`. Mirrors the shape of `Base.show` for references but each
token (delimiter, name, index, type) is a separate `TextString` span
with its own color.
"""
struct ReferenceToText <: Projection
    font::StyleFont
end
ReferenceToText(; font=font_ubuntu_monospace_regular_24) = ReferenceToText(font)

map_reference_forward(::ReferenceToText, ::SimpleIoMap, _) = nothing
map_reference_backward(::ReferenceToText, ::SimpleIoMap, _) = nothing

# Append the colored token spans for a single step to `spans`.
function _emit_step_short!(spans::Vector{TextDocument}, p::ReferenceToText, step::FieldReference)
    push!(spans, _tok(".", p.font, color_solarized_gray))
    push!(spans, _tok(step.name, p.font, color_solarized_cyan))
end

function _emit_step_short!(spans::Vector{TextDocument}, p::ReferenceToText, step::RangeReference)
    if is_element_reference(step)
        push!(spans, _tok("[", p.font, color_solarized_gray))
        push!(spans, _tok(string(step.start + 1), p.font, color_solarized_magenta))
        push!(spans, _tok("]", p.font, color_solarized_gray))
    elseif is_position_reference(step)
        push!(spans, _tok("{", p.font, color_solarized_gray))
        push!(spans, _tok(string(step.start), p.font, color_solarized_magenta))
        push!(spans, _tok("}", p.font, color_solarized_gray))
    else
        push!(spans, _tok("{", p.font, color_solarized_gray))
        push!(spans, _tok(string(step.start), p.font, color_solarized_magenta))
        push!(spans, _tok(":", p.font, color_solarized_gray))
        push!(spans, _tok(string(step.stop), p.font, color_solarized_magenta))
        push!(spans, _tok("}", p.font, color_solarized_gray))
    end
end

function _emit_step_short!(spans::Vector{TextDocument}, p::ReferenceToText, step::TypeReference)
    push!(spans, _tok("::", p.font, color_solarized_gray))
    push!(spans, _tok(string(step.type), p.font, color_solarized_orange))
end

function _emit_step_short!(spans::Vector{TextDocument}, p::ReferenceToText, step::FunctionReference)
    push!(spans, _tok("(", p.font, color_solarized_gray))
    push!(spans, _tok(string(step.f), p.font, color_solarized_green))
    push!(spans, _tok(")", p.font, color_solarized_gray))
end

function _emit_step_short!(spans::Vector{TextDocument}, p::ReferenceToText, step::PointReference)
    push!(spans, _tok("@(", p.font, color_solarized_gray))
    push!(spans, _tok(string(step.x), p.font, color_solarized_magenta))
    push!(spans, _tok(",", p.font, color_solarized_gray))
    push!(spans, _tok(string(step.y), p.font, color_solarized_magenta))
    push!(spans, _tok(")", p.font, color_solarized_gray))
end

function _emit_step_short!(spans::Vector{TextDocument}, p::ReferenceToText, step::ProjectionReference)
    push!(spans, _tok("<", p.font, color_solarized_gray))
    push!(spans, _tok(_projection_name(step.projection), p.font, color_solarized_yellow))
    if !(step.output_path isa EmptyReferencePath)
        push!(spans, _tok(": ", p.font, color_solarized_gray))
        _emit_path_short!(spans, p, step.output_path)
    end
    push!(spans, _tok(">", p.font, color_solarized_gray))
end

# Fallback for unknown step subtypes — surface them in red rather than throw.
function _emit_step_short!(spans::Vector{TextDocument}, p::ReferenceToText, step::ReferenceStep)
    push!(spans, _tok(string(step), p.font, color_solarized_red))
end

function _emit_path_short!(spans::Vector{TextDocument}, p::ReferenceToText, path::ConcreteReferencePath)
    _emit_step_short!(spans, p, head(path))
    t = tail(path)
    t isa EmptyReferencePath || _emit_path_short!(spans, p, t)
end

_emit_path_short!(::Vector{TextDocument}, ::ReferenceToText, ::EmptyReferencePath) = nothing

function _short_text(p::ReferenceToText, ref)
    spans = TextDocument[]
    if ref === nothing
        push!(spans, _tok("(no selection)", p.font, color_solarized_gray))
    elseif ref isa EmptyReferencePath
        push!(spans, _tok("∅", p.font, color_solarized_gray))
    else
        _emit_path_short!(spans, p, ref)
    end
    TextText(spans...)
end

projection_print(p::ReferenceToText, recursion, ::Nothing, ctx) =
    SimpleIoMap(p, nothing, _short_text(p, nothing))

projection_print(p::ReferenceToText, recursion, ref::EmptyReferencePath, ctx) =
    SimpleIoMap(p, ref, _short_text(p, ref))

projection_print(p::ReferenceToText, recursion, ref::ConcreteReferencePath, ctx) =
    SimpleIoMap(p, ref, _short_text(p, ref))

# ─────────────────────────────────────────────────────────────────────────
# ReferenceToHumanReadableText (long form)
# ─────────────────────────────────────────────────────────────────────────

"""
    ReferenceToHumanReadableText(document; font=font_ubuntu_monospace_regular_24)

Projection that renders a `Reference` as a multi-line narrative
`TextText`. One phrase per line, in **reverse order** (innermost step
first), with each phrase shaped as
`the <step-description> of the <parent-type>` where `<parent-type>` is
the Julia type name of the value the step is applied to.

The `document` field is the document the reference points into; it is
needed to derive each step's parent type via `evaluate_reference`. The
document is captured at construction time — reactive callers should
rebuild the projection inside a `Cell` keyed on the document if they
need live updates.
"""
struct ReferenceToHumanReadableText <: Projection
    document::Any
    font::StyleFont
end
ReferenceToHumanReadableText(document; font=font_ubuntu_monospace_regular_24) =
    ReferenceToHumanReadableText(document, font)

map_reference_forward(::ReferenceToHumanReadableText, ::SimpleIoMap, _) = nothing
map_reference_backward(::ReferenceToHumanReadableText, ::SimpleIoMap, _) = nothing

function _parent_type_name(document, prefix::ReferencePath)
    document === nothing && return "?"
    try
        string(typeof(evaluate_reference(document, prefix)))
    catch
        "?"
    end
end

function _emit_type_tail!(line::Vector{TextDocument}, p::ReferenceToHumanReadableText,
                          document, prefix::ReferencePath)
    name = _parent_type_name(document, prefix)
    push!(line, _tok(" of the ", p.font, color_solarized_gray))
    color = name == "?" ? color_solarized_red : color_solarized_orange
    push!(line, _tok(name, p.font, color))
end

# Build the phrase spans for a single step. Returns `Vector{TextDocument}`.
function _phrase_for(p::ReferenceToHumanReadableText, step::FieldReference,
                     document, prefix::ReferencePath)
    line = TextDocument[]
    push!(line, _tok("the ", p.font, color_solarized_gray))
    push!(line, _tok(step.name, p.font, color_solarized_cyan))
    _emit_type_tail!(line, p, document, prefix)
    line
end

function _phrase_for(p::ReferenceToHumanReadableText, step::RangeReference,
                     document, prefix::ReferencePath)
    line = TextDocument[]
    push!(line, _tok("the ", p.font, color_solarized_gray))
    if is_element_reference(step)
        push!(line, _tok(_ordinal(step.start + 1), p.font, color_solarized_magenta))
        push!(line, _tok(" element", p.font, color_solarized_gray))
    elseif is_position_reference(step)
        push!(line, _tok(_ordinal(step.start), p.font, color_solarized_magenta))
        push!(line, _tok(" position", p.font, color_solarized_gray))
    else
        push!(line, _tok("range ", p.font, color_solarized_gray))
        push!(line, _tok(string(step.start), p.font, color_solarized_magenta))
        push!(line, _tok(" to ", p.font, color_solarized_gray))
        push!(line, _tok(string(step.stop), p.font, color_solarized_magenta))
    end
    _emit_type_tail!(line, p, document, prefix)
    line
end

function _phrase_for(p::ReferenceToHumanReadableText, step::TypeReference,
                     document, prefix::ReferencePath)
    line = TextDocument[]
    push!(line, _tok("the elements of type ", p.font, color_solarized_gray))
    push!(line, _tok(string(step.type), p.font, color_solarized_orange))
    _emit_type_tail!(line, p, document, prefix)
    line
end

function _phrase_for(p::ReferenceToHumanReadableText, step::FunctionReference,
                     document, prefix::ReferencePath)
    line = TextDocument[]
    push!(line, _tok("the elements matching ", p.font, color_solarized_gray))
    push!(line, _tok(string(step.f), p.font, color_solarized_green))
    _emit_type_tail!(line, p, document, prefix)
    line
end

function _phrase_for(p::ReferenceToHumanReadableText, step::PointReference,
                     document, prefix::ReferencePath)
    line = TextDocument[]
    push!(line, _tok("the pixel at (", p.font, color_solarized_gray))
    push!(line, _tok(string(step.x), p.font, color_solarized_magenta))
    push!(line, _tok(", ", p.font, color_solarized_gray))
    push!(line, _tok(string(step.y), p.font, color_solarized_magenta))
    push!(line, _tok(")", p.font, color_solarized_gray))
    _emit_type_tail!(line, p, document, prefix)
    line
end

function _phrase_for_projection(p::ReferenceToHumanReadableText, step::ProjectionReference,
                                document, prefix::ReferencePath)
    line = TextDocument[]
    push!(line, _tok("inside the ", p.font, color_solarized_gray))
    push!(line, _tok(_projection_name(step.projection), p.font, color_solarized_yellow))
    push!(line, _tok(" projection", p.font, color_solarized_gray))
    _emit_type_tail!(line, p, document, prefix)
    line
end

# Fallback for unknown step subtypes — surface them in red.
function _phrase_for(p::ReferenceToHumanReadableText, step::ReferenceStep,
                     document, prefix::ReferencePath)
    line = TextDocument[string(step) |> s -> _tok(s, p.font, color_solarized_red)]
    line
end

# Walk a path front-to-back, appending one line per step to `lines`.
# `prefix` is the path leading up to but not including the current step,
# used for the parent-type lookup. `document` is the document the prefix
# is evaluated against (the outer document at the top level, or the
# projection's output at nested levels — for nested levels we pass
# `nothing` since the projection's output is not addressable here, which
# yields "?" tails inside nested projection paths).
function _walk_long!(lines::Vector{Vector{TextDocument}},
                     p::ReferenceToHumanReadableText,
                     path::ConcreteReferencePath,
                     document, prefix::ReferencePath)
    step = head(path)
    if step isa ProjectionReference
        if !(step.output_path isa EmptyReferencePath)
            _walk_long!(lines, p, step.output_path, nothing, EmptyReferencePath())
        end
        push!(lines, _phrase_for_projection(p, step, document, prefix))
    else
        push!(lines, _phrase_for(p, step, document, prefix))
    end
    new_prefix = append_reference(prefix, step)
    t = tail(path)
    t isa EmptyReferencePath || _walk_long!(lines, p, t, document, new_prefix)
end

_walk_long!(::Vector{Vector{TextDocument}}, ::ReferenceToHumanReadableText,
            ::EmptyReferencePath, _, ::ReferencePath) = nothing

function _long_text(p::ReferenceToHumanReadableText, ref)
    if ref === nothing
        return TextText(_tok("no selection", p.font, color_solarized_gray))
    elseif ref isa EmptyReferencePath
        type_name = p.document === nothing ? "document" : string(typeof(p.document))
        type_color = p.document === nothing ? color_solarized_gray : color_solarized_orange
        return TextText(
            _tok("the whole ", p.font, color_solarized_gray),
            _tok(type_name, p.font, type_color),
        )
    end
    lines = Vector{Vector{TextDocument}}()
    _walk_long!(lines, p, ref, p.document, EmptyReferencePath())
    reverse!(lines)
    spans = TextDocument[]
    for (i, line) in enumerate(lines)
        append!(spans, line)
        i < length(lines) && push!(spans, TextNewline(font=p.font))
    end
    TextText(spans...)
end

projection_print(p::ReferenceToHumanReadableText, recursion, ::Nothing, ctx) =
    SimpleIoMap(p, nothing, _long_text(p, nothing))

projection_print(p::ReferenceToHumanReadableText, recursion, ref::EmptyReferencePath, ctx) =
    SimpleIoMap(p, ref, _long_text(p, ref))

projection_print(p::ReferenceToHumanReadableText, recursion, ref::ConcreteReferencePath, ctx) =
    SimpleIoMap(p, ref, _long_text(p, ref))

end # module
