"""
    IniModule

The OMNeT++ INI file document domain provides reactive representations of INI
configuration files. Every INI node is a Document with all mutable fields
wrapped in reactive Cells, enabling automatic dependency tracking and
incremental updates.

The domain includes:
- **Entry types**: `IniConfigOption` (dotless keys), `IniParamAssignment` (dotted keys)
- **Structure types**: `IniFile` (top-level), `IniSection` (config section)
- **Leaf types**: `IniComment`, `IniInclude`, `IniInsertion`

Config options control the simulation engine (e.g. `network`, `sim-time-limit`),
while parameter assignments set model parameters via dotted wildcard paths
(e.g. `**.host[*].iaTime`). Per-object config options (dotted keys with a hyphen
in the last component) are also stored as `IniParamAssignment`.

Selection semantics:
- IniFile: `.children[i]` — cursor within child i
- IniSection: `.entries[i]` — cursor within entry i
- IniConfigOption/IniParamAssignment: `.key[k]` or `.value[k]` — character offset
- IniComment: `.text[k]` — character offset
- IniInclude: `.path[k]` — character offset
"""
module IniModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
import ..OperationApiModule: _apply_string_replace!
export IniDocument, IniInsertion, IniComment, IniInclude, IniConfigOption, IniParamAssignment, IniSection, IniFile,
       IIniInsertion, IIniComment, IIniInclude, IIniConfigOption, IIniParamAssignment, IIniSection, IIniFile

# ── IniDocument (abstract base) ──────────────────────────────────────────────

"""
    IniDocument

Abstract base type for all INI document types. Every concrete INI type
subtypes `IniDocument` and must have a `selection::Reference` field as required
by the `Document` contract.
"""
abstract type IniDocument <: Document end

# ── IniInsertion ─────────────────────────────────────────────────────────────

@document struct IniInsertion <: IniDocument
    value::Any
    selection::Reference
end
IniInsertion() = IniInsertion(Cell(nothing), Cell(nothing))

# ── IniComment ───────────────────────────────────────────────────────────────

"""
    IniComment(text)

A standalone comment line. `text` holds the content after `#` (the leading
`#` is excluded but any space immediately after it is preserved).

# Fields

- `text::Cell` — holds comment content as `String`
- `selection::Reference` — holds the ReferencePath for cursor position
"""
@document struct IniComment <: IniDocument
    text::String
    selection::Reference
end

IniComment(text::AbstractString) = IniComment(Cell(String(text)), Cell(nothing))

# ── IniInclude ───────────────────────────────────────────────────────────────

"""
    IniInclude(path)

An `include` directive. `path` holds the included file path.

# Fields

- `path::Cell` — holds the file path as `String`
- `selection::Reference` — holds the ReferencePath for cursor position
"""
@document struct IniInclude <: IniDocument
    path::String
    selection::Reference
end

IniInclude(path::AbstractString) = IniInclude(Cell(String(path)), Cell(nothing))

# ── IniConfigOption ──────────────────────────────────────────────────────────

"""
    IniConfigOption(key, value; comment=nothing)

A configuration option entry — a key-value pair where the key contains no dots.
These control the simulation engine: `network`, `sim-time-limit`, `extends`,
`description`, `repeat`, etc.

# Fields

- `key::Cell` — option name, no dots (e.g. `"network"`, `"sim-time-limit"`)
- `value::Cell` — value string (e.g. `"Aloha"`, `"100h"`)
- `comment::Cell` — `Nothing` or trailing inline comment `String`
- `selection::Reference` — holds the ReferencePath for cursor position
"""
@document struct IniConfigOption <: IniDocument
    key::String
    value::String
    comment::Any
    selection::Reference
end

IniConfigOption(key::AbstractString, value::AbstractString; comment=nothing) =
    IniConfigOption(Cell(String(key)), Cell(String(value)), Cell(comment), Cell(nothing))

# ── IniParamAssignment ───────────────────────────────────────────────────────

