"""
    ObjectToJsonModule

Object → JsonDocument projection. The JSON counterpart of `ObjectToSyntax`:
reflects *any* Julia value into a nested `JsonDocument` tree using runtime type
information, for **LLM consumption** (JSON is the format models have the
strongest priors for and round-trip most reliably).

Structs become a `JsonObject` carrying a reserved `"type"` entry (the type name)
plus one entry per field, each holding the recursively projected field value.
Collections (`CellVector` / `AbstractArray`) become a `JsonArray`. Primitive
values map to the matching JSON primitive.

**Read-only**: this is a serialiser, not an editor view — `map_reference_*` and
`projection_read` all return `nothing`, mirroring `DbCatalogToJson`.
"""
module ObjectToJsonModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..JsonModule: JsonDocument, JsonNull, JsonBool, JsonNumber, JsonString,
                     JsonArray, JsonObject, JsonObjectEntry
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap
import ..ReferenceModule: ElementReference, FieldReference
import ..PrinterContextModule: PrinterContext, child_context, with_property, get_property
import ..JsonToSyntaxModule: JsonToSyntax
import ..SyntaxToTextModule: SyntaxToText
import ..TextToStringModule: TextToString
import ..SequentialProjectionModule: SequentialProjection
import ..RecursiveProjectionModule: RecursiveProjection

export NothingToJsonNull, BoolToJsonBool, NumberToJsonNumber, StringToJsonString,
       SymbolToJsonString, CharToJsonString, CellToJson, ObjectNodeToJsonObject,
       ObjectToJson, json_object

# ── NothingToJsonNull ────────────────────────────────────────────────────────

struct NothingToJsonNull <: Projection end

projection_print(p::NothingToJsonNull, recursion, ::Nothing, ctx) =
    SimpleIoMap(p, nothing, JsonNull())

map_reference_forward(::NothingToJsonNull, iomap, ref) = nothing
map_reference_backward(::NothingToJsonNull, iomap, ref) = nothing
projection_read(::NothingToJsonNull, iomap, op) = nothing

# ── BoolToJsonBool ───────────────────────────────────────────────────────────

struct BoolToJsonBool <: Projection end

projection_print(p::BoolToJsonBool, recursion, b::Bool, ctx) =
    SimpleIoMap(p, b, JsonBool(b))

map_reference_forward(::BoolToJsonBool, iomap, ref) = nothing
map_reference_backward(::BoolToJsonBool, iomap, ref) = nothing
projection_read(::BoolToJsonBool, iomap, op) = nothing

# ── NumberToJsonNumber ───────────────────────────────────────────────────────
# `JsonNumber` only holds `Real`; non-`Real` numbers (e.g. Complex) stringify
# into a `JsonString` so no information is lost.

struct NumberToJsonNumber <: Projection end

function projection_print(p::NumberToJsonNumber, recursion, n::Number, ctx)
    out = n isa Real ? JsonNumber(n) : JsonString(string(n))
    SimpleIoMap(p, n, out)
end

map_reference_forward(::NumberToJsonNumber, iomap, ref) = nothing
map_reference_backward(::NumberToJsonNumber, iomap, ref) = nothing
projection_read(::NumberToJsonNumber, iomap, op) = nothing

# ── StringToJsonString ───────────────────────────────────────────────────────

struct StringToJsonString <: Projection end

projection_print(p::StringToJsonString, recursion, s::AbstractString, ctx) =
    SimpleIoMap(p, s, JsonString(string(s)))

map_reference_forward(::StringToJsonString, iomap, ref) = nothing
map_reference_backward(::StringToJsonString, iomap, ref) = nothing
projection_read(::StringToJsonString, iomap, op) = nothing

# ── SymbolToJsonString ───────────────────────────────────────────────────────

struct SymbolToJsonString <: Projection end

projection_print(p::SymbolToJsonString, recursion, s::Symbol, ctx) =
    SimpleIoMap(p, s, JsonString(string(s)))

