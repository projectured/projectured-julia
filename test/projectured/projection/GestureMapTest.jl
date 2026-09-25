# The gesture-help projection: a GestureMap built from what the READER answered
# when asked what is available, rendered through GestureMapToSyntax (and onward via
# the normal Syntax → Text pipeline). Proves the reification — what is *shown* is
# exactly what could *fire*, because it came back the same way a keystroke would.

# Ask a pipeline what it offers, the way the help window does.
_collect(projection, document) = begin
    iomap = print_document(projection, document)
    answer = read_intent(projection, nothing, Intent(CollectIntents()), iomap)
    answer isa Intent ? answer.operation : answer
end

function test_gesture_map()
@testset "GestureMap help projection" begin

    g2s = GestureMapToSyntax()

    @testset "renders gesture → description rows grouped by domain" begin
        obj = JsonObject("a" => JsonNumber(1))
        set_selection!(obj, EmptyReference())
        gmap = make_gesture_map(_collect(RecursiveProjection(JsonToSyntax()), obj))
        text = render(print_document(g2s, gmap).output)
        # Domain headings.
        @test occursin("JsonObject", text)
        @test occursin("JsonDocument", text)
        # Own object gestures and an inherited type-to-replace row.
        @test occursin(", — Insert a new entry", text)
        @test occursin("Tab — Move from key to value", text)
        @test occursin("n — Replace with null", text)
        # Greying is now the honest answer, because it IS the built operation: with
        # the whole value selected the type-to-replace rules can fire, and Tab
        # cannot — `move_to_field` declines when the cursor is not in a key. The old
        # flag consulted only the `applicable` precondition and so claimed Tab was
        # available when pressing it would have done nothing.
        @test !occursin("Replace with null  (n/a)", text)
        @test occursin("Tab — Move from key to value  (n/a)", text)
    end

    @testset "greys rows whose precondition fails for the selection" begin
        obj = JsonObject("a" => JsonNumber(1))         # selection === nothing → type-replace n/a
        gmap = make_gesture_map(_collect(RecursiveProjection(JsonToSyntax()), obj))
        text = render(print_document(g2s, gmap).output)
        @test occursin("n — Replace with null  (n/a)", text)   # greyed
        @test occursin(", — Insert a new entry", text)          # still applicable
        @test !occursin("Insert a new entry  (n/a)", text)
    end

    @testset "contextual collection feeds the map" begin
        arr = JsonArray([JsonNumber(1)])
        set_selection!(arr, EmptyReference())
        gmap = make_gesture_map(_collect(RecursiveProjection(JsonToSyntax()), arr))
        @test length(gmap.rows) == 9                            # array's full set
        text = render(print_document(g2s, gmap).output)
        @test occursin(", — Insert a new element", text)
    end

    @testset "a row carries the operation it would apply" begin
        obj = JsonObject("a" => JsonNumber(1))
        set_selection!(obj, EmptyReference())
        rows = make_gesture_map(_collect(RecursiveProjection(JsonToSyntax()), obj)).rows
        # Every row that can fire right now carries a built operation, ready to
        # apply against the document these rows were collected over.
        insert = only(r for r in rows if r.description == "Insert a new entry")
        @test insert.operation !== nothing
        # "Replace with a number" needs the digit the user typed, so no operation
        # can be built without the keystroke — the row shows, greyed.
        number = only(r for r in rows if r.description == "Replace with a number")
        @test number.operation === nothing
    end

    @testset "a row for a binding with no gesture says how to reach it" begin
        gmap = GestureMap(rows = [
            GestureRow("", "Sort the entries", "JsonObject", DoNothingOperation())])
        text = render(print_document(g2s, gmap).output)
        # The gesture column tells the user what to do instead of pressing a key.
        @test occursin("by name — Sort the entries", text)
    end

    @testset "is_help_gesture recognizes the help summons" begin
        @test is_help_gesture(KeyDown(:f1, ModifierKeys(); time = 0.0))
        @test !is_help_gesture(KeyDown(:home, ModifierKeys(); time = 0.0))
        @test !is_help_gesture(KeyPress('?'; time = 0.0))
    end

end
end

export test_gesture_map
