# The formula examples as a person uses them: a key in a number of a sheet starts
# the edit mode of its formula, and Enter commits it and computes each formula
# that reads it, in a sheet of its own and in a sheet that a Markdown page holds.

"""
    test_formula_examples()

A digit in an input of the invoice and of the report starts the edit mode of the
formula with a draft, and Enter commits the draft and computes the formulas that
read it: the total of the invoice and the interest of the report.
"""
function test_formula_examples()
@testset "the formula examples take a key and Enter" begin

measure = FixedMeasure(8, 12, 4, 0)
# An editor of `document` in which `9` is typed after the first digit at `caret`.
function type_digit!(document, projection, caret)
    backend = HeadlessBackend()
    editor = build_editor(document, projection; backend, devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, tabs = false, appearance = false, settings = false, undo = true)
    set_selection!(document, extend_reference(caret, PositionReferenceStep(1)))
    run_frame!(editor)
    ProjecturedPlatformTest._nav_press!(editor, backend, KeyPress('9', "9", ModifierKeys(); time = 0.0))
    editor, backend
end

@testset "the invoice" begin
    invoice = make_formula_invoice_document_example()
    quantity = invoice.formulas[6]                             # B2 = 4
    @test get_formula_result(invoice.formulas[end]) == 55.8    # D7, the total
    editor, backend = type_digit!(invoice, make_formula_projection_example(; measure),
                                       @reference(invoice, formulas[6].code.value))
    @test quantity.draft isa PrimitiveNumber && quantity.draft.value == 49
    @test get_formula_result(quantity) == 4
    ProjecturedPlatformTest._nav_press!(editor, backend, KeyPress('\n'; time = 0.0))
    @test quantity.draft === nothing && get_formula_result(quantity) == 49
    @test get_formula_result(invoice.formulas[end]) ≈ (49 * 5.5 + 9.6 + 14.9) * 1.2
end

@testset "the report" begin
    report = make_formula_report_document_example()
    sheet = report.elements[3]
    principal = sheet.formulas[1]                              # 250000
    interest = get_formula_result(sheet.formulas[end])
    editor, backend = type_digit!(report, make_formula_report_projection_example(; measure),
                                       @reference(report, elements[3].formulas[1].code.value))
    @test principal.draft isa PrimitiveNumber && principal.draft.value == 2950000
    ProjecturedPlatformTest._nav_press!(editor, backend, KeyPress('\n'; time = 0.0))
    @test get_formula_result(principal) == 2950000
    @test get_formula_result(sheet.formulas[end]) ≈ interest * 2950000 / 250000
end

end
end
