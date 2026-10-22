# Fragment of `ResearchModule` — a study as a folder: the study in `study.pred`,
# the report in `study.md`, and each document that an item holds as its design,
# its method, its content or its prediction in a file of its own, named by the id
# of the item. The save cuts the graph into the files, and the load splices it
# back.

"The file that holds the study itself."
const RESEARCH_STUDY_FILE_NAME = "study.pred"

"The file that holds the report of a study."
const RESEARCH_REPORT_FILE_NAME = "study.md"

# Whether a document that an item holds takes a file of its own: a file document
# is one already, and a document that a `.pred` file writes takes a `.pred` file. A
# text does not: it stays in the file of the study.
_takes_research_file(document) =
    document isa FileDocument ||
    (is_pred_document(document) && !(document isa PrimitiveDocument) && !(document isa ResearchDocument))

"""
    collect_study_blocks(study) -> Vector{Pair{String, Any}}

Every document of `study` that takes a file of its own, each once, with the stem
of its file: the design, the method, the content and the prediction of each item,
as `"x1-design" => design`, and each block of the report that is not Markdown, as
`"report-2" => block`. A file document keeps its own name.
"""
function collect_study_blocks(study::ResearchStudy)
    blocks = Pair{String, Any}[]
    seen = IdDict{Any, Bool}()
    function add!(stem, document)
        document isa Document || return
        _takes_research_file(document) || return
        haskey(seen, document) && return
        seen[document] = true
        push!(blocks, stem => document)
    end
    for item in collect_study_items(study)
        for field in _RESEARCH_CONTENT_FIELDS
            hasfield(typeof(item), field) || continue
            add!(lowercase(item.id) * "-" * string(field), getproperty(item, field))
        end
    end
    report = study.report
    if report isa MarkdownRoot
        for (index, element) in enumerate(report.elements)
            element isa ResearchItem && continue
            add!("report-" * string(index), element)
        end
    end
    blocks
end

"""
    save_study_folder!(study, directory) -> String

Write `study` as a folder: each document of `collect_study_blocks` in a file of
its own, the report as `study.md`, and the study as `study.pred`, which names every
other file with a marker. A document that a file holds at two places, such as an
item that a link and a list hold, is written once. The save is atomic: nothing is
written unless every file can be cut and printed. Answer the folder.

Use it to keep a study as files beside the project that it studies.

# Example

    save_study_folder!(study_1, "buffer-study")

See also `load_study_folder`.
"""
function save_study_folder! end

function save_study_folder!(study, directory::AbstractString)
    document = get_document(study)
    files = Any[]
    for (stem, block) in collect_study_blocks(document)
        push!(files, block isa FileDocument ? block : PredFile(stem * ".pred", block))
    end
    document.report isa MarkdownRoot && push!(files, MarkdownFile(RESEARCH_REPORT_FILE_NAME, document.report))
    push!(files, PredFile(RESEARCH_STUDY_FILE_NAME, document))
    mkpath(directory)
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
