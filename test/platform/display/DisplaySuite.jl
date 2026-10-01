"""
    test_display()

Run this package's whole suite: the layering guard and a value shown in an
editor.
"""
function test_display()
    @testset "ProjecturedPlatform" begin
        test_editor_display()
    end
end

export test_display, test_editor_display