map_reference_forward(::SymbolToJsonString, iomap, ref) = nothing
map_reference_backward(::SymbolToJsonString, iomap, ref) = nothing
projection_read(::SymbolToJsonString, iomap, op) = nothing

# ── CharToJsonString ─────────────────────────────────────────────────────────

struct CharToJsonString <: Projection end

projection_print(p::CharToJsonString, recursion, c::Char, ctx) =
    SimpleIoMap(p, c, JsonString(string(c)))

map_reference_forward(::CharToJsonString, iomap, ref) = nothing
map_reference_backward(::CharToJsonString, iomap, ref) = nothing
projection_read(::CharToJsonString, iomap, op) = nothing

# ── CellToJson ───────────────────────────────────────────────────────────────
# Unwraps a Cell and projects its contents transparently (mirror CellToSyntax).

struct CellToJson <: Projection end

function projection_print(p::CellToJson, recursion, cell::Cell, ctx)
    visited = get_property(ctx, :objects_seen, nothing)
    if visited !== nothing && haskey(visited, cell)
        return SimpleIoMap(p, cell, JsonString("⟨cycle: Cell⟩"))
    end
    new_visited = visited === nothing ? IdDict{Any,Bool}() : copy(visited)
    new_visited[cell] = true
    ctx = with_property(ctx, :objects_seen, new_visited)
    projection_printer_recurse(recursion, cell[], ctx)
end

map_reference_forward(::CellToJson, iomap, ref) = nothing
map_reference_backward(::CellToJson, iomap, ref) = nothing
projection_read(::CellToJson, iomap, op) = nothing

# ── ObjectNodeToJsonObject ───────────────────────────────────────────────────
#
# The `Any` fallback. Maps:
#   - CellVector / AbstractArray → JsonArray of recursively-projected elements
#   - struct                     → JsonObject with a reserved type-name entry
#                                  followed by one entry per field
#
# Carries over ObjectToSyntax's behaviour: noise-field filtering (:ref and
# :selection), mutable-ancestor cycle detection, undefined-field handling, and
# an optional element/field `filter` predicate.

struct ObjectNodeToJsonObject <: Projection
    include_selection::Bool
    type_key::Union{String,Nothing}
    filter::Any
end
ObjectNodeToJsonObject(; include_selection=false, type_key="type", filter=nothing) =
    ObjectNodeToJsonObject(include_selection, type_key, filter)

# Unwrap a Cell for predicate/filter testing; pass non-cells through.
_unwrap_cell(x) = x isa Cell ? x[] : x

_json_object(entries::Vector{Cell}) = JsonObject(CellVector(entries), Cell(false), Cell(nothing))
_json_array(elements::Vector{Cell}) = JsonArray(CellVector(elements), Cell(false), Cell(nothing))