"""
    IniParamAssignment(key, value; comment=nothing)

A parameter assignment entry — a key-value pair where the key contains dots.
This covers both model parameter assignments (`Aloha.numHosts`, `**.host[*].iaTime`)
and per-object config options (`**.vector-recording`, `**.rng-0`, `**.typename`).

# Fields

- `key::Cell` — dotted key with optional wildcards (e.g. `"Aloha.numHosts"`, `"**.host[*].iaTime"`)
- `value::Cell` — value string (e.g. `"20"`, `"exponential(2s)"`)
- `comment::Cell` — `Nothing` or trailing inline comment `String`
- `selection::Reference` — holds the ReferencePath for cursor position
"""
@document struct IniParamAssignment <: IniDocument
    key::String
    value::String
    comment::Any
    selection::Reference
end

IniParamAssignment(key::AbstractString, value::AbstractString; comment=nothing) =
    IniParamAssignment(Cell(String(key)), Cell(String(value)), Cell(comment), Cell(nothing))

# ── IniSection ───────────────────────────────────────────────────────────────

"""
    IniSection(name; is_general=false, collapsed=false)
    IniSection(name, entries; is_general, collapsed)

A configuration section: `[General]` or `[Config Name]` / `[Name]`.

# Fields

- `name::Cell` — `"General"` or the config name (e.g. `"PureAloha1"`)
- `is_general::Cell` — `true` for `[General]`
- `entries::CellVector` — holds `IniConfigOption`, `IniParamAssignment`, `IniComment`, `IniInclude`
- `collapsed::Cell` — UI fold state
- `selection::Reference` — holds the ReferencePath for cursor position
"""
@document struct IniSection <: IniDocument
    name::String
    is_general::Bool
    entries::CellVector
    collapsed::Bool
    selection::Reference
end

IniSection(name::AbstractString; is_general::Bool=(name == "General"), collapsed::Bool=false) =
    IniSection(Cell(String(name)), Cell(is_general), CellVector(), Cell(collapsed), Cell(nothing))

function IniSection(name::AbstractString, entries::Vector;
                    is_general::Bool=(name == "General"), collapsed::Bool=false)
    IniSection(Cell(String(name)), Cell(is_general),
               CellVector(Cell[Cell(e) for e in entries]),
               Cell(collapsed), Cell(nothing))
end

# ── IniSection: collection access ────────────────────────────────────────────

Base.length(s::IniSection)               = length(s.entries)
Base.isempty(s::IniSection)              = isempty(s.entries)
Base.getindex(s::IniSection, i::Integer) = s.entries[i]
Base.firstindex(::IniSection)            = 1
Base.lastindex(s::IniSection)            = length(s)
Base.iterate(s::IniSection, state...)    = iterate(s.entries, state...)
Base.eachindex(s::IniSection)            = eachindex(s.entries)

function Base.push!(s::IniSection, entries::IniDocument...)
    for e in entries
        push!(s.entries, Cell(e))
    end
    return s
end

function Base.setindex!(s::IniSection, entry::IniDocument, i::Integer)
    s.entries[i] = entry
    return entry
end

function Base.deleteat!(s::IniSection, i)
    deleteat!(s.entries, i)
    return s
end

function Base.insert!(s::IniSection, i::Integer, entry::IniDocument)
    insert!(s.entries, i, Cell(entry))
    return s
end

function Base.pop!(s::IniSection)
    pop!(s.entries)
end

# ── IniFile ──────────────────────────────────────────────────────────────────

"""
    IniFile()
    IniFile(children::Vector)

The top-level INI file container. `children` holds `IniSection`, `IniComment`,
and `IniInclude` nodes.

# Fields

- `children::CellVector` — holds `IniSection`, `IniComment`, `IniInclude`
- `selection::Reference` — holds the ReferencePath for cursor position
"""
@document struct IniFile <: IniDocument
    children::CellVector
    selection::Reference
end

IniFile() = IniFile(CellVector(), Cell(nothing))

function IniFile(children::Vector)
    IniFile(CellVector(Cell[Cell(c) for c in children]), Cell(nothing))
end

# ── IniFile: collection access ───────────────────────────────────────────────

