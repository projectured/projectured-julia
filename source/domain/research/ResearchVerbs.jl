# Fragment of `ResearchModule` — the verbs that the assistant calls on a study: a
# new study, an item of each kind, a decision, the check of the predictions, the
# report, the formula sheet, and the reads of a study.
#
# Each verb takes the study as a `ReferencedDocument`, or as the study itself,
# makes the operation of a builder of `ResearchEdits.jl` with the author
# `:assistant`, and lets the readers of the editor carry it from the study to the
# root, so the history of the tab that shows the study records it, as it records
# an edit of the person. A study that no view shows takes the operation directly.
# A verb that adds an item answers it as a part of the window, a
# `ReferencedDocument`, when it was given the study as one, and as the item
# itself otherwise; a link takes either.

"""
The names that the research domain offers to the model of an assistant: the
documents of a study, the verbs that write it as the assistant, and the reads of
a study.
"""
const RESEARCH_ASSISTANT_API = (
    :ResearchStudy, :ResearchQuestion, :ResearchSource, :ResearchHypothesis, :ResearchExperiment,
    :ResearchAnalysis, :ResearchResult, :ResearchEvidence, :ResearchDecision, :ResearchAnswer,
    :ResearchExpectation, :ResearchMap, :StudyItems,
    :start_study!, :add_question!, :add_source!, :add_hypothesis!, :add_experiment!, :add_analysis!,
    :add_result!, :add_evidence!, :add_answer!, :record_decision!, :check_predictions!,
    :add_study_section!, :add_study_prose!, :embed_in_study!, :add_study_formula!,
    :describe_study, :find_study_item, :save_study_folder!, :load_study_folder,
)

# `field` is the field of the study that the operation writes. The operation is
# read from the study up to the root, so the reference names a place inside the
# study: a study can be the whole content of a history, one step from the root.
function _evaluate_research_operation!(editor, study, field::Symbol, operation, description)
    if study isa ReferencedDocument && editor isa Editor && editor.iomap !== nothing
        reference = extend_reference(get_reference(study), FieldReferenceStep(String(field)))
        rooted = find_rooted_operation(editor, reference, relative -> operation; description)
        rooted === nothing || return evaluate_operation(editor, rooted)
    end
    evaluate_operation(editor, operation)
end

# Add a new item of `type` to `study` as the assistant, and answer it: as a
# `ReferencedDocument` when `study` is one, so the answer is a part of the window.
function _add_research_item!(study, type, editor, description; fields...)
    run_on_editor_task!(editor; description) do
        document = get_document(study)
        item = make_research_item(document, type; author = :assistant, fields...)
        _evaluate_research_operation!(editor, study, get_research_kind(item).field,
                                      make_add_research_item_operation(document, item),
                                      description * " " * item.id)
        _make_study_item_part(study, item)
    end
end

# `item` of `study`, as a `ReferencedDocument` when `study` is one.
function _make_study_item_part(study::ReferencedDocument, item::ResearchItem)
    field = get_research_kind(item).field
    index = findfirst(element -> element === item, collect(getproperty(get_document(study), field)))
    index === nothing ? item : getproperty(study, field)[index]
end
_make_study_item_part(study, item) = item

# ── A study ──────────────────────────────────────────────────────────────

"""
    start_study!(title; question = nothing, editor = get_evaluation_editor()) -> ReferencedDocument

Make a new study with `title`, and with the question `question` when one is given;
open it in a tab and add it to the explorer. Answer the study as the part of the
window that the tab shows, which every other verb takes. The study and its question say that you made them.

Use it to begin the record of a piece of work by the scientific approach: a
question to answer, and later its sources, hypotheses, experiments, results,
evidence, decisions and answer.

# Example

    study_1 = start_study!("The buffer of the access router";
                           question = "Which queue capacity keeps the drop rate under 1 %?")

See also `add_question!`, `describe_study`.
"""
function start_study! end

function start_study!(title; question = nothing, editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "start_study!") do
        study = ResearchStudy(title = _make_text(title), author = :assistant, time = get_research_time())
        if question !== nothing
            push!(study.questions, make_research_item(study, ResearchQuestion; author = :assistant,
                                                      statement = question))
        end
        evaluate_operation(editor, AddExplorerEntryOperation(study))
        get_edited_document(open_pane!(study; editor))
    end
end

