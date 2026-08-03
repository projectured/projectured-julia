"""
    ReferenceToTextModule

Reference → TextBlock projections. Two projections render a `Reference`
(the linked-list path defined in `ReferenceModule`) as a `TextBlock`
document:

- `ReferenceToText` — a single colored line, the same compact shape as
  `Base.show` but rendered with color-coded tokens.
- `ReferenceToHumanReadableText` — a multi-line narrative read in
  reverse order (innermost step first), one phrase per line, with each
  step described in English and tagged with the Julia type of the value
  the step is applied to.

Both projections produce a `TextBlock` whose `selection` is always
`nothing`; v1 does not map sub-selections between Reference steps and
TextBlock spans.
"""
module ReferenceToTextModule

import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..ReferenceModule: Reference, EmptyReference, ConcreteReference,
                          ReferenceStep, RangeReferenceStep, FieldReferenceStep,
                          TypeReferenceStep,
                          is_element_reference_step, is_position_reference_step,
                          head, tail, evaluate_reference, extend_reference
import ..PointReferenceStepModule: PointReferenceStep
import ..ProjectionReferenceStepModule: ProjectionReferenceStep
import ..TextModule: TextDocument, TextBlock, TextString, TextNewline
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20, font_ubuntu_monospace_italic_20
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

# Short, unqualified name of a type (e.g. `NedParam`, `CellVector`) — far more
# readable than the fully-qualified `OmnetppPred.NedModule.NedParam`.
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
    ReferenceToText(; font=font_ubuntu_monospace_regular_20)

Projection that renders a `Reference` as a single-line, color-coded
`TextBlock`. Mirrors the shape of `Base.show` for references but each
token (delimiter, name, index, type) is a separate `TextString` span
with its own color.
"""
@projection struct ReferenceToText
    font::StyleFont = font_ubuntu_monospace_regular_20
end

map_reference_forward(::ReferenceToText, ::SimpleIoMap, _) = nothing
map_reference_backward(::ReferenceToText, ::SimpleIoMap, _) = nothing

# Append the colored token spans for a single step to `spans`.
function _emit_step_short!(spans::Vector{TextDocument}, p::ReferenceToText, step::FieldReferenceStep)
    push!(spans, _tok(".", p.font, color_solarized_gray))
    push!(spans, _tok(step.name, p.font, color_solarized_cyan))
end

function _emit_step_short!(spans::Vector{TextDocument}, p::ReferenceToText, step::RangeReferenceStep)
    if is_element_reference_step(step)
        push!(spans, _tok("[", p.font, color_solarized_gray))
        push!(spans, _tok(string(step.start + 1), p.font, color_solarized_magenta))
        push!(spans, _tok("]", p.font, color_solarized_gray))
    elseif is_position_reference_step(step)
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

function _emit_step_short!(spans::Vector{TextDocument}, p::ReferenceToText, step::TypeReferenceStep)
    push!(spans, _tok("::", p.font, color_solarized_gray))
    push!(spans, _tok(_short_type(step.type), p.font, color_solarized_orange))
end

function _emit_step_short!(spans::Vector{TextDocument}, p::ReferenceToText, step::PointReferenceStep)
    push!(spans, _tok("@(", p.font, color_solarized_gray))
    push!(spans, _tok(string(step.x), p.font, color_solarized_magenta))
    push!(spans, _tok(",", p.font, color_solarized_gray))
    push!(spans, _tok(string(step.y), p.font, color_solarized_magenta))
    push!(spans, _tok(")", p.font, color_solarized_gray))
end

function _emit_step_short!(spans::Vector{TextDocument}, p::ReferenceToText, step::ProjectionReferenceStep)
    push!(spans, _tok("<", p.font, color_solarized_gray))
    push!(spans, _tok(_projection_name(step.projection), p.font, color_solarized_yellow))
    if !(step.output_path isa EmptyReference)
        push!(spans, _tok(": ", p.font, color_solarized_gray))
        _emit_path_short!(spans, p, step.output_path)
    end
    push!(spans, _tok(">", p.font, color_solarized_gray))
end

# Fallback for unknown step subtypes — surface them in red rather than throw.
function _emit_step_short!(spans::Vector{TextDocument}, p::ReferenceToText, step::ReferenceStep)
    push!(spans, _tok(string(step), p.font, color_solarized_red))
end

# Emit the folded `::Type` checkpoint a node carries (the type the step descends
# from), the same shape the old interleaved `TypeReferenceStep` step rendered.
function _emit_type_short!(spans::Vector{TextDocument}, p::ReferenceToText, T)
    push!(spans, _tok("::", p.font, color_solarized_gray))
    push!(spans, _tok(_short_type(T), p.font, color_solarized_orange))
end

function _emit_path_short!(spans::Vector{TextDocument}, p::ReferenceToText, path::ConcreteReference)
    path.type === nothing || _emit_type_short!(spans, p, path.type)
    _emit_step_short!(spans, p, head(path))
    t = tail(path)
    if t isa EmptyReference
        t.type === nothing || _emit_type_short!(spans, p, t.type)
    else
        _emit_path_short!(spans, p, t)
    end
end

_emit_path_short!(::Vector{TextDocument}, ::ReferenceToText, ::EmptyReference) = nothing

function _short_text(p::ReferenceToText, ref)
    spans = TextDocument[]
    if ref === nothing
        push!(spans, _tok("(no selection)", p.font, color_solarized_gray))
    elseif ref isa EmptyReference
        # Whole-element selection: show its folded type if known, else ∅.
        ref.type === nothing ? push!(spans, _tok("∅", p.font, color_solarized_gray)) :
                               _emit_type_short!(spans, p, ref.type)
    else
        _emit_path_short!(spans, p, ref)
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
    ReferenceToHumanReadableText(document; font=font_ubuntu_monospace_regular_20)

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
"""
@projection struct ReferenceToHumanReadableText
    document::Any
    font::StyleFont = font_ubuntu_monospace_regular_20
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

