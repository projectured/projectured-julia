using Test
using Sockets
import HTTP
using ProjecturedMCP
using ProjecturedKernel.ToolModule
using ProjecturedPlatform.AssistantModule: SubmitJuliaOperation, SubmitProseOperation, _eval_result

function test_list_guides()
    @testset "list_guides" begin
        result = list_guides()
        @test isa(result, String)
        @test !isempty(result)
        @test occursin("**", result)                 # the name of each guide
        @test occursin("**guide/setup-guide**", result)

        # The description of a guide is its summary paragraph, and never the
        # header line above it: a model that reads `> **Kind:** …` learns the
        # kind of the document and nothing about its subject.
        for line in split(result, "\n\n")
            startswith(line, "**") || continue
            @test !occursin("**Kind:**", line)
            @test !occursin("**Status:**", line)
        end
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

function test_search_guides()
    @testset "search_guides" begin
        # A term that should appear in the guides
        result = search_guides("selection")
        @test isa(result, String)
        @test occursin("resource://guide/", result)

        # Limit is honoured (count the per-hit "resource://guide/" headers)
        result_one = search_guides("selection"; limit=1)
        @test count("resource://guide/", result_one) <= 1

        # No match
        result_none = search_guides("zzzznotarealword")
        @test occursin("No documentation matches", result_none)

        # Empty / too-short query
        @test occursin("Provide a search query", search_guides("a"))

        # Regex dispatch
        @test occursin("resource://guide/", search_guides(r"selection"))
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
        result_class = search_api("conversation"; kind="class")
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

function test_pane_tab_b1()
    @testset "pane tabs via operations + search" begin
        editing = PaneGroup(PaneTab[])
        info    = PaneGroup(PaneTab[])
        tree = PaneTree(PaneSplit(:vertical, Any[
            PaneGroup(PaneTab[PaneTab("Files", Workspace())]),
            editing,
            info,
        ]))

        # Find tabs generically with search (no bespoke list helper). The
        # explorer is not a file document, so nothing is "open" yet.
        @test isempty(search_documents(tree, x -> is_file_document(x)))

        # Open tabs by building the operation that carries its target group, then
        # applying it — the same path the editor loop runs for a gesture.
        a = JsonFile("a.json", JsonString("hi"))
        b = JsonFile("b.json", JsonNull())
        apply_pane_operation!(tree,
            make_pane_open_tab_operation(tree, editing, PaneTab(get_document_title(a), a)))
        apply_pane_operation!(tree,
            make_pane_open_tab_operation(tree, editing, PaneTab(get_document_title(b), b)))

        files = search_documents(tree, x -> is_file_document(x))
        @test length(files) == 2
        @test Set(get_document_title(f) for f in files) == Set(["a.json", "b.json"])

        # Locate a tab by content and resolve its reference back to the node.
        refs = search_references(tree,
            x -> is_file_document(x) && get_document_title(x) == "b.json")
        @test length(refs) == 1
        @test evaluate_reference(tree, refs[1]) === b

        # "Focus" is selecting that tab — a ReplaceSelectionOperation, like a click.
        apply_pane_operation!(tree, ReplaceSelectionOperation(refs[1]))
        @test evaluate_reference(tree, tree.selection) === b

        # Open onto another group; search finds it regardless of which group.
        n = JsonFile("n.json", JsonNull())
        apply_pane_operation!(tree,
            make_pane_open_tab_operation(tree, info, PaneTab(get_document_title(n), n)))
        @test any(f -> get_document_title(f) == "n.json", search_documents(tree, x -> is_file_document(x)))

        # Close a tab: find its index on the group, build the close operation.
        idx = 0
        for (i, tab) in enumerate(editing.tabs)
            get_document_title(tab.content) == "a.json" && (idx = i; break)
        end
        apply_pane_operation!(tree, make_pane_close_tab_operation(tree, editing, idx))
        @test [get_document_title(tab.content) for tab in editing.tabs] == ["b.json"]
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
    @testset "execute_julia_code!" begin
        # Need a mock editor for this test
        # For now, we'll test with a simple dict as editor
        editor = Dict("document" => "test", "projection" => "test")
        tools = ToolSet()

        # Test simple expression
        result = execute_julia_code!(tools, editor, "1 + 1")
        @test isa(result, String)
        @test occursin("2", result)

        # Test expression that uses editor
        result = execute_julia_code!(tools, editor, "editor")
        @test isa(result, String)

        # Test error handling
        result = execute_julia_code!(tools, editor, "undefined_function()")
        @test isa(result, String)
        @test occursin("Error", result) || occursin("UndefVarError", result)

        # Test multi-line code
        result = execute_julia_code!(tools, editor, """
            x = 5
            y = 10
            x + y
        """)
        @test isa(result, String)
        @test occursin("15", result)

        # Test string operations
        result = execute_julia_code!(tools, editor, "\"hello\" * \" world\"")
        @test isa(result, String)
        @test occursin("hello world", result)

        # Test array operations
        result = execute_julia_code!(tools, editor, "[1, 2, 3] .^ 2")
        @test isa(result, String)
        @test occursin("[1, 4, 9]", result)

        # Test stdout capture (using println)
        result = execute_julia_code!(tools, editor, "println(\"test output\")")
        @test isa(result, String)
        @test occursin("test output", result)

        # Test that nothing expressions don't add extra output
        result = execute_julia_code!(tools, editor, "x = 42")
        @test isa(result, String)
        # Should not contain "nothing" since x = 42 returns nothing but we don't print it

        # Test accessing editor fields
        result = execute_julia_code!(tools, editor, "editor[\"document\"]")
        @test isa(result, String)
        @test occursin("test", result)

        # Test editor variable access - verify editor is available in scope
        result = execute_julia_code!(tools, editor, "editor isa Dict")
        @test isa(result, String)
        @test occursin("true", result)

        # Test editor field access with different syntax
        result = execute_julia_code!(tools, editor, "editor[\"projection\"]")
        @test isa(result, String)
        @test occursin("test", result)

        # Test complex expression
        result = execute_julia_code!(tools, editor, "sqrt(16) + 2^3")
        @test isa(result, String)
        @test occursin("12", result)
    end
