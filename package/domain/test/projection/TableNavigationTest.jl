# ═══════════════════════════════════════════════════════════════════════════
# test/projection/TableNavigationTest.jl
#
# Grid navigation gestures for the WidgetTable → Graphics renderer (the single
# table abstraction).
#
# explore_table_selections(document, projection)
#   BFS over the tree-selection states reachable from Ctrl+Alt+Home (whole
#   table). At each state every navigation chord (arrows / Alt+arrows /
#   Shift/Ctrl+Space / Enter) is tried via read_intent; the resulting path is
#   re-applied, re-printed and the iomap walked. Returns (state_count, errors).
#
# Reference vocabulary on WidgetTable: whole cell = `rows[r][c]`, whole row =
# `rows[r]`, whole column = `column_headers[c]`, whole table = `∅`, in-cell
# cursor = `rows[r][c].<tail>`.
# ═══════════════════════════════════════════════════════════════════════════

# _wt_row / _wt_col / _wt_cell / _table_measure are defined in TableSelectionTest.jl
# (included into the same module just above this one).

function explore_table_selections(document, projection; onstate=nothing)
    nav_keys = [
        KeyDown(:up,    ModifierKeys()),
        KeyDown(:down,  ModifierKeys()),
        KeyDown(:left,  ModifierKeys()),
        KeyDown(:right, ModifierKeys()),
        KeyDown(:up,    ModifierKeys(alt=true)),
        KeyDown(:down,  ModifierKeys(alt=true)),
        KeyDown(:left,  ModifierKeys(alt=true)),
        KeyDown(:right, ModifierKeys(alt=true)),
        KeyDown(:space, ModifierKeys(shift=true)),
        KeyDown(:space, ModifierKeys(ctrl=true)),
        KeyDown(:return, ModifierKeys()),
    ]

    visited = Set{String}()
    errors  = String[]

    clear_selection!(document)
    iomap = try
        print_document(projection, document)
    catch e
        return (state_count=0, errors=["print_document failed: $e"])
    end

    op = try
        read_intent(projection, iomap, KeyDown(:home, ModifierKeys(ctrl=true, alt=true)))
    catch e
        return (state_count=0, errors=["Ctrl+Alt+Home failed: $e"])
    end
    op isa ReplaceSelectionOperation || return (state_count=0, errors=["Ctrl+Alt+Home returned $(typeof(op))"])

    queue = Any[op.path, _wt_cell(1, 1)]

    while !isempty(queue)
        path = popfirst!(queue)
        path_str = string(path)
        path_str in visited && continue
        push!(visited, path_str)
        errs_before = length(errors)

        clear_selection!(document)
        set_selection!(document, path)

        iomap = try
            print_document(projection, document)
        catch e
            msg = "reprint at [$path_str] failed: $e"
            push!(errors, msg)
            onstate === nothing || onstate(path, false, msg)
            continue
        end
        _walk!(iomap, Set{UInt64}(), errors)

        for key in nav_keys
            op = try
                read_intent(projection, iomap, key)
            catch e
                push!(errors, "reader error at [$path_str] with $key: $e")
                nothing
            end
            op isa ReplaceSelectionOperation || continue
            new_str = string(op.path)
            # Stay in structural space: an Enter into cell content is valid, but a
            # character cursor is not a tree-selection state. A whole-cell path is
            # `rows[r][c]` (two element steps then ∅); an in-cell cursor has more.
            _wt_is_structural(op.path) || continue
            new_str in visited && continue
            push!(queue, op.path)
        end

        if onstate !== nothing
            if length(errors) > errs_before
                onstate(path, false, errors[errs_before + 1])
            else
                onstate(path, true, "")
            end
        end
    end

    (state_count=length(visited), errors=errors)
end

