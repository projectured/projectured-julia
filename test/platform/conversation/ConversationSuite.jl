"""
    test_conversation()

Run every conversation test of the platform.
"""
function test_conversation()
    @testset "ProjecturedPlatform" begin
        test_assistant_api()
    end
end

export test_conversation
export test_assistant_api