function _emit_type_tail!(line::Vector{TextDocument}, p::ReferenceToHumanReadableText,
                          document, prefix::Reference, parent_type)
    name = parent_type !== nothing ? _short_type(parent_type) :
                                     _parent_type_name(document, prefix)
    push!(line, _tok(" of ", p.font, color_solarized_gray))
    push!(line, _tok(_article(name), p.font, color_solarized_gray))
    color = name == "?" ? color_solarized_red : color_solarized_orange
    push!(line, _tok(name, p.font, color))
end

# Build the leading "the <description>" spans for a single navigation step.
# The type tail (" of a <Type>") is appended by `_walk_long!`, which knows the
# parent type. Returns `Vector{TextDocument}`.
function _phrase_for(p::ReferenceToHumanReadableText, step::FieldReferenceStep)
    line = TextDocument[]
    push!(line, _tok("the ", p.font, color_solarized_gray))
    push!(line, _tok(step.name, p.font, color_solarized_cyan))
    line
end

function _phrase_for(p::ReferenceToHumanReadableText, step::RangeReferenceStep)
    line = TextDocument[]
    push!(line, _tok("the ", p.font, color_solarized_gray))
    if is_element_reference_step(step)
        push!(line, _tok(_ordinal(step.start + 1), p.font, color_solarized_magenta))
        push!(line, _tok(" element", p.font, color_solarized_gray))
    elseif is_position_reference_step(step)
        push!(line, _tok(_ordinal(step.start), p.font, color_solarized_magenta))
        push!(line, _tok(" position", p.font, color_solarized_gray))
    else
        push!(line, _tok("range ", p.font, color_solarized_gray))
        push!(line, _tok(string(step.start), p.font, color_solarized_magenta))
        push!(line, _tok(" to ", p.font, color_solarized_gray))
        push!(line, _tok(string(step.stop), p.font, color_solarized_magenta))
    end
    line
end


