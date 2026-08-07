# The gesture-help projection: a GestureMap built from the reified bindings of a
# document, rendered through GestureMapToSyntax (and onward via the normal
# Syntax → Text pipeline). Proves the reification — what is *shown* is exactly the
# bindings that could *fire*.

function test_gesture_map()
@testset "GestureMap help projection" begin

    g2s = GestureMapToSyntax()

    @testset "renders gesture → description rows grouped by domain" begin
        obj = JsonObject("a" => JsonNumber(1))
        set_selection!(obj, EmptyReference())
        gmap = gesture_map(get_document_gesture_bindings(JsonObject), obj)
        text = render(print_document(g2s, gmap).output)
        # Domain headings.
        @test occursin("JsonObject", text)
        @test occursin("JsonDocument", text)
        # Own object gestures and an inherited type-to-replace row.
        @test occursin(", — Insert a new entry", text)
        @test occursin("Tab — Move from key to value", text)
        @test occursin("n — Replace with null", text)
        # A whole-value selection makes everything applicable: nothing greyed.
        @test !occursin("(n/a)", text)
    end

    @testset "greys rows whose precondition fails for the selection" begin
        obj = JsonObject("a" => JsonNumber(1))         # selection === nothing → type-replace n/a
        gmap = gesture_map(get_document_gesture_bindings(JsonObject), obj)
        text = render(print_document(g2s, gmap).output)
        @test occursin("n — Replace with null  (n/a)", text)   # greyed
        @test occursin(", — Insert a new entry", text)          # still applicable
        @test !occursin("Insert a new entry  (n/a)", text)
    end

    @testset "contextual collection feeds the map" begin
        j2s = RecursiveProjection(JsonToSyntax())
        arr = JsonArray([JsonNumber(1)])
        set_selection!(arr, EmptyReference())
        iomap = print_document(j2s, arr)
        gmap = gesture_map(collect_gesture_bindings(j2s, nothing, iomap), arr)
        @test length(gmap.rows) == 9                            # array's full set
        text = render(print_document(g2s, gmap).output)
        @test occursin(", — Insert a new element", text)
    end

    @testset "a row carries the name a user types" begin
        obj = JsonObject("a" => JsonNumber(1))
        set_selection!(obj, EmptyReference())
        bindings = get_document_gesture_bindings(JsonObject)
        rows = [gesture_row(b, obj, obj.selection) for b in bindings]
        named = [r for r in rows if r.name !== nothing]
        # A row that has a name is named by its description.
        @test all(r -> r.name == r.description, named)
        # "Replace with a number" binds the digit the user typed, so its operation
        # reads the event and a name could not run it.
        @test [r.description for r in rows if r.name === nothing] == ["Replace with a number"]
        # The help window runs nothing, so it marks nothing runnable.
        @test all(r -> !r.runnable, rows)
        # The same rows, built by a caller that owns the document, are runnable —
        # except the one with no name, which stays unrunnable whatever the caller says.
        own = [gesture_row(b, obj, obj.selection; runnable=true) for b in bindings]
        @test [r.runnable for r in own] == [r.name !== nothing for r in own]
    end

    @testset "a row for a binding with no gesture renders without a keystroke" begin
        gmap = GestureMap(rows = [
            GestureRow("", "Sort the entries", "JsonObject", true, "Sort the entries", true)])
        text = render(print_document(g2s, gmap).output)
        @test occursin("Sort the entries", text)
        @test !occursin("—", text)          # no connective: nothing stands to its left
    end

    @testset "is_help_gesture recognizes the help summons" begin
        @test is_help_gesture(KeyDown(:f1, ModifierKeys()))
        @test !is_help_gesture(KeyDown(:home, ModifierKeys()))
        @test !is_help_gesture(KeyPress('?'))
    end

end
end

export test_gesture_map
