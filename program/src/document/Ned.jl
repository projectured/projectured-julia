"""
    NedModule

The NED2 document domain provides reactive representations of OMNeT++ Network
Description (NED) data structures. Every NED node is a Document with reactive
Cell fields, following the same patterns as `XmlModule` and `JsonModule`.

The domain models the elements defined in the NED2 DTD
(`omnetpp/doc/etc/ned2.dtd`). Wrapper elements (`parameters`, `gates`, `types`,
`submodules`, `connections`) are flattened into `CellVector` fields on the parent
type; their own attributes (e.g. `is-implicit`, `allow-unconnected`) become
boolean fields on the parent.

The domain includes:
- **Top-level**: `NedFile`, `NedPackage`, `NedImport`
- **Module/channel types**: `NedSimpleModule`, `NedCompoundModule`,
  `NedModuleInterface`, `NedChannel`, `NedChannelInterface`
- **Parameters & properties**: `NedParam`, `NedProperty`, `NedPropertyDecl`,
  `NedPropertyKey`, `NedLiteral`
- **Gates**: `NedGate`
- **Submodules & connections**: `NedSubmodule`, `NedConnection`,
  `NedConnectionGroup`, `NedLoop`, `NedCondition`
- **Clauses**: `NedExtends`, `NedInterfaceName`
- **Editor**: `NedInsertion`
- **Base type**: `NedDocument` abstract type for all NED documents
"""
module NedModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
export NedDocument,
       NedInsertion, NedExtends, NedInterfaceName, NedLoop, NedCondition, NedLiteral,
       NedPropertyKey, NedProperty, NedPropertyDecl, NedParam, NedGate,
       NedSubmodule, NedConnection, NedConnectionGroup,
       NedSimpleModule, NedCompoundModule, NedModuleInterface, NedChannel, NedChannelInterface,
       NedPackage, NedImport, NedFile,
       INedInsertion, INedExtends, INedInterfaceName, INedLoop, INedCondition, INedLiteral,
       INedPropertyKey, INedProperty, INedPropertyDecl, INedParam, INedGate,
       INedSubmodule, INedConnection, INedConnectionGroup,
       INedSimpleModule, INedCompoundModule, INedModuleInterface, INedChannel, INedChannelInterface,
       INedPackage, INedImport, INedFile

"""
    NedDocument

Abstract base type for all NED document types. Every concrete NED type
subtypes `NedDocument` and must have a `selection::Reference` field as required
by the `Document` contract.
"""
abstract type NedDocument <: Document end

# ── Leaf types ────────────────────────────────────────────────────────────

"""
    NedInsertion

Represents an insertion cursor position in a NED document.

# Fields

- `value::Any` — placeholder value
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell)
"""
@document struct NedInsertion <: NedDocument
    value::Any
    selection::Reference
end

NedInsertion() = NedInsertion(Cell(nothing), Cell(nothing))

"""
    NedExtends

Represents an `extends` clause (e.g. `extends BaseModule`).

# Fields

- `name::String` — the name of the base type
- `selection::Reference`
"""
@document struct NedExtends <: NedDocument
    name::String
    selection::Reference
end

NedExtends(name::AbstractString) = NedExtends(Cell(String(name)), Cell(nothing))

"""
    NedInterfaceName

Represents a `like` interface-name clause (e.g. `like IFoo`).

# Fields

- `name::String` — the interface name
- `selection::Reference`
"""
@document struct NedInterfaceName <: NedDocument
    name::String
    selection::Reference
end

NedInterfaceName(name::AbstractString) = NedInterfaceName(Cell(String(name)), Cell(nothing))

"""
    NedLoop

Represents a `for` loop header in a connection section
(e.g. `for i=0..n-1`).

# Fields

- `param_name::String` — loop variable name
- `from_value::Any` — `Nothing` or expression `String`
- `to_value::Any` — `Nothing` or expression `String`
- `selection::Reference`
"""
@document struct NedLoop <: NedDocument
    param_name::String
    from_value::Any
    to_value::Any
    selection::Reference
end

NedLoop(param_name::AbstractString; from=nothing, to=nothing) =
    NedLoop(Cell(String(param_name)), Cell(from), Cell(to), Cell(nothing))

