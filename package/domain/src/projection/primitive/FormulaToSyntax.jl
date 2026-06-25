"""
    FormulaToSyntaxModule

Formula → Syntax projection, composed with the Julia projection so a formula
body (a mix of `JuliaDocument` nodes and `FormulaReference`s) renders through one
shared `recursion`:

- `FormulaReference` → `SyntaxLeaf` whose value is `() -> reference.target.name`,
  coloured as a link. Reactive, so it tracks renames.
- `FormulaFormula` → `SyntaxNode` with three layouts selected by the formula's
  `display_mode` cell (`:code` / `:result` / `:both`).
- `FormulaEnvironment` → `SyntaxNode`, one formula per line.

Mappers follow the School-A peel-and-delegate pattern (see the tutorial and
documentation/projection-system.md): each node peels the one step it owns and delegates
the tail through the stored child IO maps. `FormulaToSyntax()` merges the Julia
type-dispatch table with the Formula entries into a single
`TypeDispatchingProjection` (callers wrap it once in `RecursiveProjection`, as
with `JuliaToSyntax`).
"""
module FormulaToSyntaxModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_printer_recurse, projection_read,
                              map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..FormulaModule: FormulaDocument, FormulaInsertion, FormulaReference,
                        FormulaFormula, FormulaEnvironment
import ..TextModule: TextString
import ..FontModule: StyleFont, font_ubuntu_monospace_regular_24, font_ubuntu_monospace_bold_24
import ..ColorModule: StyleColor, color_default, color_solarized_blue, color_solarized_cyan,
                      color_solarized_green, color_solarized_magenta, color_solarized_gray,
                      color_solarized_violet
import ..StyleTextModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..IoMapApiModule: IoMap
import ..ReferenceModule: ConcreteReferencePath, ElementReference, PositionReference,
                          RangeReference, FieldReference, ProjectionReference,
                          ReferencePath, EmptyReferencePath, skip_type_checkpoints
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..PrinterContextModule: child_context
import ..JuliaToSyntaxModule: JuliaToSyntax

export FormulaInsertionToSyntaxLeaf, FormulaReferenceToSyntaxLeaf,
       FormulaFormulaToSyntaxNode, FormulaEnvironmentToSyntaxNode, FormulaToSyntax

# ── Leaf helpers ─────────────────────────────────────────────────────────────

_empty(font) = TextString("", font, color_default)

# ── FormulaInsertionToSyntaxLeaf ───────────────────────────────────────────────
#
# The "insert formula" placeholder. A projection-introduced leaf with no editable
# input value, so the default forward mapper (proj-unwrapping) is correct.

@projection struct FormulaInsertionToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)
end

function projection_print(p::FormulaInsertionToSyntaxLeaf, recursion, b::FormulaInsertion, ctx)
    SimpleIoMap(p, b, SyntaxLeaf(
        TextString("insert formula", p.style);
        selection=getfield(b, :selection)))
end

# ── FormulaReferenceToSyntaxLeaf ───────────────────────────────────────────────
#
# Renders the referenced formula's *current* name, read reactively so a rename of
# the target updates every reference. The displayed name is derived from the
# target, not editable here, so the leaf has no input value mapping (the cursor
# selects the whole reference).

@projection struct FormulaReferenceToSyntaxLeaf
    style::StyleText = StyleText(font_ubuntu_monospace_bold_24, color_solarized_violet)
end

function projection_print(p::FormulaReferenceToSyntaxLeaf, recursion, r::FormulaReference, ctx)
    SimpleIoMap(p, r, SyntaxLeaf(
        TextString(() -> begin
            t = r.target
            t isa FormulaFormula ? t.name : "#REF!"
        end, p.style);
        selection=getfield(r, :selection)))
end

# ── FormulaFormulaToSyntaxNode ─────────────────────────────────────────────────
#
# Three layouts selected by the formula's `display_mode` cell:
#   :code   → recurse into `code`                         → children [code]
#   :result → recurse into `result`                       → children [result]
#   :both   → name " = " code " ⇒ " result                → children [code, result]
#
# The `code` child is recursed through the shared `recursion` (it is a mix of
# Julia nodes and FormulaReferences); the `result` is a computed `TextText`, so it
# is flattened into a self-contained result leaf rather than recursed (mirrors how
# EvaluatorForm renders its result). Only `code` therefore needs School-A
# delegation; its output child index depends on the mode.

@projection struct FormulaFormulaToSyntaxNode
    name::StyleText = StyleText(font_ubuntu_monospace_bold_24, color_solarized_blue)
    op::StyleText   = StyleText(font_ubuntu_monospace_regular_24, color_solarized_gray)
    # The result run shares the op font but is coloured distinctly (green).
    result::StyleText = StyleText(font_ubuntu_monospace_regular_24, color_solarized_green)
end

