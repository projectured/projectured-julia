# ═══════════════════════════════════════════════════════════════════════════
# test/src/projection/TableNavigationTest.jl
#
# Grid navigation gestures for the Table → Graphics projection
# (plan/pending/table-selection.md, phases 2 & 3).
#
# explore_table_selections(document, projection)
#   BFS over the tree-selection states reachable from Ctrl+Alt+Home (whole
#   table). At each state every navigation chord (Alt+arrows, Shift/Ctrl+Space,
#   Enter) is tried via projection_read; the resulting path is re-applied,
#   re-printed and the iomap walked (forcing every cell). Returns (state_count,
#   errors).
#
# test_table_navigation(label, document, projection)
#   Wraps the walker in a @testset and asserts no errors.
#
# A second @testset pins the individual moves — Alt+arrow steps with edge
# clamping, Shift/Ctrl+Space widen, Ctrl+Alt+Home, Enter, and Alt+click
# whole-cell promotion — against the deterministic synthetic-metric geometry.
# ═══════════════════════════════════════════════════════════════════════════

function explore_table_selections(document, projection; onstate=nothing)
    nav_keys = [
        KeyDown(:up,    Modifiers(alt=true)),
        KeyDown(:down,  Modifiers(alt=true)),
        KeyDown(:left,  Modifiers(alt=true)),
        KeyDown(:right, Modifiers(alt=true)),
        KeyDown(:space, Modifiers(shift=true)),
        KeyDown(:space, Modifiers(ctrl=true)),
        KeyDown(:return, Modifiers()),
    ]

    visited = Set{String}()
    errors  = String[]

    clear_selection!(document)
    iomap = try
        projection_print(projection, document)
    catch e
        return (state_count=0, errors=["projection_print failed: $e"])
    end

    # Seed: Ctrl+Alt+Home → ReplaceSelectionOperation(∅) (whole table).
    op = try
        projection_read(projection, iomap, KeyDown(:home, Modifiers(ctrl=true, alt=true)))
    catch e
        return (state_count=0, errors=["Ctrl+Alt+Home failed: $e"])
    end
    op isa ReplaceSelectionOperation || return (state_count=0, errors=["Ctrl+Alt+Home returned $(typeof(op))"])

    queue = Any[op.path]

    while !isempty(queue)
        path = popfirst!(queue)
        path_str = string(path)
        path_str in visited && continue
        push!(visited, path_str)
        errs_before = length(errors)

        clear_selection!(document)
        set_selection!(document, path)

        iomap = try
            projection_print(projection, document)
        catch e
            msg = "reprint at [$path_str] failed: $e"
            push!(errors, msg)
            onstate === nothing || onstate(path, false, msg)
            continue
        end
        _walk!(iomap, Set{UInt64}(), errors)

        for key in nav_keys
            op = try
                projection_read(projection, iomap, key)
            catch e
                push!(errors, "reader error at [$path_str] with $key: $e")
                nothing
            end
            op isa ReplaceSelectionOperation || continue
            new_str = string(op.path)
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
    iomap = projection_print(projection, document)
    op = projection_read(projection, iomap, gesture)
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
    @test nav(KeyDown(:home, Modifiers(ctrl=true, alt=true)), @reference cells[5]) == "∅"

    # Alt+arrows from a whole cell move the active cell with edge clamping.
    @test nav(KeyDown(:down,  Modifiers(alt=true)), @reference cells[5]) == ".cells[8]"
    @test nav(KeyDown(:up,    Modifiers(alt=true)), @reference cells[5]) == ".cells[2]"
    @test nav(KeyDown(:left,  Modifiers(alt=true)), @reference cells[5]) == ".cells[4]"
    @test nav(KeyDown(:right, Modifiers(alt=true)), @reference cells[5]) == ".cells[6]"
    @test nav(KeyDown(:up,    Modifiers(alt=true)), @reference cells[2]) == ".cells[2]"   # clamp top
    @test nav(KeyDown(:right, Modifiers(alt=true)), @reference cells[3]) == ".cells[3]"   # clamp right

    # Alt+arrow from an in-cell cursor first promotes to the whole cell, then moves.
    incell = ConcreteReferencePath(FieldReference("cells"),
                 ConcreteReferencePath(ElementReference(5),
                     ConcreteReferencePath(FieldReference("content"), EmptyReferencePath())))
    @test nav(KeyDown(:down, Modifiers(alt=true)), incell) == ".cells[8]"

    # Shift+Space / Ctrl+Space widen the active cell to its row / column.
    @test nav(KeyDown(:space, Modifiers(shift=true)), @reference cells[5]) == ".rows[2]"
    @test nav(KeyDown(:space, Modifiers(ctrl=true)),  @reference cells[5]) == ".columns[2]"

    # A whole row steps between rows and narrows to its first cell.
    @test nav(KeyDown(:down,  Modifiers(alt=true)), @reference rows[2]) == ".rows[3]"
    @test nav(KeyDown(:up,    Modifiers(alt=true)), @reference rows[2]) == ".rows[1]"
    @test nav(KeyDown(:right, Modifiers(alt=true)), @reference rows[2]) == ".cells[4]"
    @test nav(KeyDown(:return, Modifiers()),        @reference rows[2]) == ".cells[4]"

    # A whole column steps between columns and narrows to its first cell.
    @test nav(KeyDown(:right, Modifiers(alt=true)), @reference columns[2]) == ".columns[3]"
    @test nav(KeyDown(:left,  Modifiers(alt=true)), @reference columns[2]) == ".columns[1]"
    @test nav(KeyDown(:down,  Modifiers(alt=true)), @reference columns[2]) == ".cells[2]"
    @test nav(KeyDown(:return, Modifiers()),        @reference columns[2]) == ".cells[2]"

    # Enter on a whole cell drops a real character cursor into its content.
    @test startswith(nav(KeyDown(:return, Modifiers()), @reference cells[5]), ".cells[5].content")
