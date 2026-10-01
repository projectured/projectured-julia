"""
    test_yaml_layering()

Static layered-architecture guard for `ProjecturedYAML`.
"""
function test_yaml_layering()
    main = get_package_source_root(ProjecturedYAML)
    check_layering(main, pathof(ProjecturedYAML);
                   name = "yaml",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedYAML; all = true)
                         if isdefined(ProjecturedYAML, n) &&
                            getfield(ProjecturedYAML, n) isa Module &&
                            getfield(ProjecturedYAML, n) !== ProjecturedYAML &&
                            parentmodule(getfield(ProjecturedYAML, n)) !== ProjecturedYAML))
end

"""
    test_yaml()

Run this package's whole suite: the layering guard and every yaml test.
"""
function test_yaml()
    @testset "ProjecturedYAML" begin
        test_yaml_layering()
        test_yaml_parser()
    end
end

export test_yaml, test_yaml_layering, test_yaml_parser