"""
    NedCondition

Represents an `if` condition (e.g. `if index > 0`).

# Fields

- `condition::Any` — `Nothing` or expression `String`
- `selection::Reference`
"""
@document struct NedCondition <: NedDocument
    condition::Any
    selection::Reference
end

NedCondition(cond::AbstractString) = NedCondition(Cell(String(cond)), Cell(nothing))
NedCondition() = NedCondition(Cell(nothing), Cell(nothing))

"""
    NedLiteral

Represents a typed literal value inside a property key.

# Fields

- `type::Symbol` — `:double`, `:quantity`, `:int`, `:bool`, `:string`, `:spec`
- `text::Any` — `Nothing` or `String` (source text)
- `value::Any` — `Nothing` or `String` (semantic value)
- `selection::Reference`
"""
@document struct NedLiteral <: NedDocument
    type::Symbol
    text::Any
    value::Any
    selection::Reference
end

NedLiteral(type::Symbol; text=nothing, value=nothing) =
    NedLiteral(Cell(type), Cell(text), Cell(value), Cell(nothing))

# ── Mid-level types ───────────────────────────────────────────────────────

"""
    NedPropertyKey

Represents a key inside a `@property(key=val,...)` annotation.

# Fields

- `name::Any` — `Nothing` or `String`
- `literals::CellVector` — of `NedLiteral`
- `selection::Reference`
"""
@document struct NedPropertyKey <: NedDocument
    name::Any
    literals::CellVector
    selection::Reference
end

NedPropertyKey(; name=nothing, literals=NedLiteral[]) =
    NedPropertyKey(Cell(name), CellVector(Cell[Cell(l) for l in literals]), Cell(nothing))

"""
    NedProperty

Represents a `@property` annotation (e.g. `@display("i=block/queue")`).

# Fields

- `name::String` — the property name
- `index::Any` — `Nothing` or `String` (array index)
- `is_implicit::Bool`
- `keys::CellVector` — of `NedPropertyKey`
- `selection::Reference`
"""
@document struct NedProperty <: NedDocument
    name::String
    index::Any
    is_implicit::Bool
    keys::CellVector
    selection::Reference
end

NedProperty(name::AbstractString; index=nothing, is_implicit=false, keys=NedPropertyKey[]) =
    NedProperty(Cell(String(name)), Cell(index), Cell(is_implicit),
                CellVector(Cell[Cell(k) for k in keys]), Cell(nothing))

"""
    NedPropertyDecl

Represents a property declaration.

# Fields

- `name::String`
- `is_array::Bool`
- `keys::CellVector` — of `NedPropertyKey`
- `properties::CellVector` — of `NedProperty`
- `selection::Reference`
"""
@document struct NedPropertyDecl <: NedDocument
    name::String
    is_array::Bool
    keys::CellVector
    properties::CellVector
    selection::Reference
end

NedPropertyDecl(name::AbstractString; is_array=false) =
    NedPropertyDecl(Cell(String(name)), Cell(is_array), CellVector(), CellVector(), Cell(nothing))

"""
    NedParam

Represents a parameter declaration or assignment.

# Fields

- `name::String`
- `type::Any` — `Nothing` or `Symbol` (`:double`, `:int`, `:string`, `:bool`, `:object`, `:xml`)
- `value::Any` — `Nothing` or expression `String`
- `is_volatile::Bool`
- `is_pattern::Bool`
- `is_default::Bool`
- `properties::CellVector` — of `NedProperty`
- `selection::Reference`
"""
@document struct NedParam <: NedDocument
    name::String
    type::Any
    value::Any
    is_volatile::Bool
    is_pattern::Bool
    is_default::Bool
    properties::CellVector
    selection::Reference
end

NedParam(name::AbstractString; type=nothing, value=nothing,
         is_volatile=false, is_pattern=false, is_default=false,
         properties=NedProperty[]) =
    NedParam(Cell(String(name)), Cell(type), Cell(value),
             Cell(is_volatile), Cell(is_pattern), Cell(is_default),
             CellVector(Cell[Cell(p) for p in properties]), Cell(nothing))

"""
    NedGate

Represents a gate declaration.

# Fields

- `name::String`
- `type::Any` — `Nothing` or `Symbol` (`:input`, `:output`, `:inout`)
- `is_vector::Bool`
- `vector_size::Any` — `Nothing` or expression `String`
- `properties::CellVector` — of `NedProperty`
- `selection::Reference`
"""
@document struct NedGate <: NedDocument
    name::String
    type::Any
    is_vector::Bool
    vector_size::Any
    properties::CellVector
    selection::Reference
