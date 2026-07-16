function make_filesystem_document_example(; root=abspath(joinpath(@__DIR__, "..")))
    make_filesystem_pathname(root)
end

# Atomic file-system leaf — a single file, for the catalog. A synthetic pathname
# keeps the atom deterministic (independent of the on-disk tree); the leaf renders
# its basename (" notes.txt"). `FileSystemFile` is not exported by its module (only
# the abstract type + `make_filesystem_pathname` are), so it is named qualified.
make_filesystem_file_document_example() = FileSystemModule.FileSystemFile("/home/user/notes.txt")

# Minimal non-empty directory — one file child, for the catalog.
make_filesystem_directory_document_example() =
    FileSystemModule.FileSystemDirectory("/home/user", [FileSystemModule.FileSystemFile("/home/user/notes.txt")])
