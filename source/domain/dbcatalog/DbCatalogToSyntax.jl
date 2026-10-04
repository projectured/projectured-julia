# Fragment of `DbCatalogModule`.
#
# DbCatalog → SyntaxDocument projection. Maps the catalog hierarchy to syntax
# tree shapes with keyword grouping nodes:
#
#     DbCatalogRdbms    → entity " host:port" → keyword " Databases"
#     DbCatalogDatabase → entity " dbname"    → keyword " Schemas"
#     DbCatalogSchema   → entity " schema"    → keyword " Tables"
#     DbCatalogTable    → entity " table"     → keyword " Columns"
#     DbCatalogColumn   → SyntaxLeaf " column::type"
#
# Each non-leaf entity node is collapsible and contains a single keyword child,
# whose own children are the projected items:
#   entity_node  (ind=-1, open=" name"):    collapsible, marker-eligible
#     keyword_node (ind=-1, open=" Keyword"): collapsible, marker-eligible;
#       children = projected items
#
# Using `indentation = -1` avoids trailing newlines that create blank lines,
# while still rendering children with `\\n + indent`.
#
# Selection mapping (School A — delegate child tails through stored child IO maps):
#   Input:  <field>[i].rest        (e.g. databases[2].child_path)
#   Output: children[1].children[i].delegated(rest)
# The two levels correspond to: entity_node → keyword_node, whose children
# are the actual items.
# ── DbCatalogColumnToSyntaxLeaf ───────────────────────────────────────────────

@projection UntrackedCell struct DbCatalogColumnToSyntaxLeaf
    style::StyleText = get_db_catalog_style(nothing, :column_text)
end

function print_document(p::DbCatalogColumnToSyntaxLeaf, recursion, col::DbCatalogColumn, ctx)
    paths = make_output_path_cells(col, path -> map_reference_forward(p, nothing, path))
    SimpleIoMap(p, col, SyntaxLeaf(
        TextString(() -> " " * col.name * "::" * col.data_type, p.style);
        paths...))
end