function _phrase_for(p::ReferenceToHumanReadableText, step::PointReferenceStep)
    line = TextDocument[]
    push!(line, _tok("the pixel at (", p.font, color_solarized_gray))
    push!(line, _tok(string(step.x), p.font, color_solarized_magenta))
    push!(line, _tok(", ", p.font, color_solarized_gray))
    push!(line, _tok(string(step.y), p.font, color_solarized_magenta))
    push!(line, _tok(")", p.font, color_solarized_gray))
    line
end

function _phrase_for_projection(p::ReferenceToHumanReadableText, step::ProjectionReferenceStep)
    line = TextDocument[]
    push!(line, _tok("inside the ", p.font, color_solarized_gray))
    push!(line, _tok(_projection_name(step.projection), p.font, color_solarized_yellow))
    push!(line, _tok(" projection", p.font, color_solarized_gray))
    line
end

# Fallback for unknown step subtypes — surface them in red.
function _phrase_for(p::ReferenceToHumanReadableText, step::ReferenceStep)
    TextDocument[_tok(string(step), p.font, color_solarized_red)]
end

# Walk a path front-to-back, appending one line per step to `lines`.
# `prefix` is the path leading up to but not including the current step,
# used for the parent-type lookup. `document` is the document the prefix
# is evaluated against (the outer document at the top level, or the
# projection's output at nested levels — for nested levels we pass
# `nothing` since the projection's output is not addressable here, which
# yields "?" tails inside nested projection paths).
# `TypeReferenceStep` checkpoints are not lines: each one supplies the parent type
# of the navigation step that follows it (a canonical reference carries one
# before every step). When no checkpoint precedes a step, the parent type falls
# back to `evaluate_reference(document, prefix)`, so plain (un-annotated) refs
# still read correctly. `prefix` is the path up to but not including the step.
function _walk_long!(lines::Vector{Vector{TextDocument}},
                     p::ReferenceToHumanReadableText,
                     path::ConcreteReference,
                     document, prefix::Reference, parent_type)
    step = head(path)
    new_prefix = extend_reference(prefix, step)
    t = tail(path)
    if step isa TypeReferenceStep
        # Checkpoint: emit no line; carry its type to the next nav step.
        t isa EmptyReference || _walk_long!(lines, p, t, document, new_prefix, step.type)
        return
    end
    if step isa ProjectionReferenceStep
        if !(step.output_path isa EmptyReference)
            _walk_long!(lines, p, step.output_path, nothing, EmptyReference(), nothing)
        end
        line = _phrase_for_projection(p, step)
    else
        line = _phrase_for(p, step)
    end
    _emit_type_tail!(line, p, document, prefix, parent_type)
    push!(lines, line)
    t isa EmptyReference || _walk_long!(lines, p, t, document, new_prefix, nothing)
end

_walk_long!(::Vector{Vector{TextDocument}}, ::ReferenceToHumanReadableText,
            ::EmptyReference, _, ::Reference, _) = nothing

function _long_text(p::ReferenceToHumanReadableText, ref)
    if ref === nothing
        return TextBlock(_tok("no selection", p.font, color_solarized_gray))
    elseif ref isa EmptyReference
        type_name = p.document === nothing ? "document" : _short_type(typeof(p.document))
        type_color = p.document === nothing ? color_solarized_gray : color_solarized_orange
        return TextBlock(
            _tok("the whole ", p.font, color_solarized_gray),
            _tok(type_name, p.font, type_color),
        )
    end
    lines = Vector{Vector{TextDocument}}()
    _walk_long!(lines, p, ref, p.document, EmptyReference(), nothing)
    reverse!(lines)
    spans = TextDocument[]
    for (i, line) in enumerate(lines)
        append!(spans, line)
        if i < length(lines)
            # "which is" connects each node to its role in its parent (the line
            # below it), so the rows read as one sentence.
            push!(spans, _tok(" which is", font_ubuntu_monospace_italic_20, color_solarized_gray))
            push!(spans, TextNewline(font=p.font))
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

end # module
