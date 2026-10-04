# Fragment of `FormulaModule`.
#
# Formula → Syntax projection, composed with the Julia projection so a formula
# body (a mix of `JuliaDocument` nodes and `FormulaReference`s) renders through one
# shared `recursion`:
#
# - `FormulaReference` → `SyntaxLeaf` whose value is `() -> reference.target.name`,
#   coloured as a link. Reactive, so it tracks renames.
# - `FormulaFormula` → `SyntaxNode` with three layouts selected by the formula's
#   `display_mode` cell (`:code` / `:result` / `:both`).
# - `FormulaEnvironment` → `SyntaxNode`, one formula per line.
#
# Mappers follow the School-A peel-and-delegate pattern (see the tutorial and
# package/kernel/doc/projection-system.md): each node peels the one step it owns and delegates
# the tail through the stored child IO maps. `FormulaToSyntax()` merges the Julia
# type-dispatch table with the Formula entries into a single
# `TypeDispatchingProjection` (callers wrap it once in `RecursiveProjection`, as
# with `JuliaToSyntax`).
# ── Leaf helpers ─────────────────────────────────────────────────────────────

_empty(font) = TextString("", font)

# ── FormulaInsertionToSyntaxLeaf ───────────────────────────────────────────────
#
# The "insert formula" placeholder. A projection-introduced leaf with no editable
# input value, so the default mappers are correct: the backward map names a caret
# on the text by the leaf's own introduced step, and the forward map answers the
# path in the leaf. Each leaf of this file maps its paths forward into cells
# of its own.

function _make_forward_path_leaf(p, input, make_leaf)
    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(input, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)
    iomap = SimpleIoMap(p, input, make_leaf(paths))
    iomap_cell[] = iomap
    iomap
end

@projection UntrackedCell struct FormulaInsertionToSyntaxLeaf
    style::StyleText = get_formula_style(nothing, :insertion_text)
end

print_document(p::FormulaInsertionToSyntaxLeaf, recursion, b::FormulaInsertion, ctx) =
    _make_forward_path_leaf(p, b,
        paths -> SyntaxLeaf(TextString("insert formula", p.style); paths...))

# ── FormulaReferenceToSyntaxLeaf ───────────────────────────────────────────────
#
# Renders the referenced formula's *current* name, read reactively so a rename of
# the target updates every reference. The displayed name is derived from the
# target, not editable here, so the leaf has no input value mapping (the cursor
# selects the whole reference).

@projection UntrackedCell struct FormulaReferenceToSyntaxLeaf
    style::StyleText = get_formula_style(nothing, :reference_text)
end

print_document(p::FormulaReferenceToSyntaxLeaf, recursion, r::FormulaReference, ctx) =
    _make_forward_path_leaf(p, r, paths -> SyntaxLeaf(
        TextString(() -> begin
            t = r.target
            t isa FormulaFormula ? t.name : "#REF!"
        end, p.style);
        paths...))

# ── FormulaFormulaToSyntaxNode ─────────────────────────────────────────────────
#
# Three layouts selected by the formula's `display_mode` cell:
#   :code   → recurse into `code`                         → children [code]
#   :result → recurse into `result`                       → children [result]
#   :both   → name " = " code " ⇒ " result                → children [code, result]
#
# The `code` child is recursed through the shared `recursion` (it is a mix of
# Julia nodes and FormulaReferences); the `result` is a computed `TextBlock`, so it
# is flattened into a self-contained result leaf rather than recursed (mirrors how
# EvaluatorForm renders its result). Only `code` therefore needs School-A
# delegation; its output child index depends on the mode.

@projection UntrackedCell struct FormulaFormulaToSyntaxNode
    name::StyleText = get_formula_style(nothing, :name_text)
    op::StyleText   = get_formula_style(nothing, :operator_text)
    # The result run shares the op font but is coloured distinctly (green).
    result::StyleText = get_formula_style(nothing, :result_text)
end

# Flatten a result TextBlock into a single rendered string.
function _result_to_string(result)
    buf = IOBuffer()
    for span in result.elements
        span isa TextString && print(buf, span.content)
    end
    String(take!(buf))
end

function print_document(p::FormulaFormulaToSyntaxNode, recursion, f::FormulaFormula, ctx)
    code_ref = make_child_context(ctx, f, @reference_step code)
    code_iomap = Cell(@computation print_child(recursion, f.code, code_ref))

    # The name leaf displays the formula name; renaming is a structural
    # operation, not character editing here, so it carries no input mapping.
    name_leaf = SyntaxLeaf(TextString(() -> f.name, p.name))
    eq_leaf = SyntaxLeaf(
        TextString("=", p.op);
        open=TextString(" ", p.op.font),
        close=TextString(" ", p.op.font))
    arrow_leaf = SyntaxLeaf(
        TextString("⇒", p.op);
        open=TextString(" ", p.op.font),
        close=TextString(" ", p.op.font))
    result_leaf = SyntaxLeaf(TextString(() -> _result_to_string(f.result), p.result))

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(f, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)
    node = SyntaxNode(
        CellVector(@computation begin
            mode = f.display_mode
            if mode === :code
                SyntaxDocument[code_iomap[].output]
            elseif mode === :result
                SyntaxDocument[result_leaf]
            else  # :both (default)
                SyntaxDocument[name_leaf, eq_leaf, code_iomap[].output,
                               arrow_leaf, result_leaf]
            end
        end);
        paths...)
    iomap = ChildrenIoMap(p, f, node, Cell(@computation IoMap[code_iomap[]]))
    iomap_cell[] = iomap
    iomap
