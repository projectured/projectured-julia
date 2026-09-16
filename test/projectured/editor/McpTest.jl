using Test
using ProjecturedKernel.ToolModule
using ProjecturedAssistant.AssistantModule: SubmitJuliaOperation, SubmitProseOperation, _eval_result

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
    @testset "list_types" begin
        # Test with a known module
        result = list_types("DocumentModule")
        @test isa(result, String)
        # May return "No classes found" or actual classes
        
        # Test with non-existent module
        result = list_types("NonExistentModule")
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
    @testset "read_type_documentation" begin
        # Test reading documentation for a known class
        result = read_type_documentation("DocumentModule", "Document")
        @test isa(result, String)
        
        # Test with non-existent module
        result = read_type_documentation("NonExistentModule", "SomeClass")
        @test occursin("not found", result)
        
        # Test with non-existent class
        result = read_type_documentation("DocumentModule", "NonExistentClass")
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
        @test !occursin("— function", result_class)

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

# After register_default_tools! the search tools are registered and
# no per-function resources are; verifies the A3 fan-out drop.
function test_search_tools_registered()
    @testset "search tools registered, function resources dropped" begin
        tools = register_default_tools!(ToolSet())
        tool_names = [t.name for t in list_tools(tools)]
        @test "search_api" in tool_names
        @test "search_documentation" in tool_names

        resource_uris = [r.uri for r in list_resources(tools)]
        @test !any(u -> startswith(u, "resource://function/"), resource_uris)
        @test any(u -> startswith(u, "resource://module/"), resource_uris)

        # The search tools are callable through the registry like any tool.
        out = call_tool(tools, "search_api", Dict("query" => "replace_selection"), nothing)
        @test occursin("replace_selection", out)

        # mode "regex" makes the tool treat the query as a regular expression
        rout = call_tool(tools, "search_api",
                         Dict("query" => "^OperationModule\\.Replace", "mode" => "regex"), nothing)
        @test occursin("ReplaceSelectionOperation", rout)

        # an invalid regex is reported, not thrown
        bad = call_tool(tools, "search_documentation",
                        Dict("query" => "(unclosed", "mode" => "regex"), nothing)
        @test occursin("Invalid regex", bad)

        # in the default mode the same string is read as harmless keywords
        kout = call_tool(tools, "search_documentation", Dict("query" => "(unclosed"), nothing)
        @test isa(kout, String) && !occursin("Invalid regex", kout)
    end
end

function test_workbench_b1()
    @testset "workbench tabs via operations + search" begin
        editing = WorkbenchPage([])
        info    = WorkbenchPage([])
        wb = WorkbenchWorkbench(
            WorkbenchPage([WorkbenchNavigator(Workspace())]),
            editing,
            info,
            WorkbenchPage([]),
        )
        editor = (document = wb,)

        # Find tabs generically with search (no bespoke list helper). The
        # Navigator is not a WorkbenchEditor, so nothing is "open" yet.
        @test isempty(search_documents(wb, x -> x isa WorkbenchEditor))

        # Open tabs by building the operation that carries its target page, then
        # evaluating it — the same path the editor loop runs for a gesture.
        a = WorkbenchEditor(JsonString("hi"); title="a.json")
        b = WorkbenchEditor(JsonNull();        title="b.json")
        evaluate_operation(editor, WorkbenchOpenDocumentOperation(editing, a))
        evaluate_operation(editor, WorkbenchOpenDocumentOperation(editing, b))

        editors = search_documents(wb, x -> x isa WorkbenchEditor)
        @test length(editors) == 2
        @test Set(e.title for e in editors) == Set(["a.json", "b.json"])

        # Locate a tab by content and resolve its reference back to the node.
        refs = search_references(wb, x -> x isa WorkbenchEditor && x.title == "b.json")
        @test length(refs) == 1
        @test evaluate_reference(wb, refs[1]) === b

        # "Focus" is selecting that tab — a ReplaceSelectionOperation, like a click.
        evaluate_operation(editor, ReplaceSelectionOperation(refs[1]))
        @test evaluate_reference(wb, wb.selection) === b

        # Open onto another page; search finds it regardless of which page.
        n = WorkbenchEditor(JsonNull(); title="n.json")
        evaluate_operation(editor, WorkbenchOpenDocumentOperation(info, n))
        @test any(e -> e.title == "n.json", search_documents(wb, x -> x isa WorkbenchEditor))

        # Close a tab: find its index on the page, build the close operation.
        idx = 0
        for (i, e) in enumerate(editing.elements)
            e.title == "a.json" && (idx = i; break)
        end
        evaluate_operation(editor, WorkbenchCloseDocumentOperation(editing, idx))
        @test [e.title for e in editing.elements] == ["b.json"]
    end