# Flatten a result TextText into a single rendered string.
function _result_to_string(result)
    buf = IOBuffer()
    for span in result.elements
        span isa TextString && print(buf, span.content)
    end
    String(take!(buf))
end

function projection_print(p::FormulaFormulaToSyntaxNode, recursion, f::FormulaFormula, ctx)
    code_ref = child_context(ctx, @reference ^(ctx.reference).code)
    code_iomap = Cell(() -> projection_printer_recurse(recursion, f.code, code_ref))

    # The name leaf displays the formula name; renaming is a structural
    # operation, not character editing here, so it carries no input mapping.
    name_leaf = SyntaxLeaf(TextString(() -> f.name, p.name))
    eq_leaf = SyntaxLeaf(
        TextString("=", p.op);
        open=TextString(" ", p.op.font, color_default),
        close=TextString(" ", p.op.font, color_default))
    arrow_leaf = SyntaxLeaf(
        TextString("⇒", p.op);
        open=TextString(" ", p.op.font, color_default),
        close=TextString(" ", p.op.font, color_default))
    result_leaf = SyntaxLeaf(TextString(() -> _result_to_string(f.result), p.result))

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = hasfield(typeof(f), :selection) ? f.selection : nothing
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)
    node = SyntaxNode(
        CellVector(() -> begin
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
        selection=sel)
    iomap = ChildrenIoMap(p, f, node, Cell(() -> IoMap[code_iomap[]]))
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
        ∅ => @reference()
        code.rest... => begin
            idx = _code_index(f)
            idx === nothing && return nothing
            child = iomap.child_iomaps[][1]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing ? nothing : (@reference children[idx].^(inner))
        end
        _ => @invoke map_reference_forward(p::Projection, iomap, reference)
    end
end

function map_reference_backward(p::FormulaFormulaToSyntaxNode, iomap::ChildrenIoMap, reference)
    f = iomap.input
    idx = _code_index(f)
    @reference_case reference begin
        ∅ => @reference()
        children{s:_}.rest... => begin
            child_i = s + 1
            if idx !== nothing && child_i == idx
                # This child is the code sub-tree: delegate to its mapper.
                child = iomap.child_iomaps[][1]
                inner = map_reference_backward(child.projection, child, rest)
                inner === nothing ? nothing : (@reference code.^(inner))
            else
                # Projection-introduced child (name, "=", "⇒", result): wrap as
                # structural reference so the roundtrip can place a cursor.
                @invoke map_reference_backward(p::Projection, iomap, reference)
            end
        end
        _ => @invoke map_reference_backward(p::Projection, iomap, reference)
    end
end

# ── FormulaEnvironmentToSyntaxNode ─────────────────────────────────────────────
#
# A plain list — one formula per line — like BookmarkList in the tutorial.

@projection struct FormulaEnvironmentToSyntaxNode
    font::StyleFont = font_ubuntu_monospace_regular_24
end

function projection_print(p::FormulaEnvironmentToSyntaxNode, recursion, e::FormulaEnvironment, ctx)
    child_iomaps = Cell(() ->
        [projection_printer_recurse(recursion, e.formulas[i],
             child_context(ctx, @reference ^(ctx.reference).formulas[i]))
         for i in 1:length(e.formulas)])

    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = hasfield(typeof(e), :selection) ? e.selection : nothing
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)
    node = SyntaxNode(
        CellVector(() -> SyntaxDocument[im.output for im in child_iomaps[]]);
        sep=TextString("\n", p.font, color_default),
        selection=sel)
    iomap = ChildrenIoMap(p, e, node, child_iomaps)
    iomap_cell[] = iomap
    iomap
end

function map_reference_forward(p::FormulaEnvironmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        formulas{s:_}.rest... => begin
            child_i = s + 1
            ims = iomap.child_iomaps[]
            (child_i < 1 || child_i > length(ims)) && return nothing
            child = ims[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing ? nothing : (@reference children[child_i].^(inner))
        end
        _ => @invoke map_reference_forward(p::Projection, iomap, reference)
    end
end

function map_reference_backward(p::FormulaEnvironmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference()
        children{s:_}.rest... => begin
            child_i = s + 1
            ims = iomap.child_iomaps[]
            (child_i < 1 || child_i > length(ims)) && return nothing
            child = ims[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing ? nothing : (@reference formulas[child_i].^(inner))
        end
        _ => @invoke map_reference_backward(p::Projection, iomap, reference)
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
function FormulaToSyntax()
    julia = JuliaToSyntax()  # TypeDispatchingProjection
    pairs = copy(julia.dispatch)
    push!(pairs, FormulaInsertion   => FormulaInsertionToSyntaxLeaf())
    push!(pairs, FormulaReference    => FormulaReferenceToSyntaxLeaf())
    push!(pairs, FormulaFormula      => FormulaFormulaToSyntaxNode())
    push!(pairs, FormulaEnvironment  => FormulaEnvironmentToSyntaxNode())
    TypeDispatchingProjection(pairs)
end

end # module
