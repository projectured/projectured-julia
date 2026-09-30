# A folder is read at the first read of its elements, and each entry at its own
# first read. So a folder that nothing reads costs one `isdir`, a read of the
# length of a folder is one `readdir`, and a folder that can not be read is empty.
function test_filesystem_document()
@testset "FileSystemDocument reads a folder when something reads it" begin
    # Whether the listing of `folder` was read, and whether its entry `i` was.
    is_listing_read(folder) = is_cell_up_to_date(getfield(folder.elements, :elements))
    is_entry_read(folder, i) = is_cell_up_to_date(getfield(folder.elements, :elements)[][i])
    mktempdir() do dir
        write(joinpath(dir, "a.jl"), "")
        mkpath(joinpath(dir, "sub", "deep"))
        write(joinpath(dir, "sub", "deep", "b.jl"), "")

        root = make_filesystem_pathname(dir)
        @test root isa FileSystemDirectory
        @test !is_listing_read(root)

        # The length reads the listing and no entry.
        @test length(root.elements) == 2
        @test is_listing_read(root)
        @test !is_entry_read(root, 1) && !is_entry_read(root, 2)

        # An entry reads itself and nothing below it.
        sub = root.elements[2]
        @test sub isa FileSystemDirectory && basename(sub.pathname) == "sub"
        @test is_entry_read(root, 2) && !is_entry_read(root, 1)
        @test !is_listing_read(sub)
        @test root.elements[1] isa FileSystemFile

        # The names are in the order of `readdir`, at every depth.
        deep = sub.elements[1]
        @test basename(deep.pathname) == "deep"
        @test [basename(e.pathname) for e in deep.elements] == ["b.jl"]
    end

    # A folder that can not be read has no entries.
    mktempdir() do dir
        closed = joinpath(dir, "closed")
        mkpath(joinpath(closed, "inner"))
        chmod(closed, 0o000)
        try
            @test length(make_filesystem_pathname(closed).elements) == 0
        finally
            chmod(closed, 0o755)
        end

        # A folder that is gone before its first read has no entries either.
        gone = joinpath(dir, "gone")
        mkpath(gone)
        folder = make_filesystem_pathname(gone)
        rm(gone)
        @test length(folder.elements) == 0
    end
end
end
