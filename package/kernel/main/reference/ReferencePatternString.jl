# Fragment of `ReferenceModule` — the **string spelling of a pattern**: `ref"…"` and
# `parse_reference_pattern`, which read a dotted, glob-style key of the kind a
# configuration file is written in and answer the same `Vector{PatStep}` the Julia
# surface lowers to.
#
# One semantics, two spellings. Nothing here matches anything: it parses, and the
# matchers in `ReferenceCase.jl` and `ReferenceRules.jl` do the rest — which is the whole
# point of making it a front end rather than a second pattern language.
#
# The runtime function is not a convenience beside the macro; it is the reason the
# fragment exists. A rule set read from a configuration file has no macro, so a pattern
# has to be constructible from text at run time.
#
#     ref"**.host[*].queue.capacity"   ≡   __.host[_].queue.capacity
#
# Two departures from the language it is modelled on, both deliberate:
#
#   - **Indices shift.** A configuration counts module vectors from zero; every index in
#     this codebase is 1-based, so `host[0]` parses to element 1 and `[0..3]` to `1..4`.
#     The conversion belongs here, at the boundary, and nowhere else.
#   - **`**` is a whole component.** A key like `host**x` — a run of steps spliced into
#     the middle of a *name* — has no reading in a step-structured path, and is refused
#     rather than approximated. `**.a`, `a.**`, `a.**.b` are all fine, and are what
#     configuration keys are actually written with.

# ------------------------------------------------------------
# The surface
# ------------------------------------------------------------

const REFERENCE_PATTERN_GAP = "**"
const REFERENCE_PATTERN_LAZY_GAP = "**?"
const REFERENCE_PATTERN_ANY_STEP = "*"

# The characters that make a name a glob rather than a literal.
const _GLOB_METACHARACTERS = ('*', '?', '{')

"""
    parse_reference_pattern(text) -> Vector{PatStep}

Parse the string spelling of a pattern — dotted components, `**` for a run of steps,
`*` for one step, glob characters inside a name, `[…]` for an index — into the same
pattern data the Julia surface produces.

    parse_reference_pattern("**.host[*].queue.capacity")

Indices are converted from the 0-based counting a configuration file uses to the 1-based
counting everything here uses, so `host[0]` is the first element.
"""
function parse_reference_pattern(text::AbstractString)
    steps = PatStep[]
    for component in _split_pattern_components(text)
        _push_pattern_component!(steps, component, text)
    end
    steps
end

# Split on `.`, but not on one inside brackets or braces, and not on an escaped one.
function _split_pattern_components(text::AbstractString)
    components = String[]
    current = IOBuffer()
    depth = 0
    escaped = false
    for c in text
        if escaped
            print(current, c)
            escaped = false
        elseif c == '\\'
            print(current, c)
            escaped = true
        elseif c == '[' || c == '{'
            depth += 1
            print(current, c)
        elseif c == ']' || c == '}'
            depth -= 1
            print(current, c)
        elseif c == '.' && depth == 0
            push!(components, String(take!(current)))
        else
            print(current, c)
        end
    end
    escaped && error("pattern string ends in a backslash: $text")
    depth == 0 || error("unbalanced brackets in pattern string: $text")
    push!(components, String(take!(current)))
    components
end

function _push_pattern_component!(steps::Vector{PatStep}, component::AbstractString,
                                  text::AbstractString)
    isempty(component) && error("empty component in pattern string: $text")

    component == REFERENCE_PATTERN_LAZY_GAP && return push!(steps, PatStepGap(nothing, true))
    component == REFERENCE_PATTERN_GAP && return push!(steps, PatStepGap())
    component == REFERENCE_PATTERN_ANY_STEP && return push!(steps, PatStepAny())

    name, index = _split_component_index(component, text)
    occursin(REFERENCE_PATTERN_GAP, name) &&
        error("`**` spans whole steps, so it cannot appear inside the name `$name` — " *
              "write it as its own component, as in `a.**.b`")
    isempty(name) && error("an index needs a name in front of it: `$component`")

    push!(steps, PatStepField(_pattern_name_value(name)))
    index === nothing || push!(steps, PatStepIndex(_pattern_index_value(index, text)))
    steps
end

# Split a trailing `[…]` off a component, honouring escapes.
function _split_component_index(component::AbstractString, text::AbstractString)
    endswith(component, ']') || return (component, nothing)
    # A hand reverse scan, not `findlast`: Base's Char method wraps the Char
    # in `isequal` and lands in the generic `findlast(::Function, ...)`,
    # whose widened body is unresolvable under a trimmed build.
    open = nothing
    let i = lastindex(component)
        while i >= firstindex(component)
            if component[i] == '['
                open = i
                break
            end
            i = prevind(component, i)
        end
    end
    open === nothing && error("unbalanced `]` in pattern string: $text")
    (component[firstindex(component):prevind(component, open)],
     component[nextind(component, open):prevind(component, lastindex(component))])
end

# A name is a literal unless it says otherwise. `\x` unescapes either way, so a name
# holding a real `*` reaches the matcher as the character it is.
_pattern_name_value(name::AbstractString) =
    _has_glob_metacharacter(name) ? PatValueGlob(String(name)) :
    PatValueLiteral(_unescape_pattern(name))

function _has_glob_metacharacter(name::AbstractString)
    escaped = false
    for c in name
        if escaped
            escaped = false
        elseif c == '\\'
            escaped = true
        elseif c in _GLOB_METACHARACTERS
            return true
        end
    end
    false
end

function _unescape_pattern(name::AbstractString)
    out = IOBuffer()
    escaped = false
    for c in name
        if escaped
            print(out, c)
            escaped = false
        elseif c == '\\'
            escaped = true
        else
            print(out, c)
        end
    end
    String(take!(out))
end

# `[*]`, `[3]`, `[0..7]`. The two numeric forms shift base; the wildcard has no base to
# shift.
function _pattern_index_value(index::AbstractString, text::AbstractString)
    index == REFERENCE_PATTERN_ANY_STEP && return PatValueWildcard()

    if occursin("..", index)
        bounds = split(index, ".."; limit = 2)
        lo = tryparse(Int, strip(bounds[1]))
        hi = tryparse(Int, strip(bounds[2]))
        (lo === nothing || hi === nothing) &&
            error("`[$index]` in a pattern string must be a numeric range like [0..7]: $text")
        return PatValueRange(lo + 1, hi + 1)
    end

    single = tryparse(Int, strip(index))
    single === nothing &&
        error("`[$index]` in a pattern string must be an index, a range, or `*`: $text")
    PatValueLiteral(single + 1)
end

# ------------------------------------------------------------
# Macro entry point
# ------------------------------------------------------------

"""
    ref"**.host[*].queue.capacity"

The string spelling of a pattern, parsed at macroexpand time into the same pattern data
the Julia surface lowers to. Usable as an arm of `@reference_case` / `@reference_rules`,
or on its own as a `Vector{PatStep}`.

    @reference_rules begin
        ref"**.queue.capacity" => 100
    end

See [`parse_reference_pattern`](@ref) for the language, and for the two places it departs
from the configuration syntax it is modelled on.
"""
macro ref_str(text)
    _quote_pattern(parse_reference_pattern(text))
end
