# The label of a tab that says more than a name. The strip draws its icon, its
# text and its badges in that order; a label with a text only draws as a string
# selector draws; a badge in a tab looks as the same badge looks alone; a label
# follows its cells with no write; a caret in its text is a caret in the name; and
# a rest of the pointer on the tab says its tooltip.

# Every text that `node` draws: `(text, x, y, color, font family)`, with `x` and
# `y` in the frame of `node`, in the order of drawing.
function _collect_label_texts(node, ox = 0, oy = 0, found = Any[])
    if node isa GraphicsCanvas
        for element in node.elements
            _collect_label_texts(element, ox + Int(node.x), oy + Int(node.y), found)
        end
    elseif node isa GraphicsViewport
        _collect_label_texts(node.content, ox + Int(node.x), oy + Int(node.y), found)
    elseif node isa GraphicsText
        push!(found, (String(node.text), ox + Int(node.x), oy + Int(node.y), node.color, node.font.family))
    end
    found
end

# The first drawn text equal to `text`, or `nothing`.
function _find_label_text(texts, text)
    index = findfirst(t -> t[1] == text, texts)
    index === nothing ? nothing : texts[index]
end

function test_widget_tab_label()
@testset "WidgetTabLabel" begin

stub = FixedMeasure(10, 18, 6, 0)
make_projection() = make_widget_projection_example(measure = stub)
badges() = Any[WidgetBadge("37/40"; role = :accent), WidgetBadge("2 failed"; role = :error)]
pane_of(selector) = WidgetTabbedPane(Any[WidgetTabPage(selector, WidgetLabel("body")),
                                         ("two", WidgetLabel("2"))])
texts_of(document) = _collect_label_texts(print_document(make_projection(), document).output)

@testset "the strip draws the icon, the text and the badges in order" begin
    texts = texts_of(pane_of(WidgetTabLabel("Tests"; icon = :loader, badges = badges())))
    name = _find_label_text(texts, "Tests")
    count = _find_label_text(texts, "37/40")
    failed = _find_label_text(texts, "2 failed")
    next = _find_label_text(texts, "two")
    @test name !== nothing && count !== nothing && failed !== nothing && next !== nothing
    @test name[2] < count[2] < failed[2] < next[2]
    # The text and the badges share one line of the strip.
    @test abs(count[3] - name[3]) < 18 && abs(failed[3] - name[3]) < 18
    # The icon is a glyph of the icon font, before the text.
    icon = only(t for t in texts if t[5] == "Lucide" && t[3] < 40)
    @test icon[2] < name[2]
end

@testset "a label with a text only draws as a string selector" begin
    plain = texts_of(pane_of("Tests"))
    label = texts_of(pane_of(WidgetTabLabel("Tests")))
    @test [(t[1], t[2], t[3]) for t in label] == [(t[1], t[2], t[3]) for t in plain]
end

@testset "the icon of a label wins over the icon of its page" begin
    page(selector) = WidgetTabbedPane(Any[WidgetTabPage(selector, WidgetLabel("body"), :file)])
    glyph(texts) = only(t[1] for t in texts if t[5] == "Lucide")
    @test glyph(texts_of(page(WidgetTabLabel("Tests"; icon = :loader)))) !=
          glyph(texts_of(page(WidgetTabLabel("Tests"))))
    @test glyph(texts_of(page(WidgetTabLabel("Tests")))) == glyph(texts_of(page("Tests")))
end

@testset "a badge in a tab looks as the same badge looks alone" begin
    in_tab = _find_label_text(texts_of(pane_of(WidgetTabLabel("Tests"; badges = badges()))), "2 failed")
    alone = _find_label_text(texts_of(WidgetBadge("2 failed"; role = :error)), "2 failed")
    plain = _find_label_text(texts_of(WidgetBadge("2 failed")), "2 failed")
    @test in_tab[4] == alone[4]
    @test alone[4] != plain[4]
    success = _find_label_text(texts_of(WidgetBadge("ok"; role = :success)), "ok")
    @test success[4] != alone[4]
end

@testset "a badge refuses a role it does not know" begin
    @test_throws Exception texts_of(WidgetBadge("x"; role = :purple))
end

@testset "a label follows its cells with no write to the label" begin
    finished = Cell(1)
    label = WidgetTabLabel("Tests"; badges = () -> Any[WidgetBadge(string(finished[], "/3"))],
                           icon = () -> finished[] == 3 ? :circle_check : :loader)
    canvas = print_document(make_projection(), pane_of(label)).output
    glyph() = only(t[1] for t in _collect_label_texts(canvas) if t[5] == "Lucide")
    @test _find_label_text(_collect_label_texts(canvas), "1/3") !== nothing
    running = glyph()
    finished[] = 3
    @test _find_label_text(_collect_label_texts(canvas), "3/3") !== nothing
    @test _find_label_text(_collect_label_texts(canvas), "1/3") === nothing
    @test glyph() != running
end

@testset "a caret in the text of a label is a caret in the name" begin
    find_caret = WidgetModule._find_tab_name_caret
    in_label = Reference(FieldReferenceStep("selector_element_pairs"), ElementReferenceStep(2),
                         FieldReferenceStep("selector"), FieldReferenceStep("text"),
                         RangeReferenceStep(3, 3))
    in_string = Reference(FieldReferenceStep("selector_element_pairs"), ElementReferenceStep(2),
                          FieldReferenceStep("selector"), RangeReferenceStep(3, 3))
    elsewhere = Reference(FieldReferenceStep("selector_element_pairs"), ElementReferenceStep(2),
                          FieldReferenceStep("selector"), FieldReferenceStep("badges"),
                          RangeReferenceStep(0, 1))
    @test find_caret(in_label) == (2, 3)
    @test find_caret(in_string) == (2, 3)
    @test find_caret(elsewhere) === nothing
end

@testset "a rest of the pointer on the tab says its tooltip" begin
    projection = make_projection()
    pane = pane_of(WidgetTabLabel("Tests"; badges = badges(), tooltip = "37 of 40 finished"))
    iomap = print_document(projection, pane)
    name = _find_label_text(_collect_label_texts(iomap.output), "Tests")
    operation = read_intent(projection, iomap, MouseDwell(name[2] + 2, name[3] + 2; time = 0.0))
    @test operation !== nothing
    open = get_wrapped_operation(operation)
    @test open isa OpenTooltipOperation
    @test any(layer -> last(layer) isa PrimitiveString && last(layer).value == "37 of 40 finished",
              open.layers)
    # A tab with no tooltip says nothing of its own.
    plain = print_document(projection, pane_of("Tests"))
    name = _find_label_text(_collect_label_texts(plain.output), "Tests")
    quiet = read_intent(projection, plain, MouseDwell(name[2] + 2, name[3] + 2; time = 0.0))
    @test quiet === nothing || !any(layer -> last(layer) isa PrimitiveString,
                                    get_wrapped_operation(quiet).layers)
end

end
end
