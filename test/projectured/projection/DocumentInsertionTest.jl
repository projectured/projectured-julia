# Tests for the insert-by-typing mechanism (DocumentInsertionToSyntax):
# typing a domain name into a DocumentInsertion and committing it to that
# domain's document/insertion, and committing Julia source via JuliaInsertion —
# plus the reflection-based completion machinery (DomainModule) and the
# @domain-generated Insert/Escape kit.


# A `make_replace_document_operation(path, doc)` fold expands to a CompoundOperation whose
# first member is the ReplaceReferencedValueOperation that writes `doc`.
_written_doc(op) = op.operations[1].value

_ins_vpath(n) = ConcreteReference(FieldReferenceStep("value"),
                    ConcreteReference(RangeReferenceStep(n, n), EmptyReference()))

# A document type defined by nobody but this test file: the reflection must
# pick it up with zero registration (a zero-arg constructor is enough).
struct InsertionReflectionProbe <: Document
    selection::Any
end
InsertionReflectionProbe() = InsertionReflectionProbe(nothing)


# The colour of a role of the colour theme in the default appearance: the colour
# of the typed text of an insertion while it names nothing (`text`), one thing
# (`success_text`) or a wrong thing (`error_text`), and of its hint (`text_faint`).
_insertion_role(name) = resolve_theme_color(ColorRole(name), Appearance())