# A structural selection is `∅`, `rows[r]∅`, `column_headers[c]∅`, or
# `rows[r][c]∅` — i.e. it terminates at an element, not inside cell content.
function _wt_is_structural(path)
    path isa EmptyReference && return true
    path isa ConcreteReference || return false
    h = path.head
    h isa FieldReferenceStep || return false
    t = path.tail
    t isa ConcreteReference || return false
    (t.head isa RangeReferenceStep && is_element_reference_step(t.head)) || return false
    if h.name == "rows"
        # rows[r]∅  or  rows[r][c]∅
        t.tail isa EmptyReference && return true
        t2 = t.tail
        t2 isa ConcreteReference || return false
        (t2.head isa RangeReferenceStep && is_element_reference_step(t2.head)) || return false
        return t2.tail isa EmptyReference
    elseif h.name == "column_headers"
        return t.tail isa EmptyReference
    end
    return false
end

function test_table_navigation(label, document, projection)
    @testset "$label" begin
        result = explore_table_selections(document, projection;
            onstate = (p, ok, msg) -> begin
                ok || @warn "[$label] [$p] $msg"
                @test ok
            end)
        if result.state_count == 0
            for e in result.errors
                @warn "[$label] $e"
            end
        end
        @test result.state_count > 0
    end
end

function test_table_navigation(example::Example)
    test_table_navigation(example.name, example.document, example.projection)
end

# Run a single gesture against a freshly-printed table and return the resulting
# selection-path string ("nothing" when the reader declined).
function _table_nav(document, projection, gesture, sel)
    clear_selection!(document)
    sel === nothing || set_selection!(document, sel)
    iomap = print_document(projection, document)
    op = read_intent(projection, iomap, gesture)
    op isa ReplaceSelectionOperation ? string(op.path) : (op === nothing ? "nothing" : string(typeof(op)))
end

function test_table_navigation()
@testset "TableNavigation" begin

@testset "BFS over reachable states is clean" begin
    test_table_navigation("table",      make_table_document_example(),      make_table_projection_example(measure=_table_measure()))
    test_table_navigation("math_table", make_math_table_document_example(), make_math_table_projection_example(measure=_table_measure()))
end

@testset "individual moves (3×3 with headers)" begin
    m = _table_measure()
    doc = make_math_table_document_example()
    proj = make_math_table_projection_example(measure=m)
    nav(g, sel) = _table_nav(doc, proj, g, sel)

    # Ctrl+Alt+Home → whole table from anywhere.
    @test nav(KeyDown(:home, ModifierKeys(ctrl=true, alt=true)), _wt_cell(2, 2)) == "∅"

    # Plain (unmodified) arrows move the active cell once a whole cell is already
    # selected — no Alt needed in structural mode — with edge clamping.
    @test nav(KeyDown(:down,  ModifierKeys()), _wt_cell(2, 2)) == ".rows[3][2]"
    @test nav(KeyDown(:up,    ModifierKeys()), _wt_cell(2, 2)) == ".rows[1][2]"
    @test nav(KeyDown(:left,  ModifierKeys()), _wt_cell(2, 2)) == ".rows[2][1]"
    @test nav(KeyDown(:right, ModifierKeys()), _wt_cell(2, 2)) == ".rows[2][3]"
    @test nav(KeyDown(:up,    ModifierKeys()), _wt_cell(1, 2)) == ".rows[1][2]"   # clamp top
    @test nav(KeyDown(:right, ModifierKeys()), _wt_cell(1, 3)) == ".rows[1][3]"   # clamp right

    # Alt+arrows still navigate from a whole cell too.
    @test nav(KeyDown(:down,  ModifierKeys(alt=true)), _wt_cell(2, 2)) == ".rows[3][2]"

    # On an in-cell cursor a *plain* arrow keeps editing the text (declined here →
    # routed into content), while Alt+arrow first promotes to the whole cell. The
    # cursor is whatever Enter drops into the cell: `rows[2][2]` holds a
    # `MathBinaryOperation`, so it lands on a leaf nested inside the cell content,
    # not on a field of the cell itself.
    incell = let
        clear_selection!(doc)
        set_selection!(doc, _wt_cell(2, 2))
        op = read_intent(proj, print_document(proj, doc), KeyDown(:return, ModifierKeys()))
        op.path
    end
    # Alt+arrow promotes an in-cell cursor to the whole cell, then moves.
    @test nav(KeyDown(:down, ModifierKeys(alt=true)), incell) == ".rows[3][2]"
    @test !startswith(nav(KeyDown(:down, ModifierKeys()), incell), ".rows[3][2]")

    # Shift+Space / Ctrl+Space widen the active cell to its row / column.
    @test nav(KeyDown(:space, ModifierKeys(shift=true)), _wt_cell(2, 2)) == ".rows[2]"
    @test nav(KeyDown(:space, ModifierKeys(ctrl=true)),  _wt_cell(2, 2)) == ".column_headers[2]"

    # A whole row steps between rows and narrows to its first cell.
    @test nav(KeyDown(:down,  ModifierKeys()), _wt_row(2)) == ".rows[3]"
    @test nav(KeyDown(:up,    ModifierKeys()), _wt_row(2)) == ".rows[1]"
    @test nav(KeyDown(:right, ModifierKeys()), _wt_row(2)) == ".rows[2][1]"
    @test nav(KeyDown(:return, ModifierKeys()), _wt_row(2)) == ".rows[2][1]"

    # A whole column steps between columns and narrows to its first cell.
    @test nav(KeyDown(:right, ModifierKeys()), _wt_col(2)) == ".column_headers[3]"
    @test nav(KeyDown(:left,  ModifierKeys()), _wt_col(2)) == ".column_headers[1]"
    @test nav(KeyDown(:down,  ModifierKeys()), _wt_col(2)) == ".rows[1][2]"
    @test nav(KeyDown(:return, ModifierKeys()), _wt_col(2)) == ".rows[1][2]"

    # Enter on a whole cell drops a real character cursor into its content.
    @test startswith(nav(KeyDown(:return, ModifierKeys()), _wt_cell(2, 2)), ".rows[2][2]")
