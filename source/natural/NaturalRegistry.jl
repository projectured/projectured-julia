"""
    NaturalRegistryModule

The two tables the **natural projection** is built from, and nothing else.

The natural projection renders almost any document to graphics. To do that it
needs one dispatch entry per domain — a `JsonDocument` goes to `JsonToSyntax`, a
`GraphGraph` goes to the two graph stages — and a table that named every domain
would put the renderer above all of them. So the renderer declares the tables
and each domain fills in its own row, in a file it already has. This is the same
seam `natural_syntax_projection` uses for natural-text export, one level up: a
type key instead of an instance key.

There are three tables. Two are the ways a domain becomes graphics:

- **to-syntax** — the domain has a `*ToSyntax` projection and the shared
  `Syntax → Text → Graphics` tail draws it. This is most domains.
- **to-graphics** — the domain draws itself, because a page of blocks or a
  diagram is not a syntax tree. These entries need the backend's text-measuring
  function, so a domain registers a factory rather than a pair.

The third is the **fallback**: what to draw for a document no row claimed. It is
registered like the others and nothing registers it by default, so a renderer
draws what it was taught and an error message for the rest. `ProjecturedSyntax`
is what registers the reflection tail, and a session that never loads it never
carries it.

A row can be registered as a ready-made pair or as a factory. A factory runs on
every table build, so each renderer gets its own projection instances; a pair is
shared by every renderer that uses it. Pairs are registered first, so a domain
that wants to override another domain's row can.
"""
module NaturalRegistryModule

export register_natural_syntax!, register_natural_graphics!, register_natural_fallback!,
       natural_syntax_entries, natural_graphics_entries, natural_fallback_entries

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
first row.

Without this a document from a package the renderer cannot see falls through to
the reflection tail and renders as its field names instead of as itself.
"""
function register_natural_syntax!(pairs::Pair...)
    for pr in pairs
        key = first(pr)
        any(e -> first(e) === key, _SYNTAX_PAIRS) && continue
        push!(_SYNTAX_PAIRS, Pair{Type,Any}(key, last(pr)))
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
`factory(; measure)` returns the domain's rows; `measure(text, font) -> (w, h)`
is the backend's text-measuring function.
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
    natural_syntax_entries() -> Vector{Pair{Type,Any}}

Every registered to-syntax row: the ready-made ones first, then what the
factories build now.
"""
function natural_syntax_entries()
    out = Pair{Type,Any}[e for e in _SYNTAX_PAIRS]
    for (_, factory) in _SYNTAX_FACTORIES
        for pr in factory()
            push!(out, Pair{Type,Any}(first(pr), last(pr)))
        end
    end
    out
end

"""
    natural_graphics_entries(; measure) -> Vector{Pair{Type,Any}}

Every registered to-graphics row, built now against `measure`.
"""
function natural_graphics_entries(; measure)
    out = Pair{Type,Any}[]
    for (_, factory) in _GRAPHICS_FACTORIES
        for pr in factory(; measure = measure)
            push!(out, Pair{Type,Any}(first(pr), last(pr)))
        end
    end
    out
end

"""
    natural_fallback_entries(; measure, font, wrap) -> Vector{Pair{Type,Any}}

Every registered fallback row, built now. Empty when nothing registered one.
"""
function natural_fallback_entries(; measure, font, wrap)
    out = Pair{Type,Any}[]
    for (_, factory) in _FALLBACK_FACTORIES
        for pr in factory(; measure = measure, font = font, wrap = wrap)
            push!(out, Pair{Type,Any}(first(pr), last(pr)))
        end
    end
    out
end

end # module
