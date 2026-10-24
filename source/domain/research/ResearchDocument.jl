# Fragment of `ResearchModule` — the research document types: a study, the nine
# kinds of item that it holds, and the expectation that the prediction of a
# hypothesis can be.

abstract type ResearchDocument <: Document end

"""
The abstract type of the nine kinds of item of a study: a question, a source, a
hypothesis, an experiment, an analysis, a result, evidence, a decision and an
answer. Every item has an `id`, an `author` and a `time`; every item but a
decision has a `status`.
"""
abstract type ResearchItem <: ResearchDocument end

# ── The discourse ────────────────────────────────────────────────────────

"""
What a study must find out.

- `id` — the short name of the question in its study, such as `"Q1"`.
- `statement` — the question: a `PrimitiveString`, or a document of any domain.
- `criterion` — what would answer it: an observable, a comparison, a threshold.
- `purpose` — what the answer decides.
- `parent` — the wider question that this question refines, or `nothing`.
- `elements` — documents of any domain that the item holds, such as code, a page
  of text, a table or a chart; the outline draws each through its own view.
- `status` — `:open`, `:accepted` (the study takes it on) or `:rejected` (out of
  scope). Only a decision changes it.
- `author` — `:person` or `:assistant`; `time` — when it was made, in UTC.

Use it to read or build the question of a study.

# Example

    question_1 = ResearchQuestion(id = "Q1", statement = PrimitiveString("Which buffer keeps the drop rate under 1 %?"))

See also `add_question!`, `ResearchHypothesis`.
"""
@document struct ResearchQuestion <: ResearchItem
    id::String = ""
    statement::Any = PrimitiveString("")
    criterion::Any = PrimitiveString("")
    purpose::Any = PrimitiveString("")
    parent::Any = nothing
    elements::CellVector = CellVector()
    status::Symbol = :open
    author::Symbol = :person
    time::String = ""
end

"""
An item of the literature: a paper, a book, a standard, a data set or a web page.

- `id` — such as `"S1"`.
- `citation` — who wrote it, when, and its title.
- `link` — a DOI, a URL or the path of a file, as a text.
- `summary` — what it says that matters to the study.
- `status` — `:open`, `:accepted` (relevant and trusted) or `:rejected` (not used).
- `elements`, `author`, `time` — as for a `ResearchQuestion`.

Use it to read or build a source of a study.

# Example

    source_1 = ResearchSource(id = "S1", citation = PrimitiveString("Kleinrock, Queueing Systems, 1975"))

See also `add_source!`, `ResearchEvidence`.
"""
@document struct ResearchSource <: ResearchItem
    id::String = ""
    citation::Any = PrimitiveString("")
    link::String = ""
    summary::Any = PrimitiveString("")
    elements::CellVector = CellVector()
    status::Symbol = :open
    author::Symbol = :person
    time::String = ""
end

"""
A claim that a test can refute, with its prediction.

- `id` — such as `"H1"`.
- `statement` — the claim.
- `question` — the `ResearchQuestion` that it answers, or `nothing`.
- `prediction` — what a test must observe if the claim holds: prose, a math
  expression, or a `ResearchExpectation` that `check_predictions!` tests.
- `basis` — the items that the claim rests on, such as sources.
- `status` — `:open`, `:accepted` (the evidence supports it) or `:rejected`
  (refuted, or dropped).
- `elements`, `author`, `time` — as for a `ResearchQuestion`.

Use it to read or build a hypothesis of a study.

# Example

    hypothesis_1 = ResearchHypothesis(id = "H1", statement = PrimitiveString("A buffer of 13 packets is enough."),
                                      question = question_1)

See also `add_hypothesis!`, `ResearchExpectation`, `ResearchEvidence`.
"""
@document struct ResearchHypothesis <: ResearchItem
    id::String = ""
    statement::Any = PrimitiveString("")
    question::Any = nothing
    prediction::Any = nothing
    basis::CellVector = CellVector()
    elements::CellVector = CellVector()
    status::Symbol = :open
    author::Symbol = :person
    time::String = ""
