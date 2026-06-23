# The gesture-help projection: a GestureMap built from the reified bindings of a
# document, rendered through GestureMapToSyntax (and onward via the normal
# Syntax → Text pipeline). Proves the reification — what is *shown* is exactly the
# bindings that could *fire*.

function test_gesture_map()
@testset "GestureMap help projection" begin

    g2s = GestureMapToSyntax()

    @testset "renders gesture → description rows grouped by domain" begin
        obj = JsonObject("a" => 1)
        set_selection!(obj, EmptyReferencePath())
        gmap = gesture_map(document_gestures(JsonObject), obj)
        text = render(projection_print(g2s, gmap).output)
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
        obj = JsonObject("a" => 1)         # selection === nothing → type-replace n/a
        gmap = gesture_map(document_gestures(JsonObject), obj)
        text = render(projection_print(g2s, gmap).output)
        @test occursin("n — Replace with null  (n/a)", text)   # greyed
        @test occursin(", — Insert a new entry", text)          # still applicable
        @test !occursin("Insert a new entry  (n/a)", text)
    end

    @testset "contextual collection feeds the map" begin
        j2s = RecursiveProjection(JsonToSyntax())
        arr = JsonArray([JsonNumber(1)])
        set_selection!(arr, EmptyReferencePath())
        iomap = projection_print(j2s, arr)
        gmap = gesture_map(collect_gestures(j2s, nothing, iomap), arr)
        @test length(gmap.rows) == 9                            # array's full set
        text = render(projection_print(g2s, gmap).output)
        @test occursin(", — Insert a new element", text)
    end

    @testset "is_help_gesture recognizes the help summons" begin
        @test is_help_gesture(KeyDown(:f1, Modifiers()))
        @test !is_help_gesture(KeyDown(:home, Modifiers()))
        @test !is_help_gesture(KeyPress('?'))
    end

end
end

export test_gesture_map
