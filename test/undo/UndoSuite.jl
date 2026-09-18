"""
    test_undo_layering()

Static layered-architecture guard for `ProjecturedUndo`.
"""
function test_undo_layering()
    main = get_package_source_root(ProjecturedUndo)
    check_layering(main, pathof(ProjecturedUndo);
                   name = "undo",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedUndo; all = true)
                         if isdefined(ProjecturedUndo, n) &&
                            getfield(ProjecturedUndo, n) isa Module &&
                            getfield(ProjecturedUndo, n) !== ProjecturedUndo &&
                            parentmodule(getfield(ProjecturedUndo, n)) !== ProjecturedUndo))
end

"""
    test_undo()

Run this package's whole suite: the layering guard and every undo test.
"""
function test_undo()
    @testset "ProjecturedUndo" begin
        test_undo_layering()
        test_undo_buffer()
    end
end

export test_undo, test_undo_layering, test_undo_buffer