end

NedGate(name::AbstractString; type=nothing, is_vector=false, vector_size=nothing,
        properties=NedProperty[]) =
    NedGate(Cell(String(name)), Cell(type), Cell(is_vector), Cell(vector_size),
            CellVector(Cell[Cell(p) for p in properties]), Cell(nothing))

# ── Compound types ────────────────────────────────────────────────────────

"""
    NedSubmodule

Represents a submodule instance inside a compound module.

# Fields

- `name::String`
- `type::Any` — `Nothing` or `String` (module type name)
- `like_type::Any` — `Nothing` or `String`
- `like_expr::Any` — `Nothing` or expression `String`
- `is_default::Bool`
- `vector_size::Any` — `Nothing` or expression `String`
- `condition::Any` — `Nothing` or `NedCondition`
- `params::CellVector` — of `NedParam` / `NedProperty`
- `params_implicit::Bool`
- `gates::CellVector` — of `NedGate`
- `selection::Reference`
"""
@document struct NedSubmodule <: NedDocument
    name::String
    type::Any
    like_type::Any
    like_expr::Any
    is_default::Bool
    vector_size::Any
    condition::Any
    params::CellVector
    params_implicit::Bool
    gates::CellVector
    selection::Reference
end

NedSubmodule(name::AbstractString; type=nothing, like_type=nothing, like_expr=nothing,
             is_default=false, vector_size=nothing, condition=nothing) =
    NedSubmodule(Cell(String(name)), Cell(type), Cell(like_type), Cell(like_expr),
                 Cell(is_default), Cell(vector_size), Cell(condition),
                 CellVector(), Cell(false), CellVector(), Cell(nothing))

"""
    NedConnection

Represents a connection arrow between gates.

# Fields

- `src_module::Any` — `Nothing` or `String`
- `src_module_index::Any` — `Nothing` or expression `String`
- `src_gate::String`
- `src_gate_plusplus::Bool`
- `src_gate_index::Any` — `Nothing` or expression `String`
- `src_gate_subg::Any` — `Nothing` or `Symbol` (`:i`, `:o`)
- `dest_module::Any`
- `dest_module_index::Any`
- `dest_gate::String`
- `dest_gate_plusplus::Bool`
- `dest_gate_index::Any`
- `dest_gate_subg::Any`
- `name::Any` — `Nothing` or channel name `String`
- `type::Any` — `Nothing` or channel type `String`
- `like_type::Any`
- `like_expr::Any`
- `is_default::Bool`
- `is_bidirectional::Bool`
- `is_forward_arrow::Bool`
- `params::CellVector` — of `NedParam` / `NedProperty`
- `loops::CellVector` — of `NedLoop`
- `conditions::CellVector` — of `NedCondition`
- `selection::Reference`
"""
@document struct NedConnection <: NedDocument
    src_module::Any
    src_module_index::Any
    src_gate::String
    src_gate_plusplus::Bool
    src_gate_index::Any
    src_gate_subg::Any
    dest_module::Any
    dest_module_index::Any
    dest_gate::String
    dest_gate_plusplus::Bool
    dest_gate_index::Any
    dest_gate_subg::Any
    name::Any
    type::Any
    like_type::Any
    like_expr::Any
    is_default::Bool
    is_bidirectional::Bool
    is_forward_arrow::Bool
    params::CellVector
    loops::CellVector
    conditions::CellVector
    selection::Reference
end

NedConnection(; src_module=nothing, src_module_index=nothing,
                src_gate="", src_gate_plusplus=false, src_gate_index=nothing, src_gate_subg=nothing,
                dest_module=nothing, dest_module_index=nothing,
                dest_gate="", dest_gate_plusplus=false, dest_gate_index=nothing, dest_gate_subg=nothing,
                name=nothing, type=nothing, like_type=nothing, like_expr=nothing,
                is_default=false, is_bidirectional=false, is_forward_arrow=true) =
    NedConnection(Cell(src_module), Cell(src_module_index),
                  Cell(String(src_gate)), Cell(src_gate_plusplus), Cell(src_gate_index), Cell(src_gate_subg),
                  Cell(dest_module), Cell(dest_module_index),
                  Cell(String(dest_gate)), Cell(dest_gate_plusplus), Cell(dest_gate_index), Cell(dest_gate_subg),
                  Cell(name), Cell(type), Cell(like_type), Cell(like_expr),
                  Cell(is_default), Cell(is_bidirectional), Cell(is_forward_arrow),
                  CellVector(), CellVector(), CellVector(), Cell(nothing))