end

function test_print_object_options()
    @testset "print_object: newlines / indent / filter" begin
        doc = parse_json("[1, \"x\", true]")

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

        # filter: hide Bool-valued fields -> the JsonBool element's `value` is dropped
        filtered = print_object(doc; filter = v -> !(v isa JsonNull) && !(v isa Bool))
        # numbers/strings remain
        @test occursin("JsonNumber", filtered)

        # scalars are unaffected by the formatting flags
        @test print_object(42) == "42"
        @test print_object(42; newlines=false) == "42"
    end
end

function test_search_object()
    @testset "search_references" begin
        doc = parse_json("{\"name\": \"Alice\", \"scores\": [10, 20], \"active\": true}")

        refs = search_references(doc, v -> v isa JsonNumber)
        @test length(refs) == 2
        # references resolve back to matching nodes
        for r in refs
            v = evaluate_reference(doc, r)
            @test v isa JsonNumber
        end

        srefs = search_references(doc, v -> v isa JsonString && occursin("Alice", v.value))
        @test length(srefs) == 1
        @test evaluate_reference(doc, srefs[1]).value == "Alice"

        # no matches → empty
        @test isempty(search_references(doc, v -> v isa JsonNull))

        # a predicate that throws on some nodes is treated as no-match, not an error
        @test !isempty(search_references(doc, v -> v.value == 10))

        # Document-scoped by default: a text match on the raw "Alice" leaf folds to
        # the path of its enclosing JsonString, so the reference is selectable.
        @test length(search_references(doc, "Alice")) == 1
        @test evaluate_reference(doc, search_references(doc, "Alice")[1]) isa JsonString
        @test evaluate_reference(doc, search_references(doc, "Alice")[1]).value == "Alice"
        @test length(search_references(doc, "lic")) == 1      # substring
        @test isempty(search_references(doc, "Bob"))

        # Regex query → the two number leaves fold to their JsonNumber documents.
        @test length(search_references(doc, r"^\d+$")) == 2
        @test all(r -> evaluate_reference(doc, r) isa JsonNumber, search_references(doc, r"^\d+$"))
        @test length(search_references(doc, r"Ali")) == 1

        # raw=true reports the path to the exact matched leaf instead.
        @test evaluate_reference(doc, search_references(doc, "Alice"; raw=true)[1]) == "Alice"
        @test sort([evaluate_reference(doc, r) for r in search_references(doc, r"^\d+$"; raw=true)]) == [10, 20]

        # Returned references are canonical at rest: every navigation step is
        # preceded by a TypeReferenceStep checkpoint (as search_references produces),
        # and stripping them recovers a usable plain path.
        ar = search_references(doc, "Alice")[1]
        steps = ConcreteReference[]
        let p = ar
            while p isa ConcreteReference
                push!(steps, p)
                p = p.tail
            end
        end
        @test any(s -> s.type !== nothing, steps)   # folded: nodes carry types
        @test ar.head isa FieldReferenceStep             # head is always a nav step now
        @test ar.type !== nothing                    # first node records the document type
        @test evaluate_reference(doc, strip_reference_types(ar)) isa JsonString
    end

    @testset "search_documents" begin
        doc = parse_json("{\"name\": \"Alice\", \"scores\": [10, 20], \"active\": true}")

        # returns the matching documents themselves
        nums = search_documents(doc, v -> v isa JsonNumber)
        @test length(nums) == 2
        @test all(v -> v isa JsonNumber, nums)

        strs = search_documents(doc, v -> v isa JsonString && occursin("Alice", v.value))
        @test length(strs) == 1
        @test strs[1].value == "Alice"

        @test isempty(search_documents(doc, v -> v isa JsonNull))

        # Document-scoped: a text / regex match on a raw leaf returns the enclosing
        # document (the JsonString / JsonNumber), not the bare scalar.
        alice = search_documents(doc, "Alice")
        @test length(alice) == 1
        @test alice[1] isa JsonString && alice[1].value == "Alice"
        numdocs = search_documents(doc, r"^\d+$")
        @test length(numdocs) == 2
        @test all(v -> v isa JsonNumber, numdocs)
        @test sort([v.value for v in numdocs]) == [10, 20]

        # raw=true returns the exact matched values (bare scalars included).
        @test search_documents(doc, "Alice"; raw=true) == ["Alice"]
        @test sort(search_documents(doc, r"^\d+$"; raw=true)) == [10, 20]

        # a shared object reachable by several paths is returned only once…
        shared = JsonString("dup")
        obj = JsonObject("a" => shared, "b" => shared)
        @test length(search_documents(obj, v -> v === shared)) == 1
        # …whereas search_references reports both locations
        @test length(search_references(obj, v -> v === shared)) == 2
    end
