# Fragment of `ResearchModule` — a study as a folder: the study in `study.pred`,
# which owns every item and every document that an item reaches; the report in
# `study.md`; each node of a format with a file of its own, such as a Markdown
# statement, a math prediction or a JSON data set, in a file of that format, named
# by the id of its item and its field; and each other block of the report in a
# `.pred` file of its own. The save cuts the graph into the files, and the load
# splices it back.

"The file that holds the study itself."
const RESEARCH_STUDY_FILE_NAME = "study.pred"

"The file that holds the report of a study."
const RESEARCH_REPORT_FILE_NAME = "study.md"

"""
    collect_study_blocks(study) -> Vector{Pair{String, Any}}

Every document of `study` that a file of its own writes, each once, with the
name of its file: a node of a format, such as a Markdown paragraph, a math
expression or a JSON object, that a field of an item holds at any depth, as
`"h1-statement-1.md" => paragraph`; a file document, such as a NED or INI file,
under its own name; and a block of the report that no item reaches and that is
neither Markdown nor an item, such as a table, in a `.pred` file, as
`"report-3.pred" => table`. The report itself is not among them: it has a file of
its own name, and it writes the blocks of its own format.
"""
function collect_study_blocks(study::ResearchStudy)
    blocks = Pair{String, Any}[]
    # The walk enters only what the file of the study writes as a node: the code of
    # a formula, for one, is written as its text.
    file = PredFile(RESEARCH_STUDY_FILE_NAME, study)
    seen = IdDict{Any, Bool}(study => true)
    study.report === nothing || (seen[study.report] = true)
    function add!(stem, value)
        if is_element_collection(value) || value isa AbstractVector
            for element in value
                add!(stem, element)
            end
            return
        end
        value isa Document || return
        haskey(seen, value) && return
        seen[value] = true
        value isa ResearchItem && return
        if is_file_document(value)
            push!(blocks, get_filename(value) => value)
            return
        end
        extension = find_file_extension(value)
        if extension !== nothing
            count = length(blocks) + 1
            push!(blocks, stem * "-" * string(count) * extension => value)
            return
        end
        for name in fieldnames(typeof(value))
            (is_view_state_field(name) || !is_written_in_file(file, value, name)) && continue
            raw = getfield(value, name)
            add!(stem, raw isa AbstractCell ? raw[] : raw)
        end
    end
    for item in collect_study_items(study)
        for name in fieldnames(typeof(item))
            is_view_state_field(name) && continue
            raw = getfield(item, name)
            add!(lowercase(item.id) * "-" * string(name), raw isa AbstractCell ? raw[] : raw)
        end
    end
    if study.report isa MarkdownRoot
        for (index, element) in enumerate(study.report.elements)
            if is_file_document(element)
                add!("report", element)
            elseif element isa Document && !haskey(seen, element) && !(element isa ResearchItem) &&
                   find_file_extension(element) === nothing
                seen[element] = true
                push!(blocks, "report-" * string(index) * ".pred" => element)
            end
        end
    end
    blocks
end

# The file of a block: a file document is one already. A node of a format goes
# into a file of that format; a Markdown block that is not a page goes into a
# page of its own, so the load gives back the block and not a page.
function _make_block_file(name::AbstractString, block)
    is_file_document(block) && return block
    endswith(name, ".pred") && return PredFile(name, block)
    block isa MarkdownDocument && !(block isa MarkdownRoot) &&
        return MarkdownFile(name, MarkdownRoot(elements = Any[block]))
    get_file_document_type(name)(name, block)
end

"""
    save_study_folder!(study, directory) -> String

Write `study` as a folder: the study as `study.pred`, which owns every item and
every document that an item reaches; the report as `study.md`; and each block of
`collect_study_blocks` in a file of its format. A document that the study
holds at two places, such as an item that a link and a list hold, is written once,
and each other place holds a marker. Nothing is written unless every file can be
cut and printed; two blocks with one file name are refused. Answer the folder.

Use it to keep a study as files beside the project that it studies.

# Example

    save_study_folder!(study_1, "buffer-study")

See also `load_study_folder`.
"""
function save_study_folder! end

function save_study_folder!(study, directory::AbstractString)
    document = get_document(study)
    files = Any[PredFile(RESEARCH_STUDY_FILE_NAME, document)]
    document.report isa MarkdownRoot && push!(files, MarkdownFile(RESEARCH_REPORT_FILE_NAME, document.report))
    for (name, block) in collect_study_blocks(document)
        push!(files, _make_block_file(name, block))
    end
    names = String[get_filename(file) for file in files]
    duplicate = findfirst(name -> count(==(name), names) > 1, names)
    duplicate === nothing ||
        throw(ArgumentError("Two files of the study have the name " * repr(names[duplicate]) *
                            "; give one of them another name."))
    save_project!(FileProject(String(directory), files)) ||
        error("save_study_folder!: the study could not be cut into files; the log says why.")
    String(directory)
end

"""
    load_study_folder(directory) -> ResearchStudy

Read a folder that `save_study_folder!` wrote. The load follows what `study.pred`
names, so every link holds the same item again.

Use it to open a study that a folder keeps.

# Example

    study_1 = load_study_folder("buffer-study")

See also `save_study_folder!`.
"""
function load_study_folder end

function load_study_folder(directory::AbstractString)
    project = load_project(String(directory), [RESEARCH_STUDY_FILE_NAME]; follow = true, tolerant = true)
    study = get_file_content(project.files[1])
    study isa ResearchStudy ||
        throw(ArgumentError(joinpath(directory, RESEARCH_STUDY_FILE_NAME) * " holds a " *
                            string(nameof(typeof(study))) * " and not a study."))
    study
end