end

@testset "Alt+click promotes a data cell to a whole-cell pick" begin
    m = _table_measure()
    doc = make_math_table_document_example()
    proj = make_math_table_projection_example(measure=m)
    io = projection_print(proj, doc)
    geom = io.child_iomap.geometry[]

    # Aim at the centre of the (row 2, column 2) data cell = flat index 5.
    gc = 2 + geom.col_offset
    gr = 2 + geom.row_offset
    cx = div(geom.col_x[gc] + geom.col_x[gc+1], 2)
    cy = div(geom.row_y[gr] + geom.row_y[gr+1], 2)

    alt_op   = projection_read(proj, io, MousePress(:left, cx, cy, Modifiers(alt=true)))
    plain_op = projection_read(proj, io, MousePress(:left, cx, cy, Modifiers()))

    @test alt_op isa ReplaceSelectionOperation
    @test string(alt_op.path) == ".cells[5]"
    # Plain click on the same cell routes into its content instead.
    @test plain_op isa ReplaceSelectionOperation
    @test startswith(string(plain_op.path), ".cells[5].content")
end

@testset "header / corner clicks pick the axis" begin
    m = _table_measure()
    doc = make_math_table_document_example()
    proj = make_math_table_projection_example(measure=m)
    io = projection_print(proj, doc)
    geom = io.child_iomap.geometry[]

    # Column header strip (grid row 1) over data column 3.
    gc = 3 + geom.col_offset
    cx = div(geom.col_x[gc] + geom.col_x[gc+1], 2)
    col_op = projection_read(proj, io, MousePress(:left, cx, div(geom.row_y[2], 2), Modifiers()))
    @test col_op isa ReplaceSelectionOperation
    @test string(col_op.path) == ".columns[3]"

    # Row header strip (grid column 1) over data row 2.
    gr = 2 + geom.row_offset
    cy = div(geom.row_y[gr] + geom.row_y[gr+1], 2)
    row_op = projection_read(proj, io, MousePress(:left, div(geom.col_x[2], 2), cy, Modifiers()))
    @test row_op isa ReplaceSelectionOperation
    @test string(row_op.path) == ".rows[2]"

    # Top-left corner (header intersection) selects the whole table.
    corner_op = projection_read(proj, io, MousePress(:left, div(geom.col_x[2], 2), div(geom.row_y[2], 2), Modifiers()))
    @test corner_op isa ReplaceSelectionOperation
    @test corner_op.path isa EmptyReferencePath
end

end # @testset "TableNavigation"
end # test_table_navigation
