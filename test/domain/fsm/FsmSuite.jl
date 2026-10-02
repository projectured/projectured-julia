"""
    test_fsm_layering()

Static layered-architecture guard for `ProjecturedFSM`.
"""
function test_fsm_layering()
    main = get_package_source_root(ProjecturedFSM)
    check_layering(main, pathof(ProjecturedFSM);
                   name = "fsm",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedFSM; all = true)
                         if isdefined(ProjecturedFSM, n) &&
                            getfield(ProjecturedFSM, n) isa Module &&
                            getfield(ProjecturedFSM, n) !== ProjecturedFSM &&
                            parentmodule(getfield(ProjecturedFSM, n)) !== ProjecturedFSM))
end

"""
    test_fsm()

Run this package's whole suite: the layering guard and every fsm test.
"""
function test_fsm()
    @testset "ProjecturedFSM" begin
        test_fsm_layering()
        test_fsm_document()
        test_fsm_diagram()
        test_fsm_to_julia_code()
        test_fsm_to_syntax()
        test_fsm_theme()
    end
end

export test_fsm, test_fsm_layering, test_fsm_document, test_fsm
export test_fsm_diagram, test_fsm_to_julia_code, test_fsm_to_syntax, test_fsm_theme
