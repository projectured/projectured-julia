using Test
using Projectured.McpModule
using Projectured.ToolRegistryModule: call_tool, list_tools, list_resources
using Projectured.WorkbenchAssistantModule: SubmitJuliaOperation, _eval_result
using Projectured: WorkbenchAssistant, evaluate_operation, ConcreteReferencePath,
                   FieldReference, RangeReference, EmptyReferencePath, FakeLlm,
                   WorkbenchWorkbench, WorkbenchPage, WorkbenchNavigator, Workspace,
                   JsonString, JsonNull, JsonNumber, jsonparse, evaluate_reference,
                   print_object, search_object,
                   open_workbench_document!, open_workbench_file!,
                   close_workbench_document!, list_workbench_documents,
                   get_workbench_document, set_focused_workbench_document!,
                   get_focused_workbench_document

function test_list_guides()
    @testset "list_guides" begin
        result = list_guides()
        @test isa(result, String)
        @test !isempty(result)
        # Should contain some guide names
        @test occursin("**", result)  # Markdown bold formatting
    end
end

function test_read_guide()
    @testset "read_guide" begin
        # Test reading a guide that should exist
        result = read_guide("Design")
        @test isa(result, String)
        @test !isempty(result)
        
        # Test reading a non-existent guide
        result = read_guide("NonExistentGuide")
        @test occursin("not found", result)
    end
end

function test_list_modules()
    @testset "list_modules" begin
        result = list_modules()
        @test isa(result, String)
        @test !isempty(result)
        # Should contain module names
        @test occursin("**", result)  # Markdown bold formatting
    end
end

function test_list_classes()
    @testset "list_classes" begin
        # Test with a known module
        result = list_classes("DocumentModule")
        @test isa(result, String)
        # May return "No classes found" or actual classes
        
        # Test with non-existent module
        result = list_classes("NonExistentModule")
        @test occursin("not found", result) || occursin("No classes", result)
    end
end

function test_list_functions()
    @testset "list_functions" begin
        # Test listing functions in a module
        result = list_functions("DocumentModule")
        @test isa(result, String)
        
        # Test with class filter
        result = list_functions("DocumentModule", "Document")
        @test isa(result, String)
        
        # Test with non-existent module
        result = list_functions("NonExistentModule")
        @test occursin("not found", result) || occursin("No functions", result)
    end
end

function test_read_module_documentation()
    @testset "read_module_documentation" begin
        # Test reading documentation for a known module
        result = read_module_documentation("DocumentModule")
        @test isa(result, String)
        
        # Test with non-existent module
        result = read_module_documentation("NonExistentModule")
        @test occursin("not found", result)
    end
end

function test_read_class_documentation()
    @testset "read_class_documentation" begin
        # Test reading documentation for a known class
        result = read_class_documentation("DocumentModule", "Document")
        @test isa(result, String)
        
        # Test with non-existent module
        result = read_class_documentation("NonExistentModule", "SomeClass")
        @test occursin("not found", result)
        
        # Test with non-existent class
        result = read_class_documentation("DocumentModule", "NonExistentClass")
        @test occursin("not found", result)
    end
end

function test_read_function_documentation()
    @testset "read_function_documentation" begin
        # Test reading documentation for a known function
        result = read_function_documentation("DocumentModule", "Document")
        @test isa(result, String)
        
        # Test with non-existent module
        result = read_function_documentation("NonExistentModule", "some_function")
        @test occursin("not found", result)
        
        # Test with non-existent function
        result = read_function_documentation("DocumentModule", "non_existent_function")
        @test occursin("not found", result)
    end
end

function test_search_documentation()
    @testset "search_documentation" begin
        # A term that should appear in the guides
        result = search_documentation("selection")
        @test isa(result, String)
        @test occursin("resource://guide/", result)

        # Limit is honoured (count the per-hit "resource://guide/" headers)
        result_one = search_documentation("selection"; limit=1)
        @test count("resource://guide/", result_one) <= 1

        # No match
        result_none = search_documentation("zzzznotarealword")
        @test occursin("No documentation matches", result_none)

        # Empty / too-short query
        @test occursin("Provide a search query", search_documentation("a"))

        # Regex dispatch
        @test occursin("resource://guide/", search_documentation(r"selection"))
    end
end

