"Run the Tulip constraint-solver suite."
function test_tulip()
    @testset "ProjecturedTulip" begin
        test_constraint_solver()
    end
end

export test_tulip, test_constraint_solver