end

"""
An observation of a result or a source, and the claims that it supports or
opposes. The statement says what was observed, apart from what it means.

- `id` — such as `"E1"`.
- `statement` — the observation.
- `basis` — the results and the sources that it is an observation of.
- `supports` — the claims that it supports, such as hypotheses.
- `opposes` — the claims that it opposes.
- `status` — `:open`, `:accepted` (the observation is correct) or `:rejected`.
- `elements`, `author`, `time` — as for a `ResearchQuestion`.

Use it to read or build the evidence of a study.

# Example

    evidence_1 = ResearchEvidence(id = "E1", statement = PrimitiveString("At K = 13 the drop rate is 0.91 %."),
                                  supports = [hypothesis_1])

See also `add_evidence!`, `check_predictions!`.
"""
@document struct ResearchEvidence <: ResearchItem
    id::String = ""
    statement::Any = PrimitiveString("")
    basis::CellVector = CellVector()
    supports::CellVector = CellVector()
    opposes::CellVector = CellVector()
    elements::CellVector = CellVector()
    status::Symbol = :open
    author::Symbol = :person
    time::String = ""
end

"""
What the person or the assistant decided, and why. A decision accepts and rejects
items: it writes their `status`, and a later decision about the same item
supersedes it. Nobody edits a decision to change its sense.

- `id` — such as `"D1"`.
- `statement` — what was decided.
- `reason` — why.
- `accepts` — the items that it accepts.
- `rejects` — the items that it rejects.
- `basis` — the items that it rests on, such as evidence.
- `elements`, `author`, `time` — as for a `ResearchQuestion`. A decision has no status.

Use it to read or build a decision of a study.

# Example

    decision_1 = ResearchDecision(id = "D1", statement = PrimitiveString("H1 holds."), accepts = [hypothesis_1])

See also `record_decision!`, `ResearchHypothesis`.
"""
@document struct ResearchDecision <: ResearchItem
    id::String = ""
    statement::Any = PrimitiveString("")
    reason::Any = PrimitiveString("")
    accepts::CellVector = CellVector()
    rejects::CellVector = CellVector()
    basis::CellVector = CellVector()
    elements::CellVector = CellVector()
    author::Symbol = :person
    time::String = ""
end

"""
The answer to a question, with its caveats and its basis.

- `id` — such as `"A1"`.
- `statement` — the answer.
- `question` — the `ResearchQuestion` that it answers, or `nothing`.
- `caveats` — where the answer does not hold.
- `basis` — the items that it rests on, such as evidence and decisions.
- `status` — `:open`, `:accepted` (the answer of the study) or `:rejected`.
- `elements`, `author`, `time` — as for a `ResearchQuestion`.

Use it to read or build the answer of a study.

# Example

    answer_1 = ResearchAnswer(id = "A1", statement = PrimitiveString("13 packets."), question = question_1)

See also `add_answer!`, `ResearchQuestion`.
"""
@document struct ResearchAnswer <: ResearchItem
    id::String = ""
    statement::Any = PrimitiveString("")
    question::Any = nothing
    caveats::Any = PrimitiveString("")
    basis::CellVector = CellVector()
    elements::CellVector = CellVector()
    status::Symbol = :open
    author::Symbol = :person
    time::String = ""
end

# ── The process ──────────────────────────────────────────────────────────

