# Every text run of a printed syntax tree, in the order of the tree.
function _collect_text_runs!(runs, node)
    node isa TextString && (push!(runs, node); return runs)
    node isa Document || return runs
    for name in fieldnames(typeof(node))
        is_view_state_field(name) && continue
        value = getfield(node, name)[]
        if value isa CellVector
            foreach(element -> _collect_text_runs!(runs, element), value)
        else
            _collect_text_runs!(runs, value)
        end
    end
    runs
end

# The styles of the runs whose text is `text`, by color and weight: `:reference`
# for the reference style, `:plain` for the identifier style of Julia, and
# `:other` for any other, such as the name of a formula or a callee.
function _identifier_colors(output, text)
    rule = FormulaIdentifierToSyntaxLeaf()
    is_style(run, style) = is_color_equal(run.font_color, style.color) &&
                           run.font.weight == style.font.weight
    style(run) = is_style(run, rule.reference) ? :reference :
                 is_style(run, rule.style) ? :plain : :other
    [style(run) for run in _collect_text_runs!(Any[], output) if run.content == text]
end

# Each rectangle that a canvas draws, at its place: `(x, y, w, h)`.
function _collect_drawn_rects(canvas, ox = 0, oy = 0, found = NTuple{4,Int}[])
    x = ox + Int(canvas.x)
    y = oy + Int(canvas.y)
    for element in canvas.elements
        element = element isa Cell ? element[] : element
        if element isa GraphicsCanvas
            _collect_drawn_rects(element, x, y, found)
        elseif element isa GraphicsRect
            push!(found, (x + Int(element.x), y + Int(element.y), Int(element.w), Int(element.h)))
        end
    end
    found
end

function test_formula_to_syntax()

@testset "get_column_letter / cell_name boundaries" begin
    @test get_column_letter(1) == "A"
    @test get_column_letter(2) == "B"
    @test get_column_letter(26) == "Z"
    @test get_column_letter(27) == "AA"
    @test get_column_letter(28) == "AB"
    @test get_column_letter(52) == "AZ"
    @test get_column_letter(53) == "BA"
    @test get_column_letter(702) == "ZZ"
    @test get_column_letter(703) == "AAA"
    @test get_cell_name(1, 1) == "A1"
    @test get_cell_name(2, 1) == "B1"
    @test get_cell_name(27, 3) == "AA3"
end

@testset "an identifier that refers to a formula draws in the reference style" begin
    sheet = FormulaEnvironment([
        FormulaFormula("A", parse_julia("42")),
        FormulaFormula("x", parse_julia("1")),
        FormulaFormula("S", parse_julia("sum(x -> x * A, 1:3)")),
        FormulaFormula("E", parse_julia("A + Z")),
        FormulaFormula("F", parse_julia("y -> y^2")),
        FormulaFormula("G", parse_julia("F(3)")),
    ])
    output = print_document(RecursiveProjection(FormulaToSyntax()), sheet).output
    # The name of the formula `A` is a name, and its two uses are references.
    @test count(==(:reference), _identifier_colors(output, "A")) == 2
    # The `x` of the lambda is local, though the sheet has a formula `x`.
    @test !in(:reference, _identifier_colors(output, "x"))
    @test !in(:reference, _identifier_colors(output, "Z"))
    # A callee draws through the call rule of Julia, and keeps the callee style.
    @test !in(:reference, _identifier_colors(output, "F"))
    # A formula that the sheet gains makes its name a reference where it is used.
    push!(getfield(sheet, :formulas)[], Cell(FormulaFormula("Z", parse_julia("1"))))
    wire_result!(sheet.formulas[7], sheet)
    @test count(==(:reference), _identifier_colors(output, "Z")) == 1
end

