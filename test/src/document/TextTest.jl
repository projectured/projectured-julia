
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
@test length(st) == 2
@test st[1].content == "aaa"

push!(st, TextString("ccc", font_ubuntu_monospace_regular_24, color_default))
@test length(st) == 3

deleteat!(st, 2)
@test length(st) == 2
@test st[2].content == "ccc"

# computed text
counter = Cell(0)
dyn_span = TextString(() -> "n=$(counter[])", font_ubuntu_monospace_regular_24, color_white)
@test dyn_span.content == "n=0"
counter[] = 5
@test dyn_span.content == "n=5"

end # @testset "ReactiveText"
end # test_text
