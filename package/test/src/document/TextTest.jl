
function test_text()
@testset "ReactiveText" begin

s1 = TextString("hello", font_ubuntu_monospace_bold_24, color_red)
@test s1.content == "hello"
@test s1.font == font_ubuntu_monospace_bold_24
@test s1.font_color == color_red

s1.content = "hi"
@test s1.content == "hi"

st = TextText(
    TextString("aaa", font_ubuntu_monospace_bold_24, color_red),
    TextString("bbb", font_ubuntu_monospace_regular_24, color_blue),
)
@test length(st.elements) == 2
@test st.elements[1].content == "aaa"

push!(st.elements, TextString("ccc", font_ubuntu_monospace_regular_24, color_default))
@test length(st.elements) == 3

deleteat!(st.elements, 2)
@test length(st.elements) == 2
@test st.elements[2].content == "ccc"

# computed text
counter = Cell(0)
dyn_span = TextString(() -> "n=$(counter[])", font_ubuntu_monospace_regular_24, color_white)
@test dyn_span.content == "n=0"
counter[] = 5
@test dyn_span.content == "n=5"

end # @testset "ReactiveText"

@testset "TextGraphics inline image span" begin

img = ImageMemory(nothing)
g = TextGraphics(img, 64, 48)
@test g.content === img
@test g.width == 64
@test g.height == 48

# Mixes cleanly with TextStrings inside a TextText; length / getindex hold.
st = TextText(
    TextString("ab", font_ubuntu_monospace_regular_24, color_red),
    TextGraphics(ImageMemory(nothing), 24, 24),
    TextString("cd", font_ubuntu_monospace_regular_24, color_blue),
)
@test length(st.elements) == 3
@test st.elements[1].content == "ab"
@test st.elements[2] isa TextGraphics
@test st.elements[2].width == 24
@test st.elements[3].content == "cd"

end # @testset "TextGraphics inline image span"
end # test_text
