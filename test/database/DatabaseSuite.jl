"""
    test_database_layering()

Static layered-architecture guard for `ProjecturedDatabase`.
"""
function test_database_layering()
    main = get_package_source_root(ProjecturedDatabase)
    check_layering(main, pathof(ProjecturedDatabase);
                   name = "database",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedDatabase; all = true)
                         if isdefined(ProjecturedDatabase, n) &&
                            getfield(ProjecturedDatabase, n) isa Module &&
                            getfield(ProjecturedDatabase, n) !== ProjecturedDatabase &&
                            parentmodule(getfield(ProjecturedDatabase, n)) !== ProjecturedDatabase))
end

"""
    test_database_domain()

Run this package's whole suite: the layering guard and every database test.
"""
function test_database()
    @testset "ProjecturedDatabase" begin
        test_database_layering()
        test_database_documents()
    end
end

export test_database, test_database_layering, test_database_documents
