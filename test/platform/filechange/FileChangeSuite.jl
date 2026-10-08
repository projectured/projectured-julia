"""
    test_filechange()

Run this slice's whole suite: the store of the watched files, and its feed.
"""
function test_filechange()
    @testset "ProjecturedPlatform" begin
        test_file_change_store()
    end
end

export test_filechange, test_file_change_store
