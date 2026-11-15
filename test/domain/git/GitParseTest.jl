"""
    test_git_parse()

The parse of the output of git, on fixed texts that git 2.53 wrote for a repository
of two commits, with no git process. The second commit renames a file with two
changed hunks, adds a binary file, deletes a file, changes a mode, changes a file
with a space and a letter outside ASCII in its name and no line end, and adds a
file whose name git quotes.
"""
function test_git_parse()
    log_text = "fd722438c537c96fe00dfb4d91a5517e8e266100\x0073521a28082f6c1bd1b6a4b02b109a6333cbe7a1\x00Ann Author\x00ann@example.org\x002026-01-03T04:05:06-02:30\x00second subject continues here\x00second subject\n" *
        "continues here\n" *
        "\n" *
        "Body line one.\n" *
        "Body line two.\n" *
        "\x0073521a28082f6c1bd1b6a4b02b109a6333cbe7a1\x00\x00Ann Author\x00ann@example.org\x002026-01-02T03:04:05+01:00\x00first\x00first\n" *
        "\x00"

    show_text = "fd722438c537c96fe00dfb4d91a5517e8e266100\x0073521a28082f6c1bd1b6a4b02b109a6333cbe7a1\x00Ann Author\x00ann@example.org\x002026-01-03T04:05:06-02:30\x00second subject continues here\x00second subject\n" *
        "continues here\n" *
        "\n" *
        "Body line one.\n" *
        "Body line two.\n" *
        "\x00\n" *
        ":100644 100644 c4352f8 8d8db28 R090\x00a.txt\x00b.txt\x00:000000 100644 0000000 8352675 A\x00bin.dat\x00:100644 000000 b023018 0000000 D\x00gone.txt\x00:100644 100755 fa11a6a fa11a6a M\x00mode.sh\x00:100644 100644 1b32298 6e94b48 M\x00sp ace é.txt\x00:000000 100644 0000000 bca70f3 A\x00ta\tb\"q.txt\x002\t2\t\x00a.txt\x00b.txt\x00-\t-\tbin.dat\x000\t1\tgone.txt\x000\t0\tmode.sh\x001\t1\tsp ace é.txt\x001\t0\tta\tb\"q.txt\x00"

    # The output of `git show --format= --patch -M` of the second commit.
    patch_text = "diff --git a/a.txt b/b.txt\n" *
        "similarity index 90%\n" *
        "rename from a.txt\n" *
        "rename to b.txt\n" *
        "index c4352f8..8d8db28 100644\n" *
        "--- a/a.txt\n" *
        "+++ b/b.txt\n" *
        "@@ -1,5 +1,5 @@\n" *
        " line 1\n" *
        "-line 2\n" *
        "+LINE 2\n" *
        " line 3\n" *
        " line 4\n" *
        " line 5\n" *
        "@@ -16,5 +16,5 @@ line 15\n" *
        " line 16\n" *
        " line 17\n" *
        " line 18\n" *
        "-line 19\n" *
        "+LINE 19\n" *
        " line 20\n" *
        "diff --git a/bin.dat b/bin.dat\n" *
        "new file mode 100644\n" *
        "index 0000000..8352675\n" *
        "Binary files /dev/null and b/bin.dat differ\n" *
        "diff --git a/gone.txt b/gone.txt\n" *
        "deleted file mode 100644\n" *
        "index b023018..0000000\n" *
        "--- a/gone.txt\n" *
        "+++ /dev/null\n" *
        "@@ -1 +0,0 @@\n" *
        "-bye\n" *
        "diff --git a/mode.sh b/mode.sh\n" *
        "old mode 100644\n" *
        "new mode 100755\n" *
        "diff --git a/sp ace é.txt b/sp ace é.txt\n" *
        "index 1b32298..6e94b48 100644\n" *
        "--- a/sp ace é.txt\t\n" *
        "+++ b/sp ace é.txt\t\n" *
        "@@ -1,2 +1,2 @@\n" *
        " x\n" *
        "-y\n" *
        "\\ No newline at end of file\n" *
        "+z\n" *
        "\\ No newline at end of file\n" *
        "diff --git \"a/ta\\tb\\\"q.txt\" \"b/ta\\tb\\\"q.txt\"\n" *
        "new file mode 100644\n" *
        "index 0000000..bca70f3\n" *
        "--- /dev/null\n" *
        "+++ \"b/ta\\tb\\\"q.txt\"\n" *
        "@@ -0,0 +1 @@\n" *
        "+q\n"

    # The output of `git diff` with no options after three changes in the worktree:
    # no commit header, and a name outside ASCII in quotes with octal escapes.
    diff_text = "diff --git a/b.txt b/b.txt\n" *
        "index 8d8db28..805de1b 100644\n" *
        "--- a/b.txt\n" *
        "+++ b/b.txt\n" *
        "@@ -7,7 +7,7 @@ line 6\n" *
        " line 7\n" *
        " line 8\n" *
        " line 9\n" *
        "-line 10\n" *
        "+LINE 10\n" *
        " line 11\n" *
        " line 12\n" *
        " line 13\n" *
        "diff --git a/mode.sh b/mode.sh\n" *
        "deleted file mode 100755\n" *
        "index fa11a6a..0000000\n" *
        "--- a/mode.sh\n" *
        "+++ /dev/null\n" *
        "@@ -1 +0,0 @@\n" *
        "-echo\n" *
        "diff --git \"a/sp ace \\303\\251.txt\" \"b/sp ace \\303\\251.txt\"\n" *
        "index 6e94b48..206b378 100644\n" *
        "--- \"a/sp ace \\303\\251.txt\"\t\n" *
        "+++ \"b/sp ace \\303\\251.txt\"\t\n" *
        "@@ -1,2 +1,2 @@\n" *
        " x\n" *
        "-z\n" *
        "\\ No newline at end of file\n" *
        "+z\n"

    second_hash = "fd722438c537c96fe00dfb4d91a5517e8e266100"
    first_hash = "73521a28082f6c1bd1b6a4b02b109a6333cbe7a1"
    quoted_name = "ta\tb\"q.txt"
    spaced_name = "sp ace é.txt"
    file_facts(file) = (file.kind, file.old_path, file.new_path, file.is_binary, length(file.hunks))
    hunk_facts(hunk) = (hunk.old_start, hunk.old_count, hunk.new_start, hunk.new_count, hunk.heading)
    line_facts(hunk) = [(line.kind, line.text, line.old_number, line.new_number, line.has_line_end)
                        for line in hunk.lines]

    @testset "git parse" begin
        @testset "a log gives the header of each commit" begin
            headers = parse_git_log_text(log_text)
            @test length(headers) == 2
            second, first = headers
            @test second.hash == second_hash
            @test second.parents == [first_hash]
            @test second.author_name == "Ann Author"
            @test second.author_email == "ann@example.org"
            @test second.author_date == "2026-01-03T04:05:06-02:30"
            @test second.subject == "second subject continues here"
            @test second.message == "second subject\ncontinues here\n\nBody line one.\nBody line two."
            @test first.hash == first_hash
            @test first.parents == String[]
            @test first.author_date == "2026-01-02T03:04:05+01:00"
            @test first.subject == "first"
            @test first.message == "first"
            @test isempty(parse_git_log_text(""))
            @test_throws ArgumentError parse_git_log_text("a\0b\0")
        end

        @testset "a commit gives its header and its changed files" begin
            commit = parse_git_commit_text(show_text)
            @test commit.header.hash == second_hash
            @test commit.header.parents == [first_hash]
            @test commit.header.message == "second subject\ncontinues here\n\nBody line one.\nBody line two."
            @test [(file.kind, file.old_path, file.new_path, file.added_count, file.removed_count, file.is_binary)
                   for file in commit.files] ==
                  [(:renamed, "a.txt", "b.txt", 2, 2, false),
                   (:added, nothing, "bin.dat", 0, 0, true),
                   (:deleted, "gone.txt", nothing, 0, 1, false),
                   (:modified, "mode.sh", "mode.sh", 0, 0, false),
                   (:modified, spaced_name, spaced_name, 1, 1, false),
                   (:added, nothing, quoted_name, 1, 0, false)]
        end

        @testset "the patch of a commit gives each file and each line number" begin
            files = parse_git_diff_text(patch_text)
            @test map(file_facts, files) ==
                  [(:renamed, "a.txt", "b.txt", false, 2),
                   (:added, nothing, "bin.dat", true, 0),
                   (:deleted, "gone.txt", nothing, false, 1),
                   (:modified, "mode.sh", "mode.sh", false, 0),
                   (:modified, spaced_name, spaced_name, false, 1),
                   (:added, nothing, quoted_name, false, 1)]
            renamed = files[1]
            @test hunk_facts(renamed.hunks[1]) == (1, 5, 1, 5, "")
            @test line_facts(renamed.hunks[1]) ==
                  [(:kept, "line 1", 1, 1, true), (:removed, "line 2", 2, nothing, true),
                   (:added, "LINE 2", nothing, 2, true), (:kept, "line 3", 3, 3, true),
                   (:kept, "line 4", 4, 4, true), (:kept, "line 5", 5, 5, true)]
            @test hunk_facts(renamed.hunks[2]) == (16, 5, 16, 5, "line 15")
            @test line_facts(renamed.hunks[2]) ==
                  [(:kept, "line 16", 16, 16, true), (:kept, "line 17", 17, 17, true),
                   (:kept, "line 18", 18, 18, true), (:removed, "line 19", 19, nothing, true),
                   (:added, "LINE 19", nothing, 19, true), (:kept, "line 20", 20, 20, true)]
            @test hunk_facts(files[3].hunks[1]) == (1, 1, 0, 0, "")
            @test line_facts(files[3].hunks[1]) == [(:removed, "bye", 1, nothing, true)]
            @test hunk_facts(files[5].hunks[1]) == (1, 2, 1, 2, "")
            @test line_facts(files[5].hunks[1]) ==
                  [(:kept, "x", 1, 1, true), (:removed, "y", 2, nothing, false), (:added, "z", nothing, 2, false)]
            @test hunk_facts(files[6].hunks[1]) == (0, 0, 1, 1, "")
            @test line_facts(files[6].hunks[1]) == [(:added, "q", nothing, 1, true)]
        end

        @testset "a patch of git diff with no commit header gives its three files" begin
            files = parse_git_diff_text(diff_text)
            @test map(file_facts, files) ==
                  [(:modified, "b.txt", "b.txt", false, 1),
                   (:deleted, "mode.sh", nothing, false, 1),
                   (:modified, spaced_name, spaced_name, false, 1)]
            @test hunk_facts(files[1].hunks[1]) == (7, 7, 7, 7, "line 6")
            @test line_facts(files[1].hunks[1])[4:5] ==
                  [(:removed, "line 10", 10, nothing, true), (:added, "LINE 10", nothing, 10, true)]
            @test line_facts(files[2].hunks[1]) == [(:removed, "echo", 1, nothing, true)]
            @test line_facts(files[3].hunks[1]) ==
                  [(:kept, "x", 1, 1, true), (:removed, "z", 2, nothing, false), (:added, "z", nothing, 2, true)]
            # A text before the first file, such as the header of a commit, is no part of a file.
            @test map(file_facts, parse_git_diff_text("commit $second_hash\nAuthor: Ann\n\n    subject\n\n" * diff_text)) ==
                  map(file_facts, files)
            @test isempty(parse_git_diff_text(""))
            @test_throws ArgumentError parse_git_diff_text("diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,2 +1,2 @@\n x\n")
        end
    end
end
