# The edit of the address in the path view: Ctrl+L, typing with the hint of a
# field name, Tab, Enter and Escape, a path that reaches no node, a key on a
# committed step, and a key that reaches the page. The content is the shelf of
# `NavigatorVisitsTest.jl`, and the editor is the one of `NavigatorToWidgetTest.jl`.

_nav_type!(editor, backend, text) =
    foreach(c -> _nav_press!(editor, backend, KeyPress(c; time = 0.0)), text)
_nav_plain_key(key) = KeyDown(key, ModifierKeys(); time = 0.0)
_nav_draft_texts(navigator) = [_nav_step_text(step) for step in navigator.address_draft.steps]
_nav_step_text(step::FieldReferenceStep) = "." * step.name
_nav_step_text(step::RangeReferenceStep) = "[" * string(step.stop) * "]"
_nav_step_text(step::ReferenceInsertion) = "insertion " * step.value

function test_navigator_address()
@testset "Navigator address" begin

    @testset "the operations: start an edit, open the typed path, and end the edit" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[2]))
        holder = _NavHolder(navigator)
        _nav_apply!(holder, make_navigator_address_edit_operation(navigator))
        draft = navigator.address_draft
        @test draft.edited && draft.view === :path && draft.view_before === :titles
        @test _nav_draft_texts(navigator) == [".books", "[2]", "insertion "]
        @test _nav_steps(navigator.selection) == [FieldReferenceStep("address_draft"), FieldReferenceStep("steps"),
                                                  RangeReferenceStep(2, 3), FieldReferenceStep("value"),
                                                  RangeReferenceStep(0, 0)]
        @test is_navigator_address_selected(navigator)
        # A second Ctrl+L keeps the edit.
        @test make_navigator_address_edit_operation(navigator) === nothing
        # Escape: the copy is the address again, and the page is selected.
        _nav_apply!(holder, make_navigator_address_reset_operation(navigator))
        @test !draft.edited && draft.view === :titles && isempty(draft.steps)
        @test _nav_steps(navigator.selection) == [FieldReferenceStep("content"), _nav_steps(@reference(shelf, books[2]))...]
        @test make_navigator_address_reset_operation(navigator) === nothing
        @test make_navigator_address_commit_operation(navigator) === nothing
    end

    @testset "Enter opens a path that reaches, and keeps one that does not" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[2]))
        holder = _NavHolder(navigator)
        _nav_apply!(holder, make_navigator_address_edit_operation(navigator))
        navigator.address_draft.steps[3] = ReferenceInsertion(; value = ".chapters[5]")
        _nav_apply!(holder, make_navigator_address_commit_operation(navigator))
        draft = navigator.address_draft
        @test get_navigator_page(navigator) === shelf.books[2]
        @test _nav_draft_texts(navigator) == [".books", "[2]", ".chapters", "[5]"]
        @test draft.unreached_step == 4 && draft.edited
        @test _nav_steps(navigator.selection)[end] == RangeReferenceStep(3, 4)
        # A text that is no path stays, and Enter does nothing.
        draft.steps[4] = ReferenceInsertion(; value = "chapters")
        @test make_navigator_address_commit_operation(navigator) isa DoNothingOperation
        draft.steps[4] = ReferenceInsertion(; value = "[1]")
        _nav_apply!(holder, make_navigator_address_commit_operation(navigator))
        @test get_navigator_page(navigator) === shelf.books[2].chapters[1]
        @test !draft.edited && draft.view === :titles && draft.unreached_step == 0
        @test length(navigator.back) == 1
    end

    @testset "a person types a path with the hint of a field name, and Enter opens it" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[2]))
        editor, backend = _nav_editor(navigator)
        _nav_press!(editor, backend, _nav_key(:l))
        @test _nav_has_texts(backend, "Path", ".books", "[2]")
        _nav_type!(editor, backend, ".cha")
        @test _nav_has_texts(backend, ".books", "[2]", ".cha", "pters")
        _nav_press!(editor, backend, _nav_plain_key(:tab))
        @test _nav_draft_texts(navigator) == [".books", "[2]", "insertion .chapters"]
        _nav_type!(editor, backend, "[1]")
        _nav_press!(editor, backend, _nav_plain_key(:return))
        @test get_navigator_page(navigator) === shelf.books[2].chapters[1]
        @test navigator.address_draft.view === :titles
        @test _nav_has_texts(backend, "Names", "Shelf", _NAV_CHOICES, "B", _NAV_CHOICES, "B1")
    end

    @testset "a path that reaches no node shows a mark, and Escape ends the edit" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[2]))
        editor, backend = _nav_editor(navigator)
        _nav_press!(editor, backend, _nav_key(:l))
        _nav_type!(editor, backend, ".chapters[5]")
        _nav_press!(editor, backend, _nav_plain_key(:return))
        @test _nav_has_text(backend, "✗ step 4 reaches no part")
        @test get_navigator_page(navigator) === shelf.books[2]
        _nav_press!(editor, backend, _nav_plain_key(:escape))
        @test !navigator.address_draft.edited
        @test _nav_has_texts(backend, "Names", "Shelf", _NAV_CHOICES, "B")
    end

    @testset "a key on a committed step turns it into an insertion with its text" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[2]))
        editor, backend = _nav_editor(navigator)
        _nav_press!(editor, backend, _nav_key(:l))
        replace_selection!(editor.document, annotate_reference_types(navigator,
            Reference(FieldReferenceStep("address_draft"), FieldReferenceStep("steps"), RangeReferenceStep(0, 1))))
        run_frame!(editor)
        _nav_press!(editor, backend, _nav_plain_key(:backspace))
        @test _nav_draft_texts(navigator) == ["insertion .book", "[2]", "insertion "]
        _nav_type!(editor, backend, "s")
        @test _nav_draft_texts(navigator) == ["insertion .books", "[2]", "insertion "]
        _nav_press!(editor, backend, _nav_plain_key(:return))
        @test !navigator.address_draft.edited
        @test get_navigator_page(navigator) === shelf.books[2]
    end

    @testset "a press on the path starts an edit" begin
        shelf = _nav_make_shelf()
        navigator = Navigator(shelf, @reference(shelf, books[2]))
        editor, backend = _nav_editor(navigator)
        _nav_press!(editor, backend, _nav_click(backend, "Names"))
        @test navigator.address_draft.view === :path
        _nav_press!(editor, backend, _nav_click(backend, ".books[2]"))
        @test navigator.address_draft.edited
        @test is_navigator_address_selected(navigator)
    end

    @testset "a key reaches the page" begin
        text = WidgetText("abc")
        navigator = Navigator(text)
        editor, backend = _nav_editor(navigator)
        replace_selection!(editor.document, ConcreteReference(FieldReferenceStep("content"),
            ConcreteReference(FieldReferenceStep("content"), ConcreteReference(TextRangeReferenceStep(3, 3), EmptyReference()))))
        run_frame!(editor)
        _nav_press!(editor, backend, KeyPress('X'; time = 0.0))
        @test text.content == "abcX"
    end
end
end
