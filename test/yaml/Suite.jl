"""
    test_yaml_layering()

Static layered-architecture guard for `ProjecturedYaml`.
"""
function test_yaml_layering()
    main = package_source_root(ProjecturedYaml)
    check_layering(main, pathof(ProjecturedYaml);
                   name = "yaml",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedYaml; all = true)
                         if isdefined(ProjecturedYaml, n) &&
                            getfield(ProjecturedYaml, n) isa Module &&
                            getfield(ProjecturedYaml, n) !== ProjecturedYaml &&
                            parentmodule(getfield(ProjecturedYaml, n)) !== ProjecturedYaml))
end

"""
    test_yaml()

Run this package's whole suite: the layering guard and every yaml test.
"""
function test_yaml()
    @testset "ProjecturedYaml" begin
        test_yaml_layering()
        test_yaml_parser()
    end
end

export test_yaml, test_yaml_layering, test_yaml_parser