end

@testset "Alt+click promotes a data cell to a whole-cell pick" begin
    m = _table_measure()
    doc = make_math_table_document_example()
    proj = make_math_table_projection_example(measure=m)
    io = print_document(proj, doc)
    geom = io.geometry[]

    # Aim at the centre of the (row 2, column 2) data cell.
    gc = 2 + geom.col_offset
    gr = 2 + geom.row_offset
    cx = div(geom.col_x[gc] + geom.col_x[gc+1], 2)
    cy = div(geom.row_y[gr] + geom.row_y[gr+1], 2)

    alt_op   = read_intent(proj, io, MousePress(:left, cx, cy, ModifierKeys(alt=true)))
    plain_op = read_intent(proj, io, MousePress(:left, cx, cy, ModifierKeys()))

    @test alt_op isa ReplaceSelectionOperation
    @test string(alt_op.path) == ".rows[2][2]"
    # Plain click on the same cell routes into its content instead.
    @test plain_op isa ReplaceSelectionOperation
    @test startswith(string(plain_op.path), ".rows[2][2]")
end

@testset "header / corner clicks pick the axis" begin
    m = _table_measure()
    doc = make_math_table_document_example()
    proj = make_math_table_projection_example(measure=m)
    io = print_document(proj, doc)
    geom = io.geometry[]

    # Column header strip (grid row 1) over data column 3.
    gc = 3 + geom.col_offset
    cx = div(geom.col_x[gc] + geom.col_x[gc+1], 2)
    col_op = read_intent(proj, io, MousePress(:left, cx, div(geom.row_y[2], 2), ModifierKeys()))
    @test col_op isa ReplaceSelectionOperation
    @test string(col_op.path) == ".column_headers[3]"

    # Row header strip (grid column 1) over data row 2.
    gr = 2 + geom.row_offset
    cy = div(geom.row_y[gr] + geom.row_y[gr+1], 2)
    row_op = read_intent(proj, io, MousePress(:left, div(geom.col_x[2], 2), cy, ModifierKeys()))
    @test row_op isa ReplaceSelectionOperation
    @test string(row_op.path) == ".rows[2]"

    # Top-left corner (header intersection) selects the whole table.
    corner_op = read_intent(proj, io, MousePress(:left, div(geom.col_x[2], 2), div(geom.row_y[2], 2), ModifierKeys()))
    @test corner_op isa ReplaceSelectionOperation
    @test corner_op.path isa EmptyReference
end

end # @testset "TableNavigation"
end # test_table_navigation