end

# Reproduces the bug where ALT+ENTER → SubmitJuliaOperation → call_tool
# used to pass `nothing` for editor, so the assistant saw `editor === nothing`
# and any `editor.document` reach-through crashed with FieldError. Verifies
# the assistant forwards the live editor (or a stand-in carrying
# `.document`) all the way to `execute_julia_code!`'s `let editor = …`.
function test_assistant_editor_reference()
    @testset "assistant editor reference" begin
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
        result = execute_julia_code!(tools, editor, "evaluate_reference(5, EmptyReference())")
        @test isa(result, String)
        @test occursin("5", result)
        
        # Test that extend_reference is available by calling it
        result = execute_julia_code!(tools, editor, "extend_reference(EmptyReference(), PositionReferenceStep(1))")
        @test isa(result, String)
        # Should not error
        
        # Test that is_reference_equal is available by calling it
        result = execute_julia_code!(tools, editor, "is_reference_equal(EmptyReference(), EmptyReference())")
        @test isa(result, String)
        # Should not error
        
        # Test that PositionReferenceStep is available by constructing it
        result = execute_julia_code!(tools, editor, "PositionReferenceStep(1)")
        @test isa(result, String)
        # Should not error
        
        # Test that ElementReferenceStep is available by constructing it
        result = execute_julia_code!(tools, editor, "ElementReferenceStep(1)")
        @test isa(result, String)
        # Should not error
        
        # Test that FieldReferenceStep is available by constructing it
        result = execute_julia_code!(tools, editor, "FieldReferenceStep(\"test\")")
        @test isa(result, String)
        # Should not error
        
        # Test that EmptyReference is available by constructing it
        result = execute_julia_code!(tools, editor, "EmptyReference()")
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
        result = execute_julia_code!(tools, editor, """
            cv = CellVector([Cell(1), Cell(2), Cell(3)])
            cv[1]
        """)
        @test isa(result, String)
        @test occursin("1", result)
        
        # Test that CellVector length works (Base.length extension)
        result = execute_julia_code!(tools, editor, """
            cv = CellVector([Cell(1), Cell(2), Cell(3)])
            length(cv)
        """)
        @test isa(result, String)
        @test occursin("3", result)
        
        # Test that CellVector iteration works (Base.iterate extension)
        result = execute_julia_code!(tools, editor, """
            cv = CellVector([Cell(1), Cell(2), Cell(3)])
            collect(cv)
        """)
        @test isa(result, String)
        @test occursin("[1, 2, 3]", result)
        
        # Test that JsonArray indexing works (Base.getindex extension)
        result = execute_julia_code!(tools, editor, """
            arr = JsonArray([Cell(JsonNumber(Cell(1))), Cell(JsonNumber(Cell(2)))])
            arr[1]
        """)
        @test isa(result, String)
        @test occursin("1", result)      # arr[1] → JsonNumber(1)
    end