"""
A plan that makes new data, such as a simulation or a measurement.

- `id` — such as `"X1"`.
- `title` — what the experiment is.
- `design` — the plan: prose, a workflow of steps, a run selection, a
  configuration, or a document of any domain.
- `tests` — the hypotheses that it tests.
- `uses` — the sources and the results that it reads.
- `status` — `:open`, `:accepted` (the plan is approved) or `:rejected`.
- `elements`, `author`, `time` — as for a `ResearchQuestion`.

Use it to read or build an experiment of a study.

# Example

    experiment_1 = ResearchExperiment(id = "X1", title = PrimitiveString("Sweep K = 1 … 20"), tests = [hypothesis_1])

See also `add_experiment!`, `ResearchResult`.
"""
@document struct ResearchExperiment <: ResearchItem
    id::String = ""
    title::Any = PrimitiveString("")
    design::Any = nothing
    tests::CellVector = CellVector()
    uses::CellVector = CellVector()
    elements::CellVector = CellVector()
    status::Symbol = :open
    author::Symbol = :person
    time::String = ""
end

"""
A plan that makes a result from data that exist, such as a statistic, a fit or a
closed form.

- `id` — such as `"N1"`.
- `title` — what the analysis is.
- `method` — Julia code, a SQL query, a pivot, a formula sheet, or a document of
  any domain.
- `tests`, `uses`, `elements`, `status`, `author`, `time` — as for a `ResearchExperiment`.

Use it to read or build an analysis of a study.

# Example

    analysis_1 = ResearchAnalysis(id = "N1", title = PrimitiveString("Blocking in closed form"))

See also `add_analysis!`, `add_study_formula!`.
"""
@document struct ResearchAnalysis <: ResearchItem
    id::String = ""
    title::Any = PrimitiveString("")
    method::Any = nothing
    tests::CellVector = CellVector()
    uses::CellVector = CellVector()
    elements::CellVector = CellVector()
    status::Symbol = :open
    author::Symbol = :person
    time::String = ""
end

"""
Data that an experiment or an analysis made, or that a source reports.

- `id` — such as `"R1"`.
- `title` — what the result is.
- `content` — the data: a table, a chart, a pivot, a number, or a document of any
  domain.
- `origin` — the experiment, the analysis or the source that made it, or
  `nothing`.
- `status` — `:open`, `:accepted` (valid) or `:rejected` (not valid, such as a
  run with a fault).
- `elements`, `author`, `time` — as for a `ResearchQuestion`.

Use it to read or build a result of a study.

# Example

    result_1 = ResearchResult(id = "R1", title = PrimitiveString("Drop rate by K"), origin = experiment_1)

See also `add_result!`, `ResearchEvidence`.
"""
@document struct ResearchResult <: ResearchItem
    id::String = ""
    title::Any = PrimitiveString("")
    content::Any = nothing
    origin::Any = nothing
    elements::CellVector = CellVector()
    status::Symbol = :open
    author::Symbol = :person
    time::String = ""
end

# ── The prediction that a check tests ────────────────────────────────────

"""
A bound on recorded values: the prediction of a hypothesis that
`check_predictions!` tests.

- `result_selection` — what to read, such as a result selection of a simulator.
  The check reads it with the function that its caller gives.
- `lower`, `upper` — the bounds, each a number or `nothing`.
- `reference` — a `FormulaFormula`, or `nothing`. With a reference, the bounds are
  its value times `1 - tolerance` and `1 + tolerance`.
- `tolerance` — the share of the reference that a value can differ by.

Use it as the `prediction` of a hypothesis that a check of the results tests.

# Example

    ResearchExpectation(result_selection = selection_1, upper = 0.01)

See also `check_predictions!`, `ResearchHypothesis`.
"""
@document struct ResearchExpectation <: ResearchDocument
    result_selection::Any = nothing
    lower::Any = nothing
    upper::Any = nothing
    reference::Any = nothing
    tolerance::Any = nothing
end

# ── The study ────────────────────────────────────────────────────────────

"""
The decision that a person writes in the row of an item before it is recorded:
the item, the verdict, `:accepted` or `:rejected`, the reason, and the basis, the
items that the decision rests on. A study holds it in `deciding` while the panel
of the row is open, as state of its view.

Use it to open the panel of a decision in the outline of a study.

# Example

    study_1.deciding = ResearchDecisionDraft(item = hypothesis_1, verdict = :accepted)

See also `ResearchDecision`, which a press on Record writes.
"""
@document struct ResearchDecisionDraft <: ResearchDocument
    item::Any = nothing
    verdict::Symbol = :accepted
    reason::Any = PrimitiveString("")
    basis::CellVector = CellVector()
