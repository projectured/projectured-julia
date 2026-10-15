# A page of prose that holds a sheet: the Markdown says what the sheet computes,
# and the sheet computes it. The formulas edit as in any sheet: change the
# principal, the rate or the term and press Enter, and the payment and the totals
# compute again; Escape drops an edit. The three inputs are math code, because a
# key edits math code and no literal of Julia.
function make_formula_report_document_example()
    make_formula(name, code) = FormulaFormula(name, parse_julia(code))
    make_input(name, number) = FormulaFormula(name, parse_math(number))
    sheet = FormulaEnvironment([
        make_input("principal", "250000"),
        make_input("rate", "0.04"),
        make_input("years", "25"),
        make_formula("months", "12 * years"),
        make_formula("monthly_rate", "rate / 12"),
        make_formula("payment", "principal * monthly_rate / (1 - (1 + monthly_rate)^(-months))"),
        make_formula("total", "payment * months"),
        make_formula("interest", "total - principal"),
    ])
    evaluate_operation(nothing, ComputeFormulasOperation(sheet))
    page = MarkdownRoot([
        MarkdownHeading(1, [MarkdownText("Loan repayment")]),
        MarkdownParagraph([
            MarkdownText("A loan at a fixed rate is repaid in equal monthly payments. The sheet below computes the payment from the "),
            MarkdownStrong([MarkdownText("principal")]),
            MarkdownText(", the yearly "),
            MarkdownStrong([MarkdownText("rate")]),
            MarkdownText(" and the term in "),
            MarkdownStrong([MarkdownText("years")]),
            MarkdownText("."),
        ]),
        sheet,
        MarkdownParagraph([
            MarkdownText("Change a value and press Enter: each formula that reads it computes again."),
        ]),
        MarkdownHeading(2, [MarkdownText("How it computes")]),
        MarkdownList(false, [
            MarkdownListItem([MarkdownParagraph([
                MarkdownCode("payment"),
                MarkdownText(" is the annuity formula: the principal times the monthly rate, divided by one less the discount of the whole term."),
            ])]),
            MarkdownListItem([MarkdownParagraph([
                MarkdownCode("interest"),
                MarkdownText(" is what the loan costs: all the payments less the principal."),
            ])]),
        ]),
    ])
    # The page opens with the first formula of the sheet selected.
    set_selection!(page, @reference(page, elements[3].formulas[1]))
end
