# Fragment of `SqlModule`.
#
# SQL → SyntaxDocument projection. Renders a `SqlSelectStatement` as a syntax tree.
#
# Keywords render as bold colored leaves; identifiers as regular leaves.
# Projections compose recursively through the clause structure. Combine with
# `SyntaxToText` to get the textual form.
#
# Selection mapping is implemented at all levels: leaf projections share
# `doc.selection` with the SyntaxLeaf; `SqlSelectStatementToSyntaxNode` uses
# `ChildrenIoMap` with clause-level delegation so selection propagates through
# the full statement tree.
# ── helpers ────────────────────────────────────────────────────────────────────

_kw(text, font, color) = SyntaxLeaf(TextString(text, font, color))

_kw(text, style::StyleText) = _kw(text, style.font, style.color)

# A run of clauses joined by a separator, and nothing else — no delimiters, no
# indentation. That is exactly a separation.
_space_node(f::Function) = SyntaxSeparation(f; separator=" ")

_comma_node(f::Function, style::StyleText) = SyntaxSeparation(f; separator=TextString(", ", style))

# These three lay each child out on its own indented line, which is *per-child*
# indentation — the separator and the line chrome interleaved by one node. A
# `SyntaxIndentation` has a single child and indents that one thing, so it cannot
# express this and these stay `SyntaxNode`s. That is the combined type earning its
# keep, not a gap (see plan/pending/simplest-syntax-document.md).
_comma_body(f::Function, style::StyleText) = SyntaxNode(f; sep=TextString(",", style), indentation=1)

_newline_body(f::Function) = SyntaxNode(f; indentation=1)

_newline_body_compact(f::Function) = SyntaxNode(f; indentation=-1)

# ── SqlAllColumnsToSyntaxLeaf ─────────────────────────────────────────────────

@projection UntrackedCell struct SqlAllColumnsToSyntaxLeaf
    style::StyleText = get_sql_style(nothing, :plain_text)
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

@projection UntrackedCell struct SqlColumnReferenceToSyntaxLeaf
    style::StyleText = get_sql_style(nothing, :plain_text)
end

@projection_template SqlColumnReferenceToSyntaxLeaf SqlColumnReference (p, doc) ->
    SyntaxLeaf(TextString(() -> begin
                   q = doc.qualifier
                   col = doc.column_name.name
                   q === nothing ? col : "$(q.name).$col"
               end, p.style))

# ── SqlColumnNameToSyntaxLeaf ─────────────────────────────────────────────────
# Bare column name, used in INSERT column lists and UPDATE assignments.

@projection UntrackedCell struct SqlColumnNameToSyntaxLeaf
    style::StyleText = get_sql_style(nothing, :plain_text)
end

@projection_template SqlColumnNameToSyntaxLeaf SqlColumnName (p, doc) ->
    SyntaxLeaf(TextString(() -> doc.name, p.style))

# ── SqlTableNameToSyntaxLeaf ──────────────────────────────────────────────────
# Bare table name (with optional schema), used as the INSERT/UPDATE target.

@projection UntrackedCell struct SqlTableNameToSyntaxLeaf
    style::StyleText = get_sql_style(nothing, :name_text)
end

@projection_template SqlTableNameToSyntaxLeaf SqlTableName (p, doc) ->
    SyntaxLeaf(TextString(() -> doc.schema_name === nothing ? doc.name : "$(doc.schema_name).$(doc.name)",
                          p.style))

# ── SqlTableExpressionToSyntaxLeaf ────────────────────────────────────────────

@projection UntrackedCell struct SqlTableExpressionToSyntaxLeaf
    style::StyleText = get_sql_style(nothing, :name_text)
end

@projection_template SqlTableExpressionToSyntaxLeaf SqlTableExpression (p, doc) ->
    SyntaxLeaf(TextString(() -> begin
                   tn = doc.table_name
                   base = tn.schema_name === nothing ? tn.name : "$(tn.schema_name).$(tn.name)"
                   a = doc.alias
                   a === nothing ? base : "$base AS $(a.name)"
               end, p.style))

# ── SqlSubqueryFromItemToSyntaxNode ──────────────────────────────────────────

@projection UntrackedCell struct SqlSubqueryFromItemToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    name::StyleFont = _get_sql_font(nothing)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
    plain::StyleText = get_sql_style(nothing, :plain_text)
end

function print_document(p::SqlSubqueryFromItemToSyntaxNode, recursion, doc::SqlSubqueryFromItem, ctx)
    subq_im = Cell(@computation(print_document(recursion, recursion, doc.subquery,
                                         make_child_context(ctx, FieldReferenceStep("subquery")))))
    child_iomaps_cell = Cell(@computation Any[subq_im[]])

    paren_node = SyntaxNode(() -> SyntaxDocument[subq_im[].output]; open = TextString("(", p.plain),
                            close = TextString(")", p.plain), sep = TextString(" ", p.plain))

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation begin
            docs = SyntaxDocument[paren_node]
            if doc.alias !== nothing
                push!(docs, _kw("AS", p.keyword))
                push!(docs, SyntaxLeaf(
                    TextString(() -> doc.alias === nothing ? "" : doc.alias.name,
                               p.plain.font, p.plain.color)))
            end
            docs
        end);
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlSubqueryFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlSubqueryFromItemToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlSubqueryFromItemToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

_join_type_display(::SqlInnerJoin)      = "INNER JOIN"
_join_type_display(::SqlLeftOuterJoin)  = "LEFT OUTER JOIN"
_join_type_display(::SqlRightOuterJoin) = "RIGHT OUTER JOIN"
_join_type_display(::SqlFullOuterJoin)  = "FULL OUTER JOIN"
_join_type_display(::SqlCrossJoin)      = "CROSS JOIN"

