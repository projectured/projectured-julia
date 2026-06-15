"""
    NedToSyntaxModule

NED → SyntaxDocument projection. Maps NED document types to syntax tree
nodes for rendering as syntax-highlighted text.

Layout:
- `NedFile`            → SyntaxNode (children = package/imports/decls)
- `NedCompoundModule`  → SyntaxNode (open = "network Name {", children = sections)
- `NedSimpleModule`    → SyntaxNode (open = "simple Name {", children = params/gates)
- `NedChannel`         → SyntaxNode (open = "channel Name {", children = params)
- `NedParam`           → SyntaxLeaf (type name = value;)
- `NedGate`            → SyntaxLeaf (input name[];)
- `NedSubmodule`       → SyntaxNode (name: Type { ... })
- `NedConnection`      → SyntaxLeaf (src --> dest;)
- `NedConnectionGroup` → SyntaxNode (for ... { connections })
- `NedProperty`        → SyntaxLeaf (@name(...))
- `NedPackage`         → SyntaxLeaf (package name;)
- `NedImport`          → SyntaxLeaf (import spec;)
- `NedInsertion`       → SyntaxLeaf (placeholder)

Readers are deferred to a future step.
"""
module NedToSyntaxModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..NedModule: NedDocument, NedInsertion, NedExtends, NedInterfaceName, NedLoop, NedCondition,
                    NedLiteral, NedPropertyKey, NedProperty, NedPropertyDecl, NedParam, NedGate,
                    NedSubmodule, NedConnection, NedConnectionGroup,
                    NedSimpleModule, NedCompoundModule, NedModuleInterface, NedChannel, NedChannelInterface,
                    NedPackage, NedImport, NedFile
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_black, color_default,
                      color_solarized_blue, color_solarized_green, color_solarized_magenta,
                      color_solarized_cyan, color_solarized_yellow, color_solarized_gray,
                      color_solarized_red, color_solarized_orange, color_solarized_violet
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference, RangeReference, FieldReference,
                         ProjectionReference, ReferencePath, EmptyReferencePath, append_reference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..PrinterContextModule: child_context
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: StringReplaceRangeOperation
import ..SyntaxToTextModule: SyntaxNodeToText, _syntax_to_flat
export NedInsertionToSyntaxLeaf, NedPackageToSyntaxLeaf, NedImportToSyntaxLeaf,
       NedPropertyToSyntaxLeaf, NedParamToSyntaxLeaf, NedGateToSyntaxLeaf,
       NedSubmoduleToSyntaxNode, NedConnectionToSyntaxLeaf, NedConnectionGroupToSyntaxNode,
       NedSimpleModuleToSyntaxNode, NedCompoundModuleToSyntaxNode,
       NedModuleInterfaceToSyntaxNode, NedChannelToSyntaxNode, NedChannelInterfaceToSyntaxNode,
       NedFileToSyntaxNode, NedToSyntax

# ── Style defaults ────────────────────────────────────────────────────────

const _kw_font  = font_ubuntu_monospace_bold_24
const _kw_color = color_solarized_magenta
const _id_font  = font_ubuntu_monospace_regular_24
const _id_color = color_solarized_blue
const _type_color = color_solarized_cyan
const _str_color  = color_solarized_green
const _val_color  = color_solarized_cyan
const _op_color   = color_solarized_gray
const _prop_color = color_solarized_yellow
const _comment_color = color_solarized_gray

# ── Helpers ───────────────────────────────────────────────────────────────

_empty_ts() = TextString("", _id_font, color_default)
_ts(text, font=_id_font, color=color_default) = TextString(text, font, color)
_kw(text) = TextString(text, _kw_font, _kw_color)
_op(text) = TextString(text, _id_font, _op_color)

# ── NedInsertionToSyntaxLeaf ─────────────────────────────────────────────

struct NedInsertionToSyntaxLeaf <: Projection end

