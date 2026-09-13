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