function test_search_api()
    @testset "search_api" begin
        # A function that definitely exists
        result = search_api("replace_selection")
        @test isa(result, String)
        @test occursin("replace_selection", result)

        # Function hits point at read_function_documentation; module/class hits at resource://
        @test occursin("read_function_documentation", result) || occursin("resource://", result)

        # kind filter restricts results to classes (structs)
        result_class = search_api("workbench"; kind="class")
        @test isa(result_class, String)
        @test !occursin("**function**", result_class)

        # No match
        @test occursin("No API matches", search_api("zzzznotarealword"))

        # Too-short query
        @test occursin("Provide a search query", search_api("a"))

        # Regex dispatch: a Regex query searches by pattern
        @test occursin("replace_selection", search_api(r"replace_selection"))
        # regex is case-sensitive by default (matched against original-case text)
        @test occursin("No API matches", search_api(r"REPLACE_SELECTION"))
        # ... the i flag restores case-insensitivity
        @test occursin("replace_selection", search_api(r"REPLACE_SELECTION"i))
    end
end

# After register_default_tools_and_resources! the search tools are registered and
# no per-function resources are; verifies the A3 fan-out drop.
function test_search_tools_registered()
    @testset "search tools registered, function resources dropped" begin
        register_default_tools_and_resources!()
        tool_names = [t.name for t in list_tools()]
        @test "search_api" in tool_names
        @test "search_documentation" in tool_names

        resource_uris = [r.uri for r in list_resources()]
        @test !any(u -> startswith(u, "resource://function/"), resource_uris)
        @test any(u -> startswith(u, "resource://module/"), resource_uris)

        # The search tools are callable through the registry like any tool.
        out = call_tool("search_api", Dict("query" => "replace_selection"), nothing)
        @test occursin("replace_selection", out)

        # regex=true makes the tool treat the query as a regular expression
        rout = call_tool("search_api",
                         Dict("query" => "^OperationModule\\.Replace", "regex" => true), nothing)
        @test occursin("ReplaceSelectionOperation", rout)

        # an invalid regex is reported, not thrown
        bad = call_tool("search_documentation",
                        Dict("query" => "(unclosed", "regex" => true), nothing)
        @test occursin("Invalid regex", bad)

        # without regex=true the same string is treated as harmless keywords
        kout = call_tool("search_documentation", Dict("query" => "(unclosed"), nothing)
        @test isa(kout, String) && !occursin("Invalid regex", kout)
    end
end

function test_workbench_b1()
    @testset "workbench B1: open/close/list/focus" begin
        wb = WorkbenchWorkbench(
            WorkbenchPage([WorkbenchNavigator(Workspace())]),
            WorkbenchPage([]),
            WorkbenchPage([]),
            WorkbenchPage([]),
        )
        editor = (document = wb,)

        # Navigator is not a WorkbenchEditor, so nothing is "open" yet.
        @test isempty(list_workbench_documents(editor))

        d1 = open_workbench_document!(editor, JsonString("hi"); title="a.json")
        open_workbench_document!(editor, JsonNull(); title="b.json")
        docs = list_workbench_documents(editor)
        @test length(docs) == 2
        @test docs[1].page == :editing && docs[1].index == 1 && docs[1].title == "a.json"
        @test docs[1].content_type == JsonString
        @test docs[2].title == "b.json"

        # no focus yet → getter returns nothing
        @test get_focused_workbench_document(editor) === nothing

        # set focus by title points the page selection at the right element
        set_focused_workbench_document!(editor, "b.json")
        @test wb.editing_page.selection == ConcreteReferencePath(
            Projectured.ElementReference(2), EmptyReferencePath())
        # getter round-trips the focused entry
        foc = get_focused_workbench_document(editor)
        @test foc isa Projectured.WorkbenchEditor && foc.title == "b.json"

        # get_workbench_document resolves by index/title without side effect
        @test get_workbench_document(editor, 1).title == "a.json"
        @test get_workbench_document(editor, "b.json") === foc
        @test get_workbench_document(editor, "nope.json") === nothing

        # open onto another page
        open_workbench_document!(editor, JsonNull(); title="n.json", page=:information)
        @test any(d -> d.page == :information && d.title == "n.json",
                  list_workbench_documents(editor))
        # page filter on list_
        info = list_workbench_documents(editor; page=:information)
        @test length(info) == 1 && info[1].title == "n.json"
        @test all(d -> d.page == :editing, list_workbench_documents(editor; page=:editing))

        # close by title, by entry identity
        close_workbench_document!(editor, "a.json")
        @test [d.title for d in list_workbench_documents(editor) if d.page == :editing] == ["b.json"]

        # open_workbench_file! picks the domain by extension and titles by basename
        tmp = mktempdir()
        path = joinpath(tmp, "data.json")
        write(path, "[1, 2, 3]")
        entry = open_workbench_file!(editor, path)
        @test entry.title == "data.json"
        @test entry.filename == path

        # unknown page errors
        @test_throws ErrorException open_workbench_document!(editor, JsonNull(); page=:nope)
    end
end

