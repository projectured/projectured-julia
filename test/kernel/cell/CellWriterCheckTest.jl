# The check of the writer of a cell, `cell/CellWriterCheck.jl`.
#
# While an editor runs its loop, only the task that owns its cells writes a cell
# that a computation reads. A write from another task races the owner, and the
# check records it. The list of owners is one for the process, so each test
# removes what it added.

using Test
using ProjecturedKernel.CellModule

# A cell that a computation read, so it has a reader.
function _make_read_cell()
    source = Cell(0)
    reader = Cell(@computation source[] + 1)
    reader[]
    (source, reader)
end

function test_cell_writer_check()
@testset "the check of the writer of a cell" begin
    take_foreign_cell_writes!()

    @testset "with no owner, nothing is checked" begin
        source, _ = _make_read_cell()
        fetch(Threads.@spawn (source[] = 1))
        @test isempty(take_foreign_cell_writes!())
    end

    @testset "the owner writes, and another task is recorded once" begin
        add_cell_writer!(current_task())
        try
            source, reader = _make_read_cell()
            source[] = 1
            @test isempty(take_foreign_cell_writes!())
            writer = Threads.@spawn begin
                source[] = 2
                source[] = 3
                current_task()
            end
            task = fetch(writer)
            writes = take_foreign_cell_writes!()
            @test length(writes) == 1
            @test only(writes).task === task
            @test only(writes).cell_type <: ReactiveCell
            @test occursin("Post the write with `run_on_editor_task!`",
                           sprint(showerror, only(writes)))
            @test reader[] == 4                      # the check records; the write stands
            @test isempty(take_foreign_cell_writes!())
        finally
            remove_cell_writer!(current_task())
        end
    end

    @testset "a cell that no computation reads is not checked" begin
        add_cell_writer!(current_task())
        try
            lonely = Cell(0)
            fetch(@async (lonely[] = 1))
            @test isempty(take_foreign_cell_writes!())
        finally
            remove_cell_writer!(current_task())
        end
    end

    @testset "a computation on another task is recorded" begin
        add_cell_writer!(current_task())
        try
            source = Cell(0)
            middle = Cell(@computation source[] * 2)
            top = Cell(@computation middle[] + 1)
            top[]
            source[] = 5                             # `middle` and `top` are out of date
            task = fetch(Threads.@spawn (middle[]; current_task()))
            @test any(write -> write.task === task, take_foreign_cell_writes!())
        finally
            remove_cell_writer!(current_task())
        end
    end

    @testset "a removed owner is checked no more" begin
        add_cell_writer!(current_task())
        remove_cell_writer!(current_task())
        source, _ = _make_read_cell()
        fetch(Threads.@spawn (source[] = 1))
        @test isempty(take_foreign_cell_writes!())
    end
end
end

export test_cell_writer_check
