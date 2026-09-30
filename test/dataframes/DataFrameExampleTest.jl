# Fragment of `ProjecturedDataFramesTest` — the shape of the one factory
# `ProjecturedDataFramesExample` holds.

"""
    test_data_frame_example()

`make_data_frame_example` answers a `DataFrame` with the rows and the columns
asked for, and `missing` where the formula of `discount` says so.
"""
function test_data_frame_example()
    @testset "make_data_frame_example" begin
        table = make_data_frame_example(rows = 10)
        @test nrow(table) == 10
        @test ncol(table) == 6
        @test ismissing(table.discount[5])
    end
end