end

# ── The server ───────────────────────────────────────────────────────────────
#
# A test that starts a server binds a port that no other program holds, and
# stops the server before it ends. The library of the protocol puts a logger of
# its own in place of the global one when its loop starts. `start_mcp!` puts the
# logger that was there before back, and a test puts the logger it found back
# too, so a server that fails to start leaves no foreign logger behind.

function _find_free_mcp_port()
    port, listener = listenany(ip"127.0.0.1", 20000)
    close(listener)
    Int(port)
end

_mcp_editor() = Editor(JsonString("x"), IdentityProjection(); backend = HeadlessBackend(),
                       devices = Device[])

# One request of the protocol, and the text of its answer. `params` is the JSON
# text of the parameters.
function _post_mcp_request(port, method, params = "{}")
    body = "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"$method\", \"params\": $params}"
    response = HTTP.post("http://127.0.0.1:$port/mcp",
                         ["Content-Type" => "application/json",
                          "Accept" => "application/json, text/event-stream"],
                         body; retry = false, readtimeout = 10)
    String(response.body)
end

# Whether a server answers at `port`.
function _is_mcp_port_open(port)
    try
        HTTP.get("http://127.0.0.1:$port/mcp"; retry = false, readtimeout = 5,
                 connect_timeout = 5, status_exception = false).status == 200
    catch
        false
    end
end

function test_mcp_server()
    @testset "the MCP server" begin
        logger = Base.CoreLogging.global_logger()
        try
            @testset "it listens at the host and the port it is given" begin
                editor = _mcp_editor()
                default = McpServer(editor)
                @test default.host == "127.0.0.1" && default.port == 9876
                port = _find_free_mcp_port()
                server = make_agent_server(:mcp, editor; host = "127.0.0.1", port = port)
                @test server.host == "127.0.0.1" && server.port == port
                try
                    start_agent_server!(server)
                    @test _is_mcp_port_open(port)
                finally
                    stop_agent_server!(server)
                end
            end

            @testset "a server with a secret answers only a client that sends it" begin
                server = make_agent_server(:mcp, _mcp_editor(); port = 0, secret = true)
                access = get_agent_server_access(server)
                @test server.port != 0
                @test access.name == "projectured"
                @test access.url == "http://127.0.0.1:$(server.port)/mcp"
                header = only(access.headers)
                @test first(header) == "Authorization"
                @test startswith(last(header), "Bearer ") && length(last(header)) == 7 + 64
                body = "{\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"initialize\", \"params\": " *
                       "{\"protocolVersion\": \"2025-06-18\", \"capabilities\": {}, " *
                       "\"clientInfo\": {\"name\": \"test\", \"version\": \"1\"}}}"
                post(headers) = HTTP.post(access.url,
                    ["Content-Type" => "application/json",
                     "Accept" => "application/json, text/event-stream", headers...],
                    body; retry = false, readtimeout = 10, status_exception = false)
                try
                    start_agent_server!(server)
                    @test post(Pair{String,String}[]).status == 401
                    @test post(["Authorization" => "Bearer wrong"]).status == 401
                    answer = post([header])
                    @test answer.status == 200
                    @test occursin("protocolVersion", String(answer.body))
                finally
                    stop_agent_server!(server)
                end
                @test isempty(get_agent_server_access(McpServer(_mcp_editor(); port = 0)).headers)
            end

            @testset "the start record and a later message reach the message log" begin
                store = MessageLogStore()
                # The capture wraps a logger that takes Info and prints nowhere.
                capture = MessageLogLogger(store, Base.CoreLogging.SimpleLogger(devnull))
                Base.CoreLogging.global_logger(capture)
                port = _find_free_mcp_port()
                server = make_agent_server(:mcp, _mcp_editor(); port = port)
                try
                    start_agent_server!(server)
                    @test _is_mcp_port_open(port)
                    @test Base.CoreLogging.global_logger() === capture
                    # The record that the library writes as its loop starts goes
                    # to the logger of the process, not to the logger of the library.
                    lines, _ = take_message_lines!(store)
                    @test ("Info", "Starting MCP server: projectured") in lines
                    @info "a line after the start"
                    lines, _ = take_message_lines!(store)
                    @test ("Info", "a line after the start") in lines
                finally
                    stop_agent_server!(server)
                    Base.CoreLogging.global_logger(logger)
                end
            end

            @testset "a stopped server frees its port" begin
                port = _find_free_mcp_port()
                server = make_agent_server(:mcp, _mcp_editor(); port = port)
                start_agent_server!(server)
                @test _is_mcp_port_open(port)
                stop_agent_server!(server)
                @test !_is_mcp_port_open(port)
                @test timedwait(() -> istaskdone(server.task), 5.0) === :ok
            end

            @testset "a client lists a tool declared before the loop, and calls it" begin
                port = _find_free_mcp_port()
                editor = _mcp_editor()
                listing, answer = Ref(""), Ref("")
                ran_on = Task[]
                probe = Tool("probe_declared";
                             description = "A tool declared before the loop.",
                             parameters = NamedTuple[],
                             handler = (target, args) ->
                                 (push!(ran_on, current_task()); "probed"))
                register_tool!(editor.tools, probe)
                # The server starts when the loop starts, and the client asks
                # when it listens.
                @async begin
                    try
                        timedwait(() -> _is_mcp_port_open(port), 10.0)
                        listing[] = _post_mcp_request(port, "tools/list")
                        answer[] = _post_mcp_request(port, "tools/call",
                            "{\"name\": \"probe_declared\", \"arguments\": {}}")
                    catch exception
                        listing[] = sprint(showerror, exception)
                    end
                    post_operation!(editor, QuitEditorOperation())
                end
                run_editor!(editor; mcp = (; host = "127.0.0.1", port = port))
                @test occursin("\"execute_julia_code\"", listing[])
                @test occursin("\"probe_declared\"", listing[])
                # The call ran on the task of the loop, which is this one.
                @test occursin("probed", answer[])
                @test ran_on == [current_task()]
            end
        finally
            Base.CoreLogging.global_logger(logger)
        end
    end
