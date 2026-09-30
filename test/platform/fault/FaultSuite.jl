"""
    test_fault_layering()

Static layered-architecture guard for `ProjecturedPlatform`.
"""
function test_fault_layering()
    main = get_package_source_root(ProjecturedPlatform)
    check_layering(main, pathof(ProjecturedPlatform);
                   name = "fault",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedPlatform; all = true)
                         if isdefined(ProjecturedPlatform, n) &&
                            getfield(ProjecturedPlatform, n) isa Module &&
                            getfield(ProjecturedPlatform, n) !== ProjecturedPlatform &&
                            parentmodule(getfield(ProjecturedPlatform, n)) !== ProjecturedPlatform))
end

"""
    test_fault()

Run this package's whole suite: the layering guard, the barrier inside a
pipeline, the safe mode, and the one call a program makes to wire it all up.
"""
function test_fault()
    @testset "ProjecturedPlatform" begin
        test_fault_layering()
        test_fault_catching()
        test_fault_safe_mode()
        test_fault_tolerant_projection()
    end
end

export test_fault, test_fault_layering, test_fault_catching, test_fault_safe_mode,
       test_fault_tolerant_projection
