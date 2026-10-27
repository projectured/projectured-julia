# The evaluation of a formula by name: the value is any value, the scope binds
# its names last, and an error or a cycle is a value that a dependent gives on.

_formula_sheet(pairs...) =
    FormulaEnvironment([FormulaFormula(name, parse_julia(code)) for (name, code) in pairs])

# Compute the stored values of a sheet at once, as a script with no editor does; a
# view shows only stored values.
_compute_formula_sheet!(sheet) = (evaluate_operation(nothing, ComputeFormulasOperation(sheet)); sheet)

# An editor that a path operation writes into: it holds the document only.
struct _FormulaMockEditor
    document::Any
end

function test_formula_evaluation()
@testset "the evaluation of a formula by name" begin

    @testset "a value can be any value" begin
        sheet = _formula_sheet("A" => "42", "V" => "[1, 2, 3]", "W" => "V .* A")
        A, V, W = sheet.formulas
        @test get_formula_value(V) == [1, 2, 3]
        @test get_formula_value(W) == [42, 84, 126]
        A.code = parse_julia("2")
        @test get_formula_value(W) == [2, 4, 6]
    end

    @testset "a formula can hold a function, and a call of it is a dependency" begin
        sheet = _formula_sheet("F" => "x -> x^2", "G" => "F(3)")
        F, G = sheet.formulas
        @test get_formula_value(F) isa Function
        @test get_formula_value(G) == 9
        F.code = parse_julia("x -> x + 1")
        @test get_formula_value(G) == 4
    end

    @testset "a formula with a parameter in its name is a function" begin
        sheet = FormulaEnvironment([
            FormulaFormula("T", parse_julia("2")),
            FormulaFormula("S_{pure}(G)", parse_math("G exp(-2G)")),
            FormulaFormula("S_{peak}", parse_math("S_{pure}(0.5)")),
            FormulaFormula("ρ", parse_julia("0.8")),
            FormulaFormula("B", parse_math("ρ(1 - ρ)")),
            FormulaFormula("f", parse_julia("3")),
            FormulaFormula("g", parse_math("f(2)")),
            FormulaFormula("G", parse_julia("100")),
            FormulaFormula("H(u)", parse_math("u T")),
            FormulaFormula("K", parse_math("H(5)")),
        ])
        T, S_pure, S_peak, rho, B, f, g, G, H, K = sheet.formulas
        @test get_formula_value(S_pure) isa Function
        @test Base.invokelatest(get_formula_value(S_pure), 0.5) ≈ 0.5 * exp(-1)
        @test get_formula_value(S_peak) ≈ 0.5 * exp(-1)
        order = ProjecturedFormula.FormulaModule._order_formulas(sheet, [S_peak, S_pure])
        @test findfirst(==(S_pure), order) < findfirst(==(S_peak), order)
        @test get_formula_value(B) ≈ 0.16
        @test get_formula_value(g) == 6
        f.name = "f(x)"; f.code = parse_julia("x^2")
        @test get_formula_value(g) == 4
        # A formula named like the parameter changes nothing.
        @test Base.invokelatest(get_formula_value(S_pure), 0.5) ≈ 0.5 * exp(-1)
        # A new value of an input computes the function and its caller again.
        @test get_formula_value(K) == 10
        T.code = parse_julia("3")
        @test get_formula_value(K) == 15
    end

    @testset "a function formula is callable, in code and in a computation" begin
        sheet = FormulaEnvironment([
            FormulaFormula("S_{pure}(G)", parse_math("G e^{-2G}")),
            FormulaFormula("A", parse_julia("5")),
            FormulaFormula("E", parse_julia("1 + Z")),
        ])
        S_pure, A, E = sheet.formulas
        # In code, with no loop and no stored value, the call computes the formula.
        @test S_pure(0.5) ≈ 0.5 * exp(-1)
        @test_throws ArgumentError A(1)
        @test_throws ErrorException E(1)
        @test startswith(try E(1) catch e sprint(showerror, e) end, "#ERROR!")
        # A referenced formula calls the formula it refers to.
        part = ReferencedDocument(S_pure, @reference(sheet, formulas[1]))
        @test part(0.5) ≈ 0.5 * exp(-1)
        @test get_formula_value(part) === get_formula_value(S_pure)
        # In a computation the call reads the stored value only.
        read_in_cell() = Cell(@computation(try S_pure(0.5) catch error sprint(showerror, error) end))
        @test read_in_cell()[] == "S_{pure}(G) has no value yet"
        _compute_formula_sheet!(sheet)
        cell = read_in_cell()
        @test cell[] ≈ 0.5 * exp(-1) && !is_cell_provisional(cell)
        S_pure.is_computing = true
        cell = read_in_cell()
        @test cell[] ≈ 0.5 * exp(-1) && is_cell_provisional(cell)
        S_pure.is_computing = false
        # A new stored value draws the cell again.
        cell = read_in_cell()
        @test cell[] ≈ 0.5 * exp(-1)
        S_pure.code = parse_math("2 G")
        _compute_formula_sheet!(sheet)
        @test cell[] == 1.0
    end

    @testset "e is Euler's number, and a formula named e wins" begin
        sheet = FormulaEnvironment([FormulaFormula("E1", parse_math("e^{1}"))])
        @test get_formula_value(sheet.formulas[1]) ≈ ℯ
        sheet = FormulaEnvironment([FormulaFormula("e", parse_julia("2")),
                                    FormulaFormula("E1", parse_math("e^{3}"))])
        @test get_formula_value(sheet.formulas[2]) == 8
    end

    @testset "a local name does not refer to the formula of that name" begin
        sheet = _formula_sheet("A" => "42", "x" => "1000", "S" => "sum(x -> x * A, 1:3)")
        @test get_formula_value(sheet.formulas[3]) == 252
    end

    @testset "the scope wins over a Julia global" begin
        sheet = _formula_sheet("pi" => "3", "C" => "pi * 2", "T" => "sqrt(16)")
        @test get_formula_value(sheet.formulas[2]) == 6
        @test get_formula_value(sheet.formulas[3]) == 4.0
    end

    @testset "a math formula refers to a Julia formula by the same name" begin
        sheet = FormulaEnvironment([FormulaFormula("C", parse_julia("55")),
                                    FormulaFormula("D", parse_math("C/2"))])
        @test get_formula_value(sheet.formulas[2]) == 27.5
    end

    @testset "an error is a value that a dependent gives on" begin
        sheet = _formula_sheet("A" => "42", "E" => "A + Z", "E2" => "E + 1")
        _, E, E2 = sheet.formulas
        @test get_formula_value(E) isa FormulaError
        @test startswith(get_formula_value(E).text, "#ERROR! UndefVarError")
        @test get_formula_value(E2) === get_formula_value(E)
        push!(getfield(sheet, :formulas)[], Cell(FormulaFormula("Z", parse_julia("1"))))
        wire_result!(sheet.formulas[4], sheet)
        @test get_formula_value(E) == 43
        @test get_formula_value(E2) == 44
    end

    @testset "a cycle shows in each formula of it, and ends when it is broken" begin
        sheet = _formula_sheet("H" => "2 * K", "K" => "H + 1", "A" => "A + 1")
        H, K, A = sheet.formulas
        @test get_formula_value(H) == FormulaError("#CYCLE!")
        @test get_formula_value(K) == FormulaError("#CYCLE!")
        @test get_formula_value(A) == FormulaError("#CYCLE!")
        K.code = parse_julia("5")
        @test get_formula_value(H) == 10
        @test get_formula_value(K) == 5
    end

    @testset "the view shows a value on one line" begin
        f2s = RecursiveProjection(FormulaToSyntax())
        sheet = _compute_formula_sheet!(_formula_sheet("V" => "[1, 2, 3]", "E" => "Z"))
        V, E = sheet.formulas
        V.display_mode = :result
        @test render(print_document(f2s, V).output) == "[1, 2, 3]"
        E.display_mode = :result
        @test !occursin('\n', render(print_document(f2s, E).output))
    end
