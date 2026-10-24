"""
    test_conversation()

Run every conversation test of the platform.
"""
function test_conversation()
    @testset "ProjecturedPlatform" begin
        test_assistant_api()
        test_assistant_overview()
        test_assistant_list()
        test_conversation_theme()
        test_external_agent_turn()
        test_agent_work()
        test_assistant_work()
        test_assistant_rounds()
        test_conversation_tree()
    end
end

export test_conversation
export test_assistant_api
export test_assistant_overview
export test_assistant_list
export test_conversation_theme
export test_external_agent_turn
export test_agent_work
export test_assistant_work
export test_assistant_rounds
export test_conversation_tree
