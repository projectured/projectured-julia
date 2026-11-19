# The walk of Alt with the arrow keys through the view of a file that shows the file
# through its views: the walk stays in the views, where the caret is, and it does not
# go into the file, the scroll pane of the view or the content of a view.

function test_file_view_walk()
@testset "Alt with the arrows walks the views of a file" begin
    dir = mktempdir()
    write(joinpath(dir, "a.json"), "{\"name\": \"Alice\", \"city\": \"Paris\"}")
    w = _ce_file_window(dir, "a.json")
    path() = string(strip_reference_types(get_selection(w.scene)))
    selected() = evaluate_reference(w.scene, get_selection(w.scene))
    part() = evaluate_reference(w.scene, find_content_path(w.scene, get_selection(w.scene)))

    @testset "Alt+Up goes out through the views to the view of the file" begin
        # Alt+double click on the text and Alt+Up: the string, through its view.
        _ce_select_whole!(w, ==("Alice"))
        @test selected() isa ContentView && part() isa JsonString
        stops = Any[selected()]
        for _ in 1:8
            selected() isa FileView && break
            _ce_key!(w, :up, _CE_ALT)
            push!(stops, selected())
        end
        @test selected() isa FileView && part() isa JsonFile
        # Each stop is a view, and each stop but the last is the view of one content.
        @test all(stop -> stop isa ContentView, stops[1:(end - 1)])
        @test !occursin(".viewed", path()) && !occursin(".file", path())
    end

    @testset "Alt+Down goes into what the view of the file shows" begin
        @test selected() isa FileView
        _ce_key!(w, :down, _CE_ALT)
        @test selected() isa ContentView
        @test !occursin(".file", path()) && !occursin(".scroll", path()) && !occursin(".viewed", path())
        # Each more Alt+Down goes on through the views, down to a text in a view. No
        # path leaves the views for the content of a view, for the file or for the
        # scroll pane.
        stops = Any[]
        for _ in 1:6
            _ce_key!(w, :down, _CE_ALT)
            push!(stops, selected())
            @test !occursin(".viewed", path()) && !occursin(".file", path()) && !occursin(".scroll", path())
        end
        @test all(stop -> stop isa Union{ContentView, AbstractString}, stops)
        @test count(stop -> stop isa ContentView, stops) >= 2
        @test part() isa Union{JsonDocument, AbstractString}
    end
end
end
