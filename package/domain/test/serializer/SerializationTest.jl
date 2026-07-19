# Round-trip tests for document persistence:
#   - binary  save_document / load_document   (exact, lossless, any document)
#   - natural import_document / export_document (printer/parser text, per domain)
# plus the four editor operations and the format guards.

using Test
using ProjecturedDomainExample: json_example, xml_example, sql_syntax_example, julia_example

# evaluate_operation is duck-typed on editor.{document,iomap}; a mutable stand-in
# is enough to exercise the operations without a backend.
mutable struct _SerEditor
    document::Any
    iomap::Any
end

function test_serialization()
    @testset "Serialization" begin
        @testset "binary round-trip" begin
            for ex in (json_example, xml_example, sql_syntax_example, julia_example)
                doc  = ex.make_document()
                proj = ex.make_projection()

                p1 = tempname() * ".pdoc"
                save_document(doc, p1)
                @test isfile(p1)

                loaded = load_document(p1)
                @test loaded isa Document
                @test typeof(loaded) === typeof(doc)

                # Fixed point: re-saving the loaded document reproduces the bytes,
                # so the structural+selection content round-tripped exactly.
                p2 = tempname() * ".pdoc"
                save_document(loaded, p2)
                @test read(p1) == read(p2)

                # Loaded cells are detached from any reactive graph. The edge
                # containers are allocated lazily, so "detached" is `nothing` (never
                # allocated) or an empty container.
                selcell = getfield(loaded, :selection)
                @test (d = getfield(selcell, :deps);       d === nothing || isempty(d))
                @test (d = getfield(selcell, :dependents); d === nothing || isempty(d))
                @test getfield(selcell, :thunk) === nothing

                # The detached document still projects through the real pipeline.
                @test print_document(proj, loaded) !== nothing
            end
        end

        @testset "binary preserves selection" begin
            doc = json_example.make_document()
            set_selection!(doc, @reference(doc, entries[1].value))
            before = getfield(doc, :selection)[]
            p = tempname() * ".pdoc"
            save_document(doc, p)
            loaded = load_document(p)
            @test getfield(loaded, :selection)[] == before
        end

        @testset "binary header validation" begin
            bogus = tempname() * ".pdoc"
            write(bogus, "not a projectured document")
            @test_throws Exception load_document(bogus)
        end

        @testset "natural round-trip" begin
            # Clean data documents (no insertion placeholders).
            cases = [
                (".json", jsonparse("""{"name":"ada","age":36,"tags":["x","y"],"ok":true,"nil":null}"""), JsonObject, true),
                (".xml",  xmlparse("<a id=\"1\"><b>hi</b></a>"),                                          XmlElement, false),
                (".sql",  sqlparse("SELECT * FROM persons"),                                              SqlSelectStatement, true),
                (".jl",   juliaparse("function f(n)\n  n + 1\nend"),                                       JuliaFunction, true),
            ]
            for (ext, doc, T, text_stable) in cases
                p = tempname() * ext
                export_document(doc, p)
                @test isfile(p)

                imported = import_document(p)
                @test imported isa T

                # Exporting the re-imported document is a fixed point for domains
                # whose parser is whitespace-insensitive (JSON/SQL/Julia). XML's
                # parser captures inter-element whitespace as text, so its text is
                # only best-effort stable — we just require it re-imports.
                if text_stable
                    @test document_to_text(imported) == read(p, String)
                else
                    @test import_document(p) isa T
                end
            end
        end

        @testset "export extension guard" begin
            # Writing one format's text under another known format's extension is
            # rejected, so a later import_document can't pick the wrong parser.
            @test_throws Exception export_document(jsonparse("1"), tempname() * ".sql")
        end

        @testset "operations" begin
            # Binary save then load through editor operations (whole-root swap).
            doc = json_example.make_document()
            ed = _SerEditor(doc, "live-iomap")
            p = tempname() * ".pdoc"
            evaluate_operation(ed, SaveDocumentOperation(p))
            @test isfile(p)

            ed2 = _SerEditor(jsonparse("0"), :stale)
            evaluate_operation(ed2, LoadDocumentOperation(p))
            @test ed2.document isa JsonObject
            @test ed2.iomap === nothing

            # Natural export then import through editor operations.
            clean = jsonparse("""{"k":[1,2,3]}""")
            ed3 = _SerEditor(clean, "live-iomap")
            q = tempname() * ".json"
            evaluate_operation(ed3, ExportDocumentOperation(q))
            @test isfile(q)

            ed4 = _SerEditor(jsonparse("0"), :stale)
            evaluate_operation(ed4, ImportDocumentOperation(q))
            @test ed4.document isa JsonObject
            @test ed4.iomap === nothing
        end
    end
end