"""
    NedConnectionGroup

Represents a group of connections sharing `for`/`if` clauses.

# Fields

- `loops::CellVector` — of `NedLoop`
- `conditions::CellVector` — of `NedCondition`
- `connections::CellVector` — of `NedConnection`
- `selection::Reference`
"""
@document struct NedConnectionGroup <: NedDocument
    loops::CellVector
    conditions::CellVector
    connections::CellVector
    selection::Reference
end

NedConnectionGroup() = NedConnectionGroup(CellVector(), CellVector(), CellVector(), Cell(nothing))

# ── Top-level definition types ────────────────────────────────────────────

"""
    NedSimpleModule

Represents a `simple` module definition.

# Fields

- `name::String`
- `extends::Any` — `Nothing` or `NedExtends`
- `interface_names::CellVector` — of `NedInterfaceName`
- `params::CellVector` — of `NedParam` / `NedProperty`
- `params_implicit::Bool` — from DTD `parameters.is-implicit`
- `gates::CellVector` — of `NedGate`
- `selection::Reference`
"""
@document struct NedSimpleModule <: NedDocument
    name::String
    extends::Any
    interface_names::CellVector
    params::CellVector
    params_implicit::Bool
    gates::CellVector
    selection::Reference
end

NedSimpleModule(name::AbstractString; extends=nothing) =
    NedSimpleModule(Cell(String(name)), Cell(extends),
                    CellVector(), CellVector(), Cell(false), CellVector(), Cell(nothing))

"""
    NedCompoundModule

Represents a `module` (compound module) definition.

# Fields

- `name::String`
- `extends::Any` — `Nothing` or `NedExtends`
- `interface_names::CellVector` — of `NedInterfaceName`
- `params::CellVector` — of `NedParam` / `NedProperty`
- `params_implicit::Bool`
- `gates::CellVector` — of `NedGate`
- `types::CellVector` — inner type definitions
- `submodules::CellVector` — of `NedSubmodule`
- `connections::CellVector` — of `NedConnection` / `NedConnectionGroup`
- `connections_allow_unconnected::Bool`
- `collapsed::Bool` — UI fold state
- `selection::Reference`
"""
@document struct NedCompoundModule <: NedDocument
    name::String
    extends::Any
    interface_names::CellVector
    params::CellVector
    params_implicit::Bool
    gates::CellVector
    types::CellVector
    submodules::CellVector
    connections::CellVector
    connections_allow_unconnected::Bool
    collapsed::Bool
    selection::Reference
end

NedCompoundModule(name::AbstractString; extends=nothing) =
    NedCompoundModule(Cell(String(name)), Cell(extends),
                      CellVector(), CellVector(), Cell(false), CellVector(),
                      CellVector(), CellVector(), CellVector(),
                      Cell(false), Cell(false), Cell(nothing))

"""
    NedModuleInterface

Represents a `moduleinterface` definition.

# Fields

- `name::String`
- `extends_list::CellVector` — of `NedExtends` (multiple allowed)
- `params::CellVector`
- `params_implicit::Bool`
- `gates::CellVector`
- `selection::Reference`
"""
@document struct NedModuleInterface <: NedDocument
    name::String
    extends_list::CellVector
    params::CellVector
    params_implicit::Bool
    gates::CellVector
    selection::Reference
end

NedModuleInterface(name::AbstractString) =
    NedModuleInterface(Cell(String(name)),
                       CellVector(), CellVector(), Cell(false), CellVector(), Cell(nothing))

"""
    NedChannel

Represents a `channel` definition.

# Fields

- `name::String`
- `extends::Any` — `Nothing` or `NedExtends`
- `interface_names::CellVector` — of `NedInterfaceName`
- `params::CellVector`
- `params_implicit::Bool`
- `selection::Reference`
"""
@document struct NedChannel <: NedDocument
    name::String
    extends::Any
    interface_names::CellVector
    params::CellVector
    params_implicit::Bool
    selection::Reference
