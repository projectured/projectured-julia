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
#   diagram is not a syntax tree. Its factory also gets the backend's text
#   measure.
#
# The third is the **fallback**: what to draw for a document no row claimed. It is
# registered like the others and nothing registers it by default, so a renderer
# draws what it was taught and an error message for the rest. `ProjecturedPlatform`
# is what registers the reflection tail, and a session that never loads it never
# carries it.
#
# A row is registered as a factory, which runs on every table build with the
# `Appearance` of the editor, so each renderer gets its own projection instances
# and each instance takes the scaled theme of its domain from that editor.

# Keyed factories, `key => (; appearance) -> Vector{Pair{Type,Any}}`.
const _SYNTAX_FACTORIES = Pair{Symbol,Any}[]
# Keyed factories, `key => (; measure, appearance) -> Vector{Pair{Type,Any}}`.
const _GRAPHICS_FACTORIES = Pair{Symbol,Any}[]
# Keyed factories, `key => (; measure, font, wrap, appearance) -> Vector{Pair{Type,Any}}`.
const _FALLBACK_FACTORIES = Pair{Symbol,Any}[]

"""
    register_natural_syntax!(key::Symbol, factory) -> nothing

Teach the natural renderer how a domain becomes syntax. `factory(; appearance)`
returns the domain's rows, and runs on every table build with the `Appearance`
of the editor, so each renderer gets its own projection instances. `key` names
the registering domain and makes the registration idempotent. Call it from the
registering module's `__init__`: the table is runtime state. The rows serve the
renderer only: the notation that [`make_natural_projection`](@ref) reads is
[`register_natural_notation!`](@ref).
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
`factory(; measure, appearance)` returns the domain's rows; `measure::TextMeasure`
is the backend's text measure, and `appearance` the `Appearance` of the editor.
"""
function register_natural_graphics!(key::Symbol, factory)
    any(e -> first(e) === key, _GRAPHICS_FACTORIES) && return nothing
    push!(_GRAPHICS_FACTORIES, key => factory)
    nothing
end

"""
    register_natural_fallback!(key::Symbol, factory) -> nothing

Teach the natural renderer what to do with a document no row above it claimed.

`factory(; measure, font, wrap, appearance)` returns rows, so what a fallback covers is the
fallback's own decision — `ProjecturedPlatform` registers the reflection tail under
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
    get_natural_syntax_entries(; appearance) -> Vector{Pair{Type,Any}}

Every registered to-syntax row, built now with `appearance`: what the factories
build, then the `:syntax` rows of the rung table.
"""
function get_natural_syntax_entries(; appearance::Appearance)
    out = Pair{Type,Any}[]
    for (_, factory) in _SYNTAX_FACTORIES
        for pr in factory(; appearance = appearance)
            push!(out, Pair{Type,Any}(first(pr), last(pr)))
        end
    end
    append!(out, get_natural_entries(:syntax; appearance = appearance))
    out
end

"""
    get_natural_graphics_entries(; measure, appearance) -> Vector{Pair{Type,Any}}

Every registered to-graphics row, built now against `measure` and `appearance`.
"""
function get_natural_graphics_entries(; measure::TextMeasure, appearance::Appearance)
    out = Pair{Type,Any}[]
    for (_, factory) in _GRAPHICS_FACTORIES
        for pr in factory(; measure = measure, appearance = appearance)
            push!(out, Pair{Type,Any}(first(pr), last(pr)))
        end
    end
    append!(out, get_natural_entries(:graphics; measure = measure, appearance = appearance))
    out
end

"""
    get_natural_fallback_entries(; measure, font, wrap, appearance) -> Vector{Pair{Type,Any}}

Every registered fallback row, built now. Empty when nothing registered one.
"""
function get_natural_fallback_entries(; measure::TextMeasure, font, wrap, appearance::Appearance)
    out = Pair{Type,Any}[]
    for (_, factory) in _FALLBACK_FACTORIES
        for pr in factory(; measure = measure, font = font, wrap = wrap, appearance = appearance)
            push!(out, Pair{Type,Any}(first(pr), last(pr)))
        end
    end
    out
end
