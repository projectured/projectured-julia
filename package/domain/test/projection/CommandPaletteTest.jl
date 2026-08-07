# The command palette: the match, the selection, and the rendering. The palette is
# the running twin of the gesture-help window — both read one collected set of
# bindings and display it as GestureRows.

# Three rows that cover every case the palette distinguishes: a runnable command
# with a gesture, a runnable command without one, and a row from a deeper
# projection stage that only its key can run.
_palette_rows() = [
    GestureRow("Ctrl+C", "Copy the selection", "JsonObject",   true,  "Copy the selection", true),
    GestureRow("",       "Sort the entries",   "JsonObject",   true,  "Sort the entries",   true),
    GestureRow("Left",   "Move left",          "TextDocument", true,  "Move left",          false),
    GestureRow("n",      "Replace with null",  "JsonDocument", false, "Replace with null",  true),
]

_palette(query = "") = CommandPalette(query, _palette_rows(), nothing)

function test_command_palette()
@testset "CommandPalette" begin

    @testset "an empty query matches every row, best first" begin
        p = _palette()
        # Runnable and applicable first, then runnable but not applicable, then the
        # row only a key can run.
        @test command_palette_matches(p) == [1, 2, 4, 3]
    end

    @testset "the query matches as a subsequence, without case" begin
        # A subsequence match is deliberately loose — "sort" is also a subsequence of
        # "jsondocument replace with null" — so the rank carries the weight: the row
        # the user meant comes first.
        @test first(command_palette_matches(_palette("sort"))) == 2
        @test first(command_palette_matches(_palette("SORT"))) == 2
        @test first(command_palette_matches(_palette("srt"))) == 2     # gaps allowed
        @test command_palette_matches(_palette("copy")) == [1]
        @test command_palette_matches(_palette("json")) == [1, 2, 4]   # the domain matches too
        @test command_palette_matches(_palette("zzz")) == []
    end

    @testset "the selection names a row, and survives a narrower query" begin
        p = _palette()
        p.selection = command_palette_selection(2)
        @test command_palette_selected(p) == 2
        @test command_palette_row(p).description == "Sort the entries"
        # A query the chosen row still matches keeps it.
        p.query = "sort"
        @test command_palette_settled_selection(p) == command_palette_selection(2)
        # A query it does not match moves to the first match.
        p.query = "copy"
        @test command_palette_settled_selection(p) == command_palette_selection(1)
        # No match at all leaves nothing selected.
        p.query = "zzz"
        @test command_palette_settled_selection(p) === nothing
    end

    @testset "no selection reads as row 0" begin
        p = _palette()
        @test command_palette_selected(p) == 0
        @test command_palette_row(p) === nothing
        @test command_palette_selection(0) === nothing
    end

    @testset "a step walks the matching subset and stops at both ends" begin
        p = _palette()
        # Nothing selected: forward lands on the first match, backward on the last.
        @test command_palette_step(p, 1) == command_palette_selection(1)
        @test command_palette_step(p, -1) == command_palette_selection(3)
        p.selection = command_palette_selection(1)
        @test command_palette_step(p, 1) == command_palette_selection(2)
        @test command_palette_step(p, -1) == command_palette_selection(1)   # clamped
        p.selection = command_palette_selection(3)                          # the last match
        @test command_palette_step(p, 1) == command_palette_selection(3)    # clamped
        p.query = "zzz"
        @test command_palette_step(p, 1) === nothing
    end

    @testset "the palette renders the query, the marker, and the gesture" begin
        p = _palette()
        p.selection = command_palette_selection(2)
        text = render(print_document(CommandPaletteToSyntax(), p).output)
        @test occursin("> ▏", text)                              # the type-in line
        @test occursin("▸ Sort the entries", text)               # the chosen row
        @test occursin("  Copy the selection   [Ctrl+C]", text)  # its key, for learning it
        @test occursin("(key only)", text)                       # the row a name cannot run
        @test !occursin("Sort the entries   [", text)            # no gesture, no brackets
    end

    @testset "the rendering re-derives as the user types" begin
        p = _palette()
        output = print_document(CommandPaletteToSyntax(), p).output
        @test occursin("Copy the selection", render(output))
        # The same output tree, after a keystroke: a captured list would freeze here.
        p.query = "sort"
        text = render(output)
        @test occursin("> sort▏", text)
        @test occursin("Sort the entries", text)
        @test !occursin("Copy the selection", text)
        p.query = "zzz"
        @test occursin("no command matches", render(output))
    end

end
end

export test_command_palette
