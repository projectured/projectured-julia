function test_tabular()
@testset "Tabular" begin

# ── Fixture helpers ───────────────────────────────────────────────────────

function make_row(name, age, city, email)
    TabularRow(CellVector([
        TabularCell(name), TabularCell(age), TabularCell(city), TabularCell(email),
    ]))
end

function make_person_grid()
    TabularGrid(CellVector([
        make_row("Alice", 30, "London", "alice@example.com"),
        make_row("Bob",   25, "Paris",  "bob@example.com"),
        make_row("Carol", 35, "Berlin", "carol@example.com"),
    ]), 4)
end

# ── T1: Construction and direct access ───────────────────────────────────

@testset "T1 construction and direct access" begin
    g = make_person_grid()
    @test length(g.rows) == 3
    @test g.col_count == 4
    @test tabular_cell(g, 1, 1).content == "Alice"
    @test tabular_cell(g, 2, 2).content == 25
    @test tabular_cell(g, 3, 3).content == "Berlin"
end

# ── T2: Column view integrity ─────────────────────────────────────────────

@testset "T2 column view integrity" begin
    g = make_person_grid()
    col = tabular_column(g, 1)
    @test length(col) == 3
    @test col[1].content == "Alice"
    @test col[2].content == "Bob"
    @test col[3].content == "Carol"
end

# ── T3: Reactive sharing via column view ──────────────────────────────────

@testset "T3 reactive sharing via column view" begin
    g = make_person_grid()
    col = tabular_column(g, 1)
    c = cell_at(col, 2)
    c[] = TabularCell("Bobby")
    @test tabular_cell(g, 2, 1).content == "Bobby"
end

# ── T4: Row insert ────────────────────────────────────────────────────────

@testset "T4 row insert" begin
    g = make_person_grid()
    insert_row!(g, 2, make_row("Dave", 28, "Rome", "dave@example.com"))
    @test length(g.rows) == 4
    @test tabular_cell(g, 1, 1).content == "Alice"
    @test tabular_cell(g, 2, 1).content == "Dave"
    @test tabular_cell(g, 3, 1).content == "Bob"
    @test tabular_cell(g, 4, 1).content == "Carol"
end

# ── T5: Column view reflects row insert ──────────────────────────────────

@testset "T5 column view reflects row insert" begin
    g = make_person_grid()
    insert_row!(g, 2, make_row("Dave", 28, "Rome", "dave@example.com"))
    col = tabular_column(g, 1)
    @test length(col) == 4
    @test col[1].content == "Alice"
    @test col[2].content == "Dave"
    @test col[3].content == "Bob"
    @test col[4].content == "Carol"
end

# ── T6: Row delete ────────────────────────────────────────────────────────

@testset "T6 row delete" begin
    g = make_person_grid()
    insert_row!(g, 2, make_row("Dave", 28, "Rome", "dave@example.com"))
    delete_row!(g, 2)
    @test length(g.rows) == 3
    @test tabular_cell(g, 1, 1).content == "Alice"
    @test tabular_cell(g, 2, 1).content == "Bob"
    @test tabular_cell(g, 3, 1).content == "Carol"
end

# ── T7: Column insert ─────────────────────────────────────────────────────

@testset "T7 column insert" begin
    g = make_person_grid()
    insert_column!(g, 4, [TabularCell("+44"), TabularCell("+33"), TabularCell("+49")])
    @test g.col_count == 5
    @test tabular_cell(g, 1, 4).content == "+44"
    @test tabular_cell(g, 2, 4).content == "+33"
    @test tabular_cell(g, 3, 4).content == "+49"
    @test tabular_cell(g, 1, 5).content == "alice@example.com"
    @test tabular_cell(g, 2, 5).content == "bob@example.com"
    @test tabular_cell(g, 3, 5).content == "carol@example.com"
end

# ── T8: Column delete ─────────────────────────────────────────────────────

@testset "T8 column delete" begin
    g = make_person_grid()
    insert_column!(g, 4, [TabularCell("+44"), TabularCell("+33"), TabularCell("+49")])
    delete_column!(g, 2)
    @test g.col_count == 4
    @test tabular_cell(g, 1, 1).content == "Alice"
    @test tabular_cell(g, 1, 2).content == "London"
    @test tabular_cell(g, 2, 2).content == "Paris"
    @test tabular_cell(g, 3, 2).content == "Berlin"
    @test tabular_cell(g, 1, 3).content == "+44"
    @test tabular_cell(g, 1, 4).content == "alice@example.com"
end

# ── T9: Nesting ───────────────────────────────────────────────────────────

@testset "T9 nesting" begin
    g = make_person_grid()
    inner = TabularGrid(CellVector([
        TabularRow(CellVector([TabularCell("x"), TabularCell("y")])),
    ]), 2)
    g.rows[1].cells[1].content = inner
    @test tabular_cell(g, 1, 1).content isa TabularGrid
    inner_grid = tabular_cell(g, 1, 1).content
    @test tabular_cell(inner_grid, 1, 1).content == "x"
    @test tabular_cell(inner_grid, 1, 2).content == "y"
end

end # @testset "Tabular"
end # test_tabular