"""
    add_question!(study, statement; criterion = "", purpose = "", parent = nothing,
                  editor = get_evaluation_editor()) -> the new item

Add a question to `study`: what the study must find out, what would answer it
(`criterion`), and what the answer decides (`purpose`). `parent` is a wider
question, or its id. Answer the new question; its id is the next `Q` of the study.

Use it to state a question of a study, or a narrower question under one.

# Example

    question_1 = add_question!(study_1, "Which queue capacity keeps the drop rate under 1 %?";
                               criterion = "the drop rate of each capacity, with a 95 % interval",
                               purpose = "the capacity that the router ships with")

See also `add_hypothesis!`, `add_answer!`.
"""
function add_question! end

add_question!(study, statement; criterion = "", purpose = "", parent = nothing,
              editor = get_evaluation_editor()) =
    _add_research_item!(study, ResearchQuestion, editor, "Add the question";
                        statement, criterion, purpose, parent)

"""
    add_source!(study, citation; link = "", summary = "", editor = get_evaluation_editor())
        -> the new item

Add a source to `study`: an item of the literature, a standard or a data set.
`citation` says who wrote it, when, and its title; `link` is a DOI, a URL or a
path; `summary` says what it says that matters to the study. Answer the source.

Use it to record what you read or found that the study rests on.

# Example

    source_1 = add_source!(study_1, "Kleinrock, Queueing Systems, Volume I, 1975";
                           summary = "The blocking of M/M/1/K in closed form.")

See also `add_hypothesis!`, `add_evidence!`.
"""
function add_source! end

add_source!(study, citation; link::AbstractString = "", summary = "", editor = get_evaluation_editor()) =
    _add_research_item!(study, ResearchSource, editor, "Add the source";
                        citation, link = String(link), summary)

"""
    add_hypothesis!(study, statement; question = nothing, prediction = nothing, basis = Any[],
                    editor = get_evaluation_editor()) -> the new item

Add a hypothesis to `study`: a claim that a test can refute. `question` is the
question that it answers, `prediction` what a test must observe if it holds (prose,
or a `ResearchExpectation` that `check_predictions!` tests), and `basis` the items
that it rests on. A link is an item or its id, such as `"Q1"`. Answer the hypothesis.

Use it to propose an answer to a question that an experiment or an analysis can test.

# Example

    hypothesis_1 = add_hypothesis!(study_1, "A queue capacity of 13 is enough.";
        question = "Q1", basis = ["S1"],
        prediction = ResearchExpectation(result_selection = selection_1, upper = 0.01))

See also `add_experiment!`, `add_evidence!`, `check_predictions!`.
"""
function add_hypothesis! end

add_hypothesis!(study, statement; question = nothing, prediction = nothing, basis = Any[],
                editor = get_evaluation_editor()) =
    _add_research_item!(study, ResearchHypothesis, editor, "Add the hypothesis";
                        statement, question, prediction, basis)

"""
    add_experiment!(study, title; design = nothing, tests = Any[], uses = Any[],
                    editor = get_evaluation_editor()) -> the new item

Add an experiment to `study`: a plan that makes new data. `design` is the plan, a
document of any domain, such as prose, a run selection or a configuration; `tests`
are the hypotheses that it tests, and `uses` the sources and results that it reads.
Answer the experiment.

Use it to record how a hypothesis is tested by new data, before the runs.

# Example

    experiment_1 = add_experiment!(study_1, "Sweep K = 1 … 20"; design = selection_1, tests = ["H1"])

See also `add_result!`, `record_decision!`.
"""
function add_experiment! end

add_experiment!(study, title; design = nothing, tests = Any[], uses = Any[],
                editor = get_evaluation_editor()) =
    _add_research_item!(study, ResearchExperiment, editor, "Add the experiment";
                        title, design, tests, uses)

"""
    add_analysis!(study, title; method = nothing, tests = Any[], uses = Any[],
                  editor = get_evaluation_editor()) -> the new item

Add an analysis to `study`: a plan that makes a result from data that exist.
`method` is Julia code, a SQL query, a pivot, a formula sheet or any document.
Answer the analysis.

Use it to record a statistic, a fit or a closed form that a hypothesis is held
against.

# Example

    analysis_1 = add_analysis!(study_1, "Mean drop rate by K"; uses = ["R1"], tests = ["H1"])

See also `add_study_formula!`, `add_result!`.
"""
function add_analysis! end

add_analysis!(study, title; method = nothing, tests = Any[], uses = Any[],
              editor = get_evaluation_editor()) =
    _add_research_item!(study, ResearchAnalysis, editor, "Add the analysis";
                        title, method, tests, uses)

