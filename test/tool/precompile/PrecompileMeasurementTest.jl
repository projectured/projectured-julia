# The parts of the measurement that run in a moment: the size of a folder and
# the median of the values that new processes print.

"""
    test_precompile_measurement()

A folder measures the sum of its files, and the median of three processes is
the middle value of each label that they print.
"""
function test_precompile_measurement()
    @testset "measurement" begin
        mktempdir() do folder
            @test measure_folder_bytes(joinpath(folder, "missing")) == 0
            write(joinpath(mkpath(joinpath(folder, "a", "b")), "one"), "12345")
            write(joinpath(folder, "two"), "123")
            @test measure_folder_bytes(folder) == 8
            # Each process prints the next of 3, 1 and 2 seconds, so the median
            # of the label is 2.
            counter = joinpath(folder, "counter")
            write(counter, "0")
            script = """
                count = parse(Int, read($(repr(counter)), String)) + 1
                write($(repr(counter)), string(count))
                println("MEASUREMENT the probe: ", (3.0, 1.0, 2.0)[count])
                println("noise")
                """
            io = IOBuffer()
            medians = measure_process_median(`$(Base.julia_cmd()) --startup-file=no -e $script`;
                                             runs = 3, io)
            @test medians == ["the probe" => 2.0]
            @test occursin("the probe", String(take!(io)))
        end
    end
end
