# Tests for the insert-by-typing mechanism (DocumentInsertionToSyntax):
# typing a domain name into a DocumentInsertion and committing it to that
# domain's document/insertion, and committing Julia source via JuliaInsertion.

using Projectured: DocumentInsertion, JuliaInsertion, JsonInsertion, JuliaDocument,
                   DocumentNothing, DocumentInsertionToSyntaxLeaf, JuliaInsertionToSyntaxLeaf,
                   default_factory, default_completion,
                   projection_print, projection_read, evaluate_operation,
                   ReplaceDocumentOperation, StringReplaceRangeOperation,
                   KeyPress, KeyDown, Modifiers,
                   ConcreteReferencePath, FieldReference, RangeReference, EmptyReferencePath

_ins_vpath(n) = ConcreteReferencePath(FieldReference("value"),
                    ConcreteReferencePath(RangeReference(n, n), EmptyReferencePath()))

function test_document_insertion()
    @testset "DocumentInsertion insert-by-typing" begin
        @testset "factory + completion" begin
            @test default_factory("julia") isa JuliaInsertion
            @test default_factory("json")  isa JsonInsertion
            @test default_factory("zzz")   === nothing
            @test default_completion("jso") == "n"
            @test default_completion("xyz") == ""
        end

        @testset "type domain name -> domain insertion" begin
            ins = DocumentInsertion("juli")
            ins.selection = _ins_vpath(4)
            proj = DocumentInsertionToSyntaxLeaf()
            iom = projection_print(proj, proj, ins, nothing)

            # A printable key edits the value.
            op = projection_read(proj, iom, KeyPress('a'))
            @test op isa StringReplaceRangeOperation
            evaluate_operation((document = ins,), op)
            @test ins.value == "julia"

            # Enter commits via the factory → a JuliaInsertion.
            ins.selection = _ins_vpath(length(ins.value))
            commit = projection_read(proj, iom, KeyDown(:return, Modifiers()))
            @test commit isa ReplaceDocumentOperation
            @test commit.document isa JuliaInsertion

            # Escape aborts to DocumentNothing.
            esc = projection_read(proj, iom, KeyDown(:escape, Modifiers()))
            @test esc isa ReplaceDocumentOperation
            @test esc.document isa DocumentNothing
        end

        @testset "JuliaInsertion commits source via juliaparse" begin
            ji = JuliaInsertion("factorial(5)")
            ji.selection = _ins_vpath(length("factorial(5)"))
            jproj = JuliaInsertionToSyntaxLeaf()
            jiom = projection_print(jproj, jproj, ji, nothing)
            commit = projection_read(jproj, jiom, KeyDown(:return, Modifiers()))
            @test commit isa ReplaceDocumentOperation
            @test commit.document isa JuliaDocument

            # Unparseable / empty source cannot commit.
            empty_ji = JuliaInsertion("")
            empty_ji.selection = _ins_vpath(0)
            eiom = projection_print(jproj, jproj, empty_ji, nothing)
            @test projection_read(jproj, eiom, KeyDown(:return, Modifiers())) === nothing
        end
    end
end