"""
    add_result!(study, title, content; origin = nothing, editor = get_evaluation_editor())
        -> the new item

Add a result to `study`: the data `content` (a table, a plot, a number, any
document), which `origin` made, an experiment, an analysis or a source, or its id.
Answer the result.

Use it to keep the data of a run or an analysis in the study.

# Example

    result_1 = add_result!(study_1, "Drop rate by K", table_1; origin = "X1")

See also `add_evidence!`.
"""
function add_result! end

add_result!(study, title, content; origin = nothing, editor = get_evaluation_editor()) =
    _add_research_item!(study, ResearchResult, editor, "Add the result"; title, content, origin)

"""
    add_evidence!(study, statement; basis = Any[], supports = Any[], opposes = Any[],
                  editor = get_evaluation_editor()) -> the new item

Add evidence to `study`: an observation, stated apart from what it means, of the
results and sources of `basis`, and the claims that it `supports` and `opposes`.
Answer the evidence.

Use it to record what a result or a source shows about a hypothesis or an answer.

# Example

    evidence_1 = add_evidence!(study_1, "At K = 13 the drop rate is 0.91 % ± 0.05 %.";
                               basis = ["R1"], supports = ["H1"])

See also `record_decision!`, `check_predictions!`.
"""
function add_evidence! end

add_evidence!(study, statement; basis = Any[], supports = Any[], opposes = Any[],
              editor = get_evaluation_editor()) =
    _add_research_item!(study, ResearchEvidence, editor, "Add the evidence";
                        statement, basis, supports, opposes)

"""
    add_answer!(study, statement; question = nothing, caveats = "", basis = Any[],
                editor = get_evaluation_editor()) -> the new item

Add an answer to `study`: the answer to `question`, where it does not hold
(`caveats`), and the items that it rests on. Answer the answer item.

Use it to write down the conclusion of a study with its limits.

# Example

    answer_1 = add_answer!(study_1, "A queue capacity of 13."; question = "Q1",
                           caveats = "Poisson arrivals only.", basis = ["E1"])

See also `record_decision!`.
"""
function add_answer! end

add_answer!(study, statement; question = nothing, caveats = "", basis = Any[],
            editor = get_evaluation_editor()) =
    _add_research_item!(study, ResearchAnswer, editor, "Add the answer";
                        statement, question, caveats, basis)

"""
    record_decision!(study, statement; accepts = Any[], rejects = Any[], basis = Any[],
                     reason = "", editor = get_evaluation_editor()) -> the new item

Record a decision in `study`: what was decided and why, the items that it accepts
and rejects, and the items that it rests on. The status of each accepted item
becomes `:accepted`, and of each rejected one `:rejected`; a later decision about
the same item supersedes this one. The decision says that you made it. Answer the
decision.

Use it only when the person asks you to record a decision, or to accept or reject
an item. The person decides; the record shows who decided.

# Example

    record_decision!(study_1, "A queue capacity of 13 is enough."; accepts = ["H1", "E1"],
                     basis = ["E1"], reason = "The interval of E1 is under the bound.")

See also `add_evidence!`, `describe_study`.
"""
function record_decision! end

function record_decision!(study, statement; accepts = Any[], rejects = Any[], basis = Any[],
                          reason = "", editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "record_decision!") do
        document = get_document(study)
        decision = make_research_item(document, ResearchDecision; author = :assistant,
                                      statement, accepts, rejects, basis, reason)
        _evaluate_research_operation!(editor, study, :decisions,
                                      make_record_decision_operation(document, decision),
                                      "Record the decision " * decision.id)
        _make_study_item_part(study, decision)
    end
end

# ── The check of the predictions ─────────────────────────────────────────

"""
    get_expectation_bounds(expectation) -> (lower, upper)

The bounds that a value is held against. Without a reference they are the
`lower` and `upper` of the expectation, either of which can be `nothing`. With a
reference, a formula, they are its value times `1 - tolerance` and
`1 + tolerance`.
"""
function get_expectation_bounds(expectation::ResearchExpectation)
    reference = expectation.reference
    reference === nothing && return (expectation.lower, expectation.upper)
    reference isa FormulaFormula ||
        throw(ArgumentError("An expectation compares against a formula, and this is a " *
                            string(nameof(typeof(reference))) * "."))
    tolerance = expectation.tolerance
    tolerance isa Real || throw(ArgumentError("An expectation with a reference needs a tolerance."))
    value = get_formula_value(reference)
    value isa Real ||
        throw(ArgumentError("The reference " * repr(reference.name) * " answers " * repr(value) *
                            " and not a number."))
    minmax(value * (1 - tolerance), value * (1 + tolerance))
