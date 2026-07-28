"""
    SqlToSyntaxModule

SQL → SyntaxDocument projection. Renders a `SqlSelectStatement` as a syntax tree.

Keywords render as bold colored leaves; identifiers as regular leaves.
Projections compose recursively through the clause structure. Combine with
`SyntaxToText` to get the textual form.

Selection mapping is implemented at all levels: leaf projections share
`doc.selection` with the SyntaxLeaf; `SqlSelectStatementToSyntaxNode` uses
`ChildrenIoMap` with clause-level delegation so selection propagates through
the full statement tree.
"""
module SqlToSyntaxModule

import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..SqlDocumentModule: SqlNothing, SqlSelectStatement, SqlSelectClause, SqlFromClause, SqlWhereClause,
                            SqlWhereFilterCondition,
                            SqlSelectItem, SqlAllColumns, SqlColumnReference,
                            SqlTableName, SqlColumnName,
                            SqlTableExpression, SqlSubqueryFromItem, SqlFromItem, SqlJoinedFromItem, SqlJoinType,
                            SqlInnerJoin, SqlLeftOuterJoin, SqlRightOuterJoin, SqlFullOuterJoin, SqlCrossJoin,
                            SqlJoinOnCondition,
                            SqlScalarValue, SqlComparison, SqlAnd, SqlOr, SqlNot, SqlBooleanExpression,
                            SqlInsertStatement, SqlUpdateAssignment, SqlUpdateStatement,
                            SqlColumnDefinition, SqlCreateTableStatement, SqlCreateSchemaStatement,
                            SqlStatementList, SqlInsertion
import ..DocumentInsertionToSyntaxModule: SqlInsertionToSyntaxLeaf, InsertionNothingToSyntaxLeaf
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20
import ..ColorModule: StyleColor, color_default, color_solarized_blue, color_solarized_green
import ..StyleTextModule: StyleText, DStyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode, SyntaxSeparation, SyntaxNavigation
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..IoMapModule: ChildrenIoMap
import ..ProjectionTemplateModule: var"@projection_template", RuleIoMap
import ..ReferenceModule: ConcreteReference, ElementReferenceStep, PositionReferenceStep, FieldReferenceStep, EmptyReference
import ..ProjectionReferenceStepModule: ProjectionReferenceStep, is_introduced_reference
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..SyntaxToTextModule: SyntaxCompoundToText, _syntax_to_flat
import ..PrinterContextModule: make_child_context

export SqlAllColumnsToSyntaxLeaf, SqlColumnReferenceToSyntaxLeaf,
       SqlColumnNameToSyntaxLeaf, SqlTableNameToSyntaxLeaf,
       SqlTableExpressionToSyntaxLeaf, SqlSubqueryFromItemToSyntaxNode, SqlJoinTypeToSyntaxLeaf,
       SqlSelectItemToSyntaxNode, SqlSelectClauseToSyntaxNode,
       SqlFromItemToSyntaxNode, SqlFromClauseToSyntaxNode,
       SqlJoinedFromItemToSyntaxNode, SqlJoinOnConditionToSyntaxNode,
       SqlWhereFilterConditionToSyntaxNode, SqlWhereClauseToSyntaxNode,
       SqlScalarValueToSyntaxLeaf, SqlComparisonToSyntaxNode,
       SqlBooleanBinaryToSyntaxNode, SqlNotToSyntaxNode,
       SqlSelectStatementToSyntaxNode,
       SqlInsertStatementToSyntaxNode, SqlUpdateAssignmentToSyntaxNode,
       SqlUpdateStatementToSyntaxNode,
       SqlColumnDefinitionToSyntaxNode, SqlCreateTableStatementToSyntaxNode,
       SqlCreateSchemaStatementToSyntaxNode, SqlStatementListToSyntaxNode, SqlToSyntax

# ── helpers ────────────────────────────────────────────────────────────────────

_kw(text, font, color) = SyntaxLeaf(TextString(text, font, color))

_kw(text, style::StyleText) = _kw(text, style.font, style.color)

# A run of clauses joined by a separator, and nothing else — no delimiters, no
# indentation. That is exactly a separation.
_space_node(f::Function) = SyntaxSeparation(f; separator=" ")

_comma_node(f::Function) = SyntaxSeparation(f; separator=", ")

# These three lay each child out on its own indented line, which is *per-child*
# indentation — the separator and the line chrome interleaved by one node. A
# `SyntaxIndentation` has a single child and indents that one thing, so it cannot
# express this and these stay `SyntaxNode`s. That is the combined type earning its
# keep, not a gap (see plan/pending/simplest-syntax-document.md).
_comma_body(f::Function) = SyntaxNode(f; sep=",", indentation=1)

_newline_body(f::Function) = SyntaxNode(f; indentation=1)

_newline_body_compact(f::Function) = SyntaxNode(f; indentation=-1)

# ── SqlAllColumnsToSyntaxLeaf ─────────────────────────────────────────────────

@projection struct SqlAllColumnsToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_default)
end

# Opaque display leaf (no marker): the rendered text is a pure multi-field
# display with no editable interior. The engine derives the ∅↔∅ selection
# mapping; the shared `read_intent = nothing` (below) keeps it non-editable.
@projection_template SqlAllColumnsToSyntaxLeaf SqlAllColumns (p, doc) ->
    SyntaxLeaf(TextString(() -> begin
                   q = doc.qualifier
                   q === nothing ? "*" : "$(q.name).*"
               end, p.style))

# ── SqlColumnReferenceToSyntaxLeaf ────────────────────────────────────────────

@projection struct SqlColumnReferenceToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_default)
end

@projection_template SqlColumnReferenceToSyntaxLeaf SqlColumnReference (p, doc) ->
    SyntaxLeaf(TextString(() -> begin
                   q = doc.qualifier
                   col = doc.column_name.name
                   q === nothing ? col : "$(q.name).$col"
               end, p.style))

# ── SqlColumnNameToSyntaxLeaf ─────────────────────────────────────────────────
# Bare column name, used in INSERT column lists and UPDATE assignments.

@projection struct SqlColumnNameToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_default)
end

@projection_template SqlColumnNameToSyntaxLeaf SqlColumnName (p, doc) ->
    SyntaxLeaf(TextString(() -> doc.name, p.style))