Base.length(f::IniFile)               = length(f.children)
Base.isempty(f::IniFile)              = isempty(f.children)
Base.getindex(f::IniFile, i::Integer) = f.children[i]
Base.firstindex(::IniFile)            = 1
Base.lastindex(f::IniFile)            = length(f)
Base.iterate(f::IniFile, state...)    = iterate(f.children, state...)
Base.eachindex(f::IniFile)            = eachindex(f.children)

function Base.push!(f::IniFile, children::IniDocument...)
    for c in children
        push!(f.children, Cell(c))
    end
    return f
end

function Base.setindex!(f::IniFile, child::IniDocument, i::Integer)
    f.children[i] = child
    return child
end

function Base.deleteat!(f::IniFile, i)
    deleteat!(f.children, i)
    return f
end

function Base.insert!(f::IniFile, i::Integer, child::IniDocument)
    insert!(f.children, i, Cell(child))
    return f
end

function Base.pop!(f::IniFile)
    pop!(f.children)
end

# ── String-replace operations ────────────────────────────────────────────────

function _ini_slice_replace(old::AbstractString, s::Int, e::Int, replacement::AbstractString)
    n = length(old)
    left  = s <= 0 ? "" : first(old, s)
    right = e >= n ? "" : last(old, n - e)
    String(left) * replacement * String(right)
end

function _apply_string_replace!(target::IniConfigOption, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    if field_name == "key"
        target.key = _ini_slice_replace(target.key::AbstractString, s, e, replacement)
    elseif field_name == "value"
        target.value = _ini_slice_replace(target.value::AbstractString, s, e, replacement)
    else
        error("IniConfigOption supports only fields 'key', 'value', got: $field_name")
    end
end

function _apply_string_replace!(target::IniParamAssignment, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    if field_name == "key"
        target.key = _ini_slice_replace(target.key::AbstractString, s, e, replacement)
    elseif field_name == "value"
        target.value = _ini_slice_replace(target.value::AbstractString, s, e, replacement)
    else
        error("IniParamAssignment supports only fields 'key', 'value', got: $field_name")
    end
end

function _apply_string_replace!(target::IniComment, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    field_name == "text" || error("IniComment supports only field 'text', got: $field_name")
    target.text = _ini_slice_replace(target.text::AbstractString, s, e, replacement)
end

function _apply_string_replace!(target::IniInclude, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    field_name == "path" || error("IniInclude supports only field 'path', got: $field_name")
    target.path = _ini_slice_replace(target.path::AbstractString, s, e, replacement)
end

function _apply_string_replace!(target::IniSection, field_name::AbstractString, s::Int, e::Int, replacement::AbstractString)
    field_name == "name" || error("IniSection supports only field 'name', got: $field_name")
    target.name = _ini_slice_replace(target.name::AbstractString, s, e, replacement)
end

# ── Display ──────────────────────────────────────────────────────────────────

Base.show(io::IO, ::IniInsertion) = print(io, "IniInsertion()")

function Base.show(io::IO, c::IniComment)
    print(io, "IniComment(", repr(c.text), ")")
end

function Base.show(io::IO, inc::IniInclude)
    print(io, "IniInclude(", repr(inc.path), ")")
end

function Base.show(io::IO, opt::IniConfigOption)
    print(io, "IniConfigOption(", repr(opt.key), ", ", repr(opt.value))
    opt.comment !== nothing && print(io, ", comment=", repr(opt.comment))
    print(io, ")")
end

function Base.show(io::IO, pa::IniParamAssignment)
    print(io, "IniParamAssignment(", repr(pa.key), ", ", repr(pa.value))
    pa.comment !== nothing && print(io, ", comment=", repr(pa.comment))
    print(io, ")")
end

function Base.show(io::IO, s::IniSection)
    print(io, "IniSection(", repr(s.name))
    s.is_general && print(io, ", General")
    print(io, ", entries=", length(s.entries), ")")
end

function Base.show(io::IO, f::IniFile)
    print(io, "IniFile(children=", length(f.children), ")")
end

end # module