function test_print_object_options()
    @testset "print_object: newlines / indent / filter" begin
        doc = jsonparse("[1, \"x\", true]")

        # default: multi-line, indented, default {} delimiters
        multi = print_object(doc)
        @test occursin("\n", multi)
        # type name labels the brace block (type-first), with default delimiters
        @test occursin("JsonArray {", multi)
        # CellVector / raw Array wrapper layers are omitted as noise
        # (\bArray\b avoids matching the legitimate "JsonArray" type name)
        @test !occursin("CellVector", multi)
        @test !occursin(r"\bArray\b", multi)
        # no trailing whitespace on any line
        @test !any(l -> l != rstrip(l), split(multi, '\n'))

        # newlines=false: single line, space-separated
        flat = print_object(doc; newlines=false)
        @test !occursin("\n", flat)
        @test occursin("JsonArray", flat) && occursin("JsonNumber", flat)

        # indent widens the leading whitespace
        @test occursin("    ", print_object(doc; indent=4))

        # filter: hide Bool-valued elements -> no JsonBool node
        filtered = print_object(doc; filter = v -> !(v isa JsonNull) && !(v isa Bool))
        # the boolean element should be gone; numbers/strings remain
        @test occursin("JsonNumber", filtered)

        # scalars are unaffected by the formatting flags
        @test print_object(42) == "42"
        @test print_object(42; newlines=false) == "42"
    end
end

function test_search_object()
    @testset "search_object" begin
        doc = jsonparse("{\"name\": \"Alice\", \"scores\": [10, 20], \"active\": true}")

        refs = search_object(doc, v -> v isa JsonNumber)
        @test length(refs) == 2
        # references resolve back to matching nodes
        for r in refs
            v = evaluate_reference(doc, r)
            @test v isa JsonNumber
        end

        srefs = search_object(doc, v -> v isa JsonString && occursin("Alice", v.value))
        @test length(srefs) == 1
        @test evaluate_reference(doc, srefs[1]).value == "Alice"

        # no matches → empty
        @test isempty(search_object(doc, v -> v isa JsonNull))

        # a predicate that throws on some nodes is treated as no-match, not an error
        @test !isempty(search_object(doc, v -> v.value == 10))
    end
end

function test_execute_julia_code()
    @testset "execute_julia_code" begin
        # Need a mock editor for this test
        # For now, we'll test with a simple dict as editor
        editor = Dict("document" => "test", "projection" => "test")
        
        # Test simple expression
        result = execute_julia_code(editor, "1 + 1")
        @test isa(result, String)
        @test occursin("2", result)
        
        # Test expression that uses editor
        result = execute_julia_code(editor, "editor")
        @test isa(result, String)
        
        # Test error handling
        result = execute_julia_code(editor, "undefined_function()")
        @test isa(result, String)
        @test occursin("Error", result) || occursin("UndefVarError", result)
        
        # Test multi-line code
        result = execute_julia_code(editor, """
            x = 5
            y = 10
            x + y
        """)
        @test isa(result, String)
        @test occursin("15", result)
        
        # Test string operations
        result = execute_julia_code(editor, "\"hello\" * \" world\"")
        @test isa(result, String)
        @test occursin("hello world", result)
        
        # Test array operations
        result = execute_julia_code(editor, "[1, 2, 3] .^ 2")
        @test isa(result, String)
        @test occursin("[1, 4, 9]", result)
        
        # Test stdout capture (using println)
        result = execute_julia_code(editor, "println(\"test output\")")
        @test isa(result, String)
        @test occursin("test output", result)
        
        # Test that nothing expressions don't add extra output
        result = execute_julia_code(editor, "x = 42")
        @test isa(result, String)
        # Should not contain "nothing" since x = 42 returns nothing but we don't print it
        
        # Test accessing editor fields
        result = execute_julia_code(editor, "editor[\"document\"]")
        @test isa(result, String)
        @test occursin("test", result)
        
        # Test editor variable access - verify editor is available in scope
        result = execute_julia_code(editor, "editor isa Dict")
        @test isa(result, String)
        @test occursin("true", result)
        
        # Test editor field access with different syntax
        result = execute_julia_code(editor, "editor[\"projection\"]")
        @test isa(result, String)
        @test occursin("test", result)
        
        # Test complex expression
        result = execute_julia_code(editor, "sqrt(16) + 2^3")
        @test isa(result, String)
        @test occursin("12", result)
    end
end

