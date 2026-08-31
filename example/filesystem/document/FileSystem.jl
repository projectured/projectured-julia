"""
    filesystem_example_root() -> String

The fixture tree the file-system examples render: `example/fixture/project`, a
small directory of nested folders and a few file kinds.

A `FileSystemDocument` reads a **real path**, so an example of one has to name a
directory that exists. Pointing it at the package's own source directory made
the example change every time a file was added or removed — the rendered tree
grew and shrank with the repository, and four example suites changed their
assertion counts with it. A fixture is fixed.
"""
filesystem_example_root() = abspath(joinpath(@__DIR__, "..", "fixture", "project"))

make_filesystem_document_example(; root = filesystem_example_root()) =
    make_filesystem_pathname(root)

# Atomic file-system leaf — a single file, for the catalog. A synthetic pathname
# keeps the atom deterministic (independent of the on-disk tree); the leaf renders
# its basename (" notes.txt"). `FileSystemFile` is not exported by its module (only
# the abstract type + `make_filesystem_pathname` are), so it is named qualified.
make_filesystem_file_document_example() = FileSystemModule.FileSystemFile("/home/user/notes.txt")

# Minimal non-empty directory — one file child, for the catalog.
make_filesystem_directory_document_example() =
    FileSystemModule.FileSystemDirectory("/home/user", [FileSystemModule.FileSystemFile("/home/user/notes.txt")])
