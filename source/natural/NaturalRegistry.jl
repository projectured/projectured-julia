# Fragment of `NaturalModule`.
#
# The tables the **natural projection** is built from.
#
# `NaturalModule` beside this one is where a domain declares its notation
# now. What is left here is the keyed-factory form, which a domain uses when one
# registration carries several rows, and the fallback — plus the two `*_entries`
# functions, which read both tables so a domain can move from one to the other on
# its own.
#
# The natural projection renders almost any document to graphics. To do that it
# needs one dispatch entry per domain — a `JsonDocument` goes to `JsonToSyntax`, a
# `GraphGraph` goes to the two graph stages — and a table that named every domain
# would put the renderer above all of them. So the renderer declares the tables
# and each domain fills in its own row, in a file it already has. This is the same
# seam `NaturalModule` uses for natural text, one level up: a
# type key instead of an instance key.
#
# There are three tables. Two are the ways a domain becomes graphics:
#
# - **to-syntax** — the domain has a `*ToSyntax` projection and the shared
#   `Syntax → Text → Graphics` tail draws it. This is most domains.
# - **to-graphics** — the domain draws itself, because a page of blocks or a
#   diagram is not a syntax tree. These entries need the backend's text measure,
#   so a domain registers a factory rather than a pair.
#
# The third is the **fallback**: what to draw for a document no row claimed. It is
# registered like the others and nothing registers it by default, so a renderer
# draws what it was taught and an error message for the rest. `ProjecturedSyntax`
# is what registers the reflection tail, and a session that never loads it never
# carries it.
#
# A row can be registered as a ready-made pair or as a factory. A factory runs on
# every table build, so each renderer gets its own projection instances; a pair is
# shared by every renderer that uses it. Pairs are registered first, so a domain
# that wants to override another domain's row can.
# Ready-made rows. A row registered twice keeps the first, so a reload does not
# stack duplicates.
const _SYNTAX_PAIRS = Pair{Type,Any}[]
# Keyed factories, `key => () -> Vector{Pair{Type,Any}}`.
const _SYNTAX_FACTORIES = Pair{Symbol,Any}[]
# Keyed factories, `key => (; measure) -> Vector{Pair{Type,Any}}`.
const _GRAPHICS_FACTORIES = Pair{Symbol,Any}[]
# Keyed factories, `key => (; measure, font, wrap) -> Vector{Pair{Type,Any}}`.
const _FALLBACK_FACTORIES = Pair{Symbol,Any}[]

"""
    register_natural_syntax!(pairs::Pair...) -> nothing

Teach the natural renderer how a domain becomes syntax, as ready-made rows. Call
it from the registering module's `__init__` — the table is runtime state, not
something to bake into a precompiled image. A type registered twice keeps the
first row. [`get_natural_syntax_entries`](@ref) gives these rows before the rows
of the syntax factories and of the rung table, so a row here overrides another
row of its type. The rows serve the renderer only: the notation that
[`make_natural_projection`](@ref) reads is [`register_natural_notation!`](@ref).

Without this a document from a package the renderer cannot see falls through to
the reflection tail and renders as its field names instead of as itself.
"""
function register_natural_syntax!(pairs::Pair...)
    for pr in pairs
        document_type = first(pr)::Type
        any(e -> first(e) === document_type, _SYNTAX_PAIRS) && continue
        push!(_SYNTAX_PAIRS, Pair{Type,Any}(document_type, last(pr)))
    end
    nothing
end

"""
    register_natural_syntax!(key::Symbol, factory) -> nothing

The factory form: `factory()` returns the domain's rows, and runs on every table
build, so each renderer gets its own projection instances. Use it when a row
holds a projection with reactive state. `key` names the registering domain and
makes the registration idempotent.
"""
function register_natural_syntax!(key::Symbol, factory)
    any(e -> first(e) === key, _SYNTAX_FACTORIES) && return nothing
    push!(_SYNTAX_FACTORIES, key => factory)
    nothing
end

"""
    register_natural_graphics!(key::Symbol, factory) -> nothing

Teach the natural renderer how a domain becomes graphics **directly**, without
the syntax tail — a page of blocks, a diagram, a typeset formula.
`factory(; measure)` returns the domain's rows; `measure::TextMeasure` is the
backend's text measure.
"""
function register_natural_graphics!(key::Symbol, factory)
    any(e -> first(e) === key, _GRAPHICS_FACTORIES) && return nothing
    push!(_GRAPHICS_FACTORIES, key => factory)
    nothing
end

"""
    register_natural_fallback!(key::Symbol, factory) -> nothing

Teach the natural renderer what to do with a document no row above it claimed.

`factory(; measure, font, wrap)` returns rows, so what a fallback covers is the
fallback's own decision — `ProjecturedSyntax` registers the reflection tail under
`Any`, and the placeholder types that only its leaves can draw.

**Nothing is registered by default, and that is the point.** With no fallback the
renderer draws what it was taught and an error message for everything else. A
session that wants a document of any shape drawn as reflected syntax loads the
package that can do it.
"""
function register_natural_fallback!(key::Symbol, factory)
    any(e -> first(e) === key, _FALLBACK_FACTORIES) && return nothing
    push!(_FALLBACK_FACTORIES, key => factory)
    nothing
end

"""
    get_natural_syntax_entries() -> Vector{Pair{Type,Any}}

Every registered to-syntax row: the ready-made ones first, then what the
factories build now, then the `:syntax` rows of the rung table.
"""
function get_natural_syntax_entries()
    out = Pair{Type,Any}[e for e in _SYNTAX_PAIRS]
    for (_, factory) in _SYNTAX_FACTORIES
        for pr in factory()
            push!(out, Pair{Type,Any}(first(pr), last(pr)))
        end
    end
    append!(out, get_natural_entries(:syntax))
    out
end

"""
    get_natural_graphics_entries(; measure) -> Vector{Pair{Type,Any}}

Every registered to-graphics row, built now against `measure`.
"""
function get_natural_graphics_entries(; measure::TextMeasure)
    out = Pair{Type,Any}[]
    for (_, factory) in _GRAPHICS_FACTORIES
        for pr in factory(; measure = measure)
            push!(out, Pair{Type,Any}(first(pr), last(pr)))
        end
    end
    append!(out, get_natural_entries(:graphics; measure = measure))
    out
end

"""
    get_natural_fallback_entries(; measure, font, wrap) -> Vector{Pair{Type,Any}}

Every registered fallback row, built now. Empty when nothing registered one.
"""
function get_natural_fallback_entries(; measure::TextMeasure, font, wrap)
    out = Pair{Type,Any}[]
    for (_, factory) in _FALLBACK_FACTORIES
        for pr in factory(; measure = measure, font = font, wrap = wrap)
            push!(out, Pair{Type,Any}(first(pr), last(pr)))
        end
    end
    out
end