end
end

# The stored value: a view shows it, a computation stores it with the key of the
# code that it came from, and a value for code that changed meanwhile is dropped.
function test_formula_stored_value()
@testset "the stored value of a formula" begin

    @testset "a view shows the stored value, which a computation stores" begin
        sheet = _formula_sheet("A" => "2", "B" => "A * 3")
        A, B = sheet.formulas
        @test get_formula_result(B) === nothing
        @test get_formula_value(B) == 6                     # code computes on its own task
        @test get_formula_result(B) === nothing             # and stores nothing
        _compute_formula_sheet!(sheet)
        @test get_formula_result(A) == 2 && get_formula_result(B) == 6
        @test B.result_key == compute_formula_key(B, sheet)
        @test !A.is_computing && !B.is_computing
    end

    @testset "a new value computes the formulas that name it, and an equal value does not" begin
        sheet = _compute_formula_sheet!(_formula_sheet("A" => "2", "B" => "A * 3", "C" => "B + 1"))
        A, B, C = sheet.formulas
        A.code = parse_julia("5")
        evaluate_operation(nothing, ComputeFormulasOperation(sheet, [A]))
        @test get_formula_result(B) == 15 && get_formula_result(C) == 16
        # New code with the same value leaves the formulas that name it.
        old_key = B.result_key
        A.code = parse_julia("4 + 1")
        evaluate_operation(nothing, ComputeFormulasOperation(sheet, [A]))
        @test get_formula_result(A) == 5 && B.result_key == old_key
    end

    @testset "a value for code that changed is dropped, and the formula computes again" begin
        sheet = _compute_formula_sheet!(_formula_sheet("A" => "2"))
        A = only(sheet.formulas)
        key = compute_formula_key(A, sheet)
        A.code = parse_julia("7")
        evaluate_operation(nothing, ReplaceFormulaResultOperation(A, sheet, 99, key))
        @test get_formula_result(A) == 7
    end

    @testset "a sheet that a tab opens computes its values" begin
        sheet = _formula_sheet("A" => "2", "B" => "A + 1")
        tree = PaneTree(PaneGroup(PaneTab[PaneTab("notes", PrimitiveString("x"))]))
        apply_pane_operation!(tree, make_pane_open_tab_operation(tree, first(get_pane_groups(tree)),
                                                                 PaneTab("sheet", sheet)))
        @test get_formula_result(sheet.formulas[2]) == 3
    end

    @testset "a cycle stores its error, and the computation ends" begin
        sheet = _compute_formula_sheet!(_formula_sheet("H" => "2 * K", "K" => "H + 1"))
        H, K = sheet.formulas
        @test get_formula_result(H) == FormulaError("#CYCLE!") && get_formula_result(K) == FormulaError("#CYCLE!")
    end