function projection_print(p::ObjectNodeToJsonObject, recursion, obj, ctx)
    T = typeof(obj)

    # Cycle detection for mutable ancestors only — immutables (fonts, colors,
    # TextStrings) value-equal many times legitimately. Mirror ObjectToSyntax.
    if ismutable(obj)
        visited = get_property(ctx, :objects_seen, nothing)
        if visited !== nothing && haskey(visited, obj)
            return SimpleIoMap(p, obj, JsonString("⟨cycle: $(nameof(T))⟩"))
        end
        new_visited = visited === nothing ? IdDict{Any,Bool}() : copy(visited)
        new_visited[obj] = true
        ctx = with_property(ctx, :objects_seen, new_visited)
    end

    # Collections render as a JSON array with no type wrapper: the
    # CellVector/Array wrapper carries no structural meaning.
    if obj isa CellVector || obj isa AbstractArray
        idxs = p.filter === nothing ? collect(1:length(obj)) :
               [i for i in 1:length(obj) if p.filter(_unwrap_cell(obj[i]))]
        elements = Cell[
            Cell(projection_printer_recurse(recursion, obj[i],
                     child_context(ctx, ElementReference(i))).output)
            for i in idxs
        ]
        return SimpleIoMap(p, obj, _json_array(elements))
    end

    # Struct → object. Reserved type-name entry first (so the LLM keeps the
    # domain type), then one entry per non-noise field.
    fnames = try fieldnames(T) catch; () end
    fnames = filter(fn -> fn != :ref && (fn != :selection || p.include_selection), fnames)
    if p.filter !== nothing
        fnames = filter(fn -> isdefined(obj, fn) && p.filter(_unwrap_cell(getfield(obj, fn))), fnames)
    end

    entries = Cell[]
    if p.type_key !== nothing
        push!(entries, Cell(JsonObjectEntry(p.type_key, JsonString(string(nameof(T))))))
    end
    for fn in fnames
        value = isdefined(obj, fn) ?
            projection_printer_recurse(recursion, getfield(obj, fn),
                     child_context(ctx, FieldReference(string(fn)))).output :
            JsonString("<undefined>")
        push!(entries, Cell(JsonObjectEntry(string(fn), value)))
    end
    SimpleIoMap(p, obj, _json_object(entries))
end

map_reference_forward(::ObjectNodeToJsonObject, iomap, ref) = nothing
map_reference_backward(::ObjectNodeToJsonObject, iomap, ref) = nothing
projection_read(::ObjectNodeToJsonObject, iomap, op) = nothing

# ── Compound convenience constructor ─────────────────────────────────────────

function ObjectToJson(; include_selection=false, type_key="type", filter=nothing)
    TypeDispatchingProjection(
        Cell           => CellToJson(),
        Nothing        => NothingToJsonNull(),
        Bool           => BoolToJsonBool(),
        Number         => NumberToJsonNumber(),
        AbstractString => StringToJsonString(),
        Symbol         => SymbolToJsonString(),
        Char           => CharToJsonString(),
        Any            => ObjectNodeToJsonObject(include_selection=include_selection,
                                                 type_key=type_key, filter=filter),
    )
end

# ── json_object ──────────────────────────────────────────────────────────────
"""
    json_object(obj; include_selection=false, type_key="type", filter=nothing, indent=2) -> String

Convenience function that chains `ObjectToJson`, `JsonToSyntax`, `SyntaxToText`,
and `TextToString` to produce a JSON-text representation of any Julia object —
an easy, high-prior feed for LLM document understanding and tool/function calling.

# Arguments
- `obj`: any Julia value to reflect into JSON.
- `include_selection`: if false, `selection` fields are dropped (default: false).
- `type_key`: reserved object key carrying each struct's type name; pass
  `nothing` to omit (default: `"type"`).
- `filter`: optional predicate `value -> Bool`; when given, only struct fields and
  array/collection elements whose (Cell-unwrapped) value satisfies it are shown.
- `indent`: spaces per nesting level (default: 2).

# Examples
```julia
json_object(42)                 # "42"
json_object([1, 2, 3])          # JSON array
json_object(Point(3, 4))        # {"type":"Point", "x":3, "y":4}
```

# Notes
- Cells are unwrapped transparently; arrays project as JSON arrays, not structs.
- The `ref` field is always filtered out; `selection` unless `include_selection`.
- Read-only: this is a serialiser, not an editor view.
"""
function json_object(obj; include_selection=false, type_key="type", filter=nothing, indent::Int=2)
    seq = SequentialProjection(
        RecursiveProjection(ObjectToJson(include_selection=include_selection,
                                         type_key=type_key, filter=filter)),
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText(indent_size=indent)),
        RecursiveProjection(TextToString())
    )
    iomap = projection_print(seq, seq, obj, PrinterContext())
    out = iomap.output[]
    join((rstrip(l) for l in split(out, '\n')), '\n')
end

end # module