@testset "Ctrl+click on a reference selects the name of its formula" begin
    platform = ProjecturedPlatformTest
    sheet = FormulaEnvironment([
        FormulaFormula("beta", parse_julia("alpha + gamma")),
        FormulaFormula("gamma", parse_julia("2"); display_mode = :code),
        FormulaFormula("alpha", parse_julia("1")),
    ])
    backend = HeadlessBackend()
    projection = make_formula_projection_example(; measure = FixedMeasure(8, 12, 4, 0))
    editor = build_editor(sheet, projection; backend, devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, tabs = false, appearance = false, settings = false)
    run_frame!(editor)
    answer(event) = read_intent(editor.projection, nothing, Intent(event), editor.iomap).operation
    # The first `alpha` and the first `gamma` that the sheet draws are the uses in `beta`.
    alpha = platform._nav_click(backend, "alpha")
    gamma = platform._nav_click(backend, "gamma")
    @test alpha !== nothing && gamma !== nothing
    # A plain click selects the identifier, to edit it.
    @test answer(alpha) isa ReplaceSelectionOperation
    @test !occursin("formulas[3]", repr(answer(alpha).path))
    # Ctrl+click selects the name of the formula, where its layout shows the name,
    # and the frame draws the selection over that name.
    platform._nav_press!(editor, backend, platform._nav_ctrl_click(alpha))
    @test repr(get_selection(sheet)) == repr(@reference(sheet, formulas[3].name))
    texts = platform._nav_texts(backend)
    (_, x, y) = texts[findlast(entry -> entry[1] == "alpha", texts)]
    @test (x, y, 5 * 8, 16) in _collect_drawn_rects(last(rendered_output(backend)))
    # A formula that shows only its code is selected as a whole.
    platform._nav_press!(editor, backend, platform._nav_ctrl_click(gamma))
    @test repr(get_selection(sheet)) == repr(@reference(sheet, formulas[2]))
end

@testset "a key in the name of a formula renames the formula and its uses" begin
    platform = ProjecturedPlatformTest
    sheet = FormulaEnvironment([
        FormulaFormula("A", parse_julia("42")),
        FormulaFormula("C", parse_julia("A + 1")),
        FormulaFormula("S", parse_julia("sum(x -> x * A, 1:3)")),
        FormulaFormula("B", parse_julia("2")),
    ])
    backend = HeadlessBackend()
    projection = make_formula_projection_example(; measure = FixedMeasure(8, 12, 4, 0))
    editor = build_editor(sheet, projection; backend, devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, tabs = false, appearance = false, settings = false,
                          undo = true)
    run_frame!(editor)
    names() = [formula.name for formula in sheet.formulas]
    uses() = [print_natural_text(sheet.formulas[2].code), print_natural_text(sheet.formulas[3].code)]
    set_selection!(sheet, @reference(sheet, formulas[1].name{1}))
    run_frame!(editor)
    platform._nav_press!(editor, backend, KeyPress('l'; time = 0.0))
    @test names() == ["Al", "C", "S", "B"]
    @test uses() == ["Al + 1", "sum(x -> x * Al, 1:3)"]
    @test get_formula_value(sheet.formulas[2]) == 43
    # One undo takes back the key: the name and every use.
    platform._nav_press!(editor, backend, KeyDown(:z, ModifierKeys(ctrl = true); time = 0.0))
    @test names() == ["A", "C", "S", "B"]
    @test uses() == ["A + 1", "sum(x -> x * A, 1:3)"]
    # A key that gives the name of another formula, or a name that a local name of
    # the code would take, does nothing.
    for key in ('B', 'x')
        set_selection!(sheet, @reference(sheet, formulas[1].name[1]))
        run_frame!(editor)
        platform._nav_press!(editor, backend, KeyPress(key; time = 0.0))
        @test names() == ["A", "C", "S", "B"]
        @test uses() == ["A + 1", "sum(x -> x * A, 1:3)"]
    end
    # A math use is a math node, which a rename does not write: the key does nothing.
    math = FormulaEnvironment([FormulaFormula("A", parse_julia("1")),
                               FormulaFormula("D", parse_math("A/2"))])
    math_backend = HeadlessBackend()
    math_editor = build_editor(math, projection; backend = math_backend,
                               devices = Device[Keyboard(), Mouse(), Display()],
                               window = false, tabs = false, appearance = false, settings = false)
    set_selection!(math, @reference(math, formulas[1].name{1}))
    run_frame!(math_editor)
    platform._nav_press!(math_editor, math_backend, KeyPress('l'; time = 0.0))
    @test math.formulas[1].name == "A"
    # The same key in the name of `D`, which no formula uses, renames it.
    set_selection!(math, @reference(math, formulas[2].name{1}))
    run_frame!(math_editor)
    platform._nav_press!(math_editor, math_backend, KeyPress('l'; time = 0.0))
    @test math.formulas[2].name == "Dl"
    # A name that reads as a number is its own key. A Delete that leaves the name
    # `1` of a cell name renames the formula, and its use keeps it.
    @test get_formula_key("1") == "1" && get_formula_key("A1") == "A1"
    cells = FormulaEnvironment([FormulaFormula("A1", parse_julia("4")),
                                FormulaFormula("B1", parse_julia("A1 * 2"))])
    cells_backend = HeadlessBackend()
    cells_editor = build_editor(cells, projection; backend = cells_backend,
                                devices = Device[Keyboard(), Mouse(), Display()],
                                window = false, tabs = false, appearance = false, settings = false)
    set_selection!(cells, @reference(cells, formulas[1].name{0}))
    run_frame!(cells_editor)
    platform._nav_press!(cells_editor, cells_backend, KeyDown(:delete, ModifierKeys(); time = 0.0))
    @test cells.formulas[1].name == "1"
    @test get_formula_dependencies(cells.formulas[2], cells) == [cells.formulas[1]]
