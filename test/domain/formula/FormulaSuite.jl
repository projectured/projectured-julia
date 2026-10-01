"""
    test_formula_layering()

Static layered-architecture guard for `ProjecturedFormula`.
"""
function test_formula_layering()
    main = get_package_source_root(ProjecturedFormula)
    check_layering(main, pathof(ProjecturedFormula);
                   name = "formula",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedFormula; all = true)
                         if isdefined(ProjecturedFormula, n) &&
                            getfield(ProjecturedFormula, n) isa Module &&
                            getfield(ProjecturedFormula, n) !== ProjecturedFormula &&
                            parentmodule(getfield(ProjecturedFormula, n)) !== ProjecturedFormula))
end

"""
    test_formula()

Run this package's whole suite: the layering guard and every formula test.
"""
function test_formula()
    @testset "ProjecturedFormula" begin
        test_formula_layering()
        test_formula_to_syntax()
        test_formula_theme()
        test_formula_file()
        test_formula_math()
    end
end

export test_formula, test_formula_layering, test_formula_to_syntax, test_formula_theme,
       test_formula_file, test_formula_math
