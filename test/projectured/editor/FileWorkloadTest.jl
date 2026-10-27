# The file that the workload of each domain opens: each gesture of a file finds its
# target in the application window, with every domain of the session loaded.

"""
    test_file_workloads()

For each type that has a file of a workload (`make_workload_file`), the open of
the file from the Files pane, a click on the text that it draws, a key, a save,
an undo and the name buffer each find their target, and no barrier of the editor
catches a fault.
"""
function test_file_workloads()
    @testset "the file of each domain in the application window" begin
        for method in methods(make_workload_file)
            type = method.sig.parameters[2].parameters[1]
            @testset "the file of $(nameof(type))" begin
                file = make_workload_file(type)
                @test occursin(file.shown, file.text) || endswith(file.name, ".pred")
                @test run_file_workload(type) === nothing
            end
        end
    end
end