end

"""
The whole piece of work on one problem, from the question to the answer. A study
owns each of its items in the list of its kind; an item that links to another
item holds that item itself.

- `title` — what the study is about.
- `questions`, `sources`, `hypotheses`, `experiments`, `analyses`, `results`,
  `evidence`, `decisions`, `answers` — the items, each list in the order that
  they were made.
- `report` — a Markdown page that tells the study in order and holds items and
  other documents, or `nothing`.
- `folded` — the ids of the items whose cards the outline shows folded to their
  first line. It is view state: a fold is no edit, and the file of the study does
  not save it.
- `deciding` — the `ResearchDecisionDraft` of the panel that a row of the outline
  shows, or `nothing`. It is view state too.
- `view` — how the outline shows the study: `:kind`, a section for each kind of
  item, `:time`, a group for each day, `:map`, the map of its items and links, or
  `:report`, the report. It is view state.
- `first_text` — the quiet row that the outline of a study with no item shows,
  where the first key a person types makes the first question. It is view state.
- `editing` — the id of the item whose row shows every field, the empty ones too,
  while the caret is in it, or `nothing`. It is view state.
- `author`, `time` — who made the study, and when, in UTC.

Use it to read or build a study. A tab draws it as an outline of its items.

# Example

    study_1 = ResearchStudy(title = PrimitiveString("The buffer of the access router"),
                            questions = [question_1], hypotheses = [hypothesis_1])

See also `start_study!`, `describe_study`, `find_study_item`.
"""
@document struct ResearchStudy <: ResearchDocument
    title::Any = PrimitiveString("")
    questions::CellVector = CellVector()
    sources::CellVector = CellVector()
    hypotheses::CellVector = CellVector()
    experiments::CellVector = CellVector()
    analyses::CellVector = CellVector()
    results::CellVector = CellVector()
    evidence::CellVector = CellVector()
    decisions::CellVector = CellVector()
    answers::CellVector = CellVector()
    report::Any = nothing
    folded::Any = String[]
    deciding::Any = nothing
    view::Symbol = :kind
    first_text::Any = PrimitiveString("")
    editing::Any = nothing
    author::Symbol = :person
    time::String = ""
end

# Which rows an outline shows folded, the decision that a row writes and how the
# outline shows the study are state of the view, not things the study says: the
# file and a search leave them out.
get_view_state_fields(::Type{<:ResearchStudy}) = (:folded, :deciding, :view, :first_text, :editing)

# A draft is a part of the view of a study, no document that a person inserts.
insertable(::Type{<:ResearchDecisionDraft}) = false

# ── The kinds of item ────────────────────────────────────────────────────

"""
The kinds of item of a study, in the order of the work: for each one, the field
of the study that holds it, its type, the letter of its id, and its name.
"""
const RESEARCH_KINDS = (
    (field = :questions,   type = ResearchQuestion,   letter = "Q", name = "question"),
    (field = :sources,     type = ResearchSource,     letter = "S", name = "source"),
    (field = :hypotheses,  type = ResearchHypothesis, letter = "H", name = "hypothesis"),
    (field = :experiments, type = ResearchExperiment, letter = "X", name = "experiment"),
    (field = :analyses,    type = ResearchAnalysis,   letter = "N", name = "analysis"),
    (field = :results,     type = ResearchResult,     letter = "R", name = "result"),
    (field = :evidence,    type = ResearchEvidence,   letter = "E", name = "evidence"),
    (field = :decisions,   type = ResearchDecision,   letter = "D", name = "decision"),
    (field = :answers,     type = ResearchAnswer,     letter = "A", name = "answer"),
)

