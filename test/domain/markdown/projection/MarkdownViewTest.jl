# One Markdown document with a heading and a paragraph, in two views at three places
# of a vertical layout, printed by one recursion over the views at each stage:
# Markdown to syntax, syntax to text, and text to graphics. Each view keeps a caret
# of its own, the places of one view share its caret, and no content holds a caret.
# The heading, the paragraph and the run of text keep their children or their text
# in a field with the name `content`, which is a field of their views too. The
# helpers are those of the platform tests.

const _markdown_view_collect = ProjecturedPlatformTest._text_view_collect
const _markdown_view_caret_x = ProjecturedPlatformTest._text_view_caret_x
const _markdown_view_is_caret_live = ProjecturedPlatformTest._text_view_is_caret_live

function test_markdown_view()
@testset "MarkdownView" begin

measure = FixedMeasure(10, 18, 6, 0)
heading = MarkdownHeading(1, [MarkdownText("Title")])
paragraph = MarkdownParagraph([MarkdownText("abcd"), MarkdownStrong([MarkdownText("bold")])])
document = MarkdownRoot([heading, paragraph])
view_a = MarkdownRootView(document)
view_b = MarkdownRootView(document)
root = VerticalLayout([view_a, view_b, view_a])
stages = ChainingProjection(
    RecursiveProjection(ViewingProjection(MarkdownToSyntax())),
    RecursiveProjection(ViewingProjection(SyntaxToText(text_folds = true))),
    TextFolding(),
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        TextView  => TextViewToGraphicsCanvas(),
        TextBlock => TextBlockToGraphicsCanvas(; measure),
    ])))
projection = RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
    VerticalLayout   => VerticalLayoutToGraphicsCanvas(),
    MarkdownRootView => stages,
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
stored(view) = strip_reference_types(get_stored_selection(view))
plain(path) = strip_reference_types(path)
drawn() = _markdown_view_collect(iomap, TextViewToGraphicsCanvasIoMap)
# The text that each place draws.
texts() = [get_flat_string(m.input.viewed) for m in drawn()]

@testset "Each node has a view of its kind, under the name of the field of its content" begin
    @test view_a.elements[1] isa MarkdownHeadingView && view_a.elements[2] isa MarkdownParagraphView
    @test view_a.elements[1].content[1] isa MarkdownTextView
    @test view_a.elements[2].content[1] isa MarkdownTextView
    @test view_a.elements[1].viewed === heading && view_a.elements[2].viewed === paragraph
    @test view_a.elements[2].content[1].viewed === paragraph.content[1]
    @test view_a.elements[2] !== view_b.elements[2]
    @test view_a.elements[2].content[1] !== view_b.elements[2].content[1]
    @test texts() == fill("# Title\n\nabcd**bold**", 3)
end

@testset "A Markdown type with no view prints as content" begin
    @test paragraph.content[2] isa MarkdownStrong
    @test view_a.elements[2].content[2] === nothing
end

@testset "The step of the document gives the view of its node over the views of its blocks" begin
    step = first(filter(m -> m.input === view_a, _markdown_view_collect(iomap, ViewingIoMap)))
    @test step.output isa SyntaxNodeView && step.output.viewed === step.content.output
    children = collect(step.output.children)
    @test length(children) == 2 && all(child -> child isa SyntaxNodeView, children)
    @test all(i -> children[i].viewed === step.output.viewed.children[i], 1:2)
    # The view of the node of the paragraph holds the view of the leaf of its text.
    @test children[2].children[1] isa SyntaxLeafView
end

@testset "The carets live on the views, and no content holds one" begin
    replace_selection!(root, at(2, @reference(view_b, elements[1].content[1].content{1})))
    replace_selection!(root, at(1, @reference(view_a, elements[2].content[1].content{2})))
    @test stored(view_a.elements[2].content[1]) == plain(@reference(view_a.elements[2].content[1], content{2}))
    @test stored(view_b.elements[1].content[1]) == plain(@reference(view_b.elements[1].content[1], content{1}))
    @test is_live_selection(view_a) && !is_live_selection(view_b)
    @test all(node -> get_stored_selection(node) === nothing,
              (document, heading, paragraph, heading.content[1], paragraph.content[1]))
end

@testset "Only the place on the path from the root draws a live caret" begin
    # The paragraph is the third line: `ab|cd` puts the caret of view A at 20. The
    # heading is the first line: `# T|itle` puts the caret of view B at 30.
    @test _markdown_view_caret_x.(drawn()) == [20, 30, 20]
    @test _markdown_view_is_caret_live.(drawn()) == [true, false, false]
    replace_selection!(root, at(3, @reference(view_a, elements[2].content[1].content{2})))
    @test _markdown_view_is_caret_live.(drawn()) == [false, false, true]
    replace_selection!(root, at(1, @reference(view_a, elements[2].content[1].content{2})))
end

@testset "A typed character edits the text through its view" begin
    @test press!(typed('X')) isa ReplaceStringRangeOperation
    @test paragraph.content[1].content == "abXcd"
    @test stored(view_a) == plain(@reference(view_a, elements[2].content[1].content{3}))
    @test stored(view_b.elements[1].content[1]) == plain(@reference(view_b.elements[1].content[1], content{1}))
    @test get_stored_selection(paragraph.content[1]) === nothing
    @test texts() == fill("# Title\n\nabXcd**bold**", 3)
end

@testset "A key moves the caret of the view" begin
    @test press!(KeyDown(:right, ModifierKeys(); time = 0.0)) isa ReplaceSelectionOperation
    @test stored(view_a) == plain(@reference(view_a, elements[2].content[1].content{4}))
    @test _markdown_view_caret_x.(drawn()) == [40, 30, 40]
end

@testset "A typed character edits the text of the heading through its view" begin
    replace_selection!(root, at(2, @reference(view_b, elements[1].content[1].content{5})))
    @test press!(typed('!')) isa ReplaceStringRangeOperation
    @test heading.content[1].content == "Title!"
    @test stored(view_b) == plain(@reference(view_b, elements[1].content[1].content{6}))
    @test texts() == fill("# Title!\n\nabXcd**bold**", 3)
end

@testset "A document with no view prints as content" begin
    output = print_document(RecursiveProjection(ViewingProjection(MarkdownToSyntax())), document).output
    @test output isa SyntaxNode
end

@testset "The view types of Markdown take the declaration" begin
    run = MarkdownText("a")
    @test fieldnames(MarkdownTextView)[1] === :viewed && !(:content in fieldnames(MarkdownTextView))
    @test make_content_view(run) isa MarkdownTextView && make_content_view(run).viewed === run
    for (view_type, content, field) in [(MarkdownParagraphView, MarkdownParagraph([MarkdownText("b")]), :content),
                                        (MarkdownHeadingView, MarkdownHeading(1, [MarkdownText("c")]), :content),
                                        (MarkdownRootView, MarkdownRoot([MarkdownParagraph([MarkdownText("d")])]), :elements)]
        made = make_content_view(content)
        @test fieldnames(view_type)[1:2] == (:viewed, field)
        @test made isa view_type && made.viewed === content
        @test getproperty(made, field) isa CellVectorView &&
              getproperty(made, field).viewed === getproperty(content, field)
    end
    @test !(:level in fieldnames(MarkdownHeadingView)) && !(:collapsed in fieldnames(MarkdownRootView))
end

end
end