end

NedChannel(name::AbstractString; extends=nothing) =
    NedChannel(Cell(String(name)), Cell(extends),
               CellVector(), CellVector(), Cell(false), Cell(nothing))

"""
    NedChannelInterface

Represents a `channelinterface` definition.

# Fields

- `name::String`
- `extends_list::CellVector` — of `NedExtends` (multiple allowed)
- `params::CellVector`
- `params_implicit::Bool`
- `selection::Reference`
"""
@document struct NedChannelInterface <: NedDocument
    name::String
    extends_list::CellVector
    params::CellVector
    params_implicit::Bool
    selection::Reference
end

NedChannelInterface(name::AbstractString) =
    NedChannelInterface(Cell(String(name)),
                        CellVector(), CellVector(), Cell(false), Cell(nothing))

# ── File-level types ──────────────────────────────────────────────────────

"""
    NedPackage

Represents a `package` declaration.

# Fields

- `name::String` — the package name
- `selection::Reference`
"""
@document struct NedPackage <: NedDocument
    name::String
    selection::Reference
end

NedPackage(name::AbstractString) = NedPackage(Cell(String(name)), Cell(nothing))

"""
    NedImport

Represents an `import` statement.

# Fields

- `import_spec::String` — the import specifier (e.g. `"inet.node.*"`)
- `selection::Reference`
"""
@document struct NedImport <: NedDocument
    import_spec::String
    selection::Reference
end

NedImport(spec::AbstractString) = NedImport(Cell(String(spec)), Cell(nothing))

"""
    NedFile

Represents a complete NED source file.

# Fields

- `filename::String`
- `version::String` — NED version, default `"2"`
- `children::CellVector` — top-level declarations (`NedPackage`, `NedImport`,
  `NedPropertyDecl`, `NedProperty`, `NedSimpleModule`, `NedCompoundModule`,
  `NedModuleInterface`, `NedChannel`, `NedChannelInterface`)
- `selection::Reference`
"""
@document struct NedFile <: NedDocument
    filename::String
    version::String
    children::CellVector
    selection::Reference
end

NedFile(filename::AbstractString; version="2") =
    NedFile(Cell(String(filename)), Cell(String(version)), CellVector(), Cell(nothing))

function NedFile(filename::AbstractString, children::Vector{<:NedDocument}; version="2")
    NedFile(Cell(String(filename)), Cell(String(version)),
            CellVector(Cell[Cell(c) for c in children]), Cell(nothing))
end

# ── Children access for compound types ────────────────────────────────────

# NedFile children
Base.length(f::NedFile)               = length(f.children)
Base.isempty(f::NedFile)              = isempty(f.children)
Base.getindex(f::NedFile, i::Integer) = f.children[i]
Base.firstindex(::NedFile)            = 1
Base.lastindex(f::NedFile)            = length(f)
Base.iterate(f::NedFile, state...)    = iterate(f.children, state...)
Base.eachindex(f::NedFile)            = eachindex(f.children)

function Base.push!(f::NedFile, children::NedDocument...)
    for c in children
        push!(f.children, Cell(c))
    end
    return f
end

function Base.deleteat!(f::NedFile, i)
    deleteat!(f.children, i)
    return f
end

function Base.insert!(f::NedFile, i::Integer, child::NedDocument)
    insert!(f.children, i, Cell(child))
    return f
end

# ── Display ───────────────────────────────────────────────────────────────

Base.show(io::IO, ::NedInsertion) = print(io, "⌶")

Base.show(io::IO, e::NedExtends) = print(io, "extends ", e.name)

Base.show(io::IO, n::NedInterfaceName) = print(io, "like ", n.name)

function Base.show(io::IO, l::NedLoop)
    print(io, "for ", l.param_name, "=")
    l.from_value !== nothing && print(io, l.from_value)
    print(io, "..")
    l.to_value !== nothing && print(io, l.to_value)
end

function Base.show(io::IO, c::NedCondition)
    print(io, "if ")
    c.condition !== nothing && print(io, c.condition)
end

function Base.show(io::IO, l::NedLiteral)
    if l.text !== nothing
        print(io, l.text)
    elseif l.value !== nothing
        print(io, l.value)
    else
        print(io, "<literal:", l.type, ">")
    end
