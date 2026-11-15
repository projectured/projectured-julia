# A dwell on a part of a file in a tab, as the application opens the file: the
# part says nothing of its own, and the file says what the pointer is on, from the
# mouse target that the move before the dwell wrote into it.

function test_pointed_part()
@testset "a file says what the pointer is on" begin
    dir = mktempdir()
    path = joinpath(dir, "a.json")
    write(path, "{\"users\": [{\"name\": \"Alice\"}]}")
    document, scene, composed, iomap = _app_make_scene([path], dir; focus_file = true)
    editor = _app_make_editor(scene, composed, iomap)
    window() = get_iomap_output(editor.iomap).windows[1].content
    alice = first(place for place in _app_drawn_at(window()) if occursin("Alice", place[1]))
    (x, y) = (alice[2] + 2, alice[3] + 2)
    move = _app_fire(composed, editor.iomap, MouseMove(x, y; time = 1.0))
    move isa Operation && _app_apply!(editor, move)
    answer = _app_plain(_app_fire(composed, editor.iomap, MouseDwell(x, y; time = 2.0)))
    @test answer isa OpenTooltipOperation
    (title, note) = only(answer.layers)
    @test title == "a.json"
    @test note.facts == ["Path" => "users[1].name", "Type" => "String", "Length" => "5"]
end
end
