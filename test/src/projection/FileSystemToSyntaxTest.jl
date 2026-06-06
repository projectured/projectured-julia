function test_filesystem_to_syntax()
@testset "FileSystemToSyntax markers" begin

# A small in-memory tree: /root with two files and one non-empty subdir.
sub = FileSystemDirectory("/root/sub", FileSystemDocument[FileSystemFile("/root/sub/c.txt")])
dir = FileSystemDirectory("/root",
    FileSystemDocument[FileSystemFile("/root/a.txt"), FileSystemFile("/root/b.txt"), sub])

fs2s   = RecursiveProjection(FileSystemToSyntax())
syntax = projection_print(fs2s, dir).output      # outer directory header node

# ── filesystem_marker_eligible discriminates header vs. body wrapper ──────
@test filesystem_marker_eligible(syntax) == true          # non-empty directory header
body = syntax.children[2]
@test filesystem_marker_eligible(body) == false           # indented body wrapper

empty_syntax = projection_print(fs2s, FileSystemDirectory("/root/empty", FileSystemDocument[])).output
@test filesystem_marker_eligible(empty_syntax) == false   # nothing to fold

# ── Integrated render: one marker per non-empty directory, none on files ──
s2t = RecursiveProjection(SyntaxToText(
    expanded_marker  = TextString("▾", font_dejavu_monospace_regular_24, color_default),
    collapsed_marker = TextString("▸", font_dejavu_monospace_regular_24, color_default),
    marker_eligible  = filesystem_marker_eligible))
rendered = join(s.content for s in projection_print(s2t, syntax).output)

@test count("▾", rendered) == 2          # /root and /root/sub, not the body wrappers
@test occursin("▾ root", rendered)
@test occursin("▾ sub", rendered)
@test !occursin("▾ a.txt", rendered)     # files carry no marker
@test !occursin("▾ b.txt", rendered)
@test !occursin("▾ c.txt", rendered)

# Default SyntaxToText (no markers) leaves the filesystem render untouched.
plain = join(s.content for s in projection_print(RecursiveProjection(SyntaxToText()), syntax).output)
@test !occursin("▾", plain)
@test !occursin("▸", plain)

end # @testset "FileSystemToSyntax markers"
end # test_filesystem_to_syntax