end

Base.show(io::IO, k::NedPropertyKey) =
    print(io, join([string(l) for l in k.literals], ","))

function Base.show(io::IO, p::NedProperty)
    print(io, "@", p.name)
    p.index !== nothing && print(io, "[", p.index, "]")
    if !isempty(p.keys)
        print(io, "(", join([string(k) for k in p.keys], ";"), ")")
    end
end

function Base.show(io::IO, d::NedPropertyDecl)
    print(io, "property @", d.name)
    d.is_array && print(io, "[]")
end

function Base.show(io::IO, p::NedParam)
    p.type !== nothing && print(io, p.type, " ")
    p.is_volatile && print(io, "volatile ")
    print(io, p.name)
    if p.value !== nothing
        print(io, p.is_default ? " = default(" : " = ", p.value)
        p.is_default && print(io, ")")
    end
end

function Base.show(io::IO, g::NedGate)
    g.type !== nothing && print(io, g.type, " ")
    print(io, g.name)
    if g.is_vector
        print(io, "[")
        g.vector_size !== nothing && print(io, g.vector_size)
        print(io, "]")
    end
end

function Base.show(io::IO, s::NedSubmodule)
    print(io, s.name)
    if s.vector_size !== nothing
        print(io, "[", s.vector_size, "]")
    end
    print(io, ": ")
    if s.like_type !== nothing
        print(io, "<")
        s.like_expr !== nothing && print(io, s.like_expr)
        print(io, "> like ", s.like_type)
    elseif s.type !== nothing
        print(io, s.type)
    end
end

function Base.show(io::IO, c::NedConnection)
    if c.src_module !== nothing
        print(io, c.src_module)
        c.src_module_index !== nothing && print(io, "[", c.src_module_index, "]")
        print(io, ".")
    end
    print(io, c.src_gate)
    c.src_gate_plusplus && print(io, "++")
    c.src_gate_index !== nothing && print(io, "[", c.src_gate_index, "]")
    print(io, c.is_bidirectional ? " <--> " : (c.is_forward_arrow ? " --> " : " <-- "))
    if c.dest_module !== nothing
        print(io, c.dest_module)
        c.dest_module_index !== nothing && print(io, "[", c.dest_module_index, "]")
        print(io, ".")
    end
    print(io, c.dest_gate)
    c.dest_gate_plusplus && print(io, "++")
    c.dest_gate_index !== nothing && print(io, "[", c.dest_gate_index, "]")
end

function Base.show(io::IO, g::NedConnectionGroup)
    for l in g.loops
        show(io, l)
        print(io, " ")
    end
    for c in g.conditions
        show(io, c)
        print(io, " ")
    end
    print(io, "{ ")
    for (i, conn) in enumerate(g.connections)
        i > 1 && print(io, "; ")
        show(io, conn)
    end
    print(io, " }")
end

function Base.show(io::IO, m::NedSimpleModule)
    print(io, "simple ", m.name)
    m.extends !== nothing && print(io, " ", string(m.extends))
    print(io, " { ... }")
end

function Base.show(io::IO, m::NedCompoundModule)
    print(io, "module ", m.name)
    m.extends !== nothing && print(io, " ", string(m.extends))
    print(io, " { ... }")
end

function Base.show(io::IO, m::NedModuleInterface)
    print(io, "moduleinterface ", m.name)
    print(io, " { ... }")
end

function Base.show(io::IO, c::NedChannel)
    print(io, "channel ", c.name)
    c.extends !== nothing && print(io, " ", string(c.extends))
    print(io, " { ... }")
end

function Base.show(io::IO, c::NedChannelInterface)
    print(io, "channelinterface ", c.name)
    print(io, " { ... }")
end

Base.show(io::IO, p::NedPackage) = print(io, "package ", p.name)

Base.show(io::IO, i::NedImport) = print(io, "import ", i.import_spec)

function Base.show(io::IO, f::NedFile)
    print(io, "NedFile(\"", f.filename, "\", ", length(f.children), " declarations)")
end

# Text-replace edits for the NED domain are handled generically by
# `splice_value!` (see OperationApiModule): every type-in target field
# (`name`, `import_spec`, `value`, `filename`, `param_name`, …) is a plain
# string, so the string representation covers them. No per-type method needed.

end # module
