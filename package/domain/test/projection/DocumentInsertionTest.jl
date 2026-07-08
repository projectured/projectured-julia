# Tests for the insert-by-typing mechanism (DocumentInsertionToSyntax):
# typing a domain name into a DocumentInsertion and committing it to that
# domain's document/insertion, and committing Julia source via JuliaInsertion —
# plus the reflection-based completion machinery (DomainSupportModule) and the
# @domain-generated Insert/Escape kit.


# A `replace_document(path, doc)` fold expands to a CompoundOperation whose first
# member is the ReplaceReferencedValueOperation that writes `doc`.
_written_doc(op) = op.operations[1].value

_ins_vpath(n) = ConcreteReferencePath(FieldReference("value"),
                    ConcreteReferencePath(RangeReference(n, n), EmptyReferencePath()))

# A document type defined by nobody but this test file: the reflection must
# pick it up with zero registration (a zero-arg constructor is enough).
struct InsertionReflectionProbe <: Document
    selection::Any
end
InsertionReflectionProbe() = InsertionReflectionProbe(nothing)

function test_document_insertion()
    @testset "DocumentInsertion insert-by-typing" begin
        @testset "factory + completion" begin
            @test default_factory("julia") isa JuliaInsertion
            @test default_factory("json")  isa JsonInsertion
            @test default_factory("sql")   isa SqlInsertion
            @test default_factory("zzz")   === nothing
            @test default_completion("jso") == "n"
            @test default_completion("xyz") == ""
        end

        @testset "derived names" begin
            DS = DomainSupportModule
            @test DS.insertion_names(JsonString) == ["JsonString", "json string"]
            @test DS.insertion_names(JsonObjectEntry; root = JsonDocument) ==
                  ["JsonObjectEntry", "json object entry", "ObjectEntry", "object entry"]
            @test "julia" in DS.insertion_names(JuliaInsertion)     # @domain alias
            @test "text" in DS.insertion_names(TextText)            # hand-written alias
            @test DS.domain_prefix(JsonDocument) == "Json"
            @test DS.domain_prefix(Document) == ""
        end

        @testset "completion states" begin
            DS = DomainSupportModule
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
            DS = DomainSupportModule
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
            DS = DomainSupportModule
            # InsertionReflectionProbe is defined only in this test file — no
            # registration anywhere — yet it is a candidate with derived names.
            @test InsertionReflectionProbe in DS.insertion_candidates(Document)
            @test DS.resolve_insertion(Document, "insertion reflection probe") ===
                  InsertionReflectionProbe
            @test DS.make_insertion_document(InsertionReflectionProbe) isa
                  InsertionReflectionProbe
        end

        @testset "@domain kit: *Nothing + Insert/Escape" begin
            DS = DomainSupportModule
            # Generated placeholders exist and are excluded from candidates.
            @test JsonNothing <: JsonDocument && XmlNothing <: XmlDocument &&
                  YamlNothing <: YamlDocument && SqlNothing <: SqlDocument
            @test !DS.insertable(JsonNothing)
            @test !(JsonNothing in DS.insertion_candidates(JsonDocument))
            # Traits pair each placeholder with its insertion, both ways.
            @test DS.insertion_document(JsonNothing) === JsonInsertion
            @test DS.nothing_document(JsonInsertion) === JsonNothing
            @test DS.insertion_document(JuliaNothing) === JuliaInsertion
            @test DS.nothing_document(DocumentInsertion) === DocumentNothing
            # Insert on a placeholder replaces it with its domain's insertion,
            # cursor at the start of the value buffer.
            for (N, I) in ((DocumentNothing, DocumentInsertion),
                           (JsonNothing, JsonInsertion),
                           (XmlNothing, XmlInsertion),
                           (JuliaNothing, JuliaInsertion))
                op = GestureModule.read_document_gesture(N(), KeyDown(:insert, Modifiers()))
                @test op isa CompoundOperation
                written = _written_doc(op)
                @test written isa I
                # `with_selection` decorates the cursor with type checkpoints,
                # so compare the printed form.
                @test string(getfield(written, :selection)[]) ==
                      "::$(nameof(I)).value::String{0}"
            end
        end

        @testset "type domain name -> domain insertion" begin
            ins = DocumentInsertion("juli")
            ins.selection = _ins_vpath(4)
            proj = DocumentInsertionToSyntaxLeaf()
            iom = print_document(proj, proj, ins, nothing)

            # A printable key edits the value.
            op = read_intent(proj, iom, KeyPress('a'))
            @test op isa ReplaceStringRangeOperation
            evaluate_operation((document = ins,), op)
            @test ins.value == "julia"

            # Enter commits via the factory → a JuliaInsertion.
            ins.selection = _ins_vpath(length(ins.value))
            commit = read_intent(proj, iom, KeyDown(:return, Modifiers()))
            @test commit isa CompoundOperation
            @test _written_doc(commit) isa JuliaInsertion

            # Escape aborts to DocumentNothing.
            esc = read_intent(proj, iom, KeyDown(:escape, Modifiers()))
            @test esc isa CompoundOperation
            @test _written_doc(esc) isa DocumentNothing
        end

        @testset "JuliaInsertion commits source via juliaparse" begin
            ji = JuliaInsertion("factorial(5)")
            ji.selection = _ins_vpath(length("factorial(5)"))
            jproj = JuliaInsertionToSyntaxLeaf()
            jiom = print_document(jproj, jproj, ji, nothing)
            commit = read_intent(jproj, jiom, KeyDown(:return, Modifiers()))
            @test commit isa CompoundOperation
            @test _written_doc(commit) isa JuliaDocument

            # Unparseable / empty source cannot commit.
            empty_ji = JuliaInsertion("")
            empty_ji.selection = _ins_vpath(0)
            eiom = print_document(jproj, jproj, empty_ji, nothing)
            @test read_intent(jproj, eiom, KeyDown(:return, Modifiers())) === nothing
        end

        @testset "SqlInsertion commits source via sqlparse" begin
            si = SqlInsertion("SELECT * FROM persons")
            si.selection = _ins_vpath(length("SELECT * FROM persons"))
            sproj = SqlInsertionToSyntaxLeaf()
            siom = print_document(sproj, sproj, si, nothing)
            commit = read_intent(sproj, siom, KeyDown(:return, Modifiers()))
            @test commit isa CompoundOperation
            @test _written_doc(commit) isa SqlStatement

            # Unparseable / empty source cannot commit.
            empty_si = SqlInsertion("")
            empty_si.selection = _ins_vpath(0)
            esiom = print_document(sproj, sproj, empty_si, nothing)
            @test read_intent(sproj, esiom, KeyDown(:return, Modifiers())) === nothing
        end
    end
end
