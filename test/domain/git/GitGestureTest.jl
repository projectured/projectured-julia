"""
    test_git_gestures()

The gestures of the pages of the git domain in the window of an editor whose
document is a navigator on a commit: a Ctrl+click on a removed line of a diff visits
the file at the parent at its old line, and Back returns to the commit; a
Ctrl+Shift+click on an added line opens the file at the commit at its new line in a
new tab; a click on the path of a file in the table visits its change; and a
Ctrl+click moves no selection.
"""
function test_git_gestures()
    root_hash = "73521a28082f6c1bd1b6a4b02b109a6333cbe7a1"
    second_hash = "fd722438c537c96fe00dfb4d91a5517e8e266100"
    @testset "git gestures" begin
        mktempdir() do folder
            repository = make_git_example_repository(joinpath(folder, "repository"))

            @testset "Ctrl+click on a removed line visits the file at the parent, and Back returns" begin
                commit = GitCommit(repository, "v1")
                navigator = Navigator(commit)
                editor, backend = _git_view_editor(navigator; height = 1400)
                texts() = first.(_git_view_texts(backend))
                @test _git_view_run_frames_until(editor, () -> "-line 19" in texts())
                selection = string(commit.diff.selection)
                (x, y) = _git_gesture_place(backend, "-line 19")
                _git_view_press!(editor, backend, MouseClick(:left, x + 2, y + 2, 1, ModifierKeys(ctrl = true); time = 0.0))
                page = get_navigator_page(navigator)
                @test page isa GitFileRevision
                @test (page.repository, page.revision, page.path, page.line) == (repository, root_hash, "a.txt", 19)
                @test _git_view_run_frames_until(editor, () -> "a.txt at $root_hash" in texts())
                @test string(commit.diff.selection) == selection
                _git_view_press!(editor, backend, KeyDown(:left_bracket, ModifierKeys(ctrl = true); time = 0.0))
                @test get_navigator_page(navigator) === commit
            end

            @testset "Ctrl+Shift+click on an added line opens a new tab at the new line" begin
                commit = GitCommit(repository, "v1")
                editor, backend = _git_view_editor(Navigator(commit); height = 1400, tabs = true)
                texts() = first.(_git_view_texts(backend))
                @test _git_view_run_frames_until(editor, () -> "+LINE 19" in texts())
                (x, y) = _git_gesture_place(backend, "+LINE 19")
                _git_view_press!(editor, backend,
                                 MouseClick(:left, x + 2, y + 2, 1, ModifierKeys(ctrl = true, shift = true); time = 0.0))
                drain_operations!(editor)
                run_frame!(editor)
                tabs = _git_gesture_tabs(editor)
                @test length(tabs) == 2
                page = get_navigator_page(tabs[2].content)
                @test page isa GitFileRevision
                @test (page.revision, page.path, page.line) == (second_hash, "b.txt", 19)
            end

            @testset "a click on the path of a file in the table visits its change" begin
                commit = GitCommit(repository, "v1")
                navigator = Navigator(commit)
                editor, backend = _git_view_editor(navigator; height = 1400)
                texts() = first.(_git_view_texts(backend))
                @test _git_view_run_frames_until(editor, () -> "gone.txt" in texts() && "-bye" in texts())
                (x, y) = _git_gesture_place(backend, "gone.txt")
                _git_view_press!(editor, backend, MouseClick(:left, x + 2, y + 2, 1, ModifierKeys(); time = 0.0))
                @test get_navigator_page(navigator) === collect(commit.changes)[3]
            end
        end
    end
end

# The place of the text `text` that the frame draws highest on the page: a path
# stands in the table above the diffs too.
function _git_gesture_place(backend, text)
    found = [(entry[2], entry[3]) for entry in _git_view_texts(backend) if first(entry) == text]
    found[argmin(last.(found))]
end

# The tabs of the window of `editor`: the root of its pane tree, inside the screen,
# its first window, and the states of the gestures and of the drags of the window.
function _git_gesture_tabs(editor)
    document = editor.document
    while !hasproperty(document, :root)
        document = hasproperty(document, :windows) ? document.windows[1] : document.content
    end
    document.root.tabs
end
