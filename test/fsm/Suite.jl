"""
    test_fsm_layering()

Static layered-architecture guard for `ProjecturedFsm`.
"""
function test_fsm_layering()
    main = package_source_root(ProjecturedFsm)
    check_layering(main, pathof(ProjecturedFsm);
                   name = "fsm",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedFsm; all = true)
                         if isdefined(ProjecturedFsm, n) &&
                            getfield(ProjecturedFsm, n) isa Module &&
                            getfield(ProjecturedFsm, n) !== ProjecturedFsm &&
                            parentmodule(getfield(ProjecturedFsm, n)) !== ProjecturedFsm))
end

"""
    test_fsm()

Run this package's whole suite: the layering guard and every fsm test.
"""
function test_fsm()
    @testset "ProjecturedFsm" begin
        test_fsm_layering()
        test_fsm_document()
        test_fsm_diagram()
        test_fsm_to_julia_code()
        test_fsm_to_syntax()
    end
end

export test_fsm, test_fsm_layering, test_fsm_document, test_fsm
export test_fsm_diagram, test_fsm_to_julia_code, test_fsm_to_syntax