function projection_print(p::NedInsertionToSyntaxLeaf, recursion, ins::NedInsertion, ctx)
    output_selection = Cell(() -> map_reference_forward(p, nothing, ins.selection))
    SimpleIoMap(p, ins, SyntaxLeaf(
        _empty_ts(), _empty_ts(),
        TextString("insert NED entry here", _id_font, _comment_color),
        output_selection))
end

# ── NedPackageToSyntaxLeaf ───────────────────────────────────────────────

struct NedPackageToSyntaxLeaf <: Projection end

function map_reference_forward(::NedPackageToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        name.rest... => @reference value.^(rest)
    end
end

function map_reference_backward(::NedPackageToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value.rest... => @reference name.^(rest)
    end
end

function projection_read(p::NedPackageToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

function projection_read(p::NedPackageToSyntaxLeaf, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::NedPackageToSyntaxLeaf, recursion, pkg::NedPackage, ctx)
    sel = Cell(() -> begin
        @reference_case pkg.selection begin
            name.rest... => @reference value.^(rest)
        end
    end)
    SimpleIoMap(p, pkg, SyntaxLeaf(
        _kw("package "), _op(";"),
        TextString(() -> pkg.name, _id_font, _id_color),
        sel))
end

# ── NedImportToSyntaxLeaf ───────────────────────────────────────────────

struct NedImportToSyntaxLeaf <: Projection end

function map_reference_forward(::NedImportToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        import_spec.rest... => @reference value.^(rest)
    end
end

function map_reference_backward(::NedImportToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value.rest... => @reference import_spec.^(rest)
    end
end

function projection_read(p::NedImportToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

function projection_read(p::NedImportToSyntaxLeaf, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::NedImportToSyntaxLeaf, recursion, imp::NedImport, ctx)
    sel = Cell(() -> begin
        @reference_case imp.selection begin
            import_spec.rest... => @reference value.^(rest)
        end
    end)
    SimpleIoMap(p, imp, SyntaxLeaf(
        _kw("import "), _op(";"),
        TextString(() -> imp.import_spec, _id_font, _id_color),
        sel))
end

# ── NedPropertyToSyntaxLeaf ─────────────────────────────────────────────

struct NedPropertyToSyntaxLeaf <: Projection end

function _format_property(prop::NedProperty)
    buf = IOBuffer()
    write(buf, "@", prop.name)
    if prop.index !== nothing
        write(buf, "[", string(prop.index), "]")
    end
    if !isempty(prop.keys)
        write(buf, "(")
        for (i, key) in enumerate(prop.keys)
            i > 1 && write(buf, ";")
            if key.name !== nothing
                write(buf, key.name, "=")
            end
            for (j, lit) in enumerate(key.literals)
                j > 1 && write(buf, ",")
                if lit.text !== nothing
                    write(buf, string(lit.text))
                elseif lit.value !== nothing
                    write(buf, string(lit.value))
                end
            end
        end
        write(buf, ")")
    end
    String(take!(buf))
end

function projection_print(p::NedPropertyToSyntaxLeaf, recursion, prop::NedProperty, ctx)
    sel = Cell(() -> begin
        @reference_case prop.selection begin
            name.rest... => @reference value.^(rest)
        end
    end)
    SimpleIoMap(p, prop, SyntaxLeaf(
        _empty_ts(), _op(";"),
        TextString(() -> _format_property(prop), _id_font, _prop_color),
        sel))
end

# ── NedParamToSyntaxLeaf ─────────────────────────────────────────────────

struct NedParamToSyntaxLeaf <: Projection end

function _format_param(param::NedParam)
    buf = IOBuffer()
    param.is_volatile && write(buf, "volatile ")
    param.type !== nothing && write(buf, string(param.type), " ")
    write(buf, param.name)
    for prop in param.properties
        write(buf, " ", _format_property(prop))
    end
    if param.value !== nothing
        if param.is_default
            write(buf, " = default(", string(param.value), ")")
        else
            write(buf, " = ", string(param.value))
        end
    end
    String(take!(buf))
end

function map_reference_forward(::NedParamToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        name.rest...  => @reference value.^(rest)
        value.rest... => @reference value.^(rest)
    end
end

function map_reference_backward(::NedParamToSyntaxLeaf, iomap::SimpleIoMap, reference)
    @reference_case reference begin
        value.rest... => @reference name.^(rest)
    end
end

function projection_read(p::NedParamToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing ? ReplaceSelectionOperation(result) : nothing
end

function projection_read(p::NedParamToSyntaxLeaf, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::NedParamToSyntaxLeaf, recursion, param::NedParam, ctx)
    sel = Cell(() -> begin
        @reference_case param.selection begin
            name.rest...  => @reference value.^(rest)
            value.rest... => @reference value.^(rest)
        end
    end)
    SimpleIoMap(p, param, SyntaxLeaf(
        _empty_ts(), _op(";"),
        TextString(() -> _format_param(param), _id_font, _val_color),
        sel))
end

# ── NedGateToSyntaxLeaf ──────────────────────────────────────────────────

struct NedGateToSyntaxLeaf <: Projection end

function _format_gate(gate::NedGate)
    buf = IOBuffer()
    gate.type !== nothing && write(buf, string(gate.type), " ")
    write(buf, gate.name)
    if gate.is_vector
        write(buf, "[")
        gate.vector_size !== nothing && write(buf, string(gate.vector_size))
        write(buf, "]")
    end
    String(take!(buf))
end

function projection_print(p::NedGateToSyntaxLeaf, recursion, gate::NedGate, ctx)
    sel = Cell(() -> begin
        @reference_case gate.selection begin
            name.rest... => @reference value.^(rest)
        end
    end)
    SimpleIoMap(p, gate, SyntaxLeaf(
        _empty_ts(), _op(";"),
        TextString(() -> _format_gate(gate), _id_font, _id_color),
        sel))
end

# ── NedConnectionToSyntaxLeaf ────────────────────────────────────────────

struct NedConnectionToSyntaxLeaf <: Projection end

function _format_gate_spec(mod, mod_idx, gate, subg, gate_idx, gate_pp)
    buf = IOBuffer()
    if mod !== nothing
        write(buf, string(mod))
        mod_idx !== nothing && write(buf, "[", string(mod_idx), "]")
        write(buf, ".")
    end
    write(buf, string(gate))
    subg !== nothing && write(buf, "\$", string(subg))
    gate_idx !== nothing && write(buf, "[", string(gate_idx), "]")
    gate_pp && write(buf, "++")
    String(take!(buf))
end

function _format_connection(c::NedConnection)
    buf = IOBuffer()
    write(buf, _format_gate_spec(c.src_module, c.src_module_index,
                                  c.src_gate, c.src_gate_subg,
                                  c.src_gate_index, c.src_gate_plusplus))
    arrow = c.is_bidirectional ? " <--> " : (c.is_forward_arrow ? " --> " : " <-- ")
    if c.type !== nothing
        write(buf, arrow, string(c.type), arrow)
    elseif !isempty(c.params)
        write(buf, arrow, "{ ")
        for (i, p) in enumerate(c.params)
            i > 1 && write(buf, " ")
            if p isa NedParam
                write(buf, _format_param(p), ";")
            elseif p isa NedProperty
                write(buf, _format_property(p), ";")
            end
        end
        write(buf, " }", arrow)
    else
        write(buf, arrow)
    end
    write(buf, _format_gate_spec(c.dest_module, c.dest_module_index,
                                  c.dest_gate, c.dest_gate_subg,
                                  c.dest_gate_index, c.dest_gate_plusplus))
    for cond in c.conditions
        cond.condition !== nothing && write(buf, " if ", string(cond.condition))
    end
    String(take!(buf))
end

function projection_print(p::NedConnectionToSyntaxLeaf, recursion, conn::NedConnection, ctx)
    SimpleIoMap(p, conn, SyntaxLeaf(
        _empty_ts(), _op(";"),
        TextString(() -> _format_connection(conn), _id_font, _val_color)))
end

# ── NedConnectionGroupToSyntaxNode ───────────────────────────────────────

struct NedConnectionGroupToSyntaxNode <: Projection end

function _format_loop_header(group::NedConnectionGroup)
    buf = IOBuffer()
    for (i, loop) in enumerate(group.loops)
        i > 1 && write(buf, ", ")
        write(buf, "for ", loop.param_name, "=")
        loop.from_value !== nothing && write(buf, string(loop.from_value))
        write(buf, "..")
        loop.to_value !== nothing && write(buf, string(loop.to_value))
    end
    for cond in group.conditions
        !isempty(buf.data) && write(buf, ", ")
        write(buf, "if ")
        cond.condition !== nothing && write(buf, string(cond.condition))
    end
    String(take!(buf))
end

function map_reference_forward(p::NedConnectionGroupToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        connections{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::NedConnectionGroupToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        children{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            translated = map_reference_backward(child.projection, child, rest)
            translated === nothing && return nothing
            @reference connections[child_i].^(translated)
        end
    end
end

function projection_read(p::NedConnectionGroupToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

function projection_read(p::NedConnectionGroupToSyntaxNode, iomap::ChildrenIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::NedConnectionGroupToSyntaxNode, recursion, group::NedConnectionGroup, ctx)
    reference = ctx.reference
    child_iomaps = Cell(() -> [projection_print(recursion, recursion, conn,
                                   child_context(ctx, @reference ^(reference).connections[i]))
                               for (i, conn) in enumerate(group.connections)])

    sel = Cell(() -> begin
        path = group.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
        @reference_case path begin
            connections{s_idx:_}.rest... => begin
                child_i = s_idx + 1
                iomaps = child_iomaps[]
                child_i > length(iomaps) && return nothing
                child_sel = iomaps[child_i].output.selection
                child_sel === nothing && return nothing
                @reference children[child_i].^(child_sel)
            end
        end
    end)

    children_cv = CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]])

    output = SyntaxNode(
        TextString(() -> _format_loop_header(group), _kw_font, _kw_color),
        _op("}"),
        _empty_ts(),
        children_cv, 1, Cell(false), sel)
    ChildrenIoMap(p, group, output, child_iomaps)
end

# ── Section heading helpers ───────────────────────────────────────────────

function _module_heading(keyword::AbstractString, m, has_extends::Bool=true)
    buf = IOBuffer()
    write(buf, keyword, " ", m.name)
    if has_extends && m.extends !== nothing
        write(buf, " extends ", m.extends.name)
    end
    if hasproperty(m, :interface_names) && !isempty(m.interface_names)
        write(buf, " like ")
        for (i, iface) in enumerate(m.interface_names)
            i > 1 && write(buf, ", ")
            write(buf, iface.name)
        end
    end
    write(buf, " {")
    String(take!(buf))
end

function _interface_heading(keyword::AbstractString, m)
    buf = IOBuffer()
    write(buf, keyword, " ", m.name)
    if !isempty(m.extends_list)
        write(buf, " extends ")
        for (i, e) in enumerate(m.extends_list)
            i > 1 && write(buf, ", ")
            write(buf, e.name)
        end
    end
    write(buf, " {")
    String(take!(buf))
end

# ── Generic body projection helper ───────────────────────────────────────

# Projects a list of CellVectors into a flat child list with section headers.
# Each section is (label, field_name, cv) where cv is the CellVector.
function _project_body_children(recursion, ctx, reference, sections)
    all_iomaps = Pair{Symbol,Any}[]  # (:field, iomap)
    syntax_children = SyntaxDocument[]

    for (label, field_name, cv) in sections
        isempty(cv) && continue
        # section header as a plain leaf
        push!(syntax_children, SyntaxLeaf(_kw(label), _empty_ts(), _empty_ts()))
        push!(all_iomaps, :_header => nothing)

        for (i, child) in enumerate(cv)
            iomap = projection_print(recursion, recursion, child,
                        child_context(ctx, @reference ^(reference).^(field_name)[i]))
            push!(syntax_children, iomap.output)
            push!(all_iomaps, field_name => (i, iomap))
        end
    end

    return syntax_children, all_iomaps
end

# ── NedSimpleModuleToSyntaxNode ──────────────────────────────────────────

struct NedSimpleModuleToSyntaxNode <: Projection end

function projection_print(p::NedSimpleModuleToSyntaxNode, recursion, m::NedSimpleModule, ctx)
    reference = ctx.reference

    sections = [
        ("parameters:", :params, m.params),
        ("gates:", :gates, m.gates),
    ]

    child_iomaps_cell = Cell(() -> begin
        result = Pair{Symbol,Any}[]
        sc = SyntaxDocument[]
        for (label, field_name, cv) in sections
            isempty(cv) && continue
            push!(sc, SyntaxLeaf(_kw(label), _empty_ts(), _empty_ts()))
            push!(result, :_header => nothing)
            for (i, child) in enumerate(cv)
                im = projection_print(recursion, recursion, child,
                         child_context(ctx, @reference ^(reference).^(field_name)[i]))
                push!(sc, im.output)
                push!(result, field_name => (i, im))
            end
        end
        (sc, result)
    end)

    sel = Cell(() -> begin
        path = m.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
        nothing
    end)

    children_cv = CellVector(() -> child_iomaps_cell[][1])

    output = SyntaxNode(
        TextString(() -> _module_heading("simple", m), _kw_font, _kw_color),
        _op("}"),
        _empty_ts(),
        children_cv, 1, Cell(false), sel)
    SimpleIoMap(p, m, output)
end

# ── NedCompoundModuleToSyntaxNode ────────────────────────────────────────

struct NedCompoundModuleToSyntaxNode <: Projection end

function projection_print(p::NedCompoundModuleToSyntaxNode, recursion, m::NedCompoundModule, ctx)
    reference = ctx.reference

    sections = [
        ("parameters:", :params, m.params),
        ("gates:", :gates, m.gates),
        ("types:", :types, m.types),
        ("submodules:", :submodules, m.submodules),
        ("connections:", :connections, m.connections),
    ]

    child_iomaps_cell = Cell(() -> begin
        result = Pair{Symbol,Any}[]
        sc = SyntaxDocument[]
        for (label, field_name, cv) in sections
            isempty(cv) && continue
            push!(sc, SyntaxLeaf(_kw(label), _empty_ts(), _empty_ts()))
            push!(result, :_header => nothing)
            for (i, child) in enumerate(cv)
                im = projection_print(recursion, recursion, child,
                         child_context(ctx, @reference ^(reference).^(field_name)[i]))
                push!(sc, im.output)
                push!(result, field_name => (i, im))
            end
        end
        (sc, result)
    end)

    sel = Cell(() -> begin
        path = m.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
        nothing
    end)

    children_cv = CellVector(() -> child_iomaps_cell[][1])

    output = SyntaxNode(
        TextString(() -> _module_heading("network", m), _kw_font, _kw_color),
        _op("}"),
        _empty_ts(),
        children_cv, 1, m.collapsed, sel)
    SimpleIoMap(p, m, output)
end

# ── NedModuleInterfaceToSyntaxNode ───────────────────────────────────────

struct NedModuleInterfaceToSyntaxNode <: Projection end

function projection_print(p::NedModuleInterfaceToSyntaxNode, recursion, m::NedModuleInterface, ctx)
    reference = ctx.reference

    child_iomaps_cell = Cell(() -> begin
        result = Pair{Symbol,Any}[]
        sc = SyntaxDocument[]
        for (label, field_name, cv) in [("parameters:", :params, m.params), ("gates:", :gates, m.gates)]
            isempty(cv) && continue
            push!(sc, SyntaxLeaf(_kw(label), _empty_ts(), _empty_ts()))
            push!(result, :_header => nothing)
            for (i, child) in enumerate(cv)
                im = projection_print(recursion, recursion, child,
                         child_context(ctx, @reference ^(reference).^(field_name)[i]))
                push!(sc, im.output)
                push!(result, field_name => (i, im))
            end
        end
        (sc, result)
    end)

    sel = Cell(() -> begin
        path = m.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
        nothing
    end)

    children_cv = CellVector(() -> child_iomaps_cell[][1])

    output = SyntaxNode(
        TextString(() -> _interface_heading("moduleinterface", m), _kw_font, _kw_color),
        _op("}"),
        _empty_ts(),
        children_cv, 1, Cell(false), sel)
    SimpleIoMap(p, m, output)
end

# ── NedChannelToSyntaxNode ───────────────────────────────────────────────

struct NedChannelToSyntaxNode <: Projection end

function projection_print(p::NedChannelToSyntaxNode, recursion, ch::NedChannel, ctx)
    reference = ctx.reference

    child_iomaps_cell = Cell(() -> begin
        result = Pair{Symbol,Any}[]
        sc = SyntaxDocument[]
        for (i, child) in enumerate(ch.params)
            im = projection_print(recursion, recursion, child,
                     child_context(ctx, @reference ^(reference).params[i]))
            push!(sc, im.output)
            push!(result, :params => (i, im))
        end
        (sc, result)
    end)

    sel = Cell(() -> begin
        path = ch.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
        nothing
    end)

    children_cv = CellVector(() -> child_iomaps_cell[][1])

    output = SyntaxNode(
        TextString(() -> _module_heading("channel", ch), _kw_font, _kw_color),
        _op("}"),
        _empty_ts(),
        children_cv, 1, Cell(false), sel)
    SimpleIoMap(p, ch, output)
end

# ── NedChannelInterfaceToSyntaxNode ──────────────────────────────────────

struct NedChannelInterfaceToSyntaxNode <: Projection end

function projection_print(p::NedChannelInterfaceToSyntaxNode, recursion, ci::NedChannelInterface, ctx)
    reference = ctx.reference

    child_iomaps_cell = Cell(() -> begin
        result = Pair{Symbol,Any}[]
        sc = SyntaxDocument[]
        for (i, child) in enumerate(ci.params)
            im = projection_print(recursion, recursion, child,
                     child_context(ctx, @reference ^(reference).params[i]))
            push!(sc, im.output)
            push!(result, :params => (i, im))
        end
        (sc, result)
    end)

    sel = Cell(() -> begin
        path = ci.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
        nothing
    end)

    children_cv = CellVector(() -> child_iomaps_cell[][1])

    output = SyntaxNode(
        TextString(() -> _interface_heading("channelinterface", ci), _kw_font, _kw_color),
        _op("}"),
        _empty_ts(),
        children_cv, 1, Cell(false), sel)
    SimpleIoMap(p, ci, output)
end

# ── NedSubmoduleToSyntaxNode ─────────────────────────────────────────────

struct NedSubmoduleToSyntaxNode <: Projection end

function _format_submodule_heading(s::NedSubmodule)
    buf = IOBuffer()
    write(buf, s.name)
    s.vector_size !== nothing && write(buf, "[", string(s.vector_size), "]")
    write(buf, ": ")
    if s.like_type !== nothing
        write(buf, "<")
        s.like_expr !== nothing && write(buf, string(s.like_expr))
        write(buf, "> like ", string(s.like_type))
    elseif s.type !== nothing
        write(buf, string(s.type))
    end
    if isempty(s.params) && isempty(s.gates)
        write(buf, ";")
    else
        write(buf, " {")
    end
    String(take!(buf))
end

function projection_print(p::NedSubmoduleToSyntaxNode, recursion, sub::NedSubmodule, ctx)
    reference = ctx.reference
    has_body = !isempty(sub.params) || !isempty(sub.gates)

    child_iomaps_cell = Cell(() -> begin
        result = Pair{Symbol,Any}[]
        sc = SyntaxDocument[]
        if !isempty(sub.params)
            for (i, child) in enumerate(sub.params)
                im = projection_print(recursion, recursion, child,
                         child_context(ctx, @reference ^(reference).params[i]))
                push!(sc, im.output)
                push!(result, :params => (i, im))
            end
        end
        if !isempty(sub.gates)
            push!(sc, SyntaxLeaf(_kw("gates:"), _empty_ts(), _empty_ts()))
            push!(result, :_header => nothing)
            for (i, child) in enumerate(sub.gates)
                im = projection_print(recursion, recursion, child,
                         child_context(ctx, @reference ^(reference).gates[i]))
                push!(sc, im.output)
                push!(result, :gates => (i, im))
            end
        end
        (sc, result)
    end)

    sel = Cell(() -> begin
        path = sub.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
        nothing
    end)

    children_cv = CellVector(() -> child_iomaps_cell[][1])

    close_text = has_body ? "}" : ""
    output = SyntaxNode(
        TextString(() -> _format_submodule_heading(sub), _id_font, _id_color),
        TextString(() -> (isempty(sub.params) && isempty(sub.gates)) ? "" : "}", _id_font, _op_color),
        _empty_ts(),
        children_cv, has_body ? 1 : 0, Cell(false), sel)
    SimpleIoMap(p, sub, output)
end

# ── NedFileToSyntaxNode ──────────────────────────────────────────────────

struct NedFileToSyntaxNode <: Projection end

function map_reference_forward(p::NedFileToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        children{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference children[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::NedFileToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        children{s:_}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps[]
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            translated = map_reference_backward(child.projection, child, rest)
            translated === nothing && return nothing
            @reference children[child_i].^(translated)
        end
    end
end

function projection_read(p::NedFileToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
end

function projection_read(p::NedFileToSyntaxNode, iomap::ChildrenIoMap, op::StringReplaceRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    StringReplaceRangeOperation(new_ref, op.replacement)
end

function projection_print(p::NedFileToSyntaxNode, recursion, f::NedFile, ctx)
    reference = ctx.reference
    child_iomaps = Cell(() -> [projection_print(recursion, recursion, child,
                                   child_context(ctx, @reference ^(reference).children[i]))
                               for (i, child) in enumerate(f)])

    sel = Cell(() -> begin
        path = f.selection
        path isa ConcreteReferencePath && path.head isa ProjectionReference && return path
        @reference_case path begin
            children{s_idx:_}.rest... => begin
                child_i = s_idx + 1
                iomaps = child_iomaps[]
                child_i > length(iomaps) && return nothing
                child_sel = iomaps[child_i].output.selection
                child_sel === nothing && return nothing
                @reference children[child_i].^(child_sel)
            end
        end
    end)

    children_cv = CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]])

    output = SyntaxNode(
        _empty_ts(), _empty_ts(), _empty_ts(),
        children_cv, 0, Cell(false), sel)
    ChildrenIoMap(p, f, output, child_iomaps)
end

# ── Compound convenience constructor ─────────────────────────────────────

function NedToSyntax()
    TypeDispatchingProjection(
        NedInsertion       => NedInsertionToSyntaxLeaf(),
        NedPackage         => NedPackageToSyntaxLeaf(),
        NedImport          => NedImportToSyntaxLeaf(),
        NedProperty        => NedPropertyToSyntaxLeaf(),
        NedParam           => NedParamToSyntaxLeaf(),
        NedGate            => NedGateToSyntaxLeaf(),
        NedSubmodule       => NedSubmoduleToSyntaxNode(),
        NedConnection      => NedConnectionToSyntaxLeaf(),
        NedConnectionGroup => NedConnectionGroupToSyntaxNode(),
        NedSimpleModule    => NedSimpleModuleToSyntaxNode(),
        NedCompoundModule  => NedCompoundModuleToSyntaxNode(),
        NedModuleInterface => NedModuleInterfaceToSyntaxNode(),
        NedChannel         => NedChannelToSyntaxNode(),
        NedChannelInterface => NedChannelInterfaceToSyntaxNode(),
        NedFile            => NedFileToSyntaxNode(),
    )
end

end # module
