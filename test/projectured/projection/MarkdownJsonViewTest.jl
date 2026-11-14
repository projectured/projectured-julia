# One Markdown document that holds a JSON array, in two views at three places of a
# vertical layout: a view of the document, the view of its JSON part alone, and a
# second view of the document. The view of the document holds the view of the array
# as the view of one of its blocks, so the first and the second place show one JSON
# view, with one caret and one fold. The second view of the document has a view of
# the array of its own. Neither domain names the other: the stage of the syntax
# gives a node to the table of its domain. The helpers are those of the platform
# tests.

const _markdown_json_collect = ProjecturedPlatformTest._text_view_collect
const _markdown_json_caret_x = ProjecturedPlatformTest._text_view_caret_x
const _markdown_json_is_caret_live = ProjecturedPlatformTest._text_view_is_caret_live

function test_markdown_json_view()
@testset "A JSON part of a Markdown document, in its view and at a place of its own" begin

measure = FixedMeasure(10, 18, 6, 0)
array = JsonArray([JsonString("ab"), JsonNumber(42)])
heading = MarkdownHeading(1, [MarkdownText("Title")])
paragraph = MarkdownParagraph([MarkdownText("abcd")])
document = MarkdownRoot([heading, paragraph, array])
view = MarkdownRootView(document)
part = view.elements[3]
other = MarkdownRootView(document)
root = VerticalLayout([view, part, other])
stages = ChainingProjection(
    RecursiveProjection(ViewingProjection(make_markdown_json_to_syntax())),
    RecursiveProjection(ViewingProjection(SyntaxToText(text_folds = true))),
    TextFolding(),
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        TextView  => TextViewToGraphicsCanvas(),
        TextBlock => TextBlockToGraphicsCanvas(; measure),
    ])))
projection = RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
    VerticalLayout   => VerticalLayoutToGraphicsCanvas(),
    MarkdownRootView => stages,
    JsonArrayView    => stages,
]))
iomap = print_document(projection, root)
editor = (; document = root)
press!(event) = begin
    operation = read_intent(projection, iomap, event)
    operation === nothing || evaluate_operation(editor, operation)
    operation
end
typed(character) = KeyPress(character, ModifierKeys(); time = 0.0)

places = [@reference(root, children[1]), @reference(root, children[2]), @reference(root, children[3])]
at(place, path) = concat_references(places[place], strip_reference_types(path))
stored(node) = strip_reference_types(get_stored_selection(node))
plain(path) = strip_reference_types(path)
drawn() = _markdown_json_collect(iomap, TextViewToGraphicsCanvasIoMap)
# The text that each place draws.
texts() = [get_flat_string(m.input.viewed) for m in drawn()]
array_text(first_string) = "[\n  \"$first_string\",\n  42\n]"
document_text(title, prose, first_string) = "# $title\n\n$prose\n\n" * array_text(first_string)

@testset "The view of the document holds the view of its JSON part" begin
    @test view.elements[1] isa MarkdownHeadingView && view.elements[2] isa MarkdownParagraphView
    @test part isa JsonArrayView && part.viewed === array
    @test part.elements[1] isa JsonStringView && part.elements[2] isa JsonNumberView
    # A second view of the document has a view of the array of its own.
    @test other.elements[3] isa JsonArrayView && other.elements[3] !== part
    @test other.elements[3].viewed === array
    @test texts() == [document_text("Title", "abcd", "ab"), array_text("ab"), document_text("Title", "abcd", "ab")]
end

@testset "The step of the document gives the view of its node over the view of the node of the part" begin
    step = first(filter(m -> m.input === view, _markdown_json_collect(iomap, ViewingIoMap)))
    @test step.output isa SyntaxNodeView && step.output.viewed === step.content.output
    children = collect(step.output.children)
    @test length(children) == 3 && all(child -> child isa SyntaxNodeView, children)
    @test children[3].viewed === step.output.viewed.children[3]
    # The view of the node of the array is the output of the step of the view of
    # the array: it takes the fold of that view.
    part.collapsed = true
    @test children[3].collapsed
    part.collapsed = false
    @test !children[3].collapsed
end

