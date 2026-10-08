function test_filesystem_to_syntax()
@testset "FileSystemToSyntax markers" begin

# A small in-memory tree: /root with two files and one non-empty subdir.
sub = FileSystemDirectory("/root/sub", FileSystemDocument[FileSystemFile("/root/sub/c.txt")])
dir = FileSystemDirectory("/root",
    FileSystemDocument[FileSystemFile("/root/a.txt"), FileSystemFile("/root/b.txt"), sub])

fs2s   = RecursiveProjection(FileSystemToSyntax())
syntax = print_document(fs2s, dir).output      # outer directory header node

# ── is_filesystem_marker_eligible discriminates header vs. body wrapper ──────
@test is_filesystem_marker_eligible(syntax) == true          # non-empty directory header
body = syntax.children[2]
@test is_filesystem_marker_eligible(body) == false           # indented body wrapper

empty_syntax = print_document(fs2s, FileSystemDirectory("/root/empty", FileSystemDocument[])).output
@test is_filesystem_marker_eligible(empty_syntax) == false   # nothing to fold

# ── Integrated render: one marker per non-empty directory, none on files ──
s2t = RecursiveProjection(SyntaxToText(
    expanded_marker  = TextString("▾", StyleFont("DejaVu Sans Mono", 20), color_default),
    collapsed_marker = TextString("▸", StyleFont("DejaVu Sans Mono", 20), color_default),
    marker_eligible  = is_filesystem_marker_eligible))
rendered = get_flat_string(print_document(s2t, syntax).output)

@test count("▾", rendered) == 2          # /root and /root/sub, not the body wrappers
@test occursin("▾ root", rendered)
@test occursin("▾ sub", rendered)
@test !occursin("▾ a.txt", rendered)     # files carry no marker
@test !occursin("▾ b.txt", rendered)
@test !occursin("▾ c.txt", rendered)

# Default SyntaxToText (no markers) leaves the filesystem render untouched.
plain = get_flat_string(print_document(RecursiveProjection(SyntaxToText()), syntax).output)
@test !occursin("▾", plain)
@test !occursin("▸", plain)

end # @testset "FileSystemToSyntax markers"
end # test_filesystem_to_syntax
