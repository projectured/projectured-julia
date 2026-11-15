# The record of what a file of each format writes, for the plan
# `a-file-format-is-declared-once.md`, steps 1 and 5.
#
# For each input, two strings: the string that the write of a document by its path
# writes (`export_document` of what `import_document` read), and the string that
# `save_file!` writes for the file that `load_file` read. Each string goes to a file
# of its own, with the bytes as written:
#
#     <folder>/export/<input>    <folder>/save/<input>
#
# A call that raises writes `<input>.error` in place of `<input>`, with the first
# line of the message, and a save that writes no file writes `<input>.none`.
# `<folder>/index.tsv` lists each input with the size of each string, whether it
# ends with a line break, or the error.
#
# The inputs are the files of `REPOSITORY_INPUTS`, and each file in the folder
# `input` beside this script. When that folder does not exist, the script makes it
# first: the text of `make_workload_file` of each type that has one, and one file
# for each extension of the registry of file types that no other input has. Step 5
# runs with the folder that step 1 made, so it needs no registry.
#
# Run it from the root of the repository:
#
#     julia --project=environment/all plan/pending/a-file-format-record/record.jl [folder]
#
# The default folder is `record` beside this script. Step 5 writes into another
# folder and compares: `diff -r record <folder>`.

using ProjecturedAll
import ProjecturedLanguageServer

const HERE = @__DIR__
const ROOT = normpath(joinpath(HERE, "..", "..", ".."))
const INPUT = joinpath(HERE, "input")

# The data files of the repository, of each format that has one: the examples and
# the fixtures. The Julia files of the example packages are code, not data.
const REPOSITORY_INPUTS = [
    "example/domain/markdown/paragraphs.md",
    "example/platform/filesystem/fixture/project/README.md",
    "example/platform/filesystem/fixture/project/data/config.yaml",
    "example/platform/filesystem/fixture/project/data/sample.json",
    "example/platform/filesystem/fixture/project/doc/guide.md",
    "example/platform/filesystem/fixture/project/src/main.jl",
    "example/platform/filesystem/fixture/project/src/util.jl",
    "example/projectured/workspace/contact-list.json",
    "example/projectured/workspace/lorem-ipsum.txt",
    "test/domain/rst/fixture/rst/global.rst",
    "test/domain/rst/fixture/rst/showcase-manualconfiguration.rst",
    "test/domain/rst/fixture/rst/showcase-txop.rst",
    "test/domain/rst/fixture/rst/showcases-index.rst",
    "test/domain/rst/fixture/rst/users-guide-queueing.rst",
]

# The text of a made input for an extension whose file type has no workload text.
const SOURCE_TEXT = "int main(void) {\n    return 0;\n}\n"
const PICTURE = joinpath(ROOT, "asset", "image", "file.png")

# The read and the write of a document by its path. Step 5 removes
# `import_document` and `export_document`, and `read_document_file` and
# `write_document_file!` take their place.
read_by_path(path) =
    isdefined(Main, :import_document) ? import_document(path) : read_document_file(path)
write_by_path(document, path) =
    isdefined(Main, :export_document) ? export_document(document, path) :
                                        write_document_file!(document, path)

# Make the folder `input`: one folder for each made input, so two inputs of one
# name do not meet.
function make_inputs()
    for type in collect_workload_file_types()
        file = make_workload_file(type)
        folder = mkpath(joinpath(INPUT, "workload", string(nameof(type))))
        write(joinpath(folder, file.name), file.text)
    end
    covered = Set(lowercase(splitext(name)[2])
                  for name in vcat(REPOSITORY_INPUTS, collect_input_names()))
    registry = ProjecturedAll.SerializationModule._FILE_DOCUMENT_TYPES
    for extension in sort!(collect(keys(registry)))
        extension in covered && continue
        type = registry[extension]
        folder = mkpath(joinpath(INPUT, "extension", isempty(extension) ? "none" : extension[2:end]))
        path = joinpath(folder, "a" * extension)
        if hasmethod(make_workload_file, Tuple{Type{type}})
            write(path, make_workload_file(type).text)
        elseif type === ProjecturedAll.StyleModule.ImageFile
            cp(PICTURE, path)
        elseif type === ProjecturedLanguageServer.LanguageServerModule.SourceFile
            write(path, SOURCE_TEXT)
        else
            error("no input for the extension ", repr(extension), " of ", type)
        end
    end
end

# Each made input, as a path relative to the folder of this script, so its name
# stays the same when the plan moves.
collect_input_names() =
    isdir(INPUT) ? sort!([relpath(joinpath(folder, name), HERE)
                          for (folder, _, names) in walkdir(INPUT) for name in names]) :
                   String[]

# The file of an input: a made input is in the folder of this script, any other
# input in the repository.
get_input_path(input::AbstractString) =
    startswith(input, "input/") ? joinpath(HERE, input) : joinpath(ROOT, input)

# The first line of the message of `e`, with each path relative to where its
# input is, so the record does not name the folder of the repository.
first_line(e) = replace(first(split(sprint(showerror, e), "\n")),
                        rstrip(HERE, '/') * "/" => "", rstrip(ROOT, '/') * "/" => "")

describe_string(path) =
    isfile(path) ? (text = read(path, String);
                    string(ncodeunits(text), " bytes, ",
                           endswith(text, "\n") ? "ends with a line break" : "no line break at the end")) :
    isfile(path * ".none") ? "no file written" :
    "error: " * read(path * ".error", String)

# Write the two strings of one input, and answer its line of the index.
function record_input(input::AbstractString, folder::AbstractString)
    source = get_input_path(input)
    export_path = joinpath(mkpath(joinpath(folder, "export", dirname(input))), basename(input))
    save_folder = mkpath(joinpath(folder, "save", dirname(input)))
    save_path = joinpath(save_folder, basename(input))
    try
        write_by_path(read_by_path(source), export_path)
    catch e
        write(export_path * ".error", first_line(e))
    end
    try
        file = load_file(dirname(source), basename(input))
        save_file!(file, save_folder) || error("save_file! answered false")
        isfile(save_path) || write(save_path * ".none", "")
    catch e
        write(save_path * ".error", first_line(e))
    end
    join((input, describe_string(export_path), describe_string(save_path)), "\t")
end

function main(folder::AbstractString)
    isdir(INPUT) || make_inputs()
    isdir(folder) && error("the folder ", folder, " exists; give a new one")
    mkpath(folder)
    lines = [record_input(input, folder) for input in vcat(REPOSITORY_INPUTS, collect_input_names())]
    write(joinpath(folder, "index.tsv"), join(vcat("input\texport\tsave", lines), "\n") * "\n")
    println(length(lines), " inputs recorded in ", folder)
end

main(isempty(ARGS) ? joinpath(HERE, "record") : abspath(ARGS[1]))
