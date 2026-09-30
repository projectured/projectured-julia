"""
    test_undo_layering()

Static layered-architecture guard for `ProjecturedPlatform`.
"""
function test_undo_layering()
    main = get_package_source_root(ProjecturedPlatform)
    check_layering(main, pathof(ProjecturedPlatform);
                   name = "undo",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedPlatform; all = true)
                         if isdefined(ProjecturedPlatform, n) &&
                            getfield(ProjecturedPlatform, n) isa Module &&
                            getfield(ProjecturedPlatform, n) !== ProjecturedPlatform &&
                            parentmodule(getfield(ProjecturedPlatform, n)) !== ProjecturedPlatform))
end

"""
    test_undo()

Run this package's whole suite: the layering guard and every undo test.
"""
function test_undo()
    @testset "ProjecturedPlatform" begin
        test_undo_layering()
        test_undo_buffer()
    end
end

export test_undo, test_undo_layering, test_undo_buffer
