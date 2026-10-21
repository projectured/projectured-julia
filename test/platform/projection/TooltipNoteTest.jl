# A tooltip note, drawn by the natural projection: each piece stands where a
# person looks for it, in the texts and the colors of the tooltip theme.

const _TN_APPEARANCE = Appearance()

# The note as the tooltip window draws it: the natural projection, at most as large
# as the window.
function _tn_print(note)
    projection = NaturalToGraphics(measure = FixedMeasure(10, 18, 6, 0), appearance = _TN_APPEARANCE)
    context = with_bounded_size(PrinterContext(); width = Cell(Int32(560)), height = Cell(Int32(400)))
    get_iomap_output(print_document(projection, nothing, note, context))
end

_tn_force(value) = value isa AbstractCell ? _tn_force(value[]) : value

# Each text of a drawn note with its place, and each rectangle with its place, its
# fill and the color of its border: the offsets of the canvases around a graphic
# add up to its place.
function _tn_places(node, x = 0, y = 0, found = Any[])
    node = _tn_force(node)
    if node isa GraphicsCanvas || node isa GraphicsViewport
        nx, ny = x + Int(_tn_force(node.x)), y + Int(_tn_force(node.y))
        if node isa GraphicsViewport
            _tn_places(node.content, nx, ny, found)
        else
            for element in _tn_force(node.elements)
                _tn_places(element, nx, ny, found)
            end
        end
    elseif node isa GraphicsText
        push!(found, (String(_tn_force(node.text)), x + Int(_tn_force(node.x)), y + Int(_tn_force(node.y))))
    elseif node isa GraphicsRect
        push!(found, (:rect, x + Int(_tn_force(node.x)), y + Int(_tn_force(node.y)), _tn_force(node.color),
                      _tn_force(node.border_color)))
    end
    found
end

_tn_texts(note) = [place for place in _tn_places(_tn_print(note)) if place[1] isa String]

# The place of the one drawn text `text`.
_tn_place(texts, text) = only(place[2:3] for place in texts if place[1] == text)

_tn_style(name) = unwrap_cell(get_tooltip_style(get_scaled_theme!(_TN_APPEARANCE, TooltipTheme), name))

function test_tooltip_note()
@testset "a tooltip note" begin

@testset "the title comes first, and the key caps follow it on its line" begin
    texts = _tn_texts(TooltipNote(; title = "Palette",
                                  keys = [KeyDownPattern(:p; modifiers = [:ctrl, :shift])]))
    title = _tn_place(texts, "Palette")
    @test title[1] == 0
    caps = [_tn_place(texts, name) for name in ("Ctrl", "Shift", "P")]
    # One cap for each key, in the order of the key, after the title.
    @test caps[1][1] > title[1] + length("Palette") * 10
    @test caps[1][1] < caps[2][1] < caps[3][1]
    @test caps[1][2] == caps[2][2] == caps[3][2]
end

@testset "a key cap has the fill and the line of the theme" begin
    places = _tn_places(_tn_print(TooltipNote(; keys = [KeyDownPattern(:f5; modifiers = Symbol[])])))
    @test any(place -> place[1] === :rect && is_color_equal(place[4], _tn_style(:key_fill)) &&
                       is_color_equal(place[5], _tn_style(:key_line)), places)
end

@testset "a plus at the end of a key text is the key of the plus" begin
    texts = _tn_texts(TooltipNote(; keys = ["Ctrl++"]))
    @test [place[1] for place in sort(texts; by = place -> place[2])] == ["Ctrl", "+"]
end

@testset "two keys stand with an or between them" begin
    texts = _tn_texts(TooltipNote(; keys = ["F5", "Ctrl+R"]))
    @test _tn_place(texts, "F5")[1] < _tn_place(texts, "or")[1] < _tn_place(texts, "Ctrl")[1]
end

@testset "the text, the facts and the hint stand below the title, in this order" begin
    texts = _tn_texts(TooltipNote(; title = "Refresh", text = "Read the frame again.",
                                  facts = ["Rows" => "12480", "Read" => "14:02:11"],
                                  hint = "The filter stays."))
    title = _tn_place(texts, "Refresh")
    text = _tn_place(texts, "Read the frame again.")
    rows, value = _tn_place(texts, "Rows"), _tn_place(texts, "12480")
    read = _tn_place(texts, "Read")
    hint = _tn_place(texts, "The filter stays.")
    @test title[2] < text[2] < rows[2] < read[2] < hint[2]
    # A fact is its name and its value side by side, and the values line up.
    @test value[2] == rows[2] && value[1] > rows[1]
    @test _tn_place(texts, "14:02:11")[1] == value[1]
end

@testset "a long text breaks its lines at the edge of the window" begin
    words = join(fill("word", 40), " ")
    texts = _tn_texts(TooltipNote(; text = words))
    @test length(unique(place[3] for place in texts)) > 1
    @test all(place -> place[2] + length(place[1]) * 10 <= 560, texts)
end

@testset "a piece that is nothing or empty draws nothing" begin
    @test [place[1] for place in _tn_texts(TooltipNote(; text = "only this"))] == ["only this"]
    @test isempty(_tn_texts(TooltipNote(; title = "", text = "", hint = nothing)))
end

@testset "a warning and an error draw their mark before the title" begin
    plain = _tn_texts(TooltipNote(; title = "Folder"))
    @test _tn_place(plain, "Folder")[1] == 0
    for tone in (:warning, :error)
        texts = _tn_texts(TooltipNote(; title = "Folder", tone))
        @test length(texts) == 2
        mark = only(place for place in texts if place[1] != "Folder")
        @test mark[1] == string(find_icon_character(:warning))
        @test mark[2] < _tn_place(texts, "Folder")[1]
    end
end

@testset "a piece that is a document stands as it is" begin
    texts = _tn_texts(TooltipNote(; title = "Name", facts = ["Kind" => WidgetLabel("a widget")]))
    @test _tn_place(texts, "a widget")[2] == _tn_place(texts, "Kind")[2]
end

end # @testset
end # function