end

# The evidence of one check: what the read gave, against the bounds, for `hypothesis`.
function _make_check_evidence(study, hypothesis, values, (lower, upper))
    bounds = "[" * (lower === nothing ? "-∞" : string(lower)) * ", " *
             (upper === nothing ? "∞" : string(upper)) * "]"
    if isempty(values)
        return make_research_item(study, ResearchEvidence; author = :assistant,
            statement = "The check of " * hypothesis.id * " read no value.")
    end
    holds = all(values) do value
        (lower === nothing || value >= lower) && (upper === nothing || value <= upper)
    end
    mean = sum(values) / length(values)
    statement = "The check of " * hypothesis.id * " read " * string(length(values)) *
                (length(values) == 1 ? " value" : " values") * " with the mean " * string(mean) *
                "; " * (holds ? "every value is" : "not every value is") * " in " * bounds * "."
    make_research_item(study, ResearchEvidence; author = :assistant, statement,
                       supports = holds ? Any[hypothesis] : Any[],
                       opposes = holds ? Any[] : Any[hypothesis])
end

"""
    check_predictions!(study, read; editor = get_evaluation_editor()) -> Vector

Check each hypothesis of `study` whose prediction is a `ResearchExpectation`:
`read(selection)` answers the values that the expectation names, as numbers, and
every value must lie in its bounds. Each check adds evidence that supports the
hypothesis when every value is in the bounds, opposes it when one is not, and only
says so when the read gave no value. The expectation keeps no status, so the study
keeps every check. Answer the new evidence.

Use it after the runs, to hold the results against what the hypotheses predicted.

# Example

    check_predictions!(study_1, selection -> read_values(selection))

See also `ResearchExpectation`, `add_hypothesis!`, `record_decision!`.
"""
function check_predictions! end

function check_predictions!(study, read; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "check_predictions!") do
        document = get_document(study)
        # Every expectation is read and bounded before any evidence is added, so an
        # expectation that can not be checked leaves the study as it was.
        checks = Any[]
        for hypothesis in collect(document.hypotheses)
            hypothesis.prediction isa ResearchExpectation || continue
            selection = hypothesis.prediction.result_selection
            values = selection === nothing ? Float64[] : Float64[Float64(v) for v in read(selection)]
            push!(checks, (hypothesis, values, get_expectation_bounds(hypothesis.prediction)))
        end
        added = Any[]
        for (hypothesis, values, bounds) in checks
            evidence = _make_check_evidence(document, hypothesis, values, bounds)
            _evaluate_research_operation!(editor, study, :evidence,
                                          make_add_research_item_operation(document, evidence),
                                          "Check " * hypothesis.id)
            push!(added, _make_study_item_part(study, evidence))
        end
        added
    end
end

# ── The report ───────────────────────────────────────────────────────────

# The operation that appends `blocks` to the report of `study`, or that gives a
# study with no report a new one that holds them.
function _make_append_report_operation(study::ResearchStudy, blocks)
    report = study.report
    report isa MarkdownRoot ||
        return ReplaceReferencedValueOperation(study, "report", MarkdownRoot(elements = Any[blocks...]))
    make_insert_elements_operation(Reference(FieldReferenceStep("elements")), length(report.elements) + 1,
                                   Any[blocks...]; root = report)
end

function _append_report_blocks!(study, blocks, editor, description)
    isempty(blocks) && throw(ArgumentError("There is nothing to add to the report."))
    run_on_editor_task!(editor; description) do
        _evaluate_research_operation!(editor, study, :report,
                                      _make_append_report_operation(get_document(study), blocks), description)
        blocks
    end
end

"""
    add_study_section!(study, heading, prose; editor = get_evaluation_editor()) -> the heading

Append a section to the report of `study`: a heading and the paragraphs of
`prose`, which is Markdown. A study with no report gets one. Answer the heading.

Use it to write a titled section of the report: the question, the model, the
method, the results, the answer.

# Example

    add_study_section!(study_1, "The model", "A source feeds a queue with a finite buffer.")

See also `add_study_prose!`, `embed_in_study!`.
"""
function add_study_section! end

add_study_section!(study, heading::AbstractString, prose::AbstractString; editor = get_evaluation_editor()) =
    first(_append_report_blocks!(study,
        collect(parse_markdown("## " * String(heading) * "\n\n" * String(prose) * "\n").elements),
        editor, "add_study_section!"))

