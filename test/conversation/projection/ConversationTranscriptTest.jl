# The transcript is READ, not written. This file holds the two halves of that:
# a click names the PART it landed in, and an edit that reaches the transcript is
# declined.
#
# Naming the part is what makes a copy possible. The clipboard copies what the
# selection names, so a selection that could only say "somewhere in this
# conversation" could only ever copy the whole conversation.

_transcript_measure(text, _font) = (length(text) * 10, 20)

function _transcript_render()
    doc = ProjecturedConversationExample.make_conversation_document_example()
    proj = ProjecturedConversationExample.make_conversation_widget_projection_example(
        measure = _transcript_measure)
    (doc, proj, print_document(proj, proj, doc, PrinterContext()))
end

# The text of every GraphicsText under a printed tree, through cells, canvases
# and viewports.
function _transcript_texts(node, out = String[])
    node isa ReactiveCell && return _transcript_texts(node[], out)
    node isa GraphicsText && (push!(out, String(node.text)); return out)
    for field in (:elements, :content)
        hasproperty(node, field) || continue
        value = getproperty(node, field)
        value isa ReactiveCell && (value = value[])
        if value isa AbstractVector
            for child in value
                _transcript_texts(child, out)
            end
        elseif value !== nothing && !(value isa AbstractString)
            _transcript_texts(value, out)
        end
    end
    out
end

# Every fold a scan of the left edge produces: each distinct operation a header
# click answers with, in the order the scan meets them.
function _scan_folds(proj, io)
    found = Any[]
    for y in 2:2:900, x in 16:6:120
        op = try
            read_intent(proj, io, MousePress(:left, x, y))
        catch
            nothing
        end
        (op isa ToggleCollapseOperation || op isa ToggleEvaluatorSectionOperation) || continue
        any(q -> q === op || (typeof(q) == typeof(op) && _same_fold(q, op)), found) || push!(found, op)
    end
    found
end
_same_fold(a::ToggleCollapseOperation, b::ToggleCollapseOperation) = a.target === b.target
_same_fold(a::ToggleEvaluatorSectionOperation, b::ToggleEvaluatorSectionOperation) =
    a.form === b.form && a.section === b.section

# `turns[i].parts[j]`, the shape a click on a part must produce.
_part_path(i::Int, j::Int) =
    ConcreteReference(FieldReferenceStep("turns"),
        ConcreteReference(RangeReferenceStep(i - 1, i),
            ConcreteReference(FieldReferenceStep("parts"),
                ConcreteReference(RangeReferenceStep(j - 1, j), EmptyReference()))))

# Every distinct selection a vertical scan produces, down four columns: a part's
# body starts past its card's padding and its chevron column, and a section of
# an evaluation sits further in than a paragraph.
function _scan_selections(proj, io)
    found = Any[]
    for y in 2:2:600, x in (40, 70, 100, 130)
        op = try
            read_intent(proj, io, MousePress(:left, x, y))
        catch
            nothing
        end
        op isa ReplaceSelectionOperation || continue
        p = op.path
        # A click in the padding between two parts names the conversation
        # itself. That is honest, and it is not a part, so the scan skips it.
        # `EmptyReference` is not a singleton, so this is a type test and not an
        # identity one.
        p isa EmptyReference && continue
        any(q -> string(q) == string(p), found) || push!(found, p)
    end
    found
end

const _TRANSCRIPT_ALT = ModifierKeys(alt = true)

# Every distinct selection an Alt+press scan produces, with one press point for
# each.
function _scan_whole_selections(proj, io)
    found = Dict{String,Any}()
    for y in 2:2:900, x in (20, 40, 70, 100, 130)
        op = try
            read_intent(proj, io, MousePress(:left, x, y, _TRANSCRIPT_ALT))
        catch
            nothing
        end
        op isa ReplaceSelectionOperation || continue
        haskey(found, string(op.path)) || (found[string(op.path)] = (op.path, x, y))
    end
    found
end

# The absolute box of every selection ring that draws.
function _transcript_rings(node, x = 0, y = 0, out = Tuple{Int,Int,Int,Int}[])
    node isa ReactiveCell && return _transcript_rings(node[], x, y, out)
    if node isa GraphicsCanvas
        nx, ny = x + Int(node.x), y + Int(node.y)
        for element in node.elements
            _transcript_rings(element, nx, ny, out)
        end
    elseif node isa GraphicsViewport
        _transcript_rings(node.content, x + Int(node.x), y + Int(node.y), out)
    elseif node isa GraphicsRect && Int(node.border_width) > 0 &&
           node.border_color.blue == SELECTION_RING_COLOR.blue &&
           node.border_color.red == SELECTION_RING_COLOR.red
        push!(out, (x + Int(node.x), y + Int(node.y), Int(node.w), Int(node.h)))
    end
    out