end
end

# The formula task of an editor: while the loop runs, the code of a formula runs
# on a task of its own, and its value comes back through the door.
function test_formula_task()
@testset "the formula task of an editor" begin
    sheet = _formula_sheet("A" => "2", "T" => "(A, Base.current_task())")
    A, T = sheet.formulas
    editor = run_editor!(() -> Editor(sheet, RecursiveProjection(FormulaToSyntax());
                                      backend = HeadlessBackend(), devices = Device[]); wait = false)
    loop = editor.loop_task
    try
        run_on_editor_task!(() -> evaluate_operation(editor, ComputeFormulasOperation(sheet)), editor)
        read_stored() = run_on_editor_task!(() -> (get_formula_result(T), T.is_computing), editor)
        deadline = time() + 30
        while time() < deadline
            (value, computing) = read_stored()
            value !== nothing && !computing && break
            sleep(0.05)
        end
        (value, computing) = read_stored()
        @test !computing && value isa Tuple && value[1] == 2
        @test value[2] isa Task && value[2] !== loop
        @test run_on_editor_task!(() -> get_formula_result(A), editor) == 2
    finally
        post_operation!(editor, QuitEditorOperation())
        wait(loop)
    end
end
end

# The formula task waits for an editor that is busy longer than the time limit of
# a call, as with the first print of a large document, and the values still come
# back. The test waits past that limit, so it takes more than 30 seconds.
function test_formula_task_waits_for_a_busy_editor()
@testset "the formula task waits for a busy editor" begin
    sheet = _formula_sheet("A" => "(sleep(1.0); 2)", "B" => "A + 1")
    A, B = sheet.formulas
    editor = run_editor!(() -> Editor(sheet, RecursiveProjection(FormulaToSyntax());
                                      backend = HeadlessBackend(), devices = Device[]); wait = false)
    loop = editor.loop_task
    gate = Channel{Nothing}(1)
    try
        run_on_editor_task!(() -> evaluate_operation(editor, ComputeFormulasOperation(sheet)), editor)
        # A long unit holds the editor while the code of A runs, so the next call
        # of the formula task waits for it.
        run_on_editor_task!(() -> take!(gate), editor; wait = false)
        sleep(EDITOR_CALL_TIMEOUT_SECONDS + 2)
        put!(gate, nothing)
        read_stored() = run_on_editor_task!(() -> (get_formula_result(B), B.is_computing), editor)
        deadline = time() + 30
        while time() < deadline
            (value, computing) = read_stored()
            value !== nothing && !computing && break
            sleep(0.05)
        end
        @test read_stored() == (3, false)
        @test run_on_editor_task!(() -> get_formula_result(A), editor) == 2
    finally
        isready(gate) || put!(gate, nothing)
        post_operation!(editor, QuitEditorOperation())
        wait(loop)
    end
end
end
