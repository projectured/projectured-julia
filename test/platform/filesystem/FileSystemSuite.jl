"""
    test_filesystem()

Run this package's whole suite: the layering guard and every filesystem test.
"""
function test_filesystem()
    @testset "ProjecturedPlatform" begin
        test_filesystem_document()
        test_filesystem_to_syntax()
        test_filesystem_to_widget()
        test_workspace_duplicate()
        test_workspace_to_filesystem()
    end
end

export test_filesystem, test_filesystem_document, test_filesystem_to_syntax,
       test_filesystem_to_widget, test_workspace_duplicate, test_workspace_to_filesystem
