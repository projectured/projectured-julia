"""
    test_conversation_layering()

Static layered-architecture guard for `ProjecturedPlatform`.
"""
function test_conversation_layering()
    main = get_package_source_root(ProjecturedPlatform)
    check_layering(main, pathof(ProjecturedPlatform);
                   name = "conversation",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedPlatform; all = true)
                         if isdefined(ProjecturedPlatform, n) &&
                            getfield(ProjecturedPlatform, n) isa Module &&
                            getfield(ProjecturedPlatform, n) !== ProjecturedPlatform &&
                            parentmodule(getfield(ProjecturedPlatform, n)) !== ProjecturedPlatform))
end

"""
    test_conversation()

Run this package's whole suite: the layering guard and every conversation test.
"""
function test_conversation()
    @testset "ProjecturedPlatform" begin
        test_conversation_layering()
        test_conversation_editor()
        test_conversation_transcript()
    end
end

export test_conversation, test_conversation_layering
export test_conversation_editor, test_conversation_transcript
