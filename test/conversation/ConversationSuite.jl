"""
    test_conversation_layering()

Static layered-architecture guard for `ProjecturedConversation`.
"""
function test_conversation_layering()
    main = get_package_source_root(ProjecturedConversation)
    check_layering(main, pathof(ProjecturedConversation);
                   name = "conversation",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedConversation; all = true)
                         if isdefined(ProjecturedConversation, n) &&
                            getfield(ProjecturedConversation, n) isa Module &&
                            getfield(ProjecturedConversation, n) !== ProjecturedConversation &&
                            parentmodule(getfield(ProjecturedConversation, n)) !== ProjecturedConversation))
end

"""
    test_conversation()

Run this package's whole suite: the layering guard and every conversation test.
"""
function test_conversation()
    @testset "ProjecturedConversation" begin
        test_conversation_layering()
        test_conversation_editor()
        test_conversation_transcript()
    end
end

export test_conversation, test_conversation_layering
export test_conversation_editor, test_conversation_transcript
