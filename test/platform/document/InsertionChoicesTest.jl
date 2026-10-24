# The kinds that a person picks from while typing: a whole name first, then a word
# of a name, and the traits that say what a kind shows and where it stands.

function test_insertion_choices()
@testset "insertion choices" begin
    @testset "a word of a name finds a kind, after the kinds of which a whole name starts so" begin
        found = find_insertion_choices(Document, "block")
        @test TextBlock in found
        starts(T) = any(name -> startswith(lowercase(name), "block"), get_insertion_names(T))
        @test !starts(TextBlock)
        # The kinds of which a whole name starts so come first.
        whole = filter(starts, found)
        @test found[1:length(whole)] == whole
        # A word match completes, with no continuation: its name does not start so.
        completed = complete_insertion(Document, "block")
        @test completed.state !== :invalid
        any(starts, found) || @test completed.continuation == ""
        # Nothing finds nothing, and an empty text finds every kind that is kept.
        @test isempty(find_insertion_choices(Document, "zzzzz"))
        kept = find_insertion_choices(Document, ""; include = T -> T === TextBlock)
        @test kept == Type[TextBlock]
    end

    @testset "a kind has no icon and stands as no element unless its domain says so" begin
        @test get_insertion_icon(TextBlock) === nothing
        @test !is_element_type(TextBlock)
    end

    @testset "an empty insertion shows a pale text that names what it takes" begin
        @test DOCUMENT_INSERTION_PLACEHOLDER == "Type a kind"
    end

    @testset "the first key of an insertion opens the list of the kinds it names, which the next keys type into" begin
        leaf = DocumentInsertionToSyntaxLeaf()
        insertion = with_value_caret(DocumentInsertion(""), 0)
        iomap = print_document(leaf, nothing, insertion, PrinterContext())
        answer = read_intent(leaf, iomap, KeyPress('c'; time = 0.0))
        @test answer isa CompoundOperation
        typed, opened = answer.operations
        @test typed isa ReplaceStringRangeOperation && typed.replacement == "c"
        @test opened isa ReplaceViewStateOperation && opened.operation isa OpenContextMenuOperation
        list = opened.operation.layers[1][2]
        @test list isa WidgetChoiceList && list.query == "c"
        # The rows are the kinds that the text names, the whole-name matches first.
        @test [choice.value for choice in list.find("c")] == first(find_insertion_choices(Document, "c"), 12)
        @test all(choice -> !isempty(choice.label), list.find("c"))
        # A key in the list narrows it and writes the text of the field.
        insertion.value = "c"
        choice_projection = WidgetChoiceListToWidget()
        listed = print_document(choice_projection, nothing, list, PrinterContext())
        read_list(gesture) = read_intent(choice_projection, nothing, Intent(gesture), listed).operation
        narrowed = read_list(KeyPress('h'; time = 0.0))
        @test narrowed isa CompoundOperation
        edited = narrowed.operations[2]
        @test edited isa EditMenuPartOperation
        @test edited.operation isa ReplaceStringRangeOperation && edited.operation.replacement == "ch"
        @test string(edited.operation.reference) == ".value[1]"
        evaluate_operation(nothing, narrowed.operations[1])
        @test list.query == "ch"
        # Return makes a document of the kind of the first row in place of the insertion.
        found = list.find("ch")
        if !isempty(found)
            chosen = read_list(KeyPress('\n'; time = 0.0))
            made = chosen.operations[1].operation
            @test made.operations[1].value isa found[1].value
        end
        # An insertion of a domain, which a person types in place, opens no list.
        domain = DomainInsertionToSyntaxLeaf(TextDocument)
        text = with_value_caret(TextInsertion(""), 0)
        @test read_intent(domain, print_document(domain, nothing, text, PrinterContext()),
                          KeyPress('b'; time = 0.0)) isa ReplaceStringRangeOperation
    end
end
end
