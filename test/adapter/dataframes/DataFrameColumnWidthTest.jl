# The width of a column of a view, set by the drag of the right edge of its
# header through the loop of a real editor, whose drag tracker gives the table
# the moves of the drag by its path.

# A backend that draws nothing, and hands the loop the events of a test.
mutable struct _ColumnWidthBackend <: Backend
    events::Vector{Any}
    rendered::Vector{Any}
end
_ColumnWidthBackend() = _ColumnWidthBackend(Any[], Any[])
BackendModule.initialize_backend!(::_ColumnWidthBackend) = nothing
BackendModule.quit_backend!(::_ColumnWidthBackend) = nothing
BackendModule.take_from_devices!(backend::_ColumnWidthBackend, devices) =
    isempty(backend.events) ? nothing : popfirst!(backend.events)
BackendModule.write_to_devices!(backend::_ColumnWidthBackend, devices, output) =
    (push!(backend.rendered, output); nothing)

# The first IO map of type `type` under `node`, through the fields of each IO map.
function _find_iomap_of(node, type::Type, seen = IdDict{Any,Bool}())
    node isa AbstractCell && return _find_iomap_of(node[], type, seen)
    node isa IoMap || return nothing
    haskey(seen, node) && return nothing
    seen[node] = true
    node isa type && return node
    for field in fieldnames(typeof(node))
        value = getfield(node, field)
        value = value isa AbstractCell ? value[] : value
        for candidate in (value isa AbstractVector ? value : (value,))
            candidate isa Tuple && !isempty(candidate) && (candidate = last(candidate))
            found = _find_iomap_of(candidate, type, seen)
            found === nothing || return found
        end
    end
    nothing
end

"""
    test_data_frame_column_width()

A drag of the right edge of a header gives its column a width, which the view
keeps by the name of the column, and Escape during the drag puts back the width
of the press. A sort and a duplicate keep the width.
"""
function test_data_frame_column_width()
    @testset "the width of a column of a view" begin
        none = ModifierKeys()
        frame = DataFrame(id = 1:20, name = ["item $(i)" for i in 1:20], price = collect(1.0:20.0))
        view = DataFrameView(frame)
        backend = _ColumnWidthBackend()
        editor = build_editor(view, NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                              backend, devices = Device[Keyboard(), Mouse(), Display()], tabs = false,
                              window = (; title = "W", width = 900, height = 400))
        run_frame!(editor)
        send!(event) = (push!(backend.events, WindowInput(:W, event)); run_frame!(editor))
        label_at(text) = only((t[1], t[2]) for t in _data_frame_texts(last(backend.rendered).windows[1].content)
                              if t[3] == text)
        table_iomap = _find_iomap_of(editor.iomap, WidgetTableListIoMap)
        state = table_iomap.state
        (name_x, name_y) = label_at("name :: String")
        # The right edge of the column `id` is the rule before the header of `name`.
        edge = name_x - state.pad_x - state.bw

        @testset "the pointer is a double arrow over the edge" begin
            window = last(backend.rendered).windows[1].content
            @test find_pointer_shape(window, edge, name_y + 2) === :double_arrow_horizontal
            @test find_pointer_shape(window, name_x + 20, name_y + 2) !== :double_arrow_horizontal
        end

        @testset "the edge lights under the pointer" begin
            send!(MouseMove(edge, name_y + 2; time = 0.5))
            target = table_iomap.input.mouse_target
            @test target isa ConcreteReference && target.head == FieldReferenceStep("columns") &&
                  target.tail.tail.head == FieldReferenceStep("policy")
            send!(MouseMove(name_x + 20, name_y + 2; time = 0.6))
            target = table_iomap.input.mouse_target
            @test !(target isa ConcreteReference && target.head == FieldReferenceStep("columns") &&
                    target.tail.tail isa ConcreteReference && target.tail.tail.head == FieldReferenceStep("policy"))
        end

        @testset "a drag of the edge sets the width, and the view keeps it by name" begin
            send!(MouseDown(:left, edge, name_y + 2, none; time = 1.0))
            send!(MouseMove(edge + 40, name_y + 2, MouseButtons(:left), none; time = 1.1))
            # The pointer keeps the double arrow over the cells and outside the window.
            window = last(backend.rendered).windows[1].content
            @test find_pointer_shape(window, name_x + 20, name_y + 80) === :double_arrow_horizontal
            @test find_pointer_shape(window, 2000, -30) === :double_arrow_horizontal
            send!(MouseUp(:left, edge + 40, name_y + 2, none; time = 1.2))
            window = last(backend.rendered).windows[1].content
            @test find_pointer_shape(window, name_x + 20, name_y + 80) !== :double_arrow_horizontal
            @test haskey(view.column_widths, "id")
            @test label_at("name :: String")[1] == name_x + 40
            # The release ends the drag that the table keeps.
            @test table_iomap.input.column_drag === nothing
        end

        @testset "Escape during a drag puts back the width of the press" begin
            width = view.column_widths["id"]
            moved = edge + 40
            send!(MouseDown(:left, moved, name_y + 2, none; time = 2.0))
            send!(MouseMove(moved + 30, name_y + 2, MouseButtons(:left), none; time = 2.1))
            @test view.column_widths["id"] == width + 30
            send!(KeyDown(:escape, none; time = 2.2))
            @test view.column_widths["id"] == width
            @test label_at("name :: String")[1] == name_x + 40
        end

        @testset "a sort and a duplicate keep the width" begin
            width = view.column_widths["id"]
            push!(view.query.sort_keys, DataFrameSortKey(; column = "price", descending = true))
            run_frame!(editor)
            @test view.column_widths["id"] == width
            @test label_at("name :: String")[1] == name_x + 40
            duplicate = make_document_duplicate(view)
            @test duplicate.column_widths == view.column_widths
        end
    end
end