"""
    add_study_prose!(study, prose; editor = get_evaluation_editor()) -> the last paragraph

Append the paragraphs of `prose`, which is Markdown, to the report of `study`.

Use it to write an explanation, a remark or a transition into the report.

# Example

    add_study_prose!(study_1, "The load is 0.8, so the queue is busy four fifths of the time.")

See also `add_study_section!`.
"""
function add_study_prose! end

add_study_prose!(study, prose::AbstractString; editor = get_evaluation_editor()) =
    last(_append_report_blocks!(study, collect(parse_markdown(String(prose) * "\n").elements),
                                editor, "add_study_prose!"))

"""
    embed_in_study!(study, documents...; editor = get_evaluation_editor()) -> the last document

Place documents as blocks of the report of `study`, in order: an item of the
study, a file, a table, a plot, any document. An item is the item itself, so a
change of it shows in the report.

Use it to put an item or a document into the report where the reader sees it.

# Example

    embed_in_study!(study_1, find_study_item(study_1, "E1"))

See also `add_study_section!`.
"""
function embed_in_study! end

embed_in_study!(study, documents...; editor = get_evaluation_editor()) =
    last(_append_report_blocks!(study, Any[get_document(document) for document in documents],
                                editor, "embed_in_study!"))

# ── The formula sheet ────────────────────────────────────────────────────

"""
    add_study_formula!(study, name, text; editor = get_evaluation_editor()) -> FormulaFormula

Add a named formula, written in math notation, to the sheet of the analysis of
`study` whose method is a formula sheet. A study with no such analysis gets one,
"Closed form". Answer the formula; `get_formula_value` reads its value.

Use it to write a closed form that a hypothesis is held against, such as the
blocking of a queue.

# Example

    add_study_formula!(study_1, "P_block", "(1 - rho) rho^(K + 1) / (1 - rho^(K + 2))")

See also `ResearchExpectation`, `check_predictions!`.
"""
function add_study_formula! end

function add_study_formula!(study, name::AbstractString, text::AbstractString;
                            editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "add_study_formula!") do
        document = get_document(study)
        analysis = findfirst(item -> item.method isa FormulaEnvironment, collect(document.analyses))
        sheet = if analysis === nothing
            made = FormulaEnvironment(Any[])
            item = make_research_item(document, ResearchAnalysis; author = :assistant,
                                      title = "Closed form", method = made)
            _evaluate_research_operation!(editor, study, :analyses,
                                          make_add_research_item_operation(document, item),
                                          "Add the analysis " * item.id)
            made
        else
            document.analyses[analysis].method
        end
        formula = FormulaFormula(String(name), parse_math(String(text)))
        _evaluate_research_operation!(editor, study, :analyses,
            make_insert_elements_operation(Reference(FieldReferenceStep("formulas")),
                                           length(sheet.formulas) + 1, Any[formula]; root = sheet),
            "Add the formula " * repr(String(name)))
        wire_result!(formula, sheet)
        # The sheet shows the value of the new formula once it computes: on the
        # formula task of the editor while its loop runs, and at once with no loop.
        evaluate_operation(editor, ComputeFormulasOperation(sheet, FormulaFormula[formula]))
        formula
    end
end

# ── Reading ──────────────────────────────────────────────────────────────

function find_study_item(study::ReferencedDocument, id::AbstractString)
    item = find_study_item(get_document(study), id)
    item === nothing ? nothing : _make_study_item_part(study, item)
end

"""
    describe_study(study) -> Base.Text

The outline of `study` as text: its title, then one line for each item, with its
id, its status, its text, its links, its author and its time.

Use it to read a study before you add to it, or to say what it holds.

# Example

    describe_study(study_1)

See also `find_study_item`, `StudyItems`.
"""
function describe_study end

function describe_study(study)
    document = get_document(study)
    lines = String[_format_plain_text(document.title)]
    for item in collect_study_items(document)
        status = has_research_status(item) ? " [" * string(item.status) * "]" : ""
        links = [describe_research_link(item, name, linked) for (name, linked) in collect_research_links(item)]
        push!(lines, item.id * status * " " * _format_plain_text(get_research_item_text(item)) *
                     (isempty(links) ? "" : " (" * join(links, "; ") * ")") *
                     " — " * string(item.author) * ", " * item.time)
    end
    Base.Text(join(lines, "\n"))
end
