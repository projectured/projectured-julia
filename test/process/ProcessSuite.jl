"""
    test_process_layering()

Static layered-architecture guard for `ProjecturedProcess`.
"""
function test_process_layering()
    main = get_package_source_root(ProjecturedProcess)
    check_layering(main, pathof(ProjecturedProcess);
                   name = "process",
                   # PAR-QUALIFIED-EXTENSION: the header imports what it extends
                   qualified_files = Set(["ProcessDocument.jl"]),
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedProcess; all = true)
                         if isdefined(ProjecturedProcess, n) &&
                            getfield(ProjecturedProcess, n) isa Module &&
                            getfield(ProjecturedProcess, n) !== ProjecturedProcess &&
                            parentmodule(getfield(ProjecturedProcess, n)) !== ProjecturedProcess))
end

"""
    test_process()

Run this package's whole suite: the layering guard and every process test.
"""
function test_process()
    @testset "ProjecturedProcess" begin
        test_process_layering()
        test_process_document()
        test_process_debug()
        test_process_diagram()
        test_process_to_julia_code()
        test_process_to_syntax()
    end
end

export test_process, test_process_layering, test_process_document, test_process
export test_process_debug, test_process_diagram, test_process_to_julia_code
export test_process_to_syntax