"The statuses of an item: only a decision changes them."
const RESEARCH_STATUSES = (:open, :accepted, :rejected)

"The authors of an item."
const RESEARCH_AUTHORS = (:person, :assistant)

"""
    get_research_kind(type) -> NamedTuple

The entry of `RESEARCH_KINDS` for the item type `type` or for an item: its field,
its type, its letter and its name.
"""
function get_research_kind(type::Type{<:ResearchItem})
    for kind in RESEARCH_KINDS
        type <: kind.type && return kind
    end
    throw(ArgumentError("No kind of item is a " * string(nameof(type)) * "."))
end
get_research_kind(item::ResearchItem) = get_research_kind(typeof(item))

"""
    has_research_status(item) -> Bool

Whether `item` has a status: every item but a decision.
"""
has_research_status(item::ResearchItem) = !(item isa ResearchDecision)

"""
    collect_study_items(study) -> Vector{ResearchItem}

The items of the lists of `study`, in the order of the kinds and, in a list, in
the order that they were made. An item that a link holds is not given again.
"""
function collect_study_items(study::ResearchStudy)
    items = ResearchItem[]
    for kind in RESEARCH_KINDS
        append!(items, getproperty(study, kind.field))
    end
    items
end

# ── The time ─────────────────────────────────────────────────────────────

const _RESEARCH_TIME_FORMAT = Dates.DateFormat("yyyy-mm-ddTHH:MM:SS")

"""
    format_research_time(time::DateTime) -> String

The text that the `time` of an item holds for `time`, a UTC time:
`"2026-10-22T07:12:00Z"`.
"""
format_research_time(time::Dates.DateTime) = Dates.format(time, _RESEARCH_TIME_FORMAT) * "Z"

"""
    get_research_time() -> String

The text that the `time` of an item made now holds: the UTC time, to the second.
"""
get_research_time() = format_research_time(Dates.now(Dates.UTC))

"""
    find_research_time(text) -> Union{DateTime, Nothing}

The UTC time that the `time` text of an item holds, or `nothing` when the text is
not a time.
"""
function find_research_time(text::AbstractString)
    isempty(text) && return nothing
    try
        Dates.DateTime(rstrip(text, 'Z'), _RESEARCH_TIME_FORMAT)
    catch
        nothing
    end
end

# The time of an item as a person reads it: the local time of that moment, to the
# minute, with the offset of the time zone on that date. A text that is not a time
# stays as it is.
function _format_local_time(text::AbstractString)
    time = find_research_time(text)
    time === nothing && return String(text)
    Libc.strftime("%Y-%m-%d %H:%M", Libc.TmStruct(Dates.datetime2unix(time)))
end

# ── The texts ────────────────────────────────────────────────────────────

"""
    get_research_item_text(item) -> Any

The text that names `item`: the title of an experiment, an analysis or a result,
the citation of a source, the statement of any other item.
"""
get_research_item_text(item::Union{ResearchExperiment, ResearchAnalysis, ResearchResult}) = item.title
get_research_item_text(item::ResearchSource) = item.citation
get_research_item_text(item::ResearchItem) = item.statement

_format_plain_text(text::AbstractString) = String(text)
_format_plain_text(text::PrimitiveString) = something(text.value, "")
# A document of another domain, such as a Markdown paragraph, as its own text, when
# its domain has a text form.
_format_plain_text(text::Document) =
    make_natural_projection(text, :string) === nothing ? "" : print_natural_text(text)
_format_plain_text(text) = ""

_make_text(text::AbstractString) = PrimitiveString(String(text))
_make_text(text::Document) = text
_make_text(::Nothing) = PrimitiveString("")
_make_text(text) = PrimitiveString(string(text))

# The name of a tab that shows a study: its title.
get_document_title(study::ResearchStudy) =
    (text = _format_plain_text(study.title); isempty(text) ? "Study" : text)