@testset "The caret of the JSON part is one caret at its two places" begin
    replace_selection!(root, at(1, @reference(view, elements[3].elements[1].value{1})))
    @test stored(part) == plain(@reference(part, elements[1].value{1}))
    @test is_live_selection(view) && is_live_selection(part)
    @test get_stored_selection(other) === nothing
    @test all(node -> get_stored_selection(node) === nothing, (document, array, array.elements[1]))
    # The path goes through the first place, so the caret is live there, and the
    # place of the part draws the same caret as a dormant one. The line of the string
    # is `  "ab",`, so `.value{1}` is drawn at 40. The second view of the document
    # draws no caret.
    xs = _markdown_json_caret_x.(drawn())
    @test xs == [40, 40, nothing]
    @test _markdown_json_is_caret_live.(drawn()) == [true, false, false]
    # The path through the place of the part makes that place the live one.
    replace_selection!(root, at(2, @reference(part, elements[1].value{1})))
    @test stored(part) == plain(@reference(part, elements[1].value{1}))
    @test _markdown_json_caret_x.(drawn()) == xs
    @test _markdown_json_is_caret_live.(drawn()) == [false, true, false]
end

@testset "A typed character at the place of the part edits the array, and the document shows it" begin
    @test press!(typed('X')) isa ReplaceStringRangeOperation
    @test array.elements[1].value == "aXb"
    @test stored(part) == plain(@reference(part, elements[1].value{2}))
    @test texts() == [document_text("Title", "abcd", "aXb"), array_text("aXb"), document_text("Title", "abcd", "aXb")]
end

@testset "A typed character in the document edits the JSON part through the view of the document" begin
    replace_selection!(root, at(1, @reference(view, elements[3].elements[1].value{0})))
    @test press!(typed('Y')) isa ReplaceStringRangeOperation
    @test array.elements[1].value == "YaXb"
    @test stored(view) == plain(@reference(view, elements[3].elements[1].value{1}))
    @test get_stored_selection(array.elements[1]) === nothing
    @test texts()[2] == array_text("YaXb")
end

@testset "A typed character in the paragraph edits the Markdown beside the JSON part" begin
    replace_selection!(root, at(1, @reference(view, elements[2].content[1].content{4})))
    @test press!(typed('!')) isa ReplaceStringRangeOperation
    @test paragraph.content[1].content == "abcd!"
    @test stored(view) == plain(@reference(view, elements[2].content[1].content{5}))
    # The caret left the JSON part, whose view keeps its place as a dormant caret.
    @test stored(part) == plain(@reference(part, elements[1].value{1})) && !is_live_selection(part)
    @test texts() == [document_text("Title", "abcd!", "YaXb"), array_text("YaXb"),
                      document_text("Title", "abcd!", "YaXb")]
end

@testset "The fold of the JSON part is one fold at its two places" begin
    is_folded(text) = !occursin("\"YaXb\"", text)
    evaluate_operation(editor, ToggleFoldOperation(at(1, @reference(view, elements[3]))))
    @test part.collapsed && !other.elements[3].collapsed
    @test is_folded.(texts()) == [true, true, false]
    evaluate_operation(editor, ToggleFoldOperation(places[2]))
    @test !part.collapsed
    @test is_folded.(texts()) == [false, false, false]
end

@testset "A key of the JSON view fires inside the view of the document" begin
    # A key goes down along the live caret. The view of the document has no key
    # table; the view of the array is deeper on the caret and reads the comma.
    replace_selection!(root, at(1, @reference(view, elements[3].elements[2])))
    @test press!(typed(',')) isa CompoundOperation
    @test length(array.elements) == 3 && array.elements[3] isa JsonInsertion
    @test stored(view) == plain(@reference(view, elements[3].elements[3]))
    @test get_stored_selection(array) === nothing
    # A key that replaces an element with one of another kind.
    replace_selection!(root, at(1, @reference(view, elements[3].elements[2])))
    @test press!(typed('n')) isa CompoundOperation
    @test array.elements[2] isa JsonNull
    @test part.elements[2] isa JsonNullView && other.elements[3].elements[2] isa JsonNullView
    @test all(text -> occursin("\n  null,\n", text), texts())
    # The paragraph is no part of the array, so the comma of the array does not
    # fire there: the text takes the key and types it.
    replace_selection!(root, at(1, @reference(view, elements[2].content[1].content{0})))
    @test press!(typed(',')) isa ReplaceStringRangeOperation
    @test paragraph.content[1].content == ",abcd!"
    @test length(array.elements) == 3
end

end
end
