# An edit of a break in a code block goes to its code: Enter inserts a `'\n'`, and
# Backspace at the start of a line or Delete at the end of one deletes a `'\n'`.

function test_markdown_code_block_edit()
@testset "Enter, Backspace and Delete edit the breaks of a code block" begin

projection = ChainingProjection(RecursiveProjection(MarkdownToSyntax()),
                                RecursiveProjection(SyntaxToText()),
                                TextToGraphics(; measure = FixedMeasure(8, 12, 4, 0)))
document = MarkdownRoot([MarkdownCodeBlock("julia", "ab\ncd")])

# Every canvas of a graphics output, so the printer computes the layout.
function _force_layout(node)
    if node isa GraphicsCanvas
        foreach(_force_layout, node.elements)
    elseif node isa GraphicsViewport
        _force_layout(node.content)
    end
end

# Put the caret at `selection`, press `key`, and evaluate what the key reads to.
function press!(selection, key)
    clear_selection!(document)
    set_selection!(document, selection)
    iomap = print_document(projection, document)
    _force_layout(iomap.output)
    op = read_intent(projection, iomap, (character = find_typed_character(key)) === nothing ? KeyDown(key, ModifierKeys(); time = 0.0) : KeyPress(character, ModifierKeys(); time = 0.0))
    op === nothing || evaluate_operation((document = document,), op)
    op
end

@test press!(@reference(document, elements[1].code{2}), :return) isa ReplaceStringRangeOperation
@test document.elements[1].code == "ab\n\ncd"
@test press!(@reference(document, elements[1].code{3}), :backspace) isa ReplaceStringRangeOperation
@test document.elements[1].code == "ab\ncd"
@test press!(@reference(document, elements[1].code{2}), :delete) isa ReplaceStringRangeOperation
@test document.elements[1].code == "abcd"

end # @testset
end
