# Tests for the insert-by-typing mechanism (DocumentInsertionToSyntax):
# typing a domain name into a DocumentInsertion and committing it to that
# domain's document/insertion, and committing Julia source via JuliaInsertion.


# A `replace_document(path, doc)` fold expands to a CompoundOperation whose first
# member is the ReplaceReferencedValueOperation that writes `doc`.
_written_doc(op) = op.operations[1].value

_ins_vpath(n) = ConcreteReferencePath(FieldReference("value"),
                    ConcreteReferencePath(RangeReference(n, n), EmptyReferencePath()))

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