end

_turn_path(i::Int) = ConcreteReference(FieldReferenceStep("turns"),
                         ConcreteReference(RangeReferenceStep(i - 1, i), EmptyReference()))
_section_path(i::Int, j::Int, name) =
    ConcreteReference(FieldReferenceStep("turns"),
        ConcreteReference(RangeReferenceStep(i - 1, i),
            ConcreteReference(FieldReferenceStep("parts"),
                ConcreteReference(RangeReferenceStep(j - 1, j),
                    ConcreteReference(FieldReferenceStep("content"),
                        ConcreteReference(FieldReferenceStep(name), EmptyReference()))))))
_is_same_path(a, b) = string(strip_reference_types(a)) == string(strip_reference_types(b))

function test_conversation_transcript()
    @testset "a fold names its node, and a section fold names its section" begin
        doc, proj, io = _transcript_render()
        folds = _scan_folds(proj, io)
        # Every fold the scan finds is the transcript's own: a domain node or a
        # section of a form, never a widget.
        for op in folds
            if op isa ToggleCollapseOperation
                @test op.target isa ConversationTurn || op.target isa ConversationPart
            else
                @test op isa ToggleEvaluatorSectionOperation
            end
        end
        ef = doc.turns[3].parts[1].content
        @test ef isa EvaluatorForm
        sections = [op for op in folds if op isa ToggleEvaluatorSectionOperation && op.form === ef]
        @test Set(op.section for op in sections) == Set([:form, :result])

        # The result section starts open and draws its text; a fold closes it,
        # and the text goes with it. The form section is untouched.
        @test ef.result_collapsed == false
        @test "120" in _transcript_texts(io.output)
        evaluate_operation((document = doc,), only(op for op in sections if op.section === :result))
        @test ef.result_collapsed == true
        @test ef.form_collapsed == false
        @test !("120" in _transcript_texts(io.output))
        @test "code" in _transcript_texts(io.output)
        @test "result" in _transcript_texts(io.output)

        # A failed evaluation starts with its error folded, and says so.
        failed = EvaluatorForm(JuliaIdentifier("sqrt(-1)");
                               result = make_evaluator_result_text("DomainError"), is_error = true)
        @test failed.result_collapsed == true
        @test failed.form_collapsed == false
        @test get_evaluation_section_labels(failed) == ("code", "error")
    end

    @testset "the header of a form names the tool or the resource" begin
        read = EvaluatorForm(make_evaluator_arguments_text(Dict("uri" => "resource://guide/orientation"));
                             tool_name = "read_resource",
                             input = Dict{String,Any}("uri" => "resource://guide/orientation"))
        @test get_evaluation_title(read) == "resource · resource://guide/orientation"
        @test get_evaluation_section_labels(read) == ("arguments", "result")
        listing = EvaluatorForm(TextBlock(); tool_name = "list_resources")
        @test get_evaluation_title(listing) == "resources"
        search = EvaluatorForm(TextBlock(); tool_name = "search_api",
                               input = Dict{String,Any}("query" => "make_child_context", "kind" => "function"))
        @test get_evaluation_title(search) == "tool · search_api \"make_child_context\""
        bare = EvaluatorForm(TextBlock(); tool_name = "search_guides")
        @test get_evaluation_title(bare) == "tool · search_guides"
        long = EvaluatorForm(TextBlock(); tool_name = "search_api",
                             input = Dict{String,Any}("query" => "x"^80))
        @test endswith(get_evaluation_title(long), "…\"") && length(get_evaluation_title(long)) < 90
        @test get_evaluation_title(EvaluatorForm(JuliaIdentifier("1"))) == "eval"
        # The arguments of a call draw one line each, in key order.
        lines = [span.content for span in make_evaluator_arguments_text(Dict("uri" => "u", "depth" => 2)).elements
                 if hasproperty(span, :content)]
        @test join(lines) == "depth: 2\nuri: u"
    end

    @testset "a click names the part it landed in" begin
        (doc, proj, io) = _transcript_render()
        # A folded part shows its header and nothing else, and the header is
        # the fold. The thinking part starts folded, so it is unfolded first;
        # a click on it then names it like a click on any other part.
        doc.turns[2].parts[1].collapsed = false
        found = _scan_selections(proj, io)
        # The example is [user: 1 part], [assistant: 4 parts], [user: 1 part].
        # Every one of the six is reachable, and each is named exactly.
        wanted = [_part_path(1, 1), _part_path(2, 1), _part_path(2, 2),
                  _part_path(2, 3), _part_path(2, 4), _part_path(3, 1)]
        for w in wanted
            @test any(f -> string(f) == string(w), found)
        end
        # And nothing else. A click that lands in the padding between parts says
        # `EmptyReference` (the conversation itself), which the scan skips.
        @test length(found) == length(wanted)
    end

    @testset "a selection round-trips through both maps" begin
        doc = ProjecturedConversationExample.make_conversation_document_example()
        proj = RecursiveProjection(ConversationToWidget())
        io = print_document(proj, proj, doc, PrinterContext())
        for (i, j) in ((1, 1), (2, 1), (2, 4), (3, 1))
            path = _part_path(i, j)
            forward = map_reference_forward(io.projection, io, path)
            @test forward !== nothing
            back = map_reference_backward(io.projection, io, forward)
            @test string(back) == string(path)
        end
    end

    @testset "the transcript declines an edit" begin
        (doc, proj, io) = _transcript_render()
        # Each of the three edit operations, aimed at a part that exists. A
        # transcript records what was said; nothing here rewrites it.
        path = _part_path(2, 2)
        for op in (ReplaceReferencedValueOperation(nothing, path, "x"),
                   ReplaceStringRangeOperation(path, "x"),
                   ReplaceNumberRangeOperation(path, "1"))
            @test read_intent(proj, io, op) === nothing
        end
        # A selection is not an edit, and it passes.
        @test read_intent(proj, io, ReplaceSelectionOperation(EmptyReference())) isa
              ReplaceSelectionOperation
    end

    @testset "an Alt+click names the innermost object" begin
        (doc, proj, io) = _transcript_render()
        doc.turns[2].parts[1].collapsed = false
        found = _scan_whole_selections(proj, io)
        paths = [v[1] for v in values(found)]
        ef = doc.turns[3].parts[1].content
        # A message, from its header; a part; and both sections of the evaluation.
        for wanted in (_turn_path(1), _turn_path(2), _turn_path(3),
                       _part_path(2, 2), _part_path(3, 1),
                       _section_path(3, 1, "form"), _section_path(3, 1, "result"))
            @test any(p -> _is_same_path(p, wanted), paths)
        end
        @test evaluate_reference(doc, _section_path(3, 1, "form")) === ef.form
        @test evaluate_reference(doc, _section_path(3, 1, "result")) === ef.result
        # Nothing deeper than a section, and no text position.
        for p in paths
            steps = get_reference_steps(strip_reference_types(p))
            @test length(steps) in (0, 2, 4, 6)
        end
        # A plain press on the result still names the part that holds it.
        (_, x, y) = found[string(first(p for p in paths if _is_same_path(p, _section_path(3, 1, "result"))))]
        plain = read_intent(proj, io, MousePress(:left, x, y))
        @test plain isa ReplaceSelectionOperation
        @test _is_same_path(plain.path, _part_path(3, 1))
    end

    @testset "the selected object draws a ring, and nothing else does" begin
        (doc, proj, io) = _transcript_render()
        @test isempty(_transcript_rings(io.output))
        found = _scan_whole_selections(proj, io)
        for wanted in (_turn_path(2), _part_path(2, 2), _section_path(3, 1, "result"))
            (path, x, y) = found[string(first(v[1] for v in values(found) if _is_same_path(v[1], wanted)))]
            replace_selection!(doc, path)
            rings = _transcript_rings(io.output)
            @test length(rings) == 1
            # The ring holds the point that was pressed.
            (rx, ry, rw, rh) = only(rings)
            @test rx <= x < rx + rw && ry <= y < ry + rh
        end
        # The result's ring holds the text of the result.
        replace_selection!(doc, _section_path(3, 1, "result"))
        (rx, ry, rw, rh) = only(_transcript_rings(io.output))
        @test rw > 0 && rh > 0
        clear_selection!(doc)
        @test isempty(_transcript_rings(io.output))
    end

    @testset "Alt and an arrow walk the objects of the transcript" begin
        doc = ProjecturedConversationExample.make_conversation_document_example()
        walk(path, direction) = compute_transcript_walk(doc, path, direction)
        # The conversation: down to the first message, and nothing above it.
        @test _is_same_path(walk(EmptyReference(), :down), _turn_path(1))
        @test walk(EmptyReference(), :up) === nothing
        # Messages: up is the conversation, sideways the neighbours, down a part.
        @test walk(_turn_path(1), :up) isa EmptyReference
        @test _is_same_path(walk(_turn_path(1), :right), _turn_path(2))
        @test _is_same_path(walk(_turn_path(1), :left), _turn_path(1))
        @test _is_same_path(walk(_turn_path(3), :right), _turn_path(3))
        @test _is_same_path(walk(_turn_path(2), :down), _part_path(2, 1))
        # Parts: sideways inside their message, up to it.
        @test _is_same_path(walk(_part_path(2, 1), :right), _part_path(2, 2))
        @test _is_same_path(walk(_part_path(2, 4), :right), _part_path(2, 4))
        @test _is_same_path(walk(_part_path(2, 2), :up), _turn_path(2))
        @test _is_same_path(walk(_part_path(2, 2), :down), _part_path(2, 2))
        # An evaluation: down to its form, sideways to its result, and back up.
        @test _is_same_path(walk(_part_path(3, 1), :down), _section_path(3, 1, "form"))
        @test _is_same_path(walk(_section_path(3, 1, "form"), :right), _section_path(3, 1, "result"))
        @test _is_same_path(walk(_section_path(3, 1, "result"), :right), _section_path(3, 1, "result"))
        @test _is_same_path(walk(_section_path(3, 1, "result"), :left), _section_path(3, 1, "form"))
        @test _is_same_path(walk(_section_path(3, 1, "result"), :down), _section_path(3, 1, "result"))
        @test _is_same_path(walk(_section_path(3, 1, "result"), :up), _part_path(3, 1))
        @test walk(nothing, :up) === nothing

        # The reader answers the keys from the document's selection.
        (doc, proj, io) = _transcript_render()
        replace_selection!(doc, _part_path(3, 1))
        op = read_intent(proj, io, KeyDown(:down, _TRANSCRIPT_ALT))
        @test op isa ReplaceSelectionOperation
        @test _is_same_path(op.path, _section_path(3, 1, "form"))
    end

    @testset "a paste over the transcript is refused" begin
        conversation = ProjecturedConversationExample.make_conversation_document_example()
        # The stored object is a part, which the transcript's chain can draw.
        slice = ClipboardSlice(conversation, copy_document(conversation.turns[1].parts[1]))
        projection = ClipboardSliceToAnyProjection()
        inner = ProjecturedConversationExample.make_conversation_widget_projection_example(
            measure = _transcript_measure)
        io = print_document(projection, inner, slice, PrinterContext())
        ctrl = ModifierKeys(ctrl = true)
        content = FieldReferenceStep("content")
        for target in (EmptyReference(), _turn_path(2), _part_path(2, 2), _section_path(3, 1, "result"))
            slice.selection = ConcreteReference(content, target)
            @test !(read_intent(projection, io, KeyDown(:v, ctrl)) isa CompoundOperation)
            @test !(read_intent(projection, io, KeyDown(:x, ctrl)) isa CompoundOperation)
        end
        @test !accepts_pasted_document(conversation)
    end

    @testset "a message alone in a tab still folds from its chevron" begin
        turn = ProjecturedConversationExample.make_conversation_document_example().turns[2]
        proj = ProjecturedConversationExample.make_conversation_widget_projection_example(
            measure = _transcript_measure)
        io = print_document(proj, proj, turn, PrinterContext())
        folds = _scan_folds(proj, io)
        @test any(op -> op isa ToggleCollapseOperation && op.target === turn, folds)
    end

    # Copy needs nothing new. `ClipboardSlice` copies whatever the slice's
    # selection names, and the selection now names a part — so the two compose,
    # and a transcript wrapped in a slice can be copied out of message by
    # message. This asserts the composition, because it is the whole of the
    # copy story: no code in this package takes part in it.
    @testset "a selected part copies into a clipboard slice" begin
        conversation = ProjecturedConversationExample.make_conversation_document_example()
        slice = ClipboardSlice(conversation)
        # `content.turns[2].parts[2]`: the prose part of the assistant turn. The
        # extra `content` step is the slice's own — the conversation hangs off it.
        slice.selection = ConcreteReference(FieldReferenceStep("content"), _part_path(2, 2))
        projection = ClipboardSliceToAnyProjection()
        inner = ProjecturedConversationExample.make_conversation_widget_projection_example(
            measure = _transcript_measure)
        io = print_document(projection, inner, slice, PrinterContext())

        op = read_intent(projection, io, KeyDown(:c, ModifierKeys(ctrl = true)))
        @test op isa CompoundOperation
        evaluate_operation((document = slice,), op)

        # What landed in the slice is that part, deep-copied — the part itself,
        # not the turn around it and not the whole conversation.
        stored = slice.slice
        @test stored isa ConversationPart
        @test stored !== conversation.turns[2].parts[2]
        @test stored.content isa TextBlock
    end
end