# ── SqlJoinTypeToSyntaxLeaf ───────────────────────────────────────────────────

@projection UntrackedCell struct SqlJoinTypeToSyntaxLeaf
    style::StyleText = get_sql_style(nothing, :keyword_text)
end

# The join keyword ("INNER JOIN", …) is a fixed display for the document's type.
@projection_template SqlJoinTypeToSyntaxLeaf SqlJoinType (p, doc) ->
    SyntaxLeaf(TextString(_join_type_display(doc), p.style))

# ── SqlSelectItemToSyntaxNode ─────────────────────────────────────────────────

@projection UntrackedCell struct SqlSelectItemToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    name::StyleFont = _get_sql_font(nothing)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
    plain::StyleText = get_sql_style(nothing, :plain_text)
end

function print_document(p::SqlSelectItemToSyntaxNode, recursion, doc::SqlSelectItem, ctx)
    expr_im = Cell(@computation(print_document(recursion, recursion, doc.expression,
                                         make_child_context(ctx, FieldReferenceStep("expression")))))
    child_iomaps_cell = Cell(@computation Any[expr_im[]])

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation begin
            docs = SyntaxDocument[expr_im[].output]
            if doc.column_alias !== nothing
                push!(docs, _kw("AS", p.keyword))
                push!(docs, SyntaxLeaf(
                    TextString(() -> doc.column_alias === nothing ? "" : doc.column_alias.name,
                               p.plain.font, p.plain.color)))
            end
            docs
        end);
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlSelectItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlSelectItemToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlSelectItemToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlSelectClauseToSyntaxNode ───────────────────────────────────────────────

@projection UntrackedCell struct SqlSelectClauseToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
    plain::StyleText = get_sql_style(nothing, :plain_text)
end

function print_document(p::SqlSelectClauseToSyntaxNode, recursion, doc::SqlSelectClause, ctx)
    item_ims = Cell(@computation([
        print_document(recursion, recursion, item, make_child_context(ctx, ElementReferenceStep(i)))
        for (i, item) in enumerate(doc.items)]))

    items_body = _comma_body(() -> SyntaxDocument[im.output for im in item_ims[]], p.plain)

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation begin
            kws = SyntaxDocument[_kw("SELECT", p.keyword)]
            doc.distinct !== nothing && push!(kws, _kw("DISTINCT", p.keyword))
            push!(kws, items_body)
            kws
        end);
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, doc, node, item_ims)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlSelectClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
            outer_i != body_idx && return make_introduced_reference(p, iomap, reference)
            item_i = t + 1
            cims = iomap.child_iomaps
            1 <= item_i <= length(cims) || return make_introduced_reference(p, iomap, reference)
            child = cims[item_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlSelectClause.items::CellVector[item_i].^(inner)
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlSelectClauseToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlSelectClauseToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlJoinedFromItemToSyntaxNode ─────────────────────────────────────────────

@projection UntrackedCell struct SqlJoinedFromItemToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
end

function print_document(p::SqlJoinedFromItemToSyntaxNode, recursion, doc::SqlJoinedFromItem, ctx)
    projected = Cell(@computation begin
        jt = print_document(recursion, recursion, doc.join_type,
                              make_child_context(ctx, FieldReferenceStep("join_type")))
        fi = print_document(recursion, recursion, doc.from_item,
                              make_child_context(ctx, FieldReferenceStep("from_item")))
        cond_im = doc.condition === nothing ? nothing :
            print_document(recursion, recursion, doc.condition,
                             make_child_context(ctx, FieldReferenceStep("condition")))
        (jt, fi, cond_im)
    end)
    child_iomaps_cell = Cell(@computation begin
        jt, fi, cond_im = projected[]
        cond_im === nothing ? Any[jt, fi] : Any[jt, fi, cond_im]
    end)

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation begin
            jt, fi, cond_im = projected[]
            cond_im === nothing ? SyntaxDocument[jt.output, fi.output] :
                                  SyntaxDocument[jt.output, fi.output, cond_im.output]
        end);
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlJoinedFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
            length(cims) < 3 && return make_introduced_reference(p, iomap, reference)
            child = cims[3]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlJoinedFromItem.condition.^(inner)
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlJoinedFromItemToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlJoinedFromItemToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlJoinOnConditionToSyntaxNode ─────────────────────────────────────────────

@projection UntrackedCell struct SqlJoinOnConditionToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
end

function print_document(p::SqlJoinOnConditionToSyntaxNode, recursion, doc::SqlJoinOnCondition, ctx)
    expr_im = Cell(@computation(print_document(recursion, recursion, doc.expression,
                         make_child_context(ctx, FieldReferenceStep("expression")))))
    child_iomaps_cell = Cell(@computation Any[expr_im[]])

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation(SyntaxDocument[_kw("ON", p.keyword),
                                               expr_im[].output]));
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlJoinOnConditionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlJoinOnConditionToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlJoinOnConditionToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlJoinUsingConditionToSyntaxNode ─────────────────────────────────────────
#
# `USING (a, b)`: the keyword, then the column names in parentheses, each through
# its own rule. The keyword and the parentheses have no input field, so a caret on
# them is a part that this projection printed, named by its own introduced step.

@projection UntrackedCell struct SqlJoinUsingConditionToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
end