end

# A tool that a client calls runs on the task that runs the editor's loop, in
# the drain of the inbox, and the server task waits for its answer. The test
# plays the loop: it marks its own task as the loop's and drains by hand.
function test_mcp_tool_runs_on_editor_task()
    @testset "a tool that a client calls runs on the editor task" begin
        editor = _mcp_editor()
        ran_on = Task[]
        probe = Tool("probe_task";
                     description = "Writes the document and records its task.",
                     parameters = NamedTuple[],
                     handler = (target, args) -> begin
                         push!(ran_on, current_task())
                         target.document.value = "written"
                         "done"
                     end)
        broken = Tool("probe_throws";
                      description = "Throws.",
                      parameters = NamedTuple[],
                      handler = (target, args) -> error("probe failed"))
        handlers = Dict(t.name => t.handler for t in render_mcp_tools(editor, [probe, broken]))
        editor.loop_task = current_task()
        call = @async handlers["probe_task"](Dict{String,Any}())
        @test timedwait(() -> isready(editor.inbox), 5.0) === :ok
        sleep(0.05)
        # The call waits in the inbox: nothing ran, and nothing was written.
        @test isempty(ran_on)
        @test editor.document.value == "x"
        @test !istaskdone(call)
        @test drain_operations!(editor) == 1
        @test ran_on == [current_task()]
        @test editor.document.value == "written"
        @test fetch(call).text == "done"
        # A tool that throws answers its error, and the fault is recorded.
        failing = @async handlers["probe_throws"](Dict{String,Any}())
        @test timedwait(() -> isready(editor.inbox), 5.0) === :ok
        drain_operations!(editor)
        @test occursin("probe failed", fetch(failing).text)
        @test any(record -> record.origin === :probe_throws &&
                            occursin("probe failed", record.message),
                  get_fault_records(editor.faults))
        # With no loop, the call runs at once, on the task that calls.
        editor.loop_task = nothing
        @test handlers["probe_task"](Dict{String,Any}()).text == "done"
        @test ran_on == [current_task(), current_task()]
    end
end

