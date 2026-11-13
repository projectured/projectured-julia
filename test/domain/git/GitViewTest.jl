"""
    test_git_views()

The pages of the git documents in the window of a real editor with the headless
backend: the frames of the editor read git off the loop, and the test reads the
texts that the frame draws. The text domain draws the text of each page. A page of
a commit shows its header, its files, and each hunk and line of its diffs, with the
old and the new number of a line in its gutter; a page of a change shows its diff;
a file at a revision numbers its lines and marks the named line; a read that failed
shows the words of git; and a key in a text edits nothing.
"""
function test_git_views()
    @testset "git views" begin
        mktempdir() do folder
            repository = make_git_example_repository(joinpath(folder, "repository"))
            _git_view_commit_long_files!(repository)

            @testset "the page of a commit shows its header, its files, its hunks and its lines" begin
                editor, backend = _git_view_editor(GitCommit(repository, "v1"); height = 1400)
                texts() = first.(_git_view_texts(backend))
                @test _git_view_run_frames_until(editor, () -> "+LINE 19" in texts())
                @test "second subject continues here" in texts()
                @test "fd72243 · Ann Author <ann@example.org> · 2026-01-03T04:05:06-02:30" in texts()
                @test "Parent 73521a2" in texts()
                @test "Body line one." in texts()
                @test "6 changed files" in texts()
                @test "renamed      a.txt → b.txt  +2 −2" in texts()
                @test "@@ -16,5 +16,5 @@ line 15" in texts()
                # The old and the new number of a line stand in its gutter, on its row.
                @test _git_view_has_label(backend, "-line 19", "19   ")
                @test _git_view_has_label(backend, "+LINE 19", "   19")
                @test _git_view_has_label(backend, " line 20", "20 20")
                @test "@@ -1 +0,0 @@" in texts()
                @test _git_view_has_label(backend, "-bye", " 1   ")
                @test "A binary file: no lines to show." in texts()
                @test "No line changed: the mode of the file changed." in texts()
            end

            @testset "the page of a change shows its path, its facts and its diff" begin
                change = first(collect(wait_for_cell!(getfield(GitCommit(repository, "main"), :changes);
                                                      editor = nothing)))
                @test change.new_path == "long.txt"
                editor, backend = _git_view_editor(change)
                texts() = first.(_git_view_texts(backend))
                @test _git_view_run_frames_until(editor, () -> "+long 1" in texts())
                @test "long.txt" in texts()
                @test "added · +5000 −0 · 74beec4 → $(_format_git_view_hash(change.new_revision))" in texts()
                @test "@@ -0,0 +1,5000 @@" in texts()
                @test _git_view_has_label(backend, "+long 1", "        1")
            end

            @testset "a file at a revision numbers its lines and marks the named line" begin
                file = GitFileRevision(repository, "main", "long.txt"; line = 3000)
                editor, backend = _git_view_editor(file)
                texts() = first.(_git_view_texts(backend))
                @test _git_view_run_frames_until(editor, () -> "long 1" in texts())
                @test "long.txt at main" in texts()
                @test _git_view_has_label(backend, "long 1", "   1")
                lines = file.content.lines
                @test length(lines) == 5000
                @test [line.kind for line in lines[2999:3001]] == [:kept, :marked, :kept]
            end

            @testset "a key in a text edits nothing, and a click puts the caret" begin
                file = GitFileRevision(repository, "v1", "b.txt")
                editor, backend = _git_view_editor(file)
                @test _git_view_run_frames_until(editor, () -> "line 3" in first.(_git_view_texts(backend)))
                text = file.content.text
                (_, x, y) = only(entry for entry in _git_view_texts(backend) if first(entry) == "line 3")
                _git_view_press!(editor, backend, MouseClick(:left, x + 2, y + 2, 1, ModifierKeys(); time = 0.0))
                @test occursin("content", string(file.selection))
                # A key that moves the caret reaches the text and moves it.
                before = string(file.content.selection)
                _git_view_press!(editor, backend, KeyDown(:right, ModifierKeys(); time = 0.0))
                @test string(file.content.selection) != before
                _git_view_press!(editor, backend, KeyPress('x'; time = 0.0),
                                 KeyDown(:backspace, ModifierKeys(); time = 0.0), KeyPress('\n'; time = 0.0))
                @test file.content.text == text
                @test "line 3" in first.(_git_view_texts(backend))
            end

            @testset "the page of a range shows its commits in a table" begin
                editor, backend = _git_view_editor(GitCommitRange(repository, "v1"))
                texts() = first.(_git_view_texts(backend))
                @test _git_view_run_frames_until(editor, () -> "v1 · 2 commits" in texts())
                @test _git_view_run_frames_until(editor, () -> "fd72243" in texts())
                @test all(text -> text in texts(), ("hash", "subject", "author", "date"))
                @test all(text -> text in texts(), ("second subject continues here", "first",
                                                    "Ann Author <ann@example.org>", "2026-01-02 03:04:05", "73521a2"))
                # The cells of a row stand on one row of the table, from left to right.
                drawn = _git_view_texts(backend)
                place(text) = only((entry[2], entry[3]) for entry in drawn if first(entry) == text)
                (hash_x, hash_y) = place("fd72243")
                (subject_x, subject_y) = place("second subject continues here")
                @test abs(subject_y - hash_y) <= 4 && hash_x < subject_x
            end

            @testset "a read that failed shows the words of git" begin
                editor, backend = _git_view_editor(GitCommit(repository, "no-such-revision"))
                @test _git_view_run_frames_until(editor,
                    () -> "git: fatal: bad revision 'no-such-revision^{commit}'" in first.(_git_view_texts(backend)))
                @test "no-such-revision" in first.(_git_view_texts(backend))
            end
        end
    end