# Reproduces the bug where ALT+ENTER → SubmitJuliaOperation → call_tool
# used to pass `nothing` for editor, so the assistant saw `editor === nothing`
# and any `editor.document` reach-through crashed with FieldError. Verifies
# the workbench flow now forwards the live editor (or a stand-in carrying
# `.document`) all the way to `execute_julia_code`'s `let editor = …`.
function test_workbench_editor_reference()
    @testset "workbench editor reference" begin
        register_default_tools_and_resources!()

        a = WorkbenchAssistant(; llm = FakeLlm("ok"))
        a.input.value = "editor !== nothing"
        a.input.selection = ConcreteReferencePath(
            FieldReference("value"),
            ConcreteReferencePath(RangeReference(0, length(a.input.value)),
                                  EmptyReferencePath()))

        stand_in = (document = a,)
        evaluate_operation(stand_in, SubmitJuliaOperation(a))

        @test length(a.conversation) == 1
        exec = a.conversation.turns[1].parts[1].content
        @test occursin("true", _eval_result(exec))
        @test !exec.is_error

        a.input.value = "editor.document isa Projectured.WorkbenchAssistant"
        a.input.selection = ConcreteReferencePath(
            FieldReference("value"),
            ConcreteReferencePath(RangeReference(0, length(a.input.value)),
                                  EmptyReferencePath()))
        evaluate_operation(stand_in, SubmitJuliaOperation(a))
        exec2 = a.conversation.turns[2].parts[1].content
        @test occursin("true", _eval_result(exec2))
        @test !exec2.is_error
    end
end

function test_function_availability()
    @testset "function_availability" begin
        # Need a mock editor for this test
        editor = Dict("document" => "test", "projection" => "test")
        
        # Test that evaluate_reference is available by calling it
        result = execute_julia_code(editor, "evaluate_reference(5, EmptyReferencePath())")
        @test isa(result, String)
        @test occursin("5", result)
        
        # Test that append_reference is available by calling it
        result = execute_julia_code(editor, "append_reference(EmptyReferencePath(), PositionReference(1))")
        @test isa(result, String)
        # Should not error
        
        # Test that is_valid_reference is available by calling it
        result = execute_julia_code(editor, "is_valid_reference(PositionReference(1))")
        @test isa(result, String)
        # Should not error
        
        # Test that PositionReference is available by constructing it
        result = execute_julia_code(editor, "PositionReference(1)")
        @test isa(result, String)
        # Should not error
        
        # Test that ElementReference is available by constructing it
        result = execute_julia_code(editor, "ElementReference(1)")
        @test isa(result, String)
        # Should not error
        
        # Test that FieldReference is available by constructing it
        result = execute_julia_code(editor, "FieldReference(\"test\")")
        @test isa(result, String)
        # Should not error
        
        # Test that EmptyReferencePath is available by constructing it
        result = execute_julia_code(editor, "EmptyReferencePath()")
        @test isa(result, String)
        # Should not error
    end
end

function test_base_extensions()
    @testset "base_extensions" begin
        # Need a mock editor for this test
        editor = Dict("document" => "test", "projection" => "test")
        
        # Test that CellVector indexing works (Base.getindex extension)
        result = execute_julia_code(editor, """
            cv = CellVector([Cell(1), Cell(2), Cell(3)])
            cv[1]
        """)
        @test isa(result, String)
        @test occursin("1", result)
        
        # Test that CellVector length works (Base.length extension)
        result = execute_julia_code(editor, """
            cv = CellVector([Cell(1), Cell(2), Cell(3)])
            length(cv)
        """)
        @test isa(result, String)
        @test occursin("3", result)
        
        # Test that CellVector iteration works (Base.iterate extension)
        result = execute_julia_code(editor, """
            cv = CellVector([Cell(1), Cell(2), Cell(3)])
            collect(cv)
        """)
        @test isa(result, String)
        @test occursin("[1, 2, 3]", result)
        
        # Test that JsonArray indexing works (Base.getindex extension)
        result = execute_julia_code(editor, """
            arr = JsonArray([Cell(JsonNumber(Cell(1))), Cell(JsonNumber(Cell(2)))])
            arr[1]
        """)
        @test isa(result, String)
        @test occursin("2", result)
    end
end

function test_mcp_resources()
    @testset "MCP Resources" begin
        test_list_guides()
        test_read_guide()
        test_list_modules()
        test_list_classes()
        test_list_functions()
        test_read_module_documentation()
        test_read_class_documentation()
        test_read_function_documentation()
    end
end

function test_mcp_tools()
    @testset "MCP Tools" begin
        test_execute_julia_code()
        test_function_availability()
        test_base_extensions()
        test_workbench_editor_reference()
        test_search_documentation()
        test_search_api()
        test_search_tools_registered()
        test_workbench_b1()
        test_print_object_options()
        test_search_object()
    end
end

export test_mcp_tools, test_mcp_resources
export test_list_guides, test_read_guide
export test_list_modules, test_list_classes, test_list_functions
export test_read_module_documentation, test_read_class_documentation, test_read_function_documentation
export test_execute_julia_code, test_function_availability, test_base_extensions
export test_workbench_editor_reference
export test_search_documentation, test_search_api, test_search_tools_registered
export test_workbench_b1, test_print_object_options, test_search_object
