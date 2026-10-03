"""
    test_data_frame_find()

The find field of a view: Ctrl+F puts the caret in it, and Enter in it, F3 and
Shift+F3 select the next and the previous cell whose text contains its text,
with no regard to case, in the order of the view, round the end. A find with no
match marks the field with "no match".
"""
function test_data_frame_find()
    @testset "the find of a view" begin
        projection = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        context() = with_exact_size(PrinterContext(); width = Cell(Int32(900)),
                                    height = Cell(Int32(300)))
        make_frame() = DataFrame(name = ["apple", "banana", "cherry", "date"],
                                 kind = ["fruit", "fruit", "fruit", "dried"], price = [1.5, 2.5, 3.5, 1.25])
        module_ = ProjecturedDataFrames.DataFramesModule
        whole(r, c) = ConcreteReference(FieldReferenceStep("rows"), ConcreteReference(RangeReferenceStep(r - 1, r),
            ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference())))
        function key(io, event)
            change = read_intent(projection, nothing, Intent(event, nothing), io)
            change isa Intent ? change.operation : change
        end
        f3(shift = false) = KeyDown(:f3, ModifierKeys(; shift); time = 0.0)
        selected(view) = strip_reference_types(get_selection(view))
        function open_view(frame = make_frame(); text = "")
            view = DataFrameView(frame)
            io = print_document(projection, nothing, view, context())
            getfield(view, :find_text)[] = text
            (view, io, _DataFrameFilterEditor(view))
        end
        find!(view, io, editor; shift = false) = evaluate_operation(editor, key(io, f3(shift)))

        @testset "F3 goes from cell to cell in the order of the view, round the end, with no regard to case" begin
            view, io, editor = open_view(; text = "E")
            # "e" is in apple, cherry, date and dried.
            # The selection path is a live value, so the order keeps a copy.
            order = String[]
            for _ in 1:5
                find!(view, io, editor)
                push!(order, repr(selected(view)))
            end
            @test order == repr.([whole(1, 1), whole(3, 1), whole(4, 1), whole(4, 2), whole(1, 1)])
            find!(view, io, editor; shift = true)
            @test selected(view) == whole(4, 2)
            # A number matches by its text.
            getfield(view, :find_text)[] = "2.5"
            find!(view, io, editor)
            @test selected(view) == whole(2, 3)
        end

        @testset "a find follows the sort and leaves out a hidden column" begin
            view, io, editor = open_view(; text = "e")
            evaluate_operation(editor, module_._make_sort_operation(view, "price", false))
            find!(view, io, editor)              # the kept rows: 4, 1, 2, 3
            @test selected(view) == whole(4, 1)
            evaluate_operation(editor, module_._make_hidden_columns_operation(view, ["kind"]))
            find!(view, io, editor)
            @test selected(view) == whole(1, 1)
        end

        @testset "a find with no match marks the field, and a new text takes the mark away" begin
            view, io, editor = open_view(; text = "zzz")
            find!(view, io, editor)
            @test view.find_reason == ("zzz", "no match") && module_._get_find_reason(view) == "no match"
            @test get_selection(view) === nothing
            getfield(view, :find_text)[] = "zz"
            @test module_._get_find_reason(view) === nothing
            @test key(io, f3()) isa Operation
            getfield(view, :find_text)[] = ""
            @test key(io, f3()) === nothing
        end

        @testset "Ctrl+F puts the caret in the find field, a key types there, and Enter finds" begin
            view, io, editor = open_view()
            evaluate_operation(editor, key(io, KeyDown(:f, ModifierKeys(ctrl = true); time = 0.0)))
            @test selected(view) == Reference(FieldReferenceStep("find_text"), RangeReferenceStep(0, 0))
            for character in "an"
                evaluate_operation(editor, key(io, KeyPress(character; time = 0.0)))
            end
            @test view.find_text == "an" && view.query.expression == ""
            evaluate_operation(editor, key(io, KeyDown(:return, ModifierKeys(); time = 0.0)))
            @test selected(view) == whole(2, 1)
            # Shift+Enter in the find field finds back.
            evaluate_operation(editor, key(io, KeyDown(:f, ModifierKeys(ctrl = true); time = 0.0)))
            evaluate_operation(editor, key(io, KeyDown(:return, ModifierKeys(shift = true); time = 0.0)))
            @test selected(view) == whole(2, 1)
            # From the find field a find starts at the row at the head of the
            # list, row 2 after the jump to banana, so back from it is apple.
            getfield(view, :find_text)[] = "a"
            evaluate_operation(editor, key(io, KeyDown(:f, ModifierKeys(ctrl = true); time = 0.0)))
            @test view.anchor == 2
            evaluate_operation(editor, key(io, KeyDown(:return, ModifierKeys(shift = true); time = 0.0)))
            @test selected(view) == whole(1, 1)
        end

        @testset "through a real editor, Ctrl+F, a text, Enter and F3 find, and undo takes back no find" begin
            view = DataFrameView(make_frame())
            backend = _ColumnWidthBackend()
            editor = build_editor(view, projection; backend, devices = Device[Keyboard(), Mouse(), Display()],
                                  tabs = false, undo = true, window = (; title = "W", width = 900, height = 300))
            run_frame!(editor)
            send!(event) = (push!(backend.events, WindowInput(:W, event)); run_frame!(editor))
            send!(KeyDown(:f, ModifierKeys(ctrl = true); time = 1.0))
            send!(KeyPress('e'; time = 1.1))
            send!(KeyDown(:return, ModifierKeys(); time = 1.5))
            @test view.find_text == "e" && selected(view) == whole(1, 1)
            send!(KeyDown(:f3, ModifierKeys(); time = 2.0))
            @test selected(view) == whole(3, 1)
            # The undo takes back the key in the find field, and no find.
            send!(KeyDown(:z, ModifierKeys(ctrl = true); time = 3.0))
            @test view.find_text == ""
        end

        @testset "the view jumps to the row of a match that is not at its head" begin
            frame = DataFrame(id = 1:100, name = ["item $(i)" for i in 1:100])
            view, io, editor = open_view(frame; text = "item 80")
            find!(view, io, editor)
            @test selected(view) == whole(80, 2) && view.anchor == 80
        end
    end
end