@projection_template SqlJoinUsingConditionToSyntaxNode SqlJoinUsingCondition (p, doc) ->
    SyntaxNode(SyntaxDocument[
            _kw("USING", p.keyword),
            SyntaxNode(collection(:column_names);
                       open=TextString("(", p.punctuation.font, p.punctuation.color),
                       close=TextString(")", p.punctuation.font, p.punctuation.color),
                       sep=TextString(", ", p.punctuation.font, p.punctuation.color))];
        sep=TextString(" ", p.punctuation.font, p.punctuation.color))

# ── SqlFromItemToSyntaxNode ───────────────────────────────────────────────────

@projection UntrackedCell struct SqlFromItemToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
end

function print_document(p::SqlFromItemToSyntaxNode, recursion, doc::SqlFromItem, ctx)
    projected = Cell(@computation begin
        base = print_document(recursion, recursion, doc.base_item,
                                make_child_context(ctx, FieldReferenceStep("base_item")))
        joins = [print_document(recursion, recursion, seg,
                                  make_child_context(ctx, ElementReferenceStep(i)))
                 for (i, seg) in enumerate(doc.joins)]
        (base, joins)
    end)
    child_iomaps_cell = Cell(@computation begin base, joins = projected[]; Any[base; joins] end)

    joins_body = _newline_body_compact(() -> begin
        _, joins = projected[]
        SyntaxDocument[j.output for j in joins]
    end)

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation begin
            base, joins = projected[]
            isempty(joins) ? SyntaxDocument[base.output] :
                             SyntaxDocument[base.output, joins_body]
        end);
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlFromItemToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
            outer_s != 1 && return make_introduced_reference(p, iomap, reference)       # joins_body is always at pos 2
            join_i = t + 1
            cims = iomap.child_iomaps
            cim_i = join_i + 1                  # index 1 is base_im
            1 <= cim_i <= length(cims) || return make_introduced_reference(p, iomap, reference)
            child = cims[cim_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlFromItem.joins::CellVector[join_i].^(inner)
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlFromItemToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlFromItemToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlFromClauseToSyntaxNode ─────────────────────────────────────────────────

@projection UntrackedCell struct SqlFromClauseToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
    plain::StyleText = get_sql_style(nothing, :plain_text)
end

function print_document(p::SqlFromClauseToSyntaxNode, recursion, doc::SqlFromClause, ctx)
    item_ims = Cell(@computation([
        print_document(recursion, recursion, item, make_child_context(ctx, ElementReferenceStep(i)))
        for (i, item) in enumerate(doc.items)]))

    items_body = _comma_body(() -> SyntaxDocument[im.output for im in item_ims[]], p.plain)

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation SyntaxDocument[_kw("FROM", p.keyword), items_body]);
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, doc, node, item_ims)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlFromClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
            outer_s != 1 && return make_introduced_reference(p, iomap, reference)          # items_body is always at pos 2
            item_i = t + 1
            cims = iomap.child_iomaps
            1 <= item_i <= length(cims) || return make_introduced_reference(p, iomap, reference)
            child = cims[item_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlFromClause.items::CellVector[item_i].^(inner)
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlFromClauseToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlFromClauseToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlWhereFilterConditionToSyntaxNode ──────────────────────────────────────

@projection UntrackedCell struct SqlWhereFilterConditionToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
end

function print_document(p::SqlWhereFilterConditionToSyntaxNode, recursion, doc::SqlWhereFilterCondition, ctx)
    expr_im = Cell(@computation(print_document(recursion, recursion, doc.expression,
                         make_child_context(ctx, FieldReferenceStep("expression")))))
    child_iomaps_cell = Cell(@computation Any[expr_im[]])

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    # No delimiters, no separator, no indentation — the node exists only so the whole
    # condition has a level to select (`∅`). That is a navigation anchor, not a sequence.
    # Positional (content, selection, mouse target): SyntaxNavigation has no keyword
    # constructor. The content is a computed cell so the child stays lazily projected.
    node = SyntaxNavigation(Cell(@computation expr_im[].output), paths.selection, paths.mouse_target)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlWhereFilterConditionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNavigation
        proj(^(p), inner) => inner
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
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlWhereFilterConditionToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlWhereFilterConditionToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlWhereClauseToSyntaxNode ────────────────────────────────────────────────

@projection UntrackedCell struct SqlWhereClauseToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
end

function print_document(p::SqlWhereClauseToSyntaxNode, recursion, doc::SqlWhereClause, ctx)
    cond_im = Cell(@computation(doc.condition === nothing ? nothing :
        print_document(recursion, recursion, doc.condition,
                         make_child_context(ctx, FieldReferenceStep("condition")))))
    cond_body = _newline_body(() -> begin
        ci = cond_im[]
        ci !== nothing ? SyntaxDocument[ci.output] : SyntaxDocument[]
    end)
    child_iomaps_cell = Cell(@computation begin ci = cond_im[]; ci === nothing ? Any[] : Any[ci] end)

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation SyntaxDocument[_kw("WHERE", p.keyword), cond_body]);
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlWhereClauseToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
            isempty(cims) && return make_introduced_reference(p, iomap, reference)
            child = cims[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlWhereClause.condition.^(inner)
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlWhereClauseToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlWhereClauseToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlScalarValueToSyntaxLeaf ───────────────────────────────────────────────

@projection UntrackedCell struct SqlScalarValueToSyntaxLeaf
    style::StyleText = get_sql_style(nothing, :plain_text)
end

@projection_template SqlScalarValueToSyntaxLeaf SqlScalarValue (p, doc) ->
    SyntaxLeaf(TextString(() -> begin
                   val = doc.value
                   val isa Bool           ? (val ? "TRUE" : "FALSE") :
                   val isa AbstractString ? _quote_string_literal(val) :
                   string(val)
               end, p.style))

# The text of a string literal: the value between two quotes, with each quote in
# it written twice.
_quote_string_literal(value::AbstractString) = "'" * replace(value, "'" => "''") * "'"

# ── SqlRawExpressionToSyntaxLeaf ─────────────────────────────────────────────
# The source text of an expression that the model does not have, as it is written.

@projection UntrackedCell struct SqlRawExpressionToSyntaxLeaf
    style::StyleText = get_sql_style(nothing, :plain_text)
end

@projection_template SqlRawExpressionToSyntaxLeaf SqlRawExpression (p, doc) ->
    SyntaxLeaf(TextString(() -> doc.text, p.style))

# ── SqlRawConditionToSyntaxLeaf ──────────────────────────────────────────────
# The source text of a condition that the model does not have, as it is written.

@projection UntrackedCell struct SqlRawConditionToSyntaxLeaf
    style::StyleText = get_sql_style(nothing, :plain_text)
end

@projection_template SqlRawConditionToSyntaxLeaf SqlRawCondition (p, doc) ->
    SyntaxLeaf(TextString(() -> doc.text, p.style))

# ── SqlComparisonToSyntaxNode ─────────────────────────────────────────────────

@projection UntrackedCell struct SqlComparisonToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
end

function print_document(p::SqlComparisonToSyntaxNode, recursion, doc::SqlComparison, ctx)
    projected = Cell(@computation begin
        left  = print_document(recursion, recursion, doc.left,
                                 make_child_context(ctx, FieldReferenceStep("left")))
        right = print_document(recursion, recursion, doc.right,
                                 make_child_context(ctx, FieldReferenceStep("right")))
        (left, right)
    end)
    child_iomaps_cell = Cell(@computation begin left, right = projected[]; Any[left, right] end)

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation begin
            left, right = projected[]
            SyntaxDocument[left.output, _kw(doc.operator, p.keyword), right.output]
        end);
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlComparisonToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlComparisonToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlComparisonToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlBooleanBinaryToSyntaxNode (AND / OR) ──────────────────────────────────