end

# School A for `code`. Its output child index depends on the mode:
#   :code → children[1]
#   :both → children[3]   (after name + "=")
# (In :result mode `code` is not shown, so it has no output position.)
function _code_index(f::FormulaFormula)
    mode = f.display_mode
    mode === :code ? 1 : (mode === :result ? nothing : 3)
end

function map_reference_forward(p::FormulaFormulaToSyntaxNode, iomap::ChildrenIoMap, reference)
    f = iomap.input
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        ::FormulaFormula.code.rest... => begin
            idx = _code_index(f)
            idx === nothing && return nothing
            child = iomap.child_iomaps[1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing ? nothing : (@reference ::SyntaxNode.children::CellVector[idx].^(inner))
        end
        __ => @invoke map_reference_forward(p::Projection, iomap, reference)
    end
end

function map_reference_backward(p::FormulaFormulaToSyntaxNode, iomap::ChildrenIoMap, reference)
    f = iomap.input
    idx = _code_index(f)
    @reference_case reference begin
        ∅ => @reference ::FormulaFormula
        ::SyntaxNode.children{s:_}.rest... => begin
            child_i = s + 1
            if idx !== nothing && child_i == idx
                # This child is the code sub-tree: delegate to its mapper.
                child = iomap.child_iomaps[1]
                inner = map_reference_backward(child.projection, child, rest)
                inner === nothing ? nothing : (@reference ::FormulaFormula.code.^(inner))
            else
                # Projection-introduced child (name, "=", "⇒", result): wrap as
                # structural reference so the roundtrip can place a cursor.
                @invoke map_reference_backward(p::Projection, iomap, reference)
            end
        end
        __ => @invoke map_reference_backward(p::Projection, iomap, reference)
    end
end

# ── FormulaEnvironmentToSyntaxNode ─────────────────────────────────────────────
#
# A plain list — one formula per line — like BookmarkList in the tutorial.

@projection UntrackedCell struct FormulaEnvironmentToSyntaxNode
    font::StyleFont = get_formula_style(nothing, :plain_font)
end

function print_document(p::FormulaEnvironmentToSyntaxNode, recursion, e::FormulaEnvironment, ctx)
    child_iomaps = Cell(@computation([print_child(recursion, e.formulas[i],
             make_child_context(ctx, e, (@reference_step formulas), (@reference_step [i])))
         for i in 1:length(e.formulas)]))

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(e, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)
    node = SyntaxNode(
        CellVector(@computation SyntaxDocument[im.output for im in child_iomaps[]]);
        sep=TextString("\n", p.font),
        paths...)
    iomap = ChildrenIoMap(p, e, node, child_iomaps)
    iomap_cell[] = iomap
    iomap
end

function map_reference_forward(p::FormulaEnvironmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        ::FormulaEnvironment.formulas{s:_}.rest... => begin
            child_i = s + 1
            ims = iomap.child_iomaps
            (child_i < 1 || child_i > length(ims)) && return nothing
            child = ims[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing ? nothing : (@reference ::SyntaxNode.children::CellVector[child_i].^(inner))
        end
        __ => @invoke map_reference_forward(p::Projection, iomap, reference)
    end
end

function map_reference_backward(p::FormulaEnvironmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::FormulaEnvironment
        ::SyntaxNode.children{s:_}.rest... => begin
            child_i = s + 1
            ims = iomap.child_iomaps
            (child_i < 1 || child_i > length(ims)) && return nothing
            child = ims[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing ? nothing : (@reference ::FormulaEnvironment.formulas::CellVector[child_i].^(inner))
        end
        __ => @invoke map_reference_backward(p::Projection, iomap, reference)
    end
end

# ── FormulaToSyntax convenience constructor ────────────────────────────────────
#
# Merge the Julia type-dispatch table with the Formula entries into one
# TypeDispatchingProjection, wrapped once in RecursiveProjection, so the same
# `recursion` renders both kinds of node. This is also what lets a formula appear
# inside an otherwise-Julia AST.

# Returns a bare `TypeDispatchingProjection` (the convention used by
# JuliaToSyntax / JsonToSyntax / BookToSyntax); callers wrap it once in a
# `RecursiveProjection` so node projections can recurse children.
#
# The builder gives each projection the style of its role with
# `get_formula_style`, from `theme`, a `FormulaTheme` scaled or not, or the
# default styles for `nothing`; `julia_theme` and `syntax_theme` style the
# Julia nodes a formula's code is built from, through `JuliaToSyntax`.
function FormulaToSyntax(; theme = nothing, julia_theme = nothing, syntax_theme = nothing)
    get_style(name) = get_formula_style(theme, name)
    JuliaToSyntax(
        FormulaInsertion   => FormulaInsertionToSyntaxLeaf(; style = get_style(:insertion_text)),
        FormulaReference   => FormulaReferenceToSyntaxLeaf(; style = get_style(:reference_text)),
        FormulaFormula     => FormulaFormulaToSyntaxNode(; name = get_style(:name_text),
                                                            op = get_style(:operator_text),
                                                            result = get_style(:result_text)),
        FormulaEnvironment => FormulaEnvironmentToSyntaxNode(; font = get_style(:plain_font));
        theme = julia_theme, syntax_theme)
end