end

function test_execute_julia_code()
    @testset "execute_julia_code" begin
        # Need a mock editor for this test
        # For now, we'll test with a simple dict as editor
        editor = Dict("document" => "test", "projection" => "test")
        tools = ToolSet()

        # Test simple expression
        result = execute_julia_code(tools, editor, "1 + 1")
        @test isa(result, String)
        @test occursin("2", result)

        # Test expression that uses editor
        result = execute_julia_code(tools, editor, "editor")
        @test isa(result, String)

        # Test error handling
        result = execute_julia_code(tools, editor, "undefined_function()")
        @test isa(result, String)
        @test occursin("Error", result) || occursin("UndefVarError", result)

        # Test multi-line code
        result = execute_julia_code(tools, editor, """
            x = 5
            y = 10
            x + y
        """)
        @test isa(result, String)
        @test occursin("15", result)

        # Test string operations
        result = execute_julia_code(tools, editor, "\"hello\" * \" world\"")
        @test isa(result, String)
        @test occursin("hello world", result)

        # Test array operations
        result = execute_julia_code(tools, editor, "[1, 2, 3] .^ 2")
        @test isa(result, String)
        @test occursin("[1, 4, 9]", result)

        # Test stdout capture (using println)
        result = execute_julia_code(tools, editor, "println(\"test output\")")
        @test isa(result, String)
        @test occursin("test output", result)

        # Test that nothing expressions don't add extra output
        result = execute_julia_code(tools, editor, "x = 42")
        @test isa(result, String)
        # Should not contain "nothing" since x = 42 returns nothing but we don't print it

        # Test accessing editor fields
        result = execute_julia_code(tools, editor, "editor[\"document\"]")
        @test isa(result, String)
        @test occursin("test", result)

        # Test editor variable access - verify editor is available in scope
        result = execute_julia_code(tools, editor, "editor isa Dict")
        @test isa(result, String)
        @test occursin("true", result)

        # Test editor field access with different syntax
        result = execute_julia_code(tools, editor, "editor[\"projection\"]")
        @test isa(result, String)
        @test occursin("test", result)

        # Test complex expression
        result = execute_julia_code(tools, editor, "sqrt(16) + 2^3")
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
        tools = register_default_tools!(ToolSet())

        a = Assistant(; llm = FakeLlm("ok"))
        a.input.value = "editor !== nothing"
        a.input.selection = ConcreteReference(
            FieldReferenceStep("value"),
            ConcreteReference(RangeReferenceStep(0, length(a.input.value)),
                                  EmptyReference()))

        stand_in = (document = a, tools = tools)
        evaluate_operation(stand_in, SubmitJuliaOperation(a))

        @test length(a.conversation.turns) == 1
        exec = a.conversation.turns[1].parts[1].content
        @test occursin("true", _eval_result(exec))
        @test !exec.is_error

        a.input.value = "editor.document isa Assistant"
        a.input.selection = ConcreteReference(
            FieldReferenceStep("value"),
            ConcreteReference(RangeReferenceStep(0, length(a.input.value)),
                                  EmptyReference()))
        evaluate_operation(stand_in, SubmitJuliaOperation(a))
        exec2 = a.conversation.turns[2].parts[1].content
        @test occursin("true", _eval_result(exec2))
        @test !exec2.is_error
    end
end

# Wait for an assistant turn to end, for at most `seconds`.
function _wait_for_turn_end(a; seconds = 10.0)
    deadline = time() + seconds
    while a.status === :streaming && time() < deadline
        sleep(0.01)
    end
    a.status
end