@projection UntrackedCell struct SqlBooleanBinaryToSyntaxNode <: Projection
    keyword::String
    keyword_style::StyleText
    punctuation::StyleText
end
SqlBooleanBinaryToSyntaxNode(keyword; theme = nothing,
                             keyword_style = get_sql_style(theme, :keyword_text),
                             punctuation = get_sql_style(theme, :punctuation_text)) =
    SqlBooleanBinaryToSyntaxNode(keyword, keyword_style, punctuation)

function print_document(p::SqlBooleanBinaryToSyntaxNode, recursion, doc, ctx)
    projected = Cell(@computation begin
        left  = print_document(recursion, recursion, doc.left,
                                 make_child_context(ctx, FieldReferenceStep("left")))
        right = print_document(recursion, recursion, doc.right,
                                 make_child_context(ctx, FieldReferenceStep("right")))
        (left, right)
    end)
    child_iomaps_cell = Cell(@computation begin left, right = projected[]; Any[left, right] end)

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation begin
            left, right = projected[]
            SyntaxDocument[left.output, _kw(p.keyword, p.keyword_style), right.output]
        end);
        open=TextString("(", p.punctuation.font, p.punctuation.color),
        close=TextString(")", p.punctuation.font, p.punctuation.color),
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlBooleanBinaryToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlBooleanBinaryToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlBooleanBinaryToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlNotToSyntaxNode ────────────────────────────────────────────────────────

@projection UntrackedCell struct SqlNotToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
end

function print_document(p::SqlNotToSyntaxNode, recursion, doc::SqlNot, ctx)
    expr_im = Cell(@computation(print_document(recursion, recursion, doc.expression,
                                         make_child_context(ctx, FieldReferenceStep("expression")))))
    child_iomaps_cell = Cell(@computation Any[expr_im[]])

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation SyntaxDocument[_kw("NOT", p.keyword), expr_im[].output]);
        open=TextString("(", p.punctuation.font, p.punctuation.color),
        close=TextString(")", p.punctuation.font, p.punctuation.color),
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlNotToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlNotToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlNotToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlSelectStatementToSyntaxNode ────────────────────────────────────────────
#
# Output shape (no separator at top level; each clause node ends with \n from its
# indented body, so clauses appear on separate lines without extra separators):
#   SyntaxNode (no separator):
#     select_clause node  → "SELECT [DISTINCT]\n  item,\n  …\n"
#     from_clause node    → "FROM\n  item,\n  …\n"  (omitted if it has no item)
#     where_clause node   → "WHERE\n  …\n"            (omitted if no condition)
# A clause that is omitted has no child, so the position of a clause is its index
# in `_get_printed_select_clauses`.

@projection UntrackedCell struct SqlSelectStatementToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
end

# The fields of the clauses that a statement prints, in order. A `FROM` with no
# item prints nothing, so `SELECT 1` reads back, and a `WHERE` with no condition
# prints nothing.
_get_printed_select_clauses(stmt::SqlSelectStatement) =
    [name for (name, printed) in (("select_clause", true),
                                  ("from_clause", !isempty(stmt.from_clause.items)),
                                  ("where_clause", stmt.where_clause.condition !== nothing))
     if printed]

