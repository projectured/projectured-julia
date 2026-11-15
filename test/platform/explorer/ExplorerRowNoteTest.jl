# The rows of the explorer say what they hold: each decoration gives a note that
# is made when the pointer rests, from the values the document stores, and reads
# no disk. A file is known by its path, a folder by its entries, a task by its
# execution.

_row_note_fact_names(made) = String[first(fact) for fact in made.facts if fact isa Pair]

# The note that a row of `document` shows at the dwell.
function _row_note_make(document)
    note = make_decoration_note(get_document_decoration(document))
    note isa Function || return note
    note()
end

function test_explorer_row_notes()
    @testset "the rows of the explorer say what they hold" begin
        @testset "a decoration gives a note that is made at the dwell" begin
            note = make_decoration_note(get_document_decoration(FileSystemFile("/no/such/folder/a.json")))
            @test note isa Function
            @test note() isa TooltipNote
        end

        @testset "a file says its path and its format, and reads no disk" begin
            made = _row_note_make(FileSystemFile("/no/such/folder/a.json"))
            @test made.title == "a.json"
            @test _row_note_fact_names(made) == ["Path", "Format"]
            @test made.facts[2] == ("Format" => "JSON")
        end

        @testset "a folder says its path and that it is not read yet" begin
            unread = FileSystemDirectory("/no/such/folder", FileSystemDocument[])
            unread.state = :unread
            made = _row_note_make(unread)
            @test made.title == "folder"
            @test _row_note_fact_names(made) == ["Path"]
            @test made.text == "Not read yet."
            read = _row_note_make(FileSystemDirectory("/no/such/folder",
                                                      FileSystemDocument[FileSystemFile("/no/such/folder/a.txt")]))
            @test _row_note_fact_names(read) == ["Path", "Entries"]
            @test read.facts[2] == ("Entries" => "1")
        end

        @testset "a section says its entries and the keys that rename it and add an entry" begin
            made = _row_note_make(ExplorerSection("Tools", Any[ExplorerSection("Inner", Any[])]))
            @test made.title == "Tools"
            @test _row_note_fact_names(made) == ["Entries"]
            @test made.facts[1] == ("Entries" => "1")
            @test !isempty(made.keys)
        end

        @testset "a task says its state" begin
            made = _row_note_make(TaskDocument(_TaskGroupProbeTask("echo", "exit 0")))
            @test made.title == format_task_parameters(_TaskGroupProbeTask("echo", "exit 0"))
            @test _row_note_fact_names(made) == ["State"]
            done = _row_note_make(TaskDocument(_TaskGroupProbeTask("echo", "exit 0"); status = :done))
            @test first(_row_note_fact_names(done)) == "State"
            @test done.facts[1] == ("State" => "done")
        end

        @testset "a search says what it looks for and what it found" begin
            content = ExplorerSection("Explorer", Any[ExplorerSection("x one", Any[])])
            made = _row_note_make(ExplorerSearch(content, Any[], "x"))
            @test made.title == "Search"
            @test occursin("\"x\"", made.text)
            @test _row_note_fact_names(made)[1:5] == ["Matches", "Waiting", "Depth", "Limit", "Started"]
        end

        @testset "a process says its whole command as code" begin
            command = "sleep " * "100 "^30
            process = SystemProcess(7, 1, command, "/tmp", :sleeping, 1.0e9, nothing, 1024, 2, CellVector(), 0, nothing)
            made = _row_note_make(process)
            @test made.code == command
            @test _row_note_fact_names(made) == ["Process id", "Folder", "State", "Threads", "Started"]
        end

        @testset "a log says what it keeps" begin
            made = _row_note_make(MessageLog())
            @test made.title == "Log"
            @test _row_note_fact_names(made) == ["Kept", "Capacity", "Recorded", "Errors", "Warnings"]
            gestures = _row_note_make(GestureLog())
            @test _row_note_fact_names(gestures) == ["Kept", "Capacity", "Recorded"]
        end

        @testset "a dashboard says its cards and a card says the note of its content" begin
            card = DashboardCard("Tools", ExplorerSection("Inner", Any[]))
            dashboard = _row_note_make(Dashboard("Study", Any[card]))
            @test dashboard.title == "Study"
            @test _row_note_fact_names(dashboard) == ["Cards"]
            made = _row_note_make(card)
            @test made.title == "Tools"
            @test _row_note_fact_names(made) == ["Entries"]
        end
    end
end