end

@testset "math code prints in its linear form, and the keys walk past it" begin
    sheet = FormulaEnvironment([FormulaFormula("C", parse_julia("55")),
                                FormulaFormula("D", parse_math("C/2")),
                                FormulaFormula("H", parse_julia("2"))])
    _compute_formula_sheet!(sheet)
    rendered = render(print_document(RecursiveProjection(FormulaToSyntax()), sheet).output)
    @test occursin("D = C/2 ⇒ 27.5", rendered)
    walk = ProjecturedPlatformTest.explore_position_selections(sheet, make_formula_projection_example())
    @test walk.state_count > 0
    @test isempty(walk.errors)
end

@testset "FormulaFormula view modes (code / result / both)" begin
    f2s = RecursiveProjection(FormulaToSyntax())
    env = _compute_formula_sheet!(FormulaEnvironment([FormulaFormula("A1", parse_julia("2 + 3"))]))
    f = env.formulas[1]

    f.display_mode = :code
    @test render(print_document(f2s, f).output) == "2 + 3"

    f.display_mode = :result
    @test render(print_document(f2s, f).output) == "5"

    f.display_mode = :both
    both = render(print_document(f2s, f).output)
    @test occursin("A1", both)
    @test occursin("2 + 3", both)
    @test occursin("=", both)
    @test occursin("5", both)
end

@testset "evaluation: A2 = A1 + B1, reactive recompute" begin
    a1code = parse_julia("10")  # a JuliaInteger
    b1code = parse_julia("5")
    a1 = FormulaFormula("A1", a1code)
    b1 = FormulaFormula("B1", b1code)
    a2 = FormulaFormula("A2", parse_julia("A1 + B1"))
    env = FormulaEnvironment([a1, b1, a2])

    @test get_formula_value(a1) == 10
    @test get_formula_value(b1) == 5
    @test get_formula_value(a2) == 15

    # Editing A1 invalidates and recomputes A2 (reactive propagation through the
    # dependency's result cell).
    a1code.value = 100
    @test get_formula_value(a1) == 100
    @test get_formula_value(a2) == 105
end

@testset "cycle detection: would_create_cycle rejects A1 -> A2 -> A1" begin
    a1 = FormulaFormula("A1", JuliaInteger(1))
    a2 = FormulaFormula("A2", parse_julia("A1"))   # A2 -> A1
    env = FormulaEnvironment([a1, a2])

    @test get_formula_dependencies(a2, env) == FormulaFormula[a1]
    # Adding A1 -> A2 would close the cycle A1 -> A2 -> A1.
    @test would_create_cycle(env, a1, a2) == true
    # A self-reference is also a cycle.
    @test would_create_cycle(env, a1, a1) == true
    # An independent direction is fine.
    b1 = FormulaFormula("B1", JuliaInteger(7))
    env2 = FormulaEnvironment([a1, a2, b1])
    @test would_create_cycle(env2, a1, b1) == false
end

@testset "cycle safety net: evaluator returns an error result, no hang" begin
    # Force a genuine cycle past the static check by writing the names directly,
    # then assert the re-entry guard yields a marker rather than looping.
    a1 = FormulaFormula("A1", JuliaInteger(0))
    a2 = FormulaFormula("A2", JuliaInteger(0))
    a1.code = parse_julia("A2")   # A1 -> A2
    a2.code = parse_julia("A1")   # A2 -> A1  (cycle)
    env = FormulaEnvironment([a1, a2])
    @test get_formula_value(a1) == FormulaError("#CYCLE!")
