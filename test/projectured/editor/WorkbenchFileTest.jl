# Tests for the WorkbenchEditor file keybindings (Ctrl+S save / Ctrl+O reload)
# and the format-by-extension file I/O they use. The gesture is fired through the
# *real* workbench → widget → window → screen pipeline (the same one
# `run_file_editor` runs), so this proves the read_gesture delegation in
# WorkbenchEditorToWidgetScrollPane actually lights up @gestures WorkbenchEditor.

using Test
using ProjecturedExample: make_workbench_document, make_workbench_projection,
                          _build_window_scene, _multi_window_projection

# evaluate_operation is duck-typed on editor.{document,iomap}.
mutable struct _WBFakeEditor; document::Any; iomap::Any; end

# Fire a KeyDown through the composed pipeline and return the produced operation.
function _wb_fire(composed, iomap, window_id, key; ctrl=false)
    window_input = WindowInput(window_id, KeyDown(key, ModifierKeys(ctrl=ctrl)))
    ch = read_intent(composed, nothing, Intent(window_input), iomap)
    ch isa Intent ? ch.operation : ch
end

function test_workbench_file_keys()
    @testset "WorkbenchEditor file keybindings" begin
        @testset "format-by-extension IO" begin
            # A non-existent file opens as its extension's insertion seed.
            @test make_document_for("x.json") isa JsonInsertion
            @test make_document_for("x.xml")  isa XmlInsertion
            @test make_document_for("x.sql")  isa SqlInsertion
            @test make_document_for("x.jl")   isa JuliaInsertion
            @test make_document_for("x.pdoc") isa DocumentNothing
            @test read_document_file(tempname() * ".json") isa JsonInsertion

            doc = parse_json("""{"k":1}""")
            pj = tempname() * ".json"
            write_document_file(doc, pj)
            @test occursin("\"k\"", read(pj, String))       # natural text
            pb = tempname() * ".pdoc"
            write_document_file(doc, pb)
            @test read_document_file(pb) isa JsonObject      # binary round-trip
        end

        @testset "every file format saves and loads" begin
            dir = mktempdir()
            # One small document of each natural format. Each text comes back
            # as the same text after a save and a load.
            natural = [("a.json", :json, "{\"name\": \"Alice\", \"age\": 30}"),
                       ("a.xml",  :xml,  "<a x=\"1\"><b/></a>"),
                       ("a.yaml", :yaml, "name: Alice\nage: 30\n"),
                       ("a.md",   :md,   "# Title\n\nSome text.\n"),
                       ("a.rst",  :rst,  "Title\n=====\n\nSome text.\n"),
                       ("a.math", :math, "a + b"),
                       ("a.jl",   :jl,   "function f(x)\n    x + 1\nend\n"),
                       ("a.sql",  :sql,  "SELECT a FROM t;")]
            for (name, format, text) in natural
                document = parse_natural_text(format, text)
                path = joinpath(dir, name)
                @test write_document_file(document, path) == path
                @test print_natural_text(read_document_file(path)) ==
                      print_natural_text(document)
            end

            # @broken: the XML printer indents the text of an element, and the
            # parser keeps that whitespace, so each save and load adds blank
            # space to the text.
            element = parse_natural_text(:xml, "<a>text</a>")
            path = joinpath(dir, "text.xml")
            write_document_file(element, path)
            @test_broken print_natural_text(read_document_file(path)) ==
                         print_natural_text(element)

            # A `.pred` file holds a registered document. `TestRun` is the
            # `.pred` document of FileProjectTest.jl, in this module.
            register_pred_type!(TestRun)
            path = joinpath(dir, "run.pred")
            write_document_file(TestRun(name = "aloha", count = 3), path)
            run = read_document_file(path)
            @test run isa TestRun
            @test run.name == "aloha" && run.count == 3

            # A text file, with or without an extension, is a PrimitiveString.
            for name in ("notes.txt", "README")
                path = joinpath(dir, name)
                write_document_file(PrimitiveString("line one\nline two"), path)
                @test read(path, String) == "line one\nline two"
                back = read_document_file(path)
                @test back isa PrimitiveString
                @test back.value == "line one\nline two"
            end
            @test make_document_for("new.txt") isa PrimitiveString
            @test make_document_for("NEWFILE") isa PrimitiveString
            @test make_document_for("new.pred") isa DocumentNothing
            @test has_file_document_type("x.pred")
            @test !has_file_document_type("x.png")
        end

        @testset "Ctrl+S saves, Ctrl+O reloads" begin
            path = tempname() * ".json"
            name = "a.json"
            doc  = make_workbench_document(parse_json("""{"a":1}"""); title=name, filename=path)
            proj = make_workbench_projection()
            screen   = _build_window_scene(Any[doc], String[name]; width=800, height=600)
            composed = _multi_window_projection(Any[proj])
            wid   = Symbol(name)
            iomap = print_document(composed, screen)
            ed    = _WBFakeEditor(screen, iomap)

            # Plain 's' (no Ctrl) is not a save — the tab binding requires Ctrl.
            @test !(_wb_fire(composed, iomap, wid, :s; ctrl=false) isa SaveWorkbenchEditorOperation)

            # Ctrl+S → save the tab's content to its filename.
            op = _wb_fire(composed, iomap, wid, :s; ctrl=true)
            @test op isa SaveWorkbenchEditorOperation
            evaluate_operation(ed, op)
            @test isfile(path)
            @test occursin("\"a\"", read(path, String))

            # Edit the file on disk, then Ctrl+O → reload into the tab's content.
            write(path, """{"b":2}""")
            op2 = _wb_fire(composed, iomap, wid, :o; ctrl=true)
            @test op2 isa ReloadWorkbenchEditorOperation
            tab = op2.editor
            evaluate_operation(ed, op2)
            @test tab.content isa JsonObject
        end
    end
end
