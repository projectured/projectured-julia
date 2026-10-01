"""
    test_conversation()

Run this package's whole suite: the layering guard and every conversation test.
"""
function test_conversation()
    @testset "ProjecturedPlatform" begin
        test_conversation_editor()
        test_conversation_transcript()
    end
end

export test_conversation
export test_conversation_editor, test_conversation_transcript