function print_document(p::SqlSelectStatementToSyntaxNode, recursion, stmt::SqlSelectStatement, ctx)
    child_iomaps_cell = Cell(@computation(Any[
        print_document(recursion, recursion, getproperty(stmt, Symbol(name)),
                       make_child_context(ctx, FieldReferenceStep(name)))
        for name in _get_printed_select_clauses(stmt)]))

    children = CellVector(@computation SyntaxDocument[im.output for im in child_iomaps_cell[]])

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(stmt, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(children; paths...)

    iomap = ChildrenIoMap(p, stmt, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlSelectStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
        ::SqlSelectStatement.select_clause.rest... => _map_select_clause_forward(iomap, "select_clause", rest)
        ::SqlSelectStatement.from_clause.rest... => _map_select_clause_forward(iomap, "from_clause", rest)
        ::SqlSelectStatement.where_clause.rest... => _map_select_clause_forward(iomap, "where_clause", rest)
    end
end

# A reference into the clause `name` as a reference into its child, or `nothing`
# when the statement does not print that clause.
function _map_select_clause_forward(iomap::ChildrenIoMap, name::String, rest)
    child_i = findfirst(==(name), _get_printed_select_clauses(iomap.input))
    cims = iomap.child_iomaps
    (child_i === nothing || child_i > length(cims)) && return nothing
    child = cims[child_i]
    inner = map_reference_forward(child.projection, child, rest)
    inner === nothing && return nothing
    @reference ::SyntaxNode.children::CellVector[child_i].^(inner)
end

function map_reference_backward(p::SqlSelectStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlSelectStatement
        ::SyntaxNode.children{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps
            1 <= child_i <= length(cims) || return make_introduced_reference(p, iomap, reference)
            child = cims[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            names = _get_printed_select_clauses(iomap.input)
            child_i <= length(names) || return make_introduced_reference(p, iomap, reference)
            name = names[child_i]
            if name == "select_clause"
                @reference ::SqlSelectStatement.select_clause.^(inner)
            elseif name == "from_clause"
                @reference ::SqlSelectStatement.from_clause.^(inner)
            else
                @reference ::SqlSelectStatement.where_clause.^(inner)
            end
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlSelectStatementToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

# ── SqlInsertStatementToSyntaxNode ────────────────────────────────────────────
#
# Single-line shape (sep=" "):
#   INSERT INTO <table> (<col>, …) VALUES (<val>, …)
# Child positions: [1]=INSERT [2]=INTO [3]=table [4]=columns-paren (when columns
# present) then VALUES and values-paren. The column/value leaves live one level
# deeper, inside their parenthesised comma list.

@projection UntrackedCell struct SqlInsertStatementToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
    plain::StyleText = get_sql_style(nothing, :plain_text)
end

function print_document(p::SqlInsertStatementToSyntaxNode, recursion, stmt::SqlInsertStatement, ctx)
    projected = Cell(@computation begin
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
    child_iomaps_cell = Cell(@computation begin
        table_im, col_ims, val_ims = projected[]
        Any[table_im; col_ims; val_ims]
    end)

    columns_paren = SyntaxNode(() -> begin
        _, col_ims, _ = projected[]
        SyntaxDocument[c.output for c in col_ims]
    end; open = TextString("(", p.plain), close = TextString(")", p.plain), sep = TextString(", ", p.plain))
    values_paren = SyntaxNode(() -> begin
        _, _, val_ims = projected[]
        SyntaxDocument[v.output for v in val_ims]
    end; open = TextString("(", p.plain), close = TextString(")", p.plain), sep = TextString(", ", p.plain))

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(stmt, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation begin
            _, col_ims, _ = projected[]
            docs = SyntaxDocument[_kw("INSERT", p.keyword),
                                  _kw("INTO", p.keyword),
                                  projected[][1].output]
            isempty(col_ims) || push!(docs, columns_paren)
            push!(docs, _kw("VALUES", p.keyword))
            push!(docs, values_paren)
            docs
        end);
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, stmt, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlInsertStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    ncols = length(iomap.input.columns)
    vals_idx = ncols == 0 ? 5 : 6
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
    @reference_case reference begin
        ∅ => @reference ::SqlInsertStatement
        ::SyntaxNode.children[3].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlInsertStatement.table.^(inner)
        end
        ::SyntaxNode.children{outer_s:_}.children{t:u}.rest... => begin
            ncols = length(iomap.input.columns)
            cols_present = ncols != 0
            vals_idx = cols_present ? 6 : 5
            outer_i = outer_s + 1
            child_i = t + 1
            cims = iomap.child_iomaps
            if cols_present && outer_i == 4
                cim_i = 1 + child_i
                1 <= cim_i <= length(cims) || return make_introduced_reference(p, iomap, reference)
                child = cims[cim_i]
                inner = map_reference_backward(child.projection, child, rest)
                inner === nothing && return nothing
                @reference ::SqlInsertStatement.columns::CellVector[child_i].^(inner)
            elseif outer_i == vals_idx
                cim_i = 1 + ncols + child_i
                1 <= cim_i <= length(cims) || return make_introduced_reference(p, iomap, reference)
                child = cims[cim_i]
                inner = map_reference_backward(child.projection, child, rest)
                inner === nothing && return nothing
                @reference ::SqlInsertStatement.values::CellVector[child_i].^(inner)
            else
                return make_introduced_reference(p, iomap, reference)
            end
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlInsertStatementToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlInsertStatementToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlUpdateAssignmentToSyntaxNode ───────────────────────────────────────────
# Renders `<col> = <value>`. children[1]=column, children[3]=value (the `=`
# keyword sits at children[2], like SqlComparison).

@projection UntrackedCell struct SqlUpdateAssignmentToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
end

function print_document(p::SqlUpdateAssignmentToSyntaxNode, recursion, doc::SqlUpdateAssignment, ctx)
    projected = Cell(@computation begin
        col_im = print_document(recursion, recursion, doc.column_name,
                                  make_child_context(ctx, FieldReferenceStep("column_name")))
        val_im = print_document(recursion, recursion, doc.value,
                                  make_child_context(ctx, FieldReferenceStep("value")))
        (col_im, val_im)
    end)
    child_iomaps_cell = Cell(@computation begin col_im, val_im = projected[]; Any[col_im, val_im] end)

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation begin
            col_im, val_im = projected[]
            SyntaxDocument[col_im.output, _kw("=", p.keyword), val_im.output]
        end);
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlUpdateAssignmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlUpdateAssignmentToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
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

@projection UntrackedCell struct SqlUpdateStatementToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
    plain::StyleText = get_sql_style(nothing, :plain_text)
end

function print_document(p::SqlUpdateStatementToSyntaxNode, recursion, stmt::SqlUpdateStatement, ctx)
    projected = Cell(@computation begin
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
    child_iomaps_cell = Cell(@computation begin
        table_im, assign_ims, where_im = projected[]
        where_im === nothing ? Any[table_im; assign_ims] : Any[table_im; assign_ims; where_im]
    end)

    assignments_body = _comma_node(() -> begin
        _, assign_ims, _ = projected[]
        SyntaxDocument[a.output for a in assign_ims]
    end, p.plain)

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(stmt, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation begin
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
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, stmt, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlUpdateStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    nassign = length(iomap.input.assignments)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
    @reference_case reference begin
        ∅ => @reference ::SqlUpdateStatement
        ::SyntaxNode.children[2].rest... => begin
            child = iomap.child_iomaps[1]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlUpdateStatement.table.^(inner)
        end
        ::SyntaxNode.children[6].rest... => begin
            nassign = length(iomap.input.assignments)
            cims = iomap.child_iomaps
            length(cims) < 2 + nassign && return make_introduced_reference(p, iomap, reference)
            child = cims[2 + nassign]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlUpdateStatement.where_clause::SqlWhereClause.condition.^(inner)
        end
        ::SyntaxNode.children{outer_s:_}.children{t:u}.rest... => begin
            outer_i = outer_s + 1
            outer_i != 4 && return make_introduced_reference(p, iomap, reference)
            child_i = t + 1
            cims = iomap.child_iomaps
            cim_i = 1 + child_i
            1 <= cim_i <= length(cims) || return make_introduced_reference(p, iomap, reference)
            child = cims[cim_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlUpdateStatement.assignments::CellVector[child_i].^(inner)
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlUpdateStatementToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlUpdateStatementToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlColumnDefinitionToSyntaxNode ───────────────────────────────────────────
# Renders `<column-name> <data-type>` inside a CREATE TABLE column list.
# children[1] = column_name (projected); children[2] = data-type leaf (a plain
# String on the document, so it has no projected child of its own).

@projection UntrackedCell struct SqlColumnDefinitionToSyntaxNode
    type::StyleText = get_sql_style(nothing, :plain_text)
end

function print_document(p::SqlColumnDefinitionToSyntaxNode, recursion, doc::SqlColumnDefinition, ctx)
    col_im = Cell(@computation(print_document(recursion, recursion, doc.column_name,
                                        make_child_context(ctx, FieldReferenceStep("column_name")))))
    child_iomaps_cell = Cell(@computation Any[col_im[]])

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation(SyntaxDocument[
            col_im[].output,
            SyntaxLeaf(TextString(() -> doc.data_type, p.type))]));
        sep=TextString(" ", p.type.font, p.type.color),
        paths...)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlColumnDefinitionToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlColumnDefinitionToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
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

@projection UntrackedCell struct SqlCreateTableStatementToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
    plain::StyleText = get_sql_style(nothing, :plain_text)
end

function print_document(p::SqlCreateTableStatementToSyntaxNode, recursion, stmt::SqlCreateTableStatement, ctx)
    projected = Cell(@computation begin
        table_im = print_document(recursion, recursion, stmt.table_name,
                                    make_child_context(ctx, FieldReferenceStep("table_name")))
        col_ims = [print_document(recursion, recursion, c,
                                    make_child_context(ctx, FieldReferenceStep("columns"), ElementReferenceStep(i)))
                   for (i, c) in enumerate(stmt.columns)]
        (table_im, col_ims)
    end)
    child_iomaps_cell = Cell(@computation begin
        table_im, col_ims = projected[]
        Any[table_im; col_ims]
    end)

    columns_body = SyntaxNode(() -> begin
        _, col_ims = projected[]
        SyntaxDocument[c.output for c in col_ims]
    end; open = TextString("(", p.plain), close = TextString(")", p.plain), sep = TextString(",", p.plain),
       indentation = 1)

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(stmt, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation begin
            table_im, _ = projected[]
            SyntaxDocument[_kw("CREATE", p.keyword),
                           _kw("TABLE", p.keyword),
                           table_im.output,
                           columns_body]
        end);
        close=TextString(";", p.punctuation.font, p.punctuation.color),
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, stmt, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlCreateTableStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
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
            outer_i != 4 && return make_introduced_reference(p, iomap, reference)
            child_i = t + 1
            cims = iomap.child_iomaps
            cim_i = 1 + child_i
            1 <= cim_i <= length(cims) || return make_introduced_reference(p, iomap, reference)
            child = cims[cim_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SqlCreateTableStatement.columns::CellVector[child_i].^(inner)
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlCreateTableStatementToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlCreateTableStatementToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlCreateSchemaStatementToSyntaxNode ──────────────────────────────────────
#
# Output shape (top node sep=" ", close=";"):  CREATE SCHEMA name;
# The schema name is a plain String on the document (no projected child), so the
# statement has no child iomaps; only whole-statement (∅) selection is mapped.

@projection UntrackedCell struct SqlCreateSchemaStatementToSyntaxNode
    keyword::StyleText = get_sql_style(nothing, :keyword_text)
    name::StyleFont = _get_sql_font(nothing)
    punctuation::StyleText = get_sql_style(nothing, :punctuation_text)
    name_style::StyleText = get_sql_style(nothing, :name_text)
end

function print_document(p::SqlCreateSchemaStatementToSyntaxNode, recursion, stmt::SqlCreateSchemaStatement, ctx)
    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(stmt, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation(SyntaxDocument[
            _kw("CREATE", p.keyword),
            _kw("SCHEMA", p.keyword),
            SyntaxLeaf(TextString(() -> stmt.schema_name, p.name_style.font, p.name_style.color))]));
        close=TextString(";", p.punctuation.font, p.punctuation.color),
        sep=TextString(" ", p.punctuation.font, p.punctuation.color),
        paths...)

    iomap = ChildrenIoMap(p, stmt, node, Cell(@computation Any[]))
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlCreateSchemaStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
    end
end

function map_reference_backward(p::SqlCreateSchemaStatementToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlCreateSchemaStatement
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlCreateSchemaStatementToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlCreateSchemaStatementToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── SqlStatementListToSyntaxNode ──────────────────────────────────────────────
#
# Renders an ordered statement list, blank-line separated, with every statement
# closed by `;` so that the printed list reads back as the same list. A DDL
# statement prints its own `;`, and children[i] is statements[i]. Any other
# statement is wrapped in a node whose `close` is the `;`, and children[i].children[1]
# is statements[i].

@projection UntrackedCell struct SqlStatementListToSyntaxNode
    name::StyleFont = _get_sql_font(nothing)
    plain::StyleText = get_sql_style(nothing, :plain_text)
end

_has_own_semicolon(statement) = statement isa Union{SqlCreateTableStatement, SqlCreateSchemaStatement}

_close_statement(p::SqlStatementListToSyntaxNode, im) =
    _has_own_semicolon(get_iomap_input(im)) ? im.output :
        SyntaxNode(SyntaxDocument[im.output]; close=TextString(";", p.plain.font, p.plain.color))

# The path inside a statement that the list closed, from the path inside the node
# that closes it: the node is the whole statement, and its one child is the
# statement. A caret on the `;` has no position in the statement.
_get_closed_statement_path(path) = @reference_case path begin
    ∅ => path
    ::SyntaxNode.children[1].inner... => inner
end

function print_document(p::SqlStatementListToSyntaxNode, recursion, doc::SqlStatementList, ctx)
    stmt_ims = Cell(@computation([
        print_document(recursion, recursion, s, make_child_context(ctx, ElementReferenceStep(i)))
        for (i, s) in enumerate(doc.statements)]))
    child_iomaps_cell = Cell(@computation Any[im for im in stmt_ims[]])

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    node = SyntaxNode(
        CellVector(@computation SyntaxDocument[_close_statement(p, im) for im in stmt_ims[]]);
        sep=TextString("\n\n", p.plain.font, p.plain.color),
        paths...)

    iomap = ChildrenIoMap(p, doc, node, child_iomaps_cell)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::SqlStatementListToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
        ::SqlStatementList.statements{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps
            1 <= child_i <= length(cims) || return nothing
            child = cims[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            _has_own_semicolon(get_iomap_input(child)) ?
                @reference(::SyntaxNode.children::CellVector[child_i].^(inner)) :
                @reference(::SyntaxNode.children::CellVector[child_i]::SyntaxNode.children::CellVector[1].^(inner))
        end
    end
end

function map_reference_backward(p::SqlStatementListToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SqlStatementList
        ::SyntaxNode.children{s:_}.rest... => begin
            child_i = s + 1
            cims = iomap.child_iomaps
            1 <= child_i <= length(cims) || return make_introduced_reference(p, iomap, reference)
            child = cims[child_i]
            path = _has_own_semicolon(get_iomap_input(child)) ? rest : _get_closed_statement_path(rest)
            path === nothing && return make_introduced_reference(p, iomap, reference)
            inner = map_reference_backward(child.projection, child, path)
            inner === nothing && return nothing
            @reference ::SqlStatementList.statements::CellVector[child_i].^(inner)
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::SqlStatementListToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

read_intent(::SqlStatementListToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

# ── Compound constructor ──────────────────────────────────────────────────────

# The projection of the whole domain: one rule per document type. The builder
# gives each projection the style of its role with `get_sql_style`, from
# `theme`, a `SqlTheme` scaled or not, or the default styles for `nothing`;
# `syntax_theme` styles the insertion and the empty placeholder, which are the
# syntax slice's.

function SqlToSyntax(; theme = nothing, syntax_theme = nothing)
    get_style(name) = get_sql_style(theme, name)
    leaf_plain_style = (style = get_style(:plain_text),)
    leaf_name_style = (style = get_style(:name_text),)
    keyword_style = (keyword = get_style(:keyword_text),)
    clause_styles = (keyword = get_style(:keyword_text), punctuation = get_style(:punctuation_text))
    clause_plain_styles = (keyword = get_style(:keyword_text), punctuation = get_style(:punctuation_text),
                           plain = get_style(:plain_text))
    item_styles = (keyword = get_style(:keyword_text), name = _get_sql_font(theme),
                  punctuation = get_style(:punctuation_text), plain = get_style(:plain_text))
    jt = SqlJoinTypeToSyntaxLeaf(; style = get_style(:keyword_text))
    TypeDispatchingProjection(
        SqlInsertion            => SqlInsertionToSyntaxLeaf(; theme = syntax_theme),
        SqlNothing              => InsertionNothingToSyntaxLeaf(; theme = syntax_theme),
        SqlSelectStatement      => SqlSelectStatementToSyntaxNode(; keyword_style...),
        SqlSelectClause         => SqlSelectClauseToSyntaxNode(; clause_plain_styles...),
        SqlFromClause           => SqlFromClauseToSyntaxNode(; clause_plain_styles...),
        SqlWhereClause          => SqlWhereClauseToSyntaxNode(; clause_styles...),
        SqlSelectItem           => SqlSelectItemToSyntaxNode(; item_styles...),
        SqlAllColumns           => SqlAllColumnsToSyntaxLeaf(; leaf_plain_style...),
        SqlColumnReference      => SqlColumnReferenceToSyntaxLeaf(; leaf_plain_style...),
        SqlColumnName           => SqlColumnNameToSyntaxLeaf(; leaf_plain_style...),
        SqlTableName            => SqlTableNameToSyntaxLeaf(; leaf_name_style...),
        SqlTableExpression      => SqlTableExpressionToSyntaxLeaf(; leaf_name_style...),
        SqlSubqueryFromItem     => SqlSubqueryFromItemToSyntaxNode(; item_styles...),
        SqlFromItem             => SqlFromItemToSyntaxNode(; clause_styles...),
        SqlJoinedFromItem       => SqlJoinedFromItemToSyntaxNode(; clause_styles...),
        SqlJoinOnCondition      => SqlJoinOnConditionToSyntaxNode(; clause_styles...),
        SqlJoinUsingCondition   => SqlJoinUsingConditionToSyntaxNode(; clause_styles...),
        SqlWhereFilterCondition => SqlWhereFilterConditionToSyntaxNode(; keyword_style...),
        SqlInnerJoin            => jt,
        SqlLeftOuterJoin        => jt,
        SqlRightOuterJoin       => jt,
        SqlFullOuterJoin        => jt,
        SqlCrossJoin            => jt,
        SqlScalarValue          => SqlScalarValueToSyntaxLeaf(; leaf_plain_style...),
        SqlRawExpression        => SqlRawExpressionToSyntaxLeaf(; leaf_plain_style...),
        SqlRawCondition         => SqlRawConditionToSyntaxLeaf(; leaf_plain_style...),
        SqlComparison           => SqlComparisonToSyntaxNode(; clause_styles...),
        SqlAnd                  => SqlBooleanBinaryToSyntaxNode("AND"; theme),
        SqlOr                   => SqlBooleanBinaryToSyntaxNode("OR"; theme),
        SqlNot                  => SqlNotToSyntaxNode(; clause_styles...),
        SqlInsertStatement      => SqlInsertStatementToSyntaxNode(; clause_plain_styles...),
        SqlUpdateAssignment     => SqlUpdateAssignmentToSyntaxNode(; clause_styles...),
        SqlUpdateStatement      => SqlUpdateStatementToSyntaxNode(; clause_plain_styles...),
        SqlColumnDefinition     => SqlColumnDefinitionToSyntaxNode(; type = get_style(:plain_text)),
        SqlCreateTableStatement => SqlCreateTableStatementToSyntaxNode(; clause_plain_styles...),
        SqlCreateSchemaStatement => SqlCreateSchemaStatementToSyntaxNode(; keyword = get_style(:keyword_text),
                                                                           name = _get_sql_font(theme),
                                                                           punctuation = get_style(:punctuation_text),
                                                                           name_style = get_style(:name_text)),
        SqlStatementList        => SqlStatementListToSyntaxNode(; name = _get_sql_font(theme),
                                                                  plain = get_style(:plain_text)),
    )
end

# ── The SQL source insertion ────────────────────────────────────────────────

# Commit SQL source by parsing it; partial / invalid source can't commit.
function _sql_commit(value::AbstractString)
    isempty(strip(value)) && return nothing
    try
        parse_sql_text(value)
    catch
        nothing
    end
end

"""
    SqlInsertionToSyntaxLeaf(; theme = nothing)

A SQL source insertion, committing `value` via `parse_sql_text`; the buffer is
green when it parses as a complete statement, red otherwise.
"""
SqlInsertionToSyntaxLeaf(; theme = nothing) =
    InsertionToSyntaxLeaf((ins, text) -> _sql_commit(text); completion = parse_completion(parse_sql_text), theme)

# ── Natural-format registration ─────────────────────────────────────────────
# SQL's seams for import_document / export_document / read+write_document_file.
make_document_seed(::Val{:sql}) = SqlInsertion()

# ── What this domain's natural notation is ──────────────────────────────────
# One statement: the rung it starts at and how to build it, the format it is
# written in, the extension that names the format back, and how to read that text
# in again. Runtime state, so `__init__` rather than a top-level call.

function __init__()
    register_natural_domain!(SqlDocument;
                             rung      = :syntax,
                             make      = (; appearance) -> SqlToSyntax(;
                                 theme = get_scaled_theme!(appearance, SqlTheme),
                                 syntax_theme = get_scaled_theme!(appearance, SyntaxTheme)),
                             format    = :sql,
                             extension = ".sql",
                             parse     = parse_sql_text)

    register_file_document_type!(".sql", SqlFile)
end