function map_reference_forward(p::DbCatalogColumnToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        ∅ => EmptyReference()
        proj(^(p), inner) => inner
    end
end

function map_reference_backward(p::DbCatalogColumnToSyntaxLeaf, iomap, reference)
    reference isa EmptyReference && return EmptyReference()
    reference === nothing && return nothing
    # The input type, not `iomap.input`: the printer calls the forward mapper with a
    # `nothing` iomap, so this pair must not depend on one.
    make_introduced_reference(p, DbCatalogColumn, reference)
end

function read_intent(p::DbCatalogColumnToSyntaxLeaf, iomap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing && return nothing
    make_path_operation(op, result)
end

# ── Shared reference mapping helpers ─────────────────────────────────────────
#
# All non-leaf catalog projections share the same 2-level output shape:
#   entity_node → keyword_node → children
# so the reference mapping logic is factored into shared helpers parameterised
# by the input-domain children field name ("databases", "schemas", etc.). The
# forward helper is written by hand, not as one `@reference_case`, because a
# pattern names its fields when it is written and this field name is a value.
# A part that the entity node printed (its name, a keyword, the layout) is named
# by the projection's own introduced step, which holds its path in the output.

"""
Forward: `<field_name>[i].rest → children[1].children[i].delegated(rest)`
(entity → keyword group `children[1]` → item `children[i]`).
"""
function _catalog_forward_ref(p, iomap::ChildrenIoMap, reference, field_name::String)
    reference = reference
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return introduced
    h = reference.head
    # Match: field_name{s:e}.rest (FieldReferenceStep + RangeReferenceStep + tail)
    h isa FieldReferenceStep && h.name == field_name || return nothing
    rest = reference.tail
    rest isa ConcreteReference || return nothing
    h2 = rest.head
    h2 isa RangeReferenceStep || return nothing
    child_i = h2.start + 1
    child_rest = rest.tail
    iomaps = iomap.child_iomaps
    1 <= child_i <= length(iomaps) || return nothing
    child = iomaps[child_i]
    inner = map_reference_forward(child.projection, child, child_rest)
    inner === nothing && return nothing
    @reference ::SyntaxNode.children[1].children[child_i].^(inner)
end

"""
Backward: `children[1].children[i].rest → <field_name>[i].delegated(rest)`
Peels 2 levels of children (keyword group, then the actual item).
"""
function _catalog_backward_ref(p, iomap::ChildrenIoMap, reference, field_name::String)
    reference isa EmptyReference && return EmptyReference()
    # Peel: children[1] (the keyword group), then children[i] (the item).
    @reference_case reference begin
        ::SyntaxNode.children[1].rest1... => begin
            @reference_case rest1 begin
                ::SyntaxNode.children{s:e}.rest2... => begin
                    child_i = s + 1
                    iomaps = iomap.child_iomaps
                    1 <= child_i <= length(iomaps) ||
                        return make_introduced_reference(p, iomap, reference)
                    child = iomaps[child_i]
                    inner = map_reference_backward(child.projection, child, rest2)
                    inner === nothing && return nothing
                    ConcreteReference(
                        Cell(FieldReferenceStep(field_name)),
                        Cell(ConcreteReference(
                            Cell(ElementReferenceStep(child_i)),
                            Cell(inner))))
                end
                __ => make_introduced_reference(p, iomap, reference)
            end
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

"""
Reader for `ReplaceSelectionOperation`: the backward map, which names a
structural position (an entity name, a keyword label, whitespace) by the
projection's own introduced step.
"""
function _catalog_read_selection(p, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing ? nothing : make_path_operation(op, result)
end

# ── Lazy-expansion helper ─────────────────────────────────────────────────────
#
# A catalog level's child collection is a *lazy* `CellVector` whose thunk queries
# the database only when forced (see `DatabaseInstanceToDbCatalog`). To support
# lazy expansion, an entity node starts **collapsed** unless its children are
# *already materialized* — so the initial render queries nothing, and expanding a
# node (flipping `collapsed`) is what first forces its child query, which then
# projects into syntax and widgets.
#
# "Already materialized" is read **without forcing**: the `CellVector`'s backing
# `elements` cell is a computed cell that becomes `valid` only after it has been
# evaluated (the query ran) and stays `valid` until invalidated. A value-backed
# (eagerly built) collection is `valid` from construction, so non-lazy children
# render expanded. A pre-forced lazy collection (e.g. via `explore_dbcatalog!`)
# also reads `valid`, so only the explored path opens up front.
function _children_realized(children)
    children isa CellVector || return true
    is_cell_up_to_date(getfield(children, :elements))
end

# ── Shared node builder ───────────────────────────────────────────────────────
#
# Every non-leaf catalog level produces the shape:
#   entity_node  (ind=-1, open=" name"):     ← the named entity; always expanded
#     keyword_node (ind=-1, open=" Keyword"): ← a collapsible *kind-of-child*
#       child[1..n] = projected child outputs ← its items, held directly
#
# The keyword node is its own collapsible group (a "kind" of child — Columns,
# and in future Indexes, etc. — sit side by side as sibling keyword groups under
# one entity). It is **collapsed unless its child collection is already
# materialized**, so the initial render queries nothing and expanding the group
# is what first forces its lazy `CellVector` (the DB query), which then projects
# into syntax and widgets. The entity node merely groups its keyword(s) and stays
# expanded (the user can still fold it via its header).
#
# Using ind=-1 (rather than a positive value) enters the newline branch
# (children get \n + indent) but skips the trailing \n + indent that would
# otherwise create blank lines between sibling items.
#
# Selection is wired via the deferred-iomap trick: the entity_node's selection
# cell reads from the input document's selection and maps it forward through
# this projection's own map_reference_forward. The iomap_cell is returned so
# the caller can set it after building the ChildrenIoMap.

function _catalog_syntax_node(p, recursion, ctx, input_doc,
                              name_style::StyleText, keyword_style::StyleText,
                              keyword::String, label, children)
    child_iomaps = Cell(@computation begin
        [print_child(recursion, elem, make_child_context(ctx, ElementReferenceStep(i)))
         for (i, elem) in enumerate(children)]
    end)

    # The keyword group holds the projected items directly and is the lazy /
    # collapsible unit. Collapsed until its child collection is materialized.
    keyword_node = SyntaxNode(
        CellVector(@computation SyntaxDocument[im.output for im in child_iomaps[]]);
        open=TextString(" " * keyword, keyword_style),
        indentation=-1,
        collapsed=Cell(!_children_realized(children)))

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(input_doc, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    # The entity groups its keyword(s); it stays expanded (foldable by the user).
    entity_node = SyntaxNode(
        CellVector(Cell[Cell(keyword_node)]);
        open=TextString(label, name_style),
        indentation=-1,
        paths...)

    entity_node, child_iomaps, iomap_cell
end

# ── DbCatalogTableToSyntaxNode ────────────────────────────────────────────────

@projection UntrackedCell struct DbCatalogTableToSyntaxNode
    name::StyleText    = get_db_catalog_style(nothing, :table_text)
    keyword::StyleText = get_db_catalog_style(nothing, :keyword_text)
end

function print_document(p::DbCatalogTableToSyntaxNode, recursion, table::DbCatalogTable, ctx)
    node, child_iomaps, iomap_cell = _catalog_syntax_node(
        p, recursion, ctx, table, p.name, p.keyword,
        "Columns", () -> " " * table.name, table.columns)
    iomap = ChildrenIoMap(p, table, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

map_reference_forward(p::DbCatalogTableToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_forward_ref(p, iomap, ref, "columns")
map_reference_backward(p::DbCatalogTableToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_backward_ref(p, iomap, ref, "columns")
read_intent(p::DbCatalogTableToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation) =
    _catalog_read_selection(p, iomap, op)

# ── DbCatalogSchemaToSyntaxNode ───────────────────────────────────────────────

@projection UntrackedCell struct DbCatalogSchemaToSyntaxNode
    name::StyleText    = get_db_catalog_style(nothing, :schema_text)
    keyword::StyleText = get_db_catalog_style(nothing, :keyword_text)
end

function print_document(p::DbCatalogSchemaToSyntaxNode, recursion, schema::DbCatalogSchema, ctx)
    node, child_iomaps, iomap_cell = _catalog_syntax_node(
        p, recursion, ctx, schema, p.name, p.keyword,
        "Tables", () -> " " * schema.name, schema.tables)
    iomap = ChildrenIoMap(p, schema, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

map_reference_forward(p::DbCatalogSchemaToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_forward_ref(p, iomap, ref, "tables")
map_reference_backward(p::DbCatalogSchemaToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_backward_ref(p, iomap, ref, "tables")
read_intent(p::DbCatalogSchemaToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation) =
    _catalog_read_selection(p, iomap, op)

# ── DbCatalogDatabaseToSyntaxNode ─────────────────────────────────────────────

@projection UntrackedCell struct DbCatalogDatabaseToSyntaxNode
    name::StyleText    = get_db_catalog_style(nothing, :database_text)
    keyword::StyleText = get_db_catalog_style(nothing, :keyword_text)
end

function print_document(p::DbCatalogDatabaseToSyntaxNode, recursion, db::DbCatalogDatabase, ctx)
    node, child_iomaps, iomap_cell = _catalog_syntax_node(
        p, recursion, ctx, db, p.name, p.keyword,
        "Schemas", () -> " " * db.name, db.schemas)
    iomap = ChildrenIoMap(p, db, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

map_reference_forward(p::DbCatalogDatabaseToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_forward_ref(p, iomap, ref, "schemas")
map_reference_backward(p::DbCatalogDatabaseToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_backward_ref(p, iomap, ref, "schemas")
read_intent(p::DbCatalogDatabaseToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation) =
    _catalog_read_selection(p, iomap, op)

# ── DbCatalogRdbmsToSyntaxNode ────────────────────────────────────────────────

@projection UntrackedCell struct DbCatalogRdbmsToSyntaxNode
    name::StyleText    = get_db_catalog_style(nothing, :database_text)
    keyword::StyleText = get_db_catalog_style(nothing, :keyword_text)
end

function print_document(p::DbCatalogRdbmsToSyntaxNode, recursion, rdbms::DbCatalogRdbms, ctx)
    node, child_iomaps, iomap_cell = _catalog_syntax_node(
        p, recursion, ctx, rdbms, p.name, p.keyword,
        "Databases", () -> " " * rdbms.host * ":" * string(rdbms.port), rdbms.databases)
    iomap = ChildrenIoMap(p, rdbms, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

map_reference_forward(p::DbCatalogRdbmsToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_forward_ref(p, iomap, ref, "databases")
map_reference_backward(p::DbCatalogRdbmsToSyntaxNode, iomap::ChildrenIoMap, ref) =
    _catalog_backward_ref(p, iomap, ref, "databases")
read_intent(p::DbCatalogRdbmsToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation) =
    _catalog_read_selection(p, iomap, op)

# ── Marker eligibility ──────────────────────────────────────────────────────────
#
# Entity nodes and keyword nodes carry their label in the `open` field.
# Body nodes (keyword_body) have no `open` label. This lets us mark exactly the
# collapsible named nodes — entities and keywords — while skipping body wrappers.
"""
    is_dbcatalog_marker_eligible(node) -> Bool

Predicate for `SyntaxToText(marker_eligible = …)` so the expand/collapse marker
lands on entity nodes and keyword nodes (which carry a label in `open`), but not
on body wrappers or column leaves.
"""
is_dbcatalog_marker_eligible(::SyntaxLeaf) = false
# Eligibility keys off the label alone (a present, non-empty `open`): entity and keyword
# nodes carry one, body/leaf nodes do not. Deliberately does NOT inspect
# `node.children` — a keyword group's children are a lazy `CellVector` whose
# length can't be read without forcing the database query, which would defeat
# lazy expansion.
is_dbcatalog_marker_eligible(node::SyntaxNode) =
    node.open !== nothing && !isempty(node.open.content::AbstractString)

# ── Compound constructor ──────────────────────────────────────────────────────

# The builder gives each projection the style of its role with
# `get_db_catalog_style`, from `theme`, a `DbCatalogTheme` scaled or not, or the
# default styles for `nothing`. The database and the RDBMS node take the same
# group of styles, built once.
function DbCatalogToSyntax(; theme = nothing)
    get_style(name) = get_db_catalog_style(theme, name)
    database_style = (name = get_style(:database_text), keyword = get_style(:keyword_text))
    TypeDispatchingProjection(
        DbCatalogRdbms      => DbCatalogRdbmsToSyntaxNode(; database_style...),
        DbCatalogDatabase   => DbCatalogDatabaseToSyntaxNode(; database_style...),
        DbCatalogSchema     => DbCatalogSchemaToSyntaxNode(; name = get_style(:schema_text),
                                                              keyword = get_style(:keyword_text)),
        DbCatalogTable      => DbCatalogTableToSyntaxNode(; name = get_style(:table_text),
                                                             keyword = get_style(:keyword_text)),
        DbCatalogColumn     => DbCatalogColumnToSyntaxLeaf(; style = get_style(:column_text)),
    )
end
