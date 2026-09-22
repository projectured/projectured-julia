# Fragment of `NaturalModule` — the natural notation of a domain: the three
# rungs a document can be rendered at, and the registry that says which
# projection each domain builds for each rung.

const RUNGS = (:syntax, :text, :graphics)

# What a domain can produce by itself: `Type => [(rung, make), …]`. A `make` for
# `:graphics` takes `(; measure)`; the others take no argument.
const _NOTATIONS = Pair{Type,Vector{Tuple{Symbol,Any}}}[]
# `Type => (format, extension)`.
const _FORMATS = Pair{Type,Tuple{Symbol,String}}[]
# `format => parse(text) -> Document`.
const _PARSERS = Pair{Symbol,Any}[]
# `(from, to) => make(; measure) -> Projection`.
const _LADDER = Pair{Tuple{Symbol,Symbol},Any}[]

_lookup(table, key) = for entry in table
    first(entry) === key && return last(entry)
end

# ── Registration ────────────────────────────────────────────────────────────

"""
    register_natural_notation!(T::Type, rung::Symbol, make) -> nothing

Teach the natural machinery what `T` produces by itself. `rung` is `:syntax`,
`:text` or `:graphics`; `make` builds the projection — `make()` for the first
two, `make(; measure)` for `:graphics`, which draws and so needs the backend's
text measurement.

Call it from the registering module's `__init__`: the tables are runtime state,
not something to bake into a precompiled image. A `(type, rung)` registered twice
keeps the first, so a reload does not stack duplicates.

A type may register more than one rung. Markdown is written as syntax and drawn
as a page, and both are true.
"""
function register_natural_notation!(T::Type, rung::Symbol, make)
    rung in RUNGS || error("register_natural_notation!: $(repr(rung)) is not one of $RUNGS")
    rows = _lookup(_NOTATIONS, T)
    if rows === nothing
        push!(_NOTATIONS, T => Tuple{Symbol,Any}[(rung, make)])
    elseif !any(r -> first(r) === rung, rows)
        push!(rows, (rung, make))
    end
    nothing
end

"""
    register_natural_format!(T::Type, format::Symbol, extension::AbstractString) -> nothing

Name the format `T` is written in, and the file extension that names it back:
`:json` and `".json"`. The format key is what [`parse_natural_text`](@ref) takes,
so this is the seam that turns a type into a parser.
"""
function register_natural_format!(T::Type, format::Symbol, extension::AbstractString)
    _lookup(_FORMATS, T) === nothing || return nothing
    push!(_FORMATS, T => (format, String(extension)))
    nothing
end

"""
    register_natural_parser!(format::Symbol, parse) -> nothing

Teach the machinery how to read text of `format` back into a document.
`parse(text) -> Document`.

It is keyed by the format and not by a type, so the package that owns a grammar
can fill this seam without owning the projection that prints it.
"""
function register_natural_parser!(format::Symbol, parse)
    _lookup(_PARSERS, format) === nothing || return nothing
    push!(_PARSERS, format => parse)
    nothing
end

"""
    register_natural_rung!(from::Symbol, to::Symbol, make) -> nothing

Teach the machinery one step of the ladder: `make(; measure) -> Projection` turns
a `from` document into a `to` one. This package registers `text → graphics` and
`text → string` itself; `syntax → text` belongs to whoever can supply it, and no
domain ever registers a rung.
"""
function register_natural_rung!(from::Symbol, to::Symbol, make)
    _lookup(_LADDER, (from, to)) === nothing || return nothing
    push!(_LADDER, (from, to) => make)
    nothing
end

"""
    register_natural_domain!(T::Type; rung, make, format, extension, parse) -> nothing

Everything a domain declares about its natural notation, in one call. Every
keyword is optional, so a domain that only parses, or only draws, still says so
once. It is the three registrations above; use those directly for a second rung.
"""
function register_natural_domain!(T::Type; rung = nothing, make = nothing,
                                  format = nothing, extension = nothing,
                                  parse = nothing)
    (rung === nothing) == (make === nothing) ||
        error("register_natural_domain!: name `rung` and `make` together")
    (format === nothing) == (extension === nothing) ||
        error("register_natural_domain!: name `format` and `extension` together")
    rung === nothing || register_natural_notation!(T, rung, make)
    format === nothing || register_natural_format!(T, format, extension)
    if parse !== nothing
        format === nothing &&
            error("register_natural_domain!: a parser needs the `format` it reads")
        register_natural_parser!(format, parse)
    end
    nothing
end

# ── Reading the tables ──────────────────────────────────────────────────────

# The entry of a type-keyed table whose type is the most derived one that `T` is
# a subtype of, whatever the order of the registrations, or `nothing`. A
# registration on an abstract root answers for every document under it, and a
# registration on a subtype answers for that subtype.
function _find_most_derived_entry(table, T::Type)
    found = nothing
    for entry in table
        T <: first(entry) || continue
        (found === nothing || first(entry) <: first(found)) && (found = entry)
    end
    found
end