function test_document_insertion()
    @testset "DocumentInsertion insert-by-typing" begin
        @testset "factory + completion" begin
            @test default_factory("julia") isa JuliaInsertion
            @test default_factory("json")  isa JsonInsertion
            @test default_factory("sql")   isa SqlInsertion
            @test default_factory("text")  isa TextInsertion
            @test default_factory("zzz")   === nothing
            @test default_completion("jso") == "n"
            @test default_completion("xyz") == ""
        end

        @testset "derived names" begin
            DS = DomainModule
            @test DS.get_insertion_names(JsonString) == ["JsonString", "json string"]
            @test DS.get_insertion_names(JsonObjectEntry; root = JsonDocument) ==
                  ["JsonObjectEntry", "json object entry", "ObjectEntry", "object entry"]
            @test "julia" in DS.get_insertion_names(JuliaInsertion)     # @domain alias
            @test "text" in DS.get_insertion_names(TextInsertion)       # @domain alias
            # `text` names the domain entry, so the container answers to its own
            # name — prefix-free inside the Text scope, prefixed outside it.
            @test DS.get_insertion_names(TextBlock) == ["TextBlock", "text block"]
            @test DS.get_insertion_names(TextBlock; root = TextDocument) ==
                  ["TextBlock", "text block", "Block", "block"]
            @test DS.resolve_insertion(TextDocument, "block") === TextBlock
            # It is also the only candidate in the scope, so the bare domain name
            # still commits it by unambiguous prefix. That holds only because
            # `TextLine` opts out: it is zero-arg constructible, so without the
            # opt-out it would be a candidate — one that makes `text` ambiguous,
            # and that commits a lone line as a *root* document.
            @test !DS.insertable(TextLine)
            @test !(TextLine in DS.get_insertion_candidates(TextDocument))
            @test DS.resolve_insertion(TextDocument, "text") === TextBlock
            @test DS.get_domain_prefix(JsonDocument) == "Json"
            @test DS.get_domain_prefix(TextDocument) == "Text"
            @test DS.get_domain_prefix(Document) == ""
        end

        @testset "completion states" begin
            DS = DomainModule
            @test DS.complete_insertion(Document, "  ").state === :empty
            @test DS.complete_insertion(Document, "zzz").state === :invalid
            # Unambiguous: only JsonString continues "json str"; the pale
            # continuation is the matching names' common remainder.
            c = DS.complete_insertion(Document, "json str")
            @test c.state === :unambiguous && c.continuation == "ing"
            @test c.matches == [JsonString]
            # Ambiguous: every Json* candidate matches "jso", but they still
            # share the partial continuation "n" (Tab's LCP extension).
            a = DS.complete_insertion(Document, "jso")
            @test a.state === :ambiguous && a.continuation == "n"
            @test length(a.matches) > 1
            # Prefix-free matching inside a domain scope.
            j = DS.complete_insertion(JsonDocument, "str")
            @test j.state === :unambiguous && j.continuation == "ing"
            @test j.matches == [JsonString]
            # Case-insensitive matching; continuation keeps the name's case.
            @test DS.complete_insertion(Document, "jsonstr").continuation == "ing"
        end

        @testset "resolution" begin
            DS = DomainModule
            # Exact type name / human-readable name / alias all commit.
            @test DS.resolve_insertion(Document, "JsonString") === JsonString
            @test DS.resolve_insertion(Document, "json string") === JsonString
            @test DS.resolve_insertion(Document, "julia") === JuliaInsertion
            # An unambiguous prefix commits; an ambiguous one does not.
            @test DS.resolve_insertion(Document, "json str") === JsonString
            @test DS.resolve_insertion(Document, "jso") === nothing
            # Prefix-free in a domain scope.
            @test DS.resolve_insertion(JsonDocument, "string") === JsonString
            @test DS.resolve_insertion(JsonDocument, "null") === JsonNull
            @test default_factory("json string") isa JsonString
        end

        @testset "reflection auto-extension" begin
            DS = DomainModule
            # InsertionReflectionProbe is defined only in this test file — no
            # registration anywhere — yet it is a candidate with derived names.
            @test InsertionReflectionProbe in DS.get_insertion_candidates(Document)
            @test DS.resolve_insertion(Document, "insertion reflection probe") ===
                  InsertionReflectionProbe
            @test DS.make_insertion_document(InsertionReflectionProbe) isa
                  InsertionReflectionProbe
        end

        @testset "the type search walks the modules once and misses no type" begin
            DS = DomainModule
            named = DS._collect_named_types(Base.get_world_counter())
            # The oracle shares no selection with the search: every concrete type
            # bound under its own name in a loaded module or a submodule, kept
            # when it is a subtype of the root at any depth.
            function collect_concrete_named_subtypes(root)
                found = Any[]
                mods = Base.loaded_modules_array()
                while !isempty(mods)
                    m = pop!(mods)
                    for s in names(m; all = true)
                        (Base.isdeprecated(m, s) || !isdefined(m, s)) && continue
                        t = getglobal(m, s)
                        if t isa Type
                            dt = Base.unwrap_unionall(t)
                            dt isa DataType && dt.name.name === s && dt.name.module === m &&
                                !isabstracttype(t) && t <: root && push!(found, t)
                        elseif t isa Module && nameof(t) === s && parentmodule(t) === m &&
                               t !== m && t !== Base
                            push!(mods, t)
                        end
                    end
                end
                found
            end
            searched = DS._collect_concrete!(Type[], Document, named)
            @test InsertionReflectionProbe in searched
            @test issetequal(searched, collect_concrete_named_subtypes(Document))
            # The order is depth first, each level in the order of
            # `compute_loaded_subtypes`, which walks the modules again for every
            # abstract type.
            function collect_concrete_by_subtypes!(out, root)
                for T in DS.compute_loaded_subtypes(root)
                    isabstracttype(T) ? collect_concrete_by_subtypes!(out, T) : push!(out, T)
                end
                out
            end
            @test DS._collect_concrete!(Type[], JsonDocument, named) ==
                  collect_concrete_by_subtypes!(Type[], JsonDocument)
            # The public walker gives the same answer, the same vector while no
            # type or method is defined, and walks any root, not only a document.
            @test DS.compute_concrete_subtypes(Document) == searched
            @test DS.compute_concrete_subtypes(Document) === DS.compute_concrete_subtypes(Document)
            @test ChainingProjection in DS.compute_concrete_subtypes(Projection)
            @test !any(isabstracttype, DS.compute_concrete_subtypes(Projection))
        end

        @testset "@domain kit: *Nothing + Insert/Escape" begin
            DS = DomainModule
            # Generated placeholders exist and are excluded from candidates.
            @test JsonNothing <: JsonDocument && XmlNothing <: XmlDocument &&
                  YamlNothing <: YamlDocument && SqlNothing <: SqlDocument &&
                  TextNothing <: TextDocument
            @test !DS.insertable(JsonNothing)
            @test !(JsonNothing in DS.get_insertion_candidates(JsonDocument))
            # Traits pair each placeholder with its insertion, both ways.
            @test DS.get_insertion_document(JsonNothing) === JsonInsertion
            @test DS.get_nothing_document(JsonInsertion) === JsonNothing
            @test DS.get_insertion_document(JuliaNothing) === JuliaInsertion
            @test DS.get_nothing_document(DocumentInsertion) === DocumentNothing
            # Insert on a placeholder replaces it with its domain's insertion,
            # cursor at the start of the value buffer.
            for (N, I) in ((DocumentNothing, DocumentInsertion),
                           (JsonNothing, JsonInsertion),
                           (XmlNothing, XmlInsertion),
                           (TextNothing, TextInsertion),
                           (JuliaNothing, JuliaInsertion))
                op = GestureBindingModule.read_bound_gesture(N(), KeyDown(:insert, ModifierKeys(); time = 0.0))
                @test op isa CompoundOperation
                written = _written_doc(op)
                @test written isa I
                # `set_selection!` decorates the cursor with type checkpoints,
                # so compare the printed form. The cursor terminal records
                # `::Position` (the value a zero-width caret evaluates to).
                @test string(getfield(written, :selection)[]) ==
                      "::$(nameof(I)).value::String{0}::Position"
            end
        end

        @testset "a committed insertion is editable" begin
            DS = DomainModule
            # Every committed candidate must land with a usable cursor. The Text
            # container is the regression: without its `@insertion` factory the
            # generic fallback built a bare `TextBlock()` — no spans, no selection —
            # and every character gesture declined for want of a caret, so the
            # freshly inserted text took no keystrokes.
            text = DS.make_insertion_document(TextBlock)
            @test length(text.elements) == 1
            @test text.elements[1] isa TextString
            @test string(getfield(text, :selection)[]) ==
                  "::TextBlock.elements::CellVector[1]::TextString.content::String{0}::Position"
            @test make_text_insert_operation(text, "a") isa ReplaceStringRangeOperation
        end

        @testset "rendered completion feedback" begin
            proj = DocumentInsertionToSyntaxLeaf()
            ins = DocumentInsertion("")
            ins.selection = _ins_vpath(0)
            iom = print_document(proj, proj, ins, nothing)
            node = iom.output
            # Structure: node open/close carry the label, the inner leaf the
            # typed value (reactive colour) and the pale continuation hint.
            @test node isa SyntaxDelimitation      # one leaf behind a prefix/suffix, not a sequence
            @test node.opening_delimiter.content == "Insert a new "
            @test node.closing_delimiter.content == " here"
            leaf = node.content
            @test leaf isa SyntaxLeaf
            # Empty buffer: neutral colour, no hint.
            @test leaf.value.font_color == _insertion_role(:text)
            @test leaf.close.content == ""
            # Ambiguous prefix: green typed text, no hint (Tab-only LCP).
            ins.value = "jso"
            @test leaf.value.font_color == _insertion_role(:success_text)
            @test leaf.close.content == ""
            # Unambiguous prefix: green + the continuation hint, pale green.
            ins.value = "json str"
            @test leaf.value.font_color == _insertion_role(:success_text)
            @test leaf.close.content == "ing"
            @test leaf.close.font_color == _insertion_role(:text_faint)
            # Dead end: red, no hint.
            ins.value = "zzz"
            @test leaf.value.font_color == _insertion_role(:error_text)
            @test leaf.close.content == ""
            # The value cursor round-trips through the wrapper's `.content`.
            fwd = map_reference_forward(proj, iom, _ins_vpath(2))
            @test fwd !== nothing
            back = map_reference_backward(proj, iom, fwd)
            @test ReferenceModule.strip_reference_types(back) ==
                  ReferenceModule.strip_reference_types(_ins_vpath(2))
            # The node selection is the forward image of the insertion's own cursor.
            @test string(ReferenceModule.strip_reference_types(node.selection)) ==
                  ".content.value{0}"
        end

        @testset "type domain name -> domain insertion" begin
            ins = DocumentInsertion("juli")
            ins.selection = _ins_vpath(4)
            proj = DocumentInsertionToSyntaxLeaf()
            iom = print_document(proj, proj, ins, nothing)

            # A printable key edits the value.
            op = read_intent(proj, iom, KeyPress('a'; time = 0.0))
            @test op isa ReplaceStringRangeOperation
            evaluate_operation((document = ins,), op)
            @test ins.value == "julia"

            # Enter commits via the factory → a JuliaInsertion.
            ins.selection = _ins_vpath(length(ins.value))
            commit = read_intent(proj, iom, KeyDown(:return, ModifierKeys(); time = 0.0))
            @test commit isa CompoundOperation
            @test _written_doc(commit) isa JuliaInsertion

            # Escape aborts to DocumentNothing.
            esc = read_intent(proj, iom, KeyDown(:escape, ModifierKeys(); time = 0.0))
            @test esc isa CompoundOperation
            @test _written_doc(esc) isa DocumentNothing
        end

        @testset "Enter prefix-commit + Tab accept-completion" begin
            proj = DocumentInsertionToSyntaxLeaf()
            # Ambiguous prefix: Enter declines; Tab appends the partial
            # (longest-common-prefix) completion the hint doesn't show.
            ins = DocumentInsertion("jso")
            ins.selection = _ins_vpath(3)
            iom = print_document(proj, proj, ins, nothing)
            @test read_intent(proj, iom, KeyDown(:return, ModifierKeys(); time = 0.0)) === nothing
            tab = read_intent(proj, iom, KeyDown(:tab, ModifierKeys(); time = 0.0))
            @test tab isa ReplaceStringRangeOperation
            evaluate_operation((document = ins,), tab)
            @test ins.value == "json"
            # Fully ambiguous ("json" extends nowhere): Tab declines so the
            # gesture keeps propagating; Enter commits the exact alias.
            ins.selection = _ins_vpath(4)
            @test read_intent(proj, iom, KeyDown(:tab, ModifierKeys(); time = 0.0)) === nothing
            @test _written_doc(read_intent(proj, iom, KeyDown(:return, ModifierKeys(); time = 0.0))) isa JsonInsertion
            # Unambiguous prefix: Tab accepts the whole remainder; Enter
            # commits without accepting first.
            ins.value = "json str"
            ins.selection = _ins_vpath(8)
            tab2 = read_intent(proj, iom, KeyDown(:tab, ModifierKeys(); time = 0.0))
            evaluate_operation((document = ins,), tab2)
            @test ins.value == "json string"
            @test _written_doc(read_intent(proj, iom, KeyDown(:return, ModifierKeys(); time = 0.0))) isa JsonString
            ins.value = "json str"
            @test _written_doc(read_intent(proj, iom, KeyDown(:return, ModifierKeys(); time = 0.0))) isa JsonString
        end

        @testset "domain-constrained insertions (prefix-free)" begin
            # JsonInsertion: a typed-name buffer over the JSON candidates.
            jproj = JsonInsertionToSyntaxLeaf()
            jins = JsonInsertion()
            jins.selection = _ins_vpath(0)
            jiom = print_document(jproj, jproj, jins, nothing)
            for ch in "str"
                evaluate_operation((document = jins,), read_intent(jproj, jiom, KeyPress(ch; time = 0.0)))
            end
            @test jins.value == "str"
            # Unambiguous prefix-free hint + green, and Enter commits JsonString.
            leaf = jiom.output.content
            @test leaf.close.content == "ing"
            @test leaf.value.font_color == _insertion_role(:success_text)
            commit = read_intent(jproj, jiom, KeyDown(:return, ModifierKeys(); time = 0.0))
            @test _written_doc(commit) isa JsonString
            # Escape aborts to the domain's own placeholder.
            esc = read_intent(jproj, jiom, KeyDown(:escape, ModifierKeys(); time = 0.0))
            @test _written_doc(esc) isa JsonNothing
            # XmlInsertion likewise: `elem` resolves to XmlElement.
            xproj = XmlInsertionToSyntaxLeaf()
            xins = XmlInsertion("elem")
            xins.selection = _ins_vpath(4)
            xiom = print_document(xproj, xproj, xins, nothing)
            @test _written_doc(read_intent(xproj, xiom, KeyDown(:return, ModifierKeys(); time = 0.0))) isa XmlElement
            @test _written_doc(read_intent(xproj, xiom, KeyDown(:escape, ModifierKeys(); time = 0.0))) isa XmlNothing
            # The scaffold keywords are candidates too: `julia function` from
            # the top level builds the keyword scaffold (holes + cursor).
            @test default_factory("julia function") isa JuliaFunction
        end

        @testset "JuliaInsertion commitability colours" begin
            jproj = JuliaInsertionToSyntaxLeaf()
            ji = JuliaInsertion("")
            ji.selection = _ins_vpath(0)
            jiom = print_document(jproj, jproj, ji, nothing)
            leaf = jiom.output
            @test leaf.value.font_color == _insertion_role(:text)          # empty: neutral
            ji.value = "fun"
            @test leaf.value.font_color == _insertion_role(:success_text)  # keyword prefix
            @test leaf.close.content == "ction"
            @test leaf.close.font_color == _insertion_role(:text_faint)
            ji.value = "n * factorial(n"
            @test leaf.value.font_color == _insertion_role(:error_text)    # incomplete source
            ji.value = "n * factorial(n - 1)"
            @test leaf.value.font_color == _insertion_role(:success_text)  # parses
        end

        @testset "JuliaInsertion commits source via parse_julia" begin
            ji = JuliaInsertion("factorial(5)")
            ji.selection = _ins_vpath(length("factorial(5)"))
            jproj = JuliaInsertionToSyntaxLeaf()
            jiom = print_document(jproj, jproj, ji, nothing)
            commit = read_intent(jproj, jiom, KeyDown(:return, ModifierKeys(); time = 0.0))
            @test commit isa CompoundOperation
            @test _written_doc(commit) isa JuliaDocument

            # Unparseable / empty source cannot commit.
            empty_ji = JuliaInsertion("")
            empty_ji.selection = _ins_vpath(0)
            eiom = print_document(jproj, jproj, empty_ji, nothing)
            @test read_intent(jproj, eiom, KeyDown(:return, ModifierKeys(); time = 0.0)) === nothing
        end

        @testset "SqlInsertion commits source via parse_sql_text" begin
            si = SqlInsertion("SELECT * FROM persons")
            si.selection = _ins_vpath(length("SELECT * FROM persons"))
            sproj = SqlInsertionToSyntaxLeaf()
            siom = print_document(sproj, sproj, si, nothing)
            commit = read_intent(sproj, siom, KeyDown(:return, ModifierKeys(); time = 0.0))
            @test commit isa CompoundOperation
            @test _written_doc(commit) isa SqlStatement

            # Unparseable / empty source cannot commit.
            empty_si = SqlInsertion("")
            empty_si.selection = _ins_vpath(0)
            esiom = print_document(sproj, sproj, empty_si, nothing)
            @test read_intent(sproj, esiom, KeyDown(:return, ModifierKeys(); time = 0.0)) === nothing
        end
    end
end
