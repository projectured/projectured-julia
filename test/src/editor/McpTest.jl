using Test
using Projectured.McpModule
using Projectured.ToolRegistryModule: call_tool
using Projectured.WorkbenchAssistantModule: SubmitJuliaOperation
using Projectured: WorkbenchAssistant, evaluate_operation, ConcreteReferencePath,
                   FieldReference, RangeReference, EmptyReferencePath, FakeLlm

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
        exec = a.conversation.messages[1]
        @test occursin("true", exec.result)
        @test !exec.is_error

        a.input.value = "editor.document isa Projectured.WorkbenchAssistant"
        a.input.selection = ConcreteReferencePath(
            FieldReference("value"),
            ConcreteReferencePath(RangeReference(0, length(a.input.value)),
                                  EmptyReferencePath()))
        evaluate_operation(stand_in, SubmitJuliaOperation(a))
        exec2 = a.conversation.messages[2]
        @test occursin("true", exec2.result)
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
    end
end

export test_mcp_tools, test_mcp_resources
export test_list_guides, test_read_guide
export test_list_modules, test_list_classes, test_list_functions
export test_read_module_documentation, test_read_class_documentation, test_read_function_documentation
export test_execute_julia_code, test_function_availability, test_base_extensions
export test_workbench_editor_reference
