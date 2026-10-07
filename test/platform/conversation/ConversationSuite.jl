"""
    test_conversation()

Run every conversation test of the platform.
"""
function test_conversation()
    @testset "ProjecturedPlatform" begin
        test_assistant_api()
        test_conversation_theme()
        test_external_agent_turn()
    end
end

export test_conversation
export test_assistant_api
export test_conversation_theme
export test_external_agent_turn
