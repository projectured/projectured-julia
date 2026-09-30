"""
    test_fault_layering()

Static layered-architecture guard for `ProjecturedFault`.
"""
function test_fault_layering()
    main = get_package_source_root(ProjecturedFault)
    check_layering(main, pathof(ProjecturedFault);
                   name = "fault",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedFault; all = true)
                         if isdefined(ProjecturedFault, n) &&
                            getfield(ProjecturedFault, n) isa Module &&
                            getfield(ProjecturedFault, n) !== ProjecturedFault &&
                            parentmodule(getfield(ProjecturedFault, n)) !== ProjecturedFault))
end

"""
    test_fault()

Run this package's whole suite: the layering guard, the barrier inside a
pipeline, the safe mode, and the one call a program makes to wire it all up.
"""
function test_fault()
    @testset "ProjecturedFault" begin
        test_fault_layering()
        test_fault_catching()
        test_fault_safe_mode()
        test_fault_tolerant_projection()
    end
end

export test_fault, test_fault_layering, test_fault_catching, test_fault_safe_mode,
       test_fault_tolerant_projection
