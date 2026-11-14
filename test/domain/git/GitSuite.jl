"""
    test_git_layering()

Static layered-architecture guard for `ProjecturedGit`.
"""
function test_git_layering()
    main = get_package_source_root(ProjecturedGit)
    check_layering(main, pathof(ProjecturedGit);
                   name = "git",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedGit; all = true)
                         if isdefined(ProjecturedGit, n) &&
                            getfield(ProjecturedGit, n) isa Module &&
                            getfield(ProjecturedGit, n) !== ProjecturedGit &&
                            parentmodule(getfield(ProjecturedGit, n)) !== ProjecturedGit))
end

"""
    test_git()

Run this package's whole suite: the layering guard and every git test.
"""
function test_git()
    @testset "ProjecturedGit" begin
        test_git_layering()
        test_git_parse()
        test_git_reading()
        test_git_range()
        test_git_views()
        test_git_gestures()
        test_git_verbs()
    end
end

export test_git, test_git_layering, test_git_parse, test_git_reading, test_git_range, test_git_views,
       test_git_gestures, test_git_verbs