# ── SqlTableNameToSyntaxLeaf ──────────────────────────────────────────────────
# Bare table name (with optional schema), used as the INSERT/UPDATE target.

@projection struct SqlTableNameToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@projection_template SqlTableNameToSyntaxLeaf SqlTableName (p, doc) ->
    SyntaxLeaf(TextString(() -> doc.schema_name === nothing ? doc.name : "$(doc.schema_name).$(doc.name)",
                          p.style))

# ── SqlTableExpressionToSyntaxLeaf ────────────────────────────────────────────

@projection struct SqlTableExpressionToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_solarized_green)
end

@projection_template SqlTableExpressionToSyntaxLeaf SqlTableExpression (p, doc) ->
    SyntaxLeaf(TextString(() -> begin
                   tn = doc.table_name
                   base = tn.schema_name === nothing ? tn.name : "$(tn.schema_name).$(tn.name)"
                   a = doc.alias
                   a === nothing ? base : "$base AS $(a.name)"
               end, p.style))

# ── SqlSubqueryFromItemToSyntaxNode ──────────────────────────────────────────

@projection struct SqlSubqueryFromItemToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    identifier_font::StyleFont = font_ubuntu_monospace_regular_20
end

function print_document(p::SqlSubqueryFromItemToSyntaxNode, recursion, doc::SqlSubqueryFromItem, ctx)
    subq_im = Cell(() -> print_document(recursion, recursion, doc.subquery,
                                          make_child_context(ctx, FieldReferenceStep("subquery"))))
    child_iomaps_cell = Cell(() -> Any[subq_im[]])

    paren_node = SyntaxNode("(", ")", " ", () -> SyntaxDocument[subq_im[].output])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> begin
            docs = SyntaxDocument[paren_node]
            if doc.alias !== nothing
                push!(docs, _kw("AS", p.keyword))
                push!(docs, SyntaxLeaf(
                    TextString(() -> doc.alias === nothing ? "" : doc.alias.name,
                               p.identifier_font, color_default)))
            end
            docs
        end);
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlSubqueryFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlSubqueryFromItem.subquery.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[1]::SyntaxNode.children::CellVector[1].^(inner)
        end
    end
end