# A turn whose backend has a meaning model gives it to the editor's tools, so that
# the searches of the turn rank a description by its meaning. A backend without
# one leaves the tools as they are.
function test_assistant_turn_binds_meaning_model()
    @testset "an assistant turn binds its meaning model" begin
        ToolModule._MEANING_FOLDER[] = mktempdir()
        try
            tools = register_default_tools!(ToolSet())
            a = Assistant(; llm = FakeLlm("ok"; meaning_model = "assistant-turn"))
            a.input.value = "hello"
            evaluate_operation((document = a, tools = tools), SubmitProseOperation(a))
            @test _wait_for_turn_end(a) === :idle
            @test tools.meaning_model isa MeaningModel
            @test tools.meaning_model.name == "fake/assistant-turn"

            plain_tools = register_default_tools!(ToolSet())
            plain = Assistant(; llm = FakeLlm("ok"))
            plain.input.value = "hello"
            evaluate_operation((document = plain, tools = plain_tools), SubmitProseOperation(plain))
            @test _wait_for_turn_end(plain) === :idle
            @test plain_tools.meaning_model === nothing
        finally
            ToolModule._MEANING_FOLDER[] = ""
        end
    end
end

function test_function_availability()
    @testset "function_availability" begin
        # Need a mock editor for this test
        editor = Dict("document" => "test", "projection" => "test")
        tools = ToolSet()

        # Test that evaluate_reference is available by calling it
        result = execute_julia_code(tools, editor, "evaluate_reference(5, EmptyReference())")
        @test isa(result, String)
        @test occursin("5", result)
        
        # Test that extend_reference is available by calling it
        result = execute_julia_code(tools, editor, "extend_reference(EmptyReference(), PositionReferenceStep(1))")
        @test isa(result, String)
        # Should not error
        
        # Test that is_reference_equal is available by calling it
        result = execute_julia_code(tools, editor, "is_reference_equal(EmptyReference(), EmptyReference())")
        @test isa(result, String)
        # Should not error
        
        # Test that PositionReferenceStep is available by constructing it
        result = execute_julia_code(tools, editor, "PositionReferenceStep(1)")
        @test isa(result, String)
        # Should not error
        
        # Test that ElementReferenceStep is available by constructing it
        result = execute_julia_code(tools, editor, "ElementReferenceStep(1)")
        @test isa(result, String)
        # Should not error
        
        # Test that FieldReferenceStep is available by constructing it
        result = execute_julia_code(tools, editor, "FieldReferenceStep(\"test\")")
        @test isa(result, String)
        # Should not error
        
        # Test that EmptyReference is available by constructing it
        result = execute_julia_code(tools, editor, "EmptyReference()")
        @test isa(result, String)
        # Should not error
    end
end

function test_base_extensions()
    @testset "base_extensions" begin
        # Need a mock editor for this test
        editor = Dict("document" => "test", "projection" => "test")
        tools = ToolSet()

        # Test that CellVector indexing works (Base.getindex extension)
        result = execute_julia_code(tools, editor, """
            cv = CellVector([Cell(1), Cell(2), Cell(3)])
            cv[1]
        """)
        @test isa(result, String)
        @test occursin("1", result)
        
        # Test that CellVector length works (Base.length extension)
        result = execute_julia_code(tools, editor, """
            cv = CellVector([Cell(1), Cell(2), Cell(3)])
            length(cv)
        """)
        @test isa(result, String)
        @test occursin("3", result)
        
        # Test that CellVector iteration works (Base.iterate extension)
        result = execute_julia_code(tools, editor, """
            cv = CellVector([Cell(1), Cell(2), Cell(3)])
            collect(cv)
        """)
        @test isa(result, String)
        @test occursin("[1, 2, 3]", result)
        
        # Test that JsonArray indexing works (Base.getindex extension)
        result = execute_julia_code(tools, editor, """
            arr = JsonArray([Cell(JsonNumber(Cell(1))), Cell(JsonNumber(Cell(2)))])
            arr[1]
        """)
        @test isa(result, String)
        @test occursin("1", result)      # arr[1] → JsonNumber(1)
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
        test_assistant_turn_binds_meaning_model()
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
export test_workbench_editor_reference, test_assistant_turn_binds_meaning_model
export test_search_documentation, test_search_api, test_search_tools_registered
export test_workbench_b1, test_print_object_options, test_search_object
