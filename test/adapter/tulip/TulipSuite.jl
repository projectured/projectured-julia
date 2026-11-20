"""
    test_tulip_layering()

Static layered-architecture guard for `ProjecturedTulip`.
"""
function test_tulip_layering()
    main = get_package_source_root(ProjecturedTulip)
    check_layering(main, pathof(ProjecturedTulip);
                   name = "tulip",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedTulip; all = true)
                         if isdefined(ProjecturedTulip, n) &&
                            getfield(ProjecturedTulip, n) isa Module &&
                            getfield(ProjecturedTulip, n) !== ProjecturedTulip &&
                            parentmodule(getfield(ProjecturedTulip, n)) !== ProjecturedTulip))
end

"Run the Tulip constraint-solver suite."

const test_tulip = TestSuite("ProjecturedTulip", [
    test_constraint_solver,
])

export test_tulip, test_tulip_layering, test_constraint_solver