function map_reference_backward(p::SqlSubqueryFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlSubqueryFromItem
        ::SyntaxNode.children[1].children[1].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlSubqueryFromItem.subquery.^(inner)
        end
    end
end

function read_intent(p::SqlSubqueryFromItemToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlSubqueryFromItemToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

_join_type_display(::SqlInnerJoin)      = "INNER JOIN"
_join_type_display(::SqlLeftOuterJoin)  = "LEFT OUTER JOIN"
_join_type_display(::SqlRightOuterJoin) = "RIGHT OUTER JOIN"
_join_type_display(::SqlFullOuterJoin)  = "FULL OUTER JOIN"
_join_type_display(::SqlCrossJoin)      = "CROSS JOIN"

# ── SqlJoinTypeToSyntaxLeaf ───────────────────────────────────────────────────

@projection struct SqlJoinTypeToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

# The join keyword ("INNER JOIN", …) is a fixed display for the document's type.
@projection_template SqlJoinTypeToSyntaxLeaf SqlJoinType (p, doc) ->
    SyntaxLeaf(TextString(_join_type_display(doc), p.style))

# ── SqlSelectItemToSyntaxNode ─────────────────────────────────────────────────

@projection struct SqlSelectItemToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    alias_font::StyleFont = font_ubuntu_monospace_regular_20
end

function print_document(p::SqlSelectItemToSyntaxNode, recursion, doc::SqlSelectItem, ctx)
    expr_im = Cell(() -> print_document(recursion, recursion, doc.expression,
                                          make_child_context(ctx, FieldReferenceStep("expression"))))
    child_iomaps_cell = Cell(() -> Any[expr_im[]])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> begin
            docs = SyntaxDocument[expr_im[].output]
            if doc.column_alias !== nothing
                push!(docs, _kw("AS", p.keyword))
                push!(docs, SyntaxLeaf(
                    TextString(() -> doc.column_alias === nothing ? "" : doc.column_alias.name,
                               p.alias_font, color_default)))
            end
            docs
        end);
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlSelectItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlSelectItem.expression.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[1].^(inner)
        end
    end
end

function map_reference_backward(p::SqlSelectItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlSelectItem
        ::SyntaxNode.children[1].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlSelectItem.expression.^(inner)
        end
    end
end

function read_intent(p::SqlSelectItemToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlSelectItemToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlSelectClauseToSyntaxNode ───────────────────────────────────────────────

@projection struct SqlSelectClauseToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::SqlSelectClauseToSyntaxNode, recursion, doc::SqlSelectClause, ctx)
    item_ims = Cell(() -> [
        print_document(recursion, recursion, item, make_child_context(ctx, ElementReferenceStep(i)))
        for (i, item) in enumerate(doc.items)])

    items_body = _comma_body(() -> SyntaxDocument[im.output for im in item_ims[]])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> begin
            kws = SyntaxDocument[_kw("SELECT", p.keyword)]
            doc.distinct !== nothing && push!(kws, _kw("DISTINCT", p.keyword))
            push!(kws, items_body)
            kws
        end);
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, doc, node, item_ims)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlSelectClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlSelectClause.items{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps
            1 <= child_i <= length(cims) || return nothing
            child = cims[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            body_idx = iomap.input.distinct !== nothing ? 3 : 2
            @reference ::SyntaxNode.children::CellVector[body_idx]::SyntaxNode.children::CellVector[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::SqlSelectClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlSelectClause
        ::SyntaxNode.children{outer_s:_}.children{t:u}.rest... => begin
            outer_i = outer_s + 1
            body_idx = iomap.input.distinct !== nothing ? 3 : 2
            outer_i != body_idx && return nothing
            item_i = t + 1
            cims = iomap.child_iomaps
            1 <= item_i <= length(cims) || return nothing
            child = cims[item_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlSelectClause.items::CellVector[item_i].^(inner)
        end
    end
end

function read_intent(p::SqlSelectClauseToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlSelectClauseToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlJoinedFromItemToSyntaxNode ─────────────────────────────────────────────

@projection struct SqlJoinedFromItemToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::SqlJoinedFromItemToSyntaxNode, recursion, doc::SqlJoinedFromItem, ctx)
    projected = Cell(() -> begin
        jt = print_document(recursion, recursion, doc.join_type,
                              make_child_context(ctx, FieldReferenceStep("join_type")))
        fi = print_document(recursion, recursion, doc.from_item,
                              make_child_context(ctx, FieldReferenceStep("from_item")))
        cond_im = doc.condition === nothing ? nothing :
            print_document(recursion, recursion, doc.condition,
                             make_child_context(ctx, FieldReferenceStep("condition")))
        (jt, fi, cond_im)
    end)
    child_iomaps_cell = Cell(() -> begin
        jt, fi, cond_im = projected[]
        cond_im === nothing ? Any[jt, fi] : Any[jt, fi, cond_im]
    end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> begin
            jt, fi, cond_im = projected[]
            cond_im === nothing ? SyntaxDocument[jt.output, fi.output] :
                                  SyntaxDocument[jt.output, fi.output, cond_im.output]
        end);
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlJoinedFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlJoinedFromItem.join_type.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[1].^(inner)
        end
        ::SqlJoinedFromItem.from_item.rest... => begin
            child = iomap.child_iomaps[2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[2].^(inner)
        end
        ::SqlJoinedFromItem.condition.rest... => begin
            cims = iomap.child_iomaps
            length(cims) < 3 && return nothing
            child = cims[3]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[3].^(inner)
        end
    end
end

function map_reference_backward(p::SqlJoinedFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlJoinedFromItem
        ::SyntaxNode.children[1].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlJoinedFromItem.join_type.^(inner)
        end
        ::SyntaxNode.children[2].rest... => begin
            child = iomap.child_iomaps[2]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlJoinedFromItem.from_item.^(inner)
        end
        ::SyntaxNode.children[3].rest... => begin
            cims = iomap.child_iomaps
            length(cims) < 3 && return nothing
            child = cims[3]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlJoinedFromItem.condition.^(inner)
        end
    end
end

function read_intent(p::SqlJoinedFromItemToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlJoinedFromItemToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlJoinOnConditionToSyntaxNode ─────────────────────────────────────────────

@projection struct SqlJoinOnConditionToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::SqlJoinOnConditionToSyntaxNode, recursion, doc::SqlJoinOnCondition, ctx)
    expr_im = Cell(() ->
        print_document(recursion, recursion, doc.expression,
                         make_child_context(ctx, FieldReferenceStep("expression"))))
    child_iomaps_cell = Cell(() -> Any[expr_im[]])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[_kw("ON", p.keyword), expr_im[].output]);
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlJoinOnConditionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlJoinOnCondition.expression.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[2].^(inner)
        end
    end
end

function map_reference_backward(p::SqlJoinOnConditionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlJoinOnCondition
        ::SyntaxNode.children[2].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlJoinOnCondition.expression.^(inner)
        end
    end
end

function read_intent(p::SqlJoinOnConditionToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlJoinOnConditionToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlFromItemToSyntaxNode ───────────────────────────────────────────────────

@projection struct SqlFromItemToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::SqlFromItemToSyntaxNode, recursion, doc::SqlFromItem, ctx)
    projected = Cell(() -> begin
        base = print_document(recursion, recursion, doc.base_item,
                                make_child_context(ctx, FieldReferenceStep("base_item")))
        joins = [print_document(recursion, recursion, seg,
                                  make_child_context(ctx, ElementReferenceStep(i)))
                 for (i, seg) in enumerate(doc.joins)]
        (base, joins)
    end)
    child_iomaps_cell = Cell(() -> begin base, joins = projected[]; Any[base; joins] end)

    joins_body = _newline_body_compact(() -> begin
        _, joins = projected[]
        SyntaxDocument[j.output for j in joins]
    end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> begin
            base, joins = projected[]
            isempty(joins) ? SyntaxDocument[base.output] :
                             SyntaxDocument[base.output, joins_body]
        end);
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlFromItem.base_item.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[1].^(inner)
        end
        ::SqlFromItem.joins{s:_}.rest... => begin
            join_i = s + 1
            cims = iomap.child_iomaps
            cim_i = join_i + 1                  # index 1 is base_im
            1 <= cim_i <= length(cims) || return nothing
            child = cims[cim_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[2]::SyntaxNode.children::CellVector[join_i].^(inner)
        end
    end
end

function map_reference_backward(p::SqlFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlFromItem
        ::SyntaxNode.children[1].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlFromItem.base_item.^(inner)
        end
        ::SyntaxNode.children{outer_s:_}.children{t:u}.rest... => begin
            outer_s != 1 && return nothing       # joins_body is always at pos 2
            join_i = t + 1
            cims = iomap.child_iomaps
            cim_i = join_i + 1                  # index 1 is base_im
            1 <= cim_i <= length(cims) || return nothing
            child = cims[cim_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlFromItem.joins::CellVector[join_i].^(inner)
        end
    end
end

function read_intent(p::SqlFromItemToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlFromItemToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlFromClauseToSyntaxNode ─────────────────────────────────────────────────

@projection struct SqlFromClauseToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::SqlFromClauseToSyntaxNode, recursion, doc::SqlFromClause, ctx)
    item_ims = Cell(() -> [
        print_document(recursion, recursion, item, make_child_context(ctx, ElementReferenceStep(i)))
        for (i, item) in enumerate(doc.items)])

    items_body = _comma_body(() -> SyntaxDocument[im.output for im in item_ims[]])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[_kw("FROM", p.keyword), items_body]);
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, doc, node, item_ims)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlFromClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlFromClause.items{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps
            1 <= child_i <= length(cims) || return nothing
            child = cims[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[2]::SyntaxNode.children::CellVector[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::SqlFromClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlFromClause
        ::SyntaxNode.children{outer_s:_}.children{t:u}.rest... => begin
            outer_s != 1 && return nothing          # items_body is always at pos 2
            item_i = t + 1
            cims = iomap.child_iomaps
            1 <= item_i <= length(cims) || return nothing
            child = cims[item_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlFromClause.items::CellVector[item_i].^(inner)
        end
    end
end

function read_intent(p::SqlFromClauseToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlFromClauseToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlWhereFilterConditionToSyntaxNode ──────────────────────────────────────

@projection struct SqlWhereFilterConditionToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::SqlWhereFilterConditionToSyntaxNode, recursion, doc::SqlWhereFilterCondition, ctx)
    expr_im = Cell(() ->
        print_document(recursion, recursion, doc.expression,
                         make_child_context(ctx, FieldReferenceStep("expression"))))
    child_iomaps_cell = Cell(() -> Any[expr_im[]])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    # No delimiters, no separator, no indentation — the node exists only so the whole
    # condition has a level to select (`∅`). That is a navigation anchor, not a sequence.
    # Positional (content, selection): SyntaxNavigation has no keyword constructor, and a
    # `Function` content is wrapped as a computed cell so the child stays lazily projected.
    node = SyntaxNavigation(() -> expr_im[].output, sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlWhereFilterConditionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNavigation
        proj(^(p), _) => reference
        ::SqlWhereFilterCondition.expression.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNavigation.content.^(inner)
        end
    end
end

function map_reference_backward(p::SqlWhereFilterConditionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlWhereFilterCondition
        ::SyntaxNavigation.content.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlWhereFilterCondition.expression.^(inner)
        end
    end
end

function read_intent(p::SqlWhereFilterConditionToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlWhereFilterConditionToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlWhereClauseToSyntaxNode ────────────────────────────────────────────────

@projection struct SqlWhereClauseToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::SqlWhereClauseToSyntaxNode, recursion, doc::SqlWhereClause, ctx)
    cond_im = Cell(() -> doc.condition === nothing ? nothing :
        print_document(recursion, recursion, doc.condition,
                         make_child_context(ctx, FieldReferenceStep("condition"))))
    cond_body = _newline_body(() -> begin
        ci = cond_im[]
        ci !== nothing ? SyntaxDocument[ci.output] : SyntaxDocument[]
    end)
    child_iomaps_cell = Cell(() -> begin ci = cond_im[]; ci === nothing ? Any[] : Any[ci] end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[_kw("WHERE", p.keyword), cond_body]);
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlWhereClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlWhereClause.condition.rest... => begin
            cims = iomap.child_iomaps
            isempty(cims) && return nothing
            child = cims[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[2]::SyntaxNode.children::CellVector[1].^(inner)
        end
    end
end

function map_reference_backward(p::SqlWhereClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlWhereClause
        ::SyntaxNode.children[2].children[1].rest... => begin
            cims = iomap.child_iomaps
            isempty(cims) && return nothing
            child = cims[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlWhereClause.condition.^(inner)
        end
    end
end

function read_intent(p::SqlWhereClauseToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlWhereClauseToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlScalarValueToSyntaxLeaf ───────────────────────────────────────────────

@projection struct SqlScalarValueToSyntaxLeaf
    style::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_default)
end

@projection_template SqlScalarValueToSyntaxLeaf SqlScalarValue (p, doc) ->
    SyntaxLeaf(TextString(() -> begin
                   val = doc.value
                   val isa Bool           ? (val ? "TRUE" : "FALSE") :
                   val isa AbstractString ? "'$val'" :
                   string(val)
               end, p.style))

# All seven SQL leaf projections are opaque display leaves: their content is a
# computed multi-field display with no editable interior. A caret on that introduced
# text has no input pre-image, so — exactly like XmlElementToSyntaxNode — it is
# collapsed to a bounded flat offset carried as a projection-introduced reference
# (`proj(p, {flat})`). This keeps text-navigation bounded (the domain-neutral fallback
# would grow the path without bound) while naming the whole node.
#
# The reader must name the *operation* types, not carry an `op` catch-all: a catch-all
# `read_intent(::Sql…Leaf, ::RuleIoMap, op)` is ambiguous with the template's typed
# readers — the gesture reader `read_intent(::Projection, ::RuleIoMap, ::Union{KeyPress,KeyDown})`,
# the `ClaimedGesture` reader, and `ReaderDefaults`' `::ReplaceStringRangeOperation` — so a
# bare SQL leaf atom would throw `MethodError` on every raw gesture. Instead we only add
# the selection reader; raw gestures fall to the template's own reader, and text edits are
# declined by `ReaderDefaults`' opaque-leaf rule (no bound field).
const _SqlDisplayLeaf = Union{SqlAllColumnsToSyntaxLeaf, SqlColumnReferenceToSyntaxLeaf,
                              SqlColumnNameToSyntaxLeaf, SqlTableNameToSyntaxLeaf,
                              SqlTableExpressionToSyntaxLeaf, SqlJoinTypeToSyntaxLeaf,
                              SqlScalarValueToSyntaxLeaf}

function read_intent(p::_SqlDisplayLeaf, iomap::RuleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxLeaf, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

# A `proj(p, …)` selection is this projection's own introduced position — pass it through
# unchanged; everything else defers to the generic template mapper.
function map_reference_forward(p::_SqlDisplayLeaf, iomap::RuleIoMap, reference)
    is_introduced_reference(reference) && return reference
    invoke(map_reference_forward, Tuple{Projection, RuleIoMap, Any}, p, iomap, reference)
end

# ── SqlComparisonToSyntaxNode ─────────────────────────────────────────────────

@projection struct SqlComparisonToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::SqlComparisonToSyntaxNode, recursion, doc::SqlComparison, ctx)
    projected = Cell(() -> begin
        left  = print_document(recursion, recursion, doc.left,
                                 make_child_context(ctx, FieldReferenceStep("left")))
        right = print_document(recursion, recursion, doc.right,
                                 make_child_context(ctx, FieldReferenceStep("right")))
        (left, right)
    end)
    child_iomaps_cell = Cell(() -> begin left, right = projected[]; Any[left, right] end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> begin
            left, right = projected[]
            SyntaxDocument[left.output, _kw(doc.operator, p.keyword), right.output]
        end);
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlComparisonToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlComparison.left.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[1].^(inner)
        end
        ::SqlComparison.right.rest... => begin
            child = iomap.child_iomaps[2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[3].^(inner)
        end
    end
end

function map_reference_backward(p::SqlComparisonToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlComparison
        ::SyntaxNode.children[1].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlComparison.left.^(inner)
        end
        ::SyntaxNode.children[3].rest... => begin
            child = iomap.child_iomaps[2]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlComparison.right.^(inner)
        end
    end
end

function read_intent(p::SqlComparisonToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlComparisonToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlBooleanBinaryToSyntaxNode (AND / OR) ──────────────────────────────────

@projection struct SqlBooleanBinaryToSyntaxNode <: Projection
    keyword::ImmutableCell{String}
    keyword_style::ImmutableCell{DStyleText}
end
SqlBooleanBinaryToSyntaxNode(keyword; keyword_style=StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)) =
    SqlBooleanBinaryToSyntaxNode(keyword, keyword_style)

function print_document(p::SqlBooleanBinaryToSyntaxNode, recursion, doc, ctx)
    projected = Cell(() -> begin
        left  = print_document(recursion, recursion, doc.left,
                                 make_child_context(ctx, FieldReferenceStep("left")))
        right = print_document(recursion, recursion, doc.right,
                                 make_child_context(ctx, FieldReferenceStep("right")))
        (left, right)
    end)
    child_iomaps_cell = Cell(() -> begin left, right = projected[]; Any[left, right] end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> begin
            left, right = projected[]
            SyntaxDocument[left.output, _kw(p.keyword, p.keyword_style), right.output]
        end);
        open=TextString("(", p.keyword_style.font, color_default),
        close=TextString(")", p.keyword_style.font, color_default),
        sep=TextString(" ", p.keyword_style.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlBooleanBinaryToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        left.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[1].^(inner)
        end
        right.rest... => begin
            child = iomap.child_iomaps[2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[3].^(inner)
        end
    end
end

function map_reference_backward(p::SqlBooleanBinaryToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlBooleanExpression
        ::SyntaxNode.children[1].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlBooleanExpression.left.^(inner)
        end
        ::SyntaxNode.children[3].rest... => begin
            child = iomap.child_iomaps[2]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlBooleanExpression.right.^(inner)
        end
    end
end

function read_intent(p::SqlBooleanBinaryToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlBooleanBinaryToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlNotToSyntaxNode ────────────────────────────────────────────────────────

@projection struct SqlNotToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::SqlNotToSyntaxNode, recursion, doc::SqlNot, ctx)
    expr_im = Cell(() -> print_document(recursion, recursion, doc.expression,
                                          make_child_context(ctx, FieldReferenceStep("expression"))))
    child_iomaps_cell = Cell(() -> Any[expr_im[]])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() ->
            SyntaxDocument[_kw("NOT", p.keyword), expr_im[].output]);
        open=TextString("(", p.keyword.font, color_default),
        close=TextString(")", p.keyword.font, color_default),
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlNotToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlNot.expression.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[2].^(inner)
        end
    end
end

function map_reference_backward(p::SqlNotToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlNot
        ::SyntaxNode.children[2].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlNot.expression.^(inner)
        end
    end
end

function read_intent(p::SqlNotToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlNotToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlSelectStatementToSyntaxNode ────────────────────────────────────────────
#
# Output shape (no separator at top level; each clause node ends with \n from its
# indented body, so clauses appear on separate lines without extra separators):
#   SyntaxNode (no separator):
#     children[1] = select_clause node  → "SELECT [DISTINCT]\n  item,\n  …\n"
#     children[2] = from_clause node    → "FROM\n  item,\n  …\n"
#     children[3] = where_clause node   → "WHERE\n  …\n"  (omitted if no condition)

@projection struct SqlSelectStatementToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::SqlSelectStatementToSyntaxNode, recursion, stmt::SqlSelectStatement, ctx)
    projected = Cell(() -> begin
        sc = print_document(recursion, recursion, stmt.select_clause,
                              make_child_context(ctx, FieldReferenceStep("select_clause")))
        fc = print_document(recursion, recursion, stmt.from_clause,
                              make_child_context(ctx, FieldReferenceStep("from_clause")))
        wc = stmt.where_clause.condition === nothing ? nothing :
             print_document(recursion, recursion, stmt.where_clause,
                              make_child_context(ctx, FieldReferenceStep("where_clause")))
        (sc, fc, wc)
    end)

    child_iomaps_cell = Cell(() -> begin
        sc, fc, wc = projected[]
        wc !== nothing ? Any[sc, fc, wc] : Any[sc, fc]
    end)

    children = CellVector(() -> begin
        sc, fc, wc = projected[]
        docs = SyntaxDocument[sc.output, fc.output]
        wc !== nothing && push!(docs, wc.output)
        docs
    end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = stmt.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(children; selection=sel)

    iomap = ChildrenIoMap(p, stmt, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlSelectStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlSelectStatement.select_clause.rest... => begin
            cims = iomap.child_iomaps
            child = cims[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[1].^(inner)
        end
        ::SqlSelectStatement.from_clause.rest... => begin
            cims = iomap.child_iomaps
            child = cims[2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[2].^(inner)
        end
        ::SqlSelectStatement.where_clause.rest... => begin
            cims = iomap.child_iomaps
            length(cims) < 3 && return nothing
            child = cims[3]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[3].^(inner)
        end
    end
end

function map_reference_backward(p::SqlSelectStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlSelectStatement
        ::SyntaxNode.children{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps
            1 <= child_i <= length(cims) || return nothing
            child = cims[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            if child_i == 1
                @reference ::SqlSelectStatement.select_clause.^(inner)
            elseif child_i == 2
                @reference ::SqlSelectStatement.from_clause.^(inner)
            else
                @reference ::SqlSelectStatement.where_clause.^(inner)
            end
        end
    end
end

function read_intent(p::SqlSelectStatementToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

# ── SqlInsertStatementToSyntaxNode ────────────────────────────────────────────
#
# Single-line shape (sep=" "):
#   INSERT INTO <table> (<col>, …) VALUES (<val>, …)
# Child positions: [1]=INSERT [2]=INTO [3]=table [4]=columns-paren (when columns
# present) then VALUES and values-paren. The column/value leaves live one level
# deeper, inside their parenthesised comma list.

@projection struct SqlInsertStatementToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::SqlInsertStatementToSyntaxNode, recursion, stmt::SqlInsertStatement, ctx)
    projected = Cell(() -> begin
        table_im = print_document(recursion, recursion, stmt.table,
                                    make_child_context(ctx, FieldReferenceStep("table")))
        col_ims = [print_document(recursion, recursion, c,
                                    make_child_context(ctx, FieldReferenceStep("columns"), ElementReferenceStep(i)))
                   for (i, c) in enumerate(stmt.columns)]
        val_ims = [print_document(recursion, recursion, v,
                                    make_child_context(ctx, FieldReferenceStep("values"), ElementReferenceStep(i)))
                   for (i, v) in enumerate(stmt.values)]
        (table_im, col_ims, val_ims)
    end)
    child_iomaps_cell = Cell(() -> begin
        table_im, col_ims, val_ims = projected[]
        Any[table_im; col_ims; val_ims]
    end)

    columns_paren = SyntaxNode("(", ")", ", ", () -> begin
        _, col_ims, _ = projected[]
        SyntaxDocument[c.output for c in col_ims]
    end)
    values_paren = SyntaxNode("(", ")", ", ", () -> begin
        _, _, val_ims = projected[]
        SyntaxDocument[v.output for v in val_ims]
    end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = stmt.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> begin
            _, col_ims, _ = projected[]
            docs = SyntaxDocument[_kw("INSERT", p.keyword),
                                  _kw("INTO", p.keyword),
                                  projected[][1].output]
            isempty(col_ims) || push!(docs, columns_paren)
            push!(docs, _kw("VALUES", p.keyword))
            push!(docs, values_paren)
            docs
        end);
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, stmt, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlInsertStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    ncols = length(iomap.input.columns)
    vals_idx = ncols == 0 ? 5 : 6
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlInsertStatement.table.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[3].^(inner)
        end
        ::SqlInsertStatement.columns{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps
            cim_i = 1 + child_i
            1 <= cim_i <= length(cims) || return nothing
            child = cims[cim_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[4]::SyntaxNode.children::CellVector[child_i].^(inner)
        end
        ::SqlInsertStatement.values{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps
            cim_i = 1 + ncols + child_i
            1 <= cim_i <= length(cims) || return nothing
            child = cims[cim_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[vals_idx]::SyntaxNode.children::CellVector[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::SqlInsertStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    ncols = length(iomap.input.columns)
    cols_present = ncols != 0
    vals_idx = cols_present ? 6 : 5
    @reference_case reference begin
        ∅ => @reference ::SqlInsertStatement
        ::SyntaxNode.children[3].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlInsertStatement.table.^(inner)
        end
        ::SyntaxNode.children{outer_s:_}.children{t:u}.rest... => begin
            outer_i = outer_s + 1
            child_i = t + 1
            cims = iomap.child_iomaps
            if cols_present && outer_i == 4
                cim_i = 1 + child_i
                1 <= cim_i <= length(cims) || return nothing
                child = cims[cim_i]
                inner = map_reference_backward(child.projection, child, rest)
                inner === nothing && return nothing
                @reference ::SqlInsertStatement.columns::CellVector[child_i].^(inner)
            elseif outer_i == vals_idx
                cim_i = 1 + ncols + child_i
                1 <= cim_i <= length(cims) || return nothing
                child = cims[cim_i]
                inner = map_reference_backward(child.projection, child, rest)
                inner === nothing && return nothing
                @reference ::SqlInsertStatement.values::CellVector[child_i].^(inner)
            else
                return nothing
            end
        end
    end
end

function read_intent(p::SqlInsertStatementToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlInsertStatementToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlUpdateAssignmentToSyntaxNode ───────────────────────────────────────────
# Renders `<col> = <value>`. children[1]=column, children[3]=value (the `=`
# keyword sits at children[2], like SqlComparison).

@projection struct SqlUpdateAssignmentToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::SqlUpdateAssignmentToSyntaxNode, recursion, doc::SqlUpdateAssignment, ctx)
    projected = Cell(() -> begin
        col_im = print_document(recursion, recursion, doc.column_name,
                                  make_child_context(ctx, FieldReferenceStep("column_name")))
        val_im = print_document(recursion, recursion, doc.value,
                                  make_child_context(ctx, FieldReferenceStep("value")))
        (col_im, val_im)
    end)
    child_iomaps_cell = Cell(() -> begin col_im, val_im = projected[]; Any[col_im, val_im] end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> begin
            col_im, val_im = projected[]
            SyntaxDocument[col_im.output, _kw("=", p.keyword), val_im.output]
        end);
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlUpdateAssignmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlUpdateAssignment.column_name.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[1].^(inner)
        end
        ::SqlUpdateAssignment.value.rest... => begin
            child = iomap.child_iomaps[2]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[3].^(inner)
        end
    end
end

function map_reference_backward(p::SqlUpdateAssignmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlUpdateAssignment
        ::SyntaxNode.children[1].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlUpdateAssignment.column_name.^(inner)
        end
        ::SyntaxNode.children[3].rest... => begin
            child = iomap.child_iomaps[2]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlUpdateAssignment.value.^(inner)
        end
    end
end

function read_intent(p::SqlUpdateAssignmentToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlUpdateAssignmentToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlUpdateStatementToSyntaxNode ────────────────────────────────────────────
#
# Single-line shape (sep=" "):
#   UPDATE <table> SET <assignment>, … [WHERE <condition>]
# Child positions: [1]=UPDATE [2]=table [3]=SET [4]=assignments comma-body
#   [5]=WHERE [6]=condition  (5 and 6 present only when there is a condition).
# The WHERE condition is rendered inline (the where clause's condition is
# projected directly, not the multi-line SqlWhereClause projection), keeping the
# statement on one line.

@projection struct SqlUpdateStatementToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::SqlUpdateStatementToSyntaxNode, recursion, stmt::SqlUpdateStatement, ctx)
    projected = Cell(() -> begin
        table_im = print_document(recursion, recursion, stmt.table,
                                    make_child_context(ctx, FieldReferenceStep("table")))
        assign_ims = [print_document(recursion, recursion, a,
                                       make_child_context(ctx, FieldReferenceStep("assignments"), ElementReferenceStep(i)))
                      for (i, a) in enumerate(stmt.assignments)]
        where_im = stmt.where_clause.condition === nothing ? nothing :
            print_document(recursion, recursion, stmt.where_clause.condition,
                             make_child_context(ctx, FieldReferenceStep("where_clause"), FieldReferenceStep("condition")))
        (table_im, assign_ims, where_im)
    end)
    child_iomaps_cell = Cell(() -> begin
        table_im, assign_ims, where_im = projected[]
        where_im === nothing ? Any[table_im; assign_ims] : Any[table_im; assign_ims; where_im]
    end)

    assignments_body = _comma_node(() -> begin
        _, assign_ims, _ = projected[]
        SyntaxDocument[a.output for a in assign_ims]
    end)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = stmt.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> begin
            table_im, _, where_im = projected[]
            docs = SyntaxDocument[_kw("UPDATE", p.keyword),
                                  table_im.output,
                                  _kw("SET", p.keyword),
                                  assignments_body]
            if where_im !== nothing
                push!(docs, _kw("WHERE", p.keyword))
                push!(docs, where_im.output)
            end
            docs
        end);
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, stmt, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlUpdateStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    nassign = length(iomap.input.assignments)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlUpdateStatement.table.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[2].^(inner)
        end
        ::SqlUpdateStatement.assignments{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps
            cim_i = 1 + child_i
            1 <= cim_i <= length(cims) || return nothing
            child = cims[cim_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[4]::SyntaxNode.children::CellVector[child_i].^(inner)
        end
        ::SqlUpdateStatement.where_clause.condition.rest... => begin
            cims = iomap.child_iomaps
            length(cims) < 2 + nassign && return nothing
            child = cims[2 + nassign]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[6].^(inner)
        end
    end
end

function map_reference_backward(p::SqlUpdateStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    nassign = length(iomap.input.assignments)
    @reference_case reference begin
        ∅ => @reference ::SqlUpdateStatement
        ::SyntaxNode.children[2].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlUpdateStatement.table.^(inner)
        end
        ::SyntaxNode.children[6].rest... => begin
            cims = iomap.child_iomaps
            length(cims) < 2 + nassign && return nothing
            child = cims[2 + nassign]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlUpdateStatement.where_clause::SqlWhereClause.condition.^(inner)
        end
        ::SyntaxNode.children{outer_s:_}.children{t:u}.rest... => begin
            outer_i = outer_s + 1
            outer_i != 4 && return nothing
            child_i = t + 1
            cims = iomap.child_iomaps
            cim_i = 1 + child_i
            1 <= cim_i <= length(cims) || return nothing
            child = cims[cim_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlUpdateStatement.assignments::CellVector[child_i].^(inner)
        end
    end
end

function read_intent(p::SqlUpdateStatementToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlUpdateStatementToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlColumnDefinitionToSyntaxNode ───────────────────────────────────────────
# Renders `<column-name> <data-type>` inside a CREATE TABLE column list.
# children[1] = column_name (projected); children[2] = data-type leaf (a plain
# String on the document, so it has no projected child of its own).

@projection struct SqlColumnDefinitionToSyntaxNode
    type::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_regular_20, color_default)
end

function print_document(p::SqlColumnDefinitionToSyntaxNode, recursion, doc::SqlColumnDefinition, ctx)
    col_im = Cell(() -> print_document(recursion, recursion, doc.column_name,
                                         make_child_context(ctx, FieldReferenceStep("column_name"))))
    child_iomaps_cell = Cell(() -> Any[col_im[]])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[
            col_im[].output,
            SyntaxLeaf(TextString(() -> doc.data_type, p.type))]);
        sep=TextString(" ", p.type.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlColumnDefinitionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlColumnDefinition.column_name.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[1].^(inner)
        end
    end
end

function map_reference_backward(p::SqlColumnDefinitionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlColumnDefinition
        ::SyntaxNode.children[1].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlColumnDefinition.column_name.^(inner)
        end
    end
end

function read_intent(p::SqlColumnDefinitionToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlColumnDefinitionToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlCreateTableStatementToSyntaxNode ───────────────────────────────────────
#
# Output shape (top node sep=" ", close=";"):
#   CREATE TABLE schema.table (
#       col_a integer,
#       col_b text
#   );
# Child positions: [1]=CREATE [2]=TABLE [3]=table_name [4]=columns paren-body.
# The column definition leaves live one level deeper, inside the indented,
# parenthesised comma body at children[4].

@projection struct SqlCreateTableStatementToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
end

function print_document(p::SqlCreateTableStatementToSyntaxNode, recursion, stmt::SqlCreateTableStatement, ctx)
    projected = Cell(() -> begin
        table_im = print_document(recursion, recursion, stmt.table_name,
                                    make_child_context(ctx, FieldReferenceStep("table_name")))
        col_ims = [print_document(recursion, recursion, c,
                                    make_child_context(ctx, FieldReferenceStep("columns"), ElementReferenceStep(i)))
                   for (i, c) in enumerate(stmt.columns)]
        (table_im, col_ims)
    end)
    child_iomaps_cell = Cell(() -> begin
        table_im, col_ims = projected[]
        Any[table_im; col_ims]
    end)

    columns_body = SyntaxNode("(", ")", ",", () -> begin
        _, col_ims = projected[]
        SyntaxDocument[c.output for c in col_ims]
    end; indentation=1)

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = stmt.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> begin
            table_im, _ = projected[]
            SyntaxDocument[_kw("CREATE", p.keyword),
                           _kw("TABLE", p.keyword),
                           table_im.output,
                           columns_body]
        end);
        close=TextString(";", p.keyword.font, color_default),
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, stmt, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlCreateTableStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlCreateTableStatement.table_name.rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[3].^(inner)
        end
        ::SqlCreateTableStatement.columns{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps
            cim_i = 1 + child_i
            1 <= cim_i <= length(cims) || return nothing
            child = cims[cim_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[4]::SyntaxNode.children::CellVector[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::SqlCreateTableStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlCreateTableStatement
        ::SyntaxNode.children[3].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlCreateTableStatement.table_name.^(inner)
        end
        ::SyntaxNode.children{outer_s:_}.children{t:u}.rest... => begin
            outer_i = outer_s + 1
            outer_i != 4 && return nothing
            child_i = t + 1
            cims = iomap.child_iomaps
            cim_i = 1 + child_i
            1 <= cim_i <= length(cims) || return nothing
            child = cims[cim_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlCreateTableStatement.columns::CellVector[child_i].^(inner)
        end
    end
end

function read_intent(p::SqlCreateTableStatementToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlCreateTableStatementToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlCreateSchemaStatementToSyntaxNode ──────────────────────────────────────
#
# Output shape (top node sep=" ", close=";"):  CREATE SCHEMA name;
# The schema name is a plain String on the document (no projected child), so the
# statement has no child iomaps; only whole-statement (∅) selection is mapped.

@projection struct SqlCreateSchemaStatementToSyntaxNode
    keyword::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_blue)
    identifier_font::StyleFont = font_ubuntu_monospace_regular_20
end

function print_document(p::SqlCreateSchemaStatementToSyntaxNode, recursion, stmt::SqlCreateSchemaStatement, ctx)
    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = stmt.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[
            _kw("CREATE", p.keyword),
            _kw("SCHEMA", p.keyword),
            SyntaxLeaf(TextString(() -> stmt.schema_name, p.identifier_font, color_solarized_green))]);
        close=TextString(";", p.keyword.font, color_default),
        sep=TextString(" ", p.keyword.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, stmt, node, Cell(() -> Any[]))
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlCreateSchemaStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
    end
end

function map_reference_backward(p::SqlCreateSchemaStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlCreateSchemaStatement
    end
end

function read_intent(p::SqlCreateSchemaStatementToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlCreateSchemaStatementToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlStatementListToSyntaxNode ──────────────────────────────────────────────
#
# Renders an ordered statement list, blank-line separated (each statement node
# already ends with its own `;`). children[i] = statements[i].

@projection struct SqlStatementListToSyntaxNode
    font::StyleFont = font_ubuntu_monospace_regular_20
end

function print_document(p::SqlStatementListToSyntaxNode, recursion, doc::SqlStatementList, ctx)
    stmt_ims = Cell(() -> [
        print_document(recursion, recursion, s, make_child_context(ctx, ElementReferenceStep(i)))
        for (i, s) in enumerate(doc.statements)])
    child_iomaps_cell = Cell(() -> Any[im for im in stmt_ims[]])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[im.output for im in stmt_ims[]]);
        sep=TextString("\n\n", p.font, color_default),
        selection=sel)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlStatementListToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), _) => reference
        ::SqlStatementList.statements{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps
            1 <= child_i <= length(cims) || return nothing
            child = cims[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children[child_i].^(inner)
        end
    end
end

function map_reference_backward(p::SqlStatementListToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlStatementList
        ::SyntaxNode.children{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps
            1 <= child_i <= length(cims) || return nothing
            child = cims[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlStatementList.statements::CellVector[child_i].^(inner)
        end
    end
end

function read_intent(p::SqlStatementListToSyntaxNode, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxCompoundToText(), 0)
    flat < 0 && return nothing
    return ReplaceSelectionOperation(ConcreteReference(ProjectionReferenceStep(p, ConcreteReference(PositionReferenceStep(flat)))))
end

read_intent(::SqlStatementListToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── Compound constructor ──────────────────────────────────────────────────────

function SqlToSyntax()
    jt = SqlJoinTypeToSyntaxLeaf()
    TypeDispatchingProjection(
        SqlInsertion            => SqlInsertionToSyntaxLeaf(),
        SqlNothing              => InsertionNothingToSyntaxLeaf(),
        SqlSelectStatement      => SqlSelectStatementToSyntaxNode(),
        SqlSelectClause         => SqlSelectClauseToSyntaxNode(),
        SqlFromClause           => SqlFromClauseToSyntaxNode(),
        SqlWhereClause          => SqlWhereClauseToSyntaxNode(),
        SqlSelectItem           => SqlSelectItemToSyntaxNode(),
        SqlAllColumns           => SqlAllColumnsToSyntaxLeaf(),
        SqlColumnReference      => SqlColumnReferenceToSyntaxLeaf(),
        SqlColumnName           => SqlColumnNameToSyntaxLeaf(),
        SqlTableName            => SqlTableNameToSyntaxLeaf(),
        SqlTableExpression      => SqlTableExpressionToSyntaxLeaf(),
        SqlSubqueryFromItem     => SqlSubqueryFromItemToSyntaxNode(),
        SqlFromItem             => SqlFromItemToSyntaxNode(),
        SqlJoinedFromItem       => SqlJoinedFromItemToSyntaxNode(),
        SqlJoinOnCondition      => SqlJoinOnConditionToSyntaxNode(),
        SqlWhereFilterCondition => SqlWhereFilterConditionToSyntaxNode(),
        SqlInnerJoin            => jt,
        SqlLeftOuterJoin        => jt,
        SqlRightOuterJoin       => jt,
        SqlFullOuterJoin        => jt,
        SqlCrossJoin            => jt,
        SqlScalarValue          => SqlScalarValueToSyntaxLeaf(),
        SqlComparison           => SqlComparisonToSyntaxNode(),
        SqlAnd                  => SqlBooleanBinaryToSyntaxNode("AND"),
        SqlOr                   => SqlBooleanBinaryToSyntaxNode("OR"),
        SqlNot                  => SqlNotToSyntaxNode(),
        SqlInsertStatement      => SqlInsertStatementToSyntaxNode(),
        SqlUpdateAssignment     => SqlUpdateAssignmentToSyntaxNode(),
        SqlUpdateStatement      => SqlUpdateStatementToSyntaxNode(),
        SqlColumnDefinition     => SqlColumnDefinitionToSyntaxNode(),
        SqlCreateTableStatement => SqlCreateTableStatementToSyntaxNode(),
        SqlCreateSchemaStatement => SqlCreateSchemaStatementToSyntaxNode(),
        SqlStatementList        => SqlStatementListToSyntaxNode(),
    )
end

# ── Natural-format registration ─────────────────────────────────────────────
# SQL's seams for import_document / export_document / read+write_document_file.
import ..SqlParserModule: sqlparse
import ..SqlDocumentModule: SqlDocument
import ..NaturalFormatModule: natural_syntax_projection, natural_extension, parse_natural
import ..DocumentFileModule: new_document_seed
natural_syntax_projection(::SqlDocument) = SqlToSyntax()
natural_extension(::SqlDocument) = ".sql"
parse_natural(::Val{:sql}, text::AbstractString) = sqlparse(text)
new_document_seed(::Val{:sql}) = SqlInsertion()

end # module
