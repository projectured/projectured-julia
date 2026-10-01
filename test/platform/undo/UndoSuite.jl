"""
    test_undo()

Run this package's whole suite: the layering guard and every undo test.
"""
function test_undo()
    @testset "ProjecturedPlatform" begin
        test_undo_buffer()
    end
end

export test_undo, test_undo_buffer