end

_format_git_view_hash(hash) = first(hash, 7)

# Whether the frame draws `label` in a gutter on the row of the text `text`.
function _git_view_has_label(backend, text, label)
    drawn = _git_view_texts(backend)
    rows = [entry[3] for entry in drawn if first(entry) == text]
    labels = [entry for entry in drawn if first(entry) == label]
    any(row -> any(entry -> abs(entry[3] - row) <= 4 && entry[2] < minimum(e[2] for e in drawn if first(e) == text),
                   labels), rows)
end

# Send `events` to the window of `editor` and run a frame.
_git_view_press!(editor, backend, events...) =
    (foreach(event -> push_event!(backend, WindowInput(:W, event)), events); run_frame!(editor))

# Add a commit to `repository` that adds a file of 5000 lines and a small file.
function _git_view_commit_long_files!(repository::String)
    write(joinpath(repository, "long.txt"), join(("long $n\n" for n in 1:5000)))
    write(joinpath(repository, "zz.txt"), "last\n")
    _git_view_commit!(repository, "long files", "2026-01-06T07:08:09+00:00")
    nothing
end

function _git_view_commit!(repository::String, message::String, date::String)
    for arguments in (["add", "-A"], ["commit", "-q", "-m", message])
        run(addenv(`git -C $repository $arguments`, "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1",
                   "GIT_AUTHOR_NAME" => "Ann Author", "GIT_AUTHOR_EMAIL" => "ann@example.org", "GIT_AUTHOR_DATE" => date,
                   "GIT_COMMITTER_NAME" => "Ann Author", "GIT_COMMITTER_EMAIL" => "ann@example.org",
                   "GIT_COMMITTER_DATE" => date))
    end
    nothing
end

# An editor of `document` in a window of the headless backend, so that its page has
# a size.
function _git_view_editor(document; height::Int = 600)
    backend = HeadlessBackend()
    editor = build_editor(document, NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0)); backend,
                          devices = Device[Keyboard(), Mouse(), Display()],
                          window = (; title = "W", width = 900, height), tabs = false, appearance = false,
                          settings = false)
    run_frame!(editor)
    (editor, backend)
end

# Run frames of `editor` until `done()` holds; the frames start the reads of git and
# write their answers.
function _git_view_run_frames_until(editor, done; seconds::Real = 30)
    deadline = time() + seconds
    while time() < deadline
        drain_operations!(editor)
        run_frame!(editor)
        done() && return true
        sleep(0.02)
    end
    false
end

# Each text of the last frame, with its place: (text, x, y).
function _git_view_texts(backend)
    frame = last(rendered_output(backend))
    _git_view_drawn(hasproperty(frame, :windows) ? frame.windows[1].content : frame, 0, 0, Tuple{String,Int,Int}[])
end

function _git_view_drawn(canvas, ox, oy, found)
    x = ox + Int(canvas.x)
    y = oy + Int(canvas.y)
    elements = canvas.elements
    if elements isa ListNode
        # A list builds a node when a walk first reads its link, so the walk follows
        # only the links that the layout read, from the head in both directions.
        for direction in (:next, :prev)
            node = elements
            direction === :prev && (node = _git_view_find_built_link(node, :prev))
            while node !== nothing
                _git_view_drawn_element(node.value, x, y, found)
                node = _git_view_find_built_link(node, direction)
            end
        end
    else
        for element in elements
            _git_view_drawn_element(element isa Cell ? element[] : element, x, y, found)
        end
    end
    found
end

# The neighbour of `node` on the side `direction` when the layout built it, else
# `nothing`.
function _git_view_find_built_link(node::ListNode, direction::Symbol)
    link = getfield(node, direction)
    link isa ReactiveCell && !is_cell_valid(link) && return nothing
    link[]
end

function _git_view_drawn_element(element, x, y, found)
    if element isa GraphicsText
        push!(found, (String(element.text), x + Int(element.x), y + Int(element.y)))
    elseif element isa GraphicsCanvas
        _git_view_drawn(element, x, y, found)
    elseif element isa GraphicsViewport
        _git_view_drawn(element.content, x + Int(element.x) + round(Int, element.transform.e),
                        y + Int(element.y) + round(Int, element.transform.f), found)
    end
    nothing
end
