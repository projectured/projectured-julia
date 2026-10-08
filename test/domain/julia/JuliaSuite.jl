"""
    test_julia_layering()

Static layered-architecture guard for `ProjecturedJulia`.
"""
function test_julia_layering()
    main = get_package_source_root(ProjecturedJulia)
    check_layering(main, pathof(ProjecturedJulia);
                   name = "julia",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedJulia; all = true)
                         if isdefined(ProjecturedJulia, n) &&
                            getfield(ProjecturedJulia, n) isa Module &&
                            getfield(ProjecturedJulia, n) !== ProjecturedJulia &&
                            parentmodule(getfield(ProjecturedJulia, n)) !== ProjecturedJulia))
end

"""
    test_julia()

Run this package's whole suite: the layering guard and every julia test.
"""
function test_julia()
    @testset "ProjecturedJulia" begin
        test_julia_layering()
        test_julia_parser()
        test_julia_expression()
        test_julia_definition()
        test_julia_duplicate()
        test_julia_to_syntax()
        test_julia_theme()
        test_julia_code_pieces()
        test_julia_file_view()
        test_julia_typein()
        test_conversation_editor()
        test_julia_tooltip()
        test_tooltip_window()
    end
end

export test_julia, test_julia_layering, test_julia_parser, test_julia_definition
export test_julia_expression, test_julia_duplicate, test_julia_to_syntax, test_julia_theme, test_julia_code_pieces, test_julia_file_view
export test_julia_typein, test_conversation_editor, test_julia_tooltip, test_tooltip_window