# A client that names its call in the `_meta` of the request, as Claude Code does,
# gets the document that an evaluation returns kept under that name, so the turn
# of an agent can show it live. A call with no name keeps nothing.
function test_mcp_keeps_evaluated_document()
    @testset "the document of an evaluation is kept under the id of its call" begin
        editor = _mcp_editor()
        register_default_tools!(editor.tools)
        tools = Dict(t.name => t for t in render_mcp_tools(editor, list_tools(editor.tools)))
        evaluate = tools["execute_julia_code"].handler
        library = ProjecturedMCP.McpModule.ModelContextProtocol
        server = library.mcp_server(name = "test", version = "0.0.1")
        context(meta) = library.RequestContext(server = server, meta = meta)
        evaluate(Dict{String,Any}("code" => "JsonString(\"made\")"),
                 context(Dict{String,Any}("claudecode/toolUseId" => "toolu_1")))
        @test take_tool_call_value!(editor.tools, "toolu_1") isa JsonString
        @test take_tool_call_value!(editor.tools, "toolu_1") === nothing
        # A value that is no document, a call with no id, and a context with no
        # `_meta` keep nothing.
        evaluate(Dict{String,Any}("code" => "1 + 1"), context(Dict{String,Any}("claudecode/toolUseId" => "toolu_2")))
        evaluate(Dict{String,Any}("code" => "JsonString(\"again\")"))
        evaluate(Dict{String,Any}("code" => "JsonString(\"again\")"), context(nothing))
        @test isempty(editor.tools.call_values)
    end
end

# The MCP log holds each call that a client makes, in order: a read of a
# resource, a call of code that answers, and a call of code that throws, which is
# a fault. The client posts real requests to the server of a running loop.
function test_mcp_log()
    @testset "the MCP log holds the calls that a client made" begin
        port = _find_free_mcp_port()
        log = McpLog()
        store = get_session_mcp_log_store()
        take_mcp_calls!(store)
        feed = McpLogFeed(; store, log)
        editor = Editor(JsonString("x"), IdentityProjection(); backend = HeadlessBackend(),
                        devices = Device[], feeds = Feed[feed])
        answers = String[]
        @async begin
            try
                timedwait(() -> _is_mcp_port_open(port), 10.0)
                push!(answers, _post_mcp_request(port, "resources/read", "{\"uri\": \"resource://guides\"}"))
                # Two equal failures are two faults: their exceptions are `===`.
                for code in ("1 + 1", "error(\\\"boom\\\")", "error(\\\"boom\\\")")
                    push!(answers, _post_mcp_request(port, "tools/call",
                        "{\"name\": \"execute_julia_code\", \"arguments\": {\"code\": \"$code\"}}"))
                end
            catch exception
                push!(answers, sprint(showerror, exception))
            end
            post_operation!(editor, QuitEditorOperation())
        end
        logger = Base.CoreLogging.global_logger()
        try
            run_editor!(editor; mcp = (; host = "127.0.0.1", port = port))
        finally
            Base.CoreLogging.global_logger(logger)
        end
        # A call that the last frame did not drain is in the store still.
        drain_changes!(feed, editor)
        @test length(answers) == 4
        entries = collect(log.entries)
        @test [e.method for e in entries] == ["resources/read", "tools/call", "tools/call", "tools/call"]
        @test entries[1].name == "resource://guides" && !isempty(entries[1].answer)
        @test entries[2].name == "execute_julia_code" && entries[2].arguments == "1 + 1"
        @test occursin("2", entries[2].answer) && !entries[2].fault
        @test entries[3].fault && occursin("boom", entries[3].answer)
        @test entries[4].fault && occursin("boom", entries[4].answer)
        @test all(e -> e.duration >= 0, entries)
        @test log.count == 4 && log.faults == 2
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
        test_assistant_editor_reference()
        test_assistant_turn_binds_meaning_model()
        test_search_guides()
        test_search_api()
        test_pane_tab_b1()
        test_print_object_options()
        test_search_object()
        test_mcp_server()
        test_mcp_tool_runs_on_editor_task()
        test_mcp_keeps_evaluated_document()
        test_mcp_log()
    end
end

export test_mcp_tools, test_mcp_resources, test_mcp_log
export test_list_guides, test_read_guide
export test_list_modules, test_list_classes, test_list_functions
export test_read_module_documentation, test_read_class_documentation, test_read_function_documentation
export test_execute_julia_code, test_function_availability, test_base_extensions
export test_assistant_editor_reference, test_assistant_turn_binds_meaning_model
export test_search_guides, test_search_api
export test_pane_tab_b1, test_print_object_options, test_search_object
export test_mcp_server, test_mcp_tool_runs_on_editor_task