# The rows that the most derived registered type declared.
function _notations(T::Type)
    entry = _find_most_derived_entry(_NOTATIONS, T)
    entry === nothing ? Tuple{Symbol,Any}[] : last(entry)
end

_notation(T::Type, rung::Symbol) =
    for row in _notations(T)
        first(row) === rung && return last(row)
    end

_build(make, rung::Symbol, measure) =
    rung === :graphics ? make(; measure = measure) : make()

"""
    get_natural_entries(rung::Symbol; measure = nothing) -> Vector{Pair{Type,Any}}

Every registered row for one rung, built now, as the type-keyed pairs a
dispatching projection is spliced from.
"""
function get_natural_entries(rung::Symbol; measure = nothing)
    out = Pair{Type,Any}[]
    for entry in _NOTATIONS
        for row in last(entry)
            first(row) === rung || continue
            push!(out, Pair{Type,Any}(first(entry), _build(last(row), rung, measure)))
        end
    end
    out
end

"""
    get_natural_format(::Type) -> Symbol | Nothing

The format key a type's documents are written in — `JsonDocument` → `:json`.
`nothing` for a type no domain claimed. It is what turns a **type** into the key
[`parse_natural_text`](@ref) takes, which a caller holding only a type — the
insertion a person is typing into — has no instance to ask for.
"""
function get_natural_format(T::Type)
    entry = _find_most_derived_entry(_FORMATS, T)
    entry === nothing ? nothing : first(last(entry))
end

"""
    get_natural_extension(document) -> String | Nothing

The file extension `document` is written as, `".json"`. `nothing` for a document
no domain claimed.
"""
function get_natural_extension(document)
    entry = _find_most_derived_entry(_FORMATS, typeof(document))
    entry === nothing ? nothing : last(last(entry))
end

"""
    has_natural_parser(format::Symbol) -> Bool

Whether a domain registered how to read `format` back.
"""
has_natural_parser(format::Symbol) = _lookup(_PARSERS, format) !== nothing

"""
    find_natural_parser(format::Symbol) -> Function | Nothing

The `parse(text) -> Document` registered for `format`, or `nothing` when no
domain registered one. Two formats that return the same function are one grammar
under two names, as `:yaml` and `:yml` are.
"""
find_natural_parser(format::Symbol) = _lookup(_PARSERS, format)

"""
    parse_natural_text(format::Symbol, text) -> Document

Read `text` of `format` into a document. Errors when no domain claimed the
format; ask [`has_natural_parser`](@ref) first when that is a normal answer.
"""
function parse_natural_text(format::Symbol, text::AbstractString)
    parse = _lookup(_PARSERS, format)
    parse === nothing &&
        error("parse_natural_text: no parser registered for $(repr(format))")
    parse(text)
end

# ── The ladder ──────────────────────────────────────────────────────────────

# The stages from `rung` up to `target`, or `nothing` when a step is missing.
function _climb(rung::Symbol, target::Symbol, measure)
    stages = Any[]
    while rung !== target
        make = _lookup(_LADDER, (rung, _next(rung, target)))
        make === nothing && return nothing
        push!(stages, make(; measure = measure))
        rung = _next(rung, target)
    end
    stages
end

# The rung after `rung` on the way to `target`. `:string` hangs off `:text`.
function _next(rung::Symbol, target::Symbol)
    target === :string && rung === :text && return :string
    rung === :syntax && return :text
    rung === :text && return :graphics
    rung
end

"""
    make_natural_projection(document, target::Symbol; measure = nothing) -> Projection | Nothing

The projection that takes `document` up to `target` — `:syntax`, `:text`,
`:graphics` or `:string` — or `nothing` when the ladder has no path.

It picks the highest rung the document itself declares, so a domain that draws
itself is drawn by its own stage rather than through the syntax tail, and then
chains the registered steps above it. A `:graphics` target needs `measure`.
"""
function make_natural_projection(document, target::Symbol; measure = nothing)
    rows = _notations(typeof(document))
    isempty(rows) && return nothing
    best = nothing
    for rung in (:graphics, :text, :syntax)
        rung === :graphics && target !== :graphics && continue
        make = _notation(typeof(document), rung)
        make === nothing && continue
        stages = target === rung ? Any[] : _climb(rung, target, measure)
        stages === nothing && continue
        best = ChainingProjection(RecursiveProjection(_build(make, rung, measure)),
                                  (RecursiveProjection(s) for s in stages)...)
        break
    end
    best
end

"""
    print_natural_text(document) -> String

`document` as its own text: the domain's notation, then the registered steps up
to a string, run through `print_document` and flattened.

**A shorthand, not a seam.** It is `make_natural_projection(document, :string)`,
`print_document`, and a `String`. A caller that wants the io map, or a different
last rung, builds the projection itself and runs the engine.
"""
function print_natural_text(document)
    projection = make_natural_projection(document, :string)
    projection === nothing &&
        error("print_natural_text: no natural text for $(typeof(document))")
    String(print_document(projection, document).output)
end