end

@testset "FormulaEnvironment renders one formula per line" begin
    f2s = RecursiveProjection(FormulaToSyntax())
    env = FormulaEnvironment([
        FormulaFormula("A1", parse_julia("1"); display_mode=:result),
        FormulaFormula("B1", parse_julia("2"); display_mode=:result),
    ])
    _compute_formula_sheet!(env)
    rendered = render(print_document(f2s, env).output)
    @test occursin("1", rendered)
    @test occursin("2", rendered)
    @test occursin("\n", rendered)
end

@testset "compute_topological_order: dependencies before dependents" begin
    a1 = FormulaFormula("A1", JuliaInteger(1))
    a2 = FormulaFormula("A2", parse_julia("A1"))
    a3 = FormulaFormula("A3", parse_julia("A2"))
    env = FormulaEnvironment([a3, a2, a1])
    order = compute_topological_order(env)
    @test findfirst(==(a1), order) < findfirst(==(a2), order)
    @test findfirst(==(a2), order) < findfirst(==(a3), order)
end

@testset "a write of the code starts the edit mode, and it writes the draft" begin
    sheet = _compute_formula_sheet!(FormulaEnvironment([FormulaFormula("A", parse_julia("12")),
                                                        FormulaFormula("AB", parse_julia("5")),
                                                        FormulaFormula("C", parse_julia("A + 1"))]))
    C = sheet.formulas[3]
    write = ReplaceReferencedValueOperation(nothing, @reference(sheet, formulas[3].code.left), parse_julia("AB"))
    answer = ProjecturedFormula.FormulaModule._read_formula_edit(sheet, Intent(nothing, write))
    evaluate_operation(_FormulaMockEditor(sheet), answer.operation)
    @test C.draft !== nothing && print_natural_text(C.draft) == "AB + 1"
    @test print_natural_text(C.code) == "A + 1" && get_formula_result(C) == 13
    render_shown = render(print_document(RecursiveProjection(FormulaToSyntax()), C).output)
    @test occursin("AB + 1", render_shown) && !occursin("13", render_shown)
    # A move of the selection alone starts nothing.
    select = ReplaceSelectionOperation(@reference(sheet, formulas[1].code))
    @test ProjecturedFormula.FormulaModule._read_formula_edit(sheet, Intent(nothing, select)).operation === select
end

@testset "in edit mode, Enter commits, an undo takes back the commit, and Escape drops the draft" begin
    sheet = _compute_formula_sheet!(FormulaEnvironment([FormulaFormula("A", parse_julia("12")),
                                                        FormulaFormula("AB", parse_julia("5")),
                                                        FormulaFormula("C", parse_julia("A + 1"))]))
    C = sheet.formulas[3]
    backend = HeadlessBackend()
    projection = make_formula_projection_example(; measure = FixedMeasure(8, 12, 4, 0))
    editor = build_editor(sheet, projection; backend, devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, tabs = false, appearance = false, settings = false,
                          undo = true)
    run_frame!(editor)
    press!(event) = ProjecturedPlatformTest._nav_press!(editor, backend, event)
    shown() = render(print_document(RecursiveProjection(FormulaToSyntax()), C).output)
    evaluate_operation(editor, BeginFormulaEditOperation(C; draft = parse_julia("AB + 1")))
    set_selection!(sheet, @reference(sheet, formulas[3].draft))
    run_frame!(editor)
    # Enter commits: the code takes the draft, and the formula computes again.
    press!(KeyPress('\n'; time = 0.0))
    @test C.draft === nothing && print_natural_text(C.code) == "AB + 1"
    @test get_formula_result(C) == 6 && occursin("6", shown())
    # One undo takes back the commit: the old code and the old value together, and
    # the draft is back.
    press!(KeyDown(:z, ModifierKeys(ctrl = true); time = 0.0))
    @test print_natural_text(C.code) == "A + 1" && get_formula_result(C) == 13
    @test C.draft !== nothing && print_natural_text(C.draft) == "AB + 1"
    # Escape drops the draft, and the formula shows its code and its value again.
    set_selection!(sheet, @reference(sheet, formulas[3].draft))
    run_frame!(editor)
    press!(KeyDown(:escape, ModifierKeys(); time = 0.0))
    @test C.draft === nothing && print_natural_text(C.code) == "A + 1" && occursin("13", shown())
end

end # test_formula_to_syntax
