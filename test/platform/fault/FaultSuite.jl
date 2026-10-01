"""
    test_fault()

Run this package's whole suite: the layering guard, the barrier inside a
pipeline, the safe mode, and the one call a program makes to wire it all up.
"""
function test_fault()
    @testset "ProjecturedPlatform" begin
        test_fault_catching()
        test_fault_safe_mode()
        test_fault_part()
        test_fault_tolerant_projection()
    end
end

export test_fault, test_fault_catching, test_fault_safe_mode, test_fault_part,
       test_fault_tolerant_projection
