# A study records its questions, its evidence and its decisions, and who made each one

> **Kind:** plan · **Status:** pending, written 2026-10-22 and changed the same
> day after the answers of the owner: a study combines with the domains that
> exist (§6), the author is only person or assistant (D1), an item holds the items
> that it links to (§4.4), the study of omnet-julia merges into this domain (D3,
> §8), and the domain is named Research (D4). Every decision is made. No step is
> started. ·
> **Stands on:** [workflow.md](../../documentation/package/domain/workflow/workflow.md),
> [a-workflow-records-steps-decisions-and-dates.md](../done/a-workflow-records-steps-decisions-and-dates.md),
> [domain-anatomy.md](../../documentation/design/domain-anatomy.md),
> [roster.md](../../documentation/package/platform/roster/roster.md),
> [serialization.md](../../documentation/package/platform/serialization/serialization.md),
> and in omnet-julia `documentation/package/study/study.md` and
> `documentation/requirement/simulation-tasks.md`

## 1. The request

On 2026-10-22 the owner asked for a survey of what projectured-julia and
omnet-julia hold for simulation studies, and for the design of a scientific
workbench domain with "the usual parts of solving a problem using the scientific
approach": "questions, hypothesis, literature, analysis, studies, experiments,
results, evidence, decisions, answers, etc." The representation must come from
the literature and must not be complicated. The domain has documents, projections
that show them, an extension of the explorer, and verbs of the assistant.

Two aspects are important to the owner: who did what ("the user decided
something, the AI produced some evidence"), and when.

The owner added three things the same day:

- "you should probably also check what domain projectured already comes with,
  those should combine with the scientific domains e.g. markdown, workflows,
  etc." Section 2.3 holds that survey, and section 6 the design that follows.
- "it's ok storing that the assistant made it, otherwise we open a whole new set
  of worms: what model provider, which llm model, which version, etc." (D1, §4.3).
- "I think the documents should directly contain each other, save already works
  recursively and supports storing a graph with cross references in all formats:
  markdown, json, julia, etc. it should also support in pred format. The concepts
  can still have an ID, so a person can refer to them and the ID can show up in
  prose as usual." (§4.4, step 1).
- "I choose (b), so the old study domain in omnet IDE is merged into this one"
  (D3, §8), and "I'm not sure workbench is the best domain name here, any other
  idea?", then "no user knows study yet, ignoring backward compatbility, what
  name would you suggest and why?", and "agreed" to Research (D4).

## 2. What exists (2026-10-22, main 256e3aabf)

### 2.1 projectured-julia: who, when and links

- **The Workflow domain is the nearest relative.** A `WorkflowStep` holds steps
  and decisions, a `WorkflowDecision` holds options, and each node has a journal
  of `WorkflowEntry(time, author, kind, text, source)`. The `author` is `:person`
  or `:assistant`, and the `time` is a text `"yyyy-mm-ddTHH:MM:SS"` in local time,
  because a `DateTime` in a `.pred` file needs a method for a type of `Dates`,
  which is type piracy. A change of state writes an entry. The verbs write with
  `author = :assistant`, and the buttons of the outline write with `:person`. Each
  edit is a builder over `ReplaceReferencedValueOperation`, so undo records it.
  The `text` of an entry holds a `PrimitiveString`, a Markdown node or any
  document, and a card shows a document of any domain through the view of that
  domain.
- **No other record says who.** `UndoEntry` has a time and no author.
  `ConversationTurn` has a role and two times. `GestureLogEntry` and
  `MessageLogEntry` have no time.
- **A verb does not know who calls it.** The code that a tool call runs knows its
  editor through the scoped value `_EVALUATION_EDITOR` (`CodeExecution.jl`), and
  nothing tells it its agent. The owner chose to add nothing for it (D1).
- **The save writes a graph.** In memory a document is the real graph: a shared
  subtree is one object, and a cycle is a cycle. `save_project!` cuts the graph
  into files (`FileCut.jl`). A node goes into the first file that reaches it, at
  the first place that the walk reaches. Each other place writes a marker in the
  notation of its file, `file("a.json")` or `node(file("a.json"), "children[1]")`,
  and `load_project` splices the same object back (`FileSplice.jl`). This holds
  for a node that one file holds at two places: the test "a shared subtree inside
  one file is written once" of `FileProjectTest.jl` proves it for JSON, and a
  `.pred` file writes its marker as a `PredReference`.
- **A file that is saved alone refuses a shared node.** `save_file!` cuts in a
  strict mode, in which every marker is an error. So a node that one file holds
  twice, or a cycle, is refused: the tests "a shared subtree is rejected: a single
  file cannot refer to itself" and "a cycle is rejected the same way" of
  `FileProjectTest.jl` assert it. The tab of a `.pred` file saves through
  `save_file!` (`_write_registered_file`, `DocumentFile.jl`). So a study with
  links, saved from its tab, fails today. Step 1 removes this limit.
- **The work plan names its steps by id.** A `WorkPlanStep` has an `id`, which a
  person reads in the view.
- No type in either repository is named for a hypothesis, a source, a citation,
  evidence or provenance.

### 2.2 omnet-julia

- **The study of omnet-julia** (`OmnetStudy`, `source/study/StudyDocument.jl`)
  has four documents: `StudyStudy(title, question, expectations, findings,
  formulas, page)`, `StudyQuestion(statement, answer, decision)`,
  `StudyExpectation(statement, result_selection, lower, upper, reference,
  tolerance, status, observed)` and `StudyFinding(statement, evidence)`. An
  expectation is a bound on a recorded value. `check_expectations!` reads the
  results and writes `status` (`:holds` or `:fails`) and `observed`. The
  `formulas` are a `FormulaEnvironment` of the Formula domain, and the `page` is a
  Markdown page that names each block with a `pred-ref` fence. The verbs are in
  `OmnetIde` (`source/ide/StudyVerbs.jl`): `make_study!`, `add_expectation!`,
  `check_expectations!`, `add_finding!`, `make_run_card`, `run_card!`,
  `save_study!` and others.
- **The code of the omnet study** is 1435 lines in six files:
  `source/study/StudyDocument.jl` (the four types), `StudyCheck.jl` (the check of
  an expectation, which takes the function that reads a selection, so it names no
  result reader), `StudyFile.jl` (`save_study!(study, directory)` and
  `load_study(directory)`, which cut the study into one file for each block
  through a `FileProject`), `presentation/StudyToWidget.jl` and `StudyGraphics.jl`
  (the view), and `source/ide/StudyVerbs.jl` (the sixteen verbs of
  `make_study_api`). The packages are `OmnetStudy`, `OmnetStudyPresentation` and
  their two test packages.
- **The verbs work on the study of the window.** `get_study()` answers what the
  pane "Study" holds. `make_study!(; title, question)` writes the project
  descriptor of the folder and opens the page beside the conversation.
  `open_study!()` loads `study.pred` of the folder and calls
  `place_study_blocks!`, which tells each run card and result view the folder,
  because a file writes no folder. `add_study_section!`, `add_study_prose!` and
  `embed_in_study!` grow the page; `write_ned_file!`, `write_ini_file!`,
  `write_study_file!`, `make_run_card` and `run_card!` make and run the files of a
  simulation; `add_study_formula!`, `add_expectation!`, `check_expectations!()`
  and `add_finding!` hold the knowledge; `save_study!()` writes the folder.
- **What uses it.** `IdeWindow.jl` puts the study sections of the assistant guide
  into the system text (`STUDY_GUIDE_SECTIONS`). `example/ide/StudyRecording.jl`
  holds the seven turns of the recorded video (`STUDY_TURNS`,
  `record_study_video`). `tool/assistant/study_rehearsal.jl` rehearses a model.
  The tests are `test_study()`, the view test of `OmnetStudyPresentationTest`,
  and in `OmnetIdeTest` `test_study_verbs()`, `test_study_runs()`,
  `test_assistant_study_by_hand()`, `test_study_recording_script()` and
  `test_assistant_study()`.
- **A finding and an expectation record no author and no time.** A saved
  expectation keeps only its last status.
- **A run records what and when, but not who.** The run attributes hold
  `datetime`, `runnumber`, `repetition`, `seedset`, `iterationvars` and the run id
  `<config>-<run>-<datetime>-<pid>`. A task execution holds `start_time` and
  `end_time` for the session only.
- **The task catalog** (`documentation/requirement/simulation-tasks.md`) names
  the work of a study: OT-QUESTION, OT-SCOPE, OT-PRIOR-ART, OT-EVIDENCE,
  OT-DESIGN-EXPERIMENT, OT-EXECUTE, OT-KEEP, OT-VALIDATE, OT-ANALYSE, OT-REPORT,
  OT-ITERATE and others. It uses **study** for the whole piece of work, from the
  question to the report, and **parameter study** for a plan that makes a set of
  runs.
- The explorer of a campaign window has no section for studies. A study is a
  pane titled "Study".

### 2.3 The domains and the slices that a study combines with

Each row says what the domain or the slice gives a study, and what of a study it
can hold. The mechanisms in the last column exist today.

| Domain or slice | A study holds it as | It holds a study item as | The mechanism |
| --- | --- | --- | --- |
| Markdown, RST | the longer prose of a statement, a summary, a reason or caveats | a block of a report page | a field `::Any` draws its document through the view of its domain; a page holds a node of another file, and saves a `pred-ref` fence for it, as the page of the omnet study does |
| Book | the report of a study as chapters | a block of a chapter | as above |
| Workflow | the procedure of an experiment, as steps | the content of a card on a step, such as "Validate the model" | `WorkflowCard.content` holds any document |
| Math, Formula | a prediction as an expression; a sheet of closed forms as the method of an analysis | — | the omnet study holds a `FormulaEnvironment` |
| Julia, SQL | the method of an analysis | — | a field `::Any` |
| Pivot, Chart, data frames | the content of a result; the method of an analysis | — | a field `::Any`; the omnet result tables and plots are of this kind |
| Process, FSM, Sequence chart | the model under study, or a trace as a result | — | a field `::Any` |
| JSON, YAML, XML | a data set or a configuration | — | a field `::Any`; the file of that format writes it |
| Graph | — | a vertex of the argument map | `GraphVertex.content` holds any document; FSM and Process build a `GraphGraph` |
| Roster and arrangement | — | a row of a table of items from one study or from every open study, which a filter, a sort and a group arrange | a slice adds a source and its columns; `show_roster!` makes the table |
| Explorer and navigator | — | an entry, and the page of an entry | `is_explorer_entry_type`, `get_tree_children_steps` |
| Dashboard | — | the content of a card | `DashboardCard.content` holds any document |
| Undo | every edit of a study | — | the builders answer the generic write |
| Task | the runs of an experiment, while they run | — | the omnet task groups |

In each place of the third column, the place holds the item itself, and the save
writes a marker where the file of the study owns it. An item draws there without
its study, because it holds its status and its links (§4.4, §4.5).

## 3. What the literature gives

| Source | Its types | The lesson for this domain |
| --- | --- | --- |
| W3C PROV-DM and PROV-O (Moreau and Groth, 2013) | Entity, Activity, Agent (Person, SoftwareAgent), Plan; `wasGeneratedBy`, `used`, `wasAttributedTo`, `wasDerivedFrom`; `generatedAtTime` | Who and when are a small fixed set: an agent and a time on each record. A person and a program are both agents. |
| Discourse graphs (Chan, about 2021) | Question, Claim, Evidence, Source; supports, opposes, informs, addresses | Evidence is an observation, stated apart from what it means. A claim is an interpretation. Keep the two apart. |
| Micropublications (Clark, Ciccarese and Goble, 2014); nanopublications (Groth, Gibson and Velterop, 2010) | Claim, Support, Challenge, Evidence; assertion, provenance, publication info | A statement and the record of who made it are two parts of one record. |
| IBIS (Kunz and Rittel, 1970); QOC (MacLean et al., 1991) | Issue, Position, Argument; Question, Option, Criterion | A question has candidate answers, and arguments for and against each one. A map shows them. |
| Toulmin, *The Uses of Argument* (1958) | Claim, Data, Warrant, Backing, Qualifier, Rebuttal | A conclusion carries its limits, and a decision carries its reason. |
| SEPIO (Brush et al., 2016); OBI (Bandrowski et al., 2016); ISA (Sansone et al., 2012); EXPO (Soldatova and King, 2006) | assertion, evidence line; investigation, study, assay; goal, hypothesis, design, result, conclusion | A plan and its execution are two things. The sequence of EXPO is the sequence of this domain. |
| Architecture Decision Records (Nygard, 2011); MADR | title, status, context, decision, consequences; proposed, accepted, superseded | Nobody edits a decision. A later decision supersedes it, and the status of a thing is what the last decision said. |
| Preregistration (Center for Open Science); registered reports (Chambers, 2013); Popper (1959) | question, hypothesis, design, analysis plan, inference criteria; prediction, test, corroboration | A hypothesis carries its prediction before the data exist. |
| Law, *Simulation Modeling and Analysis* (2015); Sargent (2013); TRACE (Grimm et al., 2014); provenance of simulation studies (Ruscheinski and Uhrmacher, 2017; Wilsdorf et al., 2021) | problem, assumptions, experiment design, runs, output analysis; research question, simulation experiment and simulation data as PROV entities | A simulation study fits the same small set: a simulation experiment is an activity with a plan, and its data is an entity. |
| Lab notebooks; RO-Crate (Soiland-Reyes et al., 2022) | dated, attributed entries; `CreateAction` with `agent`, `startTime`, `endTime` | A record is written at the time and is not erased. A correction is a new record. |

The sources agree on nine concepts in two layers. The **discourse layer** says
what is claimed and why: a question, a hypothesis, evidence, a decision, an
answer, and the sources. The **process layer** says how a thing came to be: an
experiment or an analysis, which is an activity with a plan, its result, an agent
and a time. Evidence joins the two layers. It is an observation of a result or of
a source, and it supports or opposes a claim.

The sources warn against five mistakes. The model of §4 avoids each one:

1. A claim that is confused with its evidence.
2. A record that changes with no trace of who changed it.
3. A status that is a part of the identity of a thing.
4. A plan that is merged with its execution.
5. A conclusion without its limits.

## 4. The model

### 4.1 The words

| Word | What it is |
| --- | --- |
| study | the whole piece of work on one problem, from the question to the answer, as the task catalog of omnet-julia uses the word; one document |
| item | one record of a study: a question, a source, a hypothesis, an experiment, an analysis, a result, evidence, a decision or an answer |
| question | what the study must find out, with what would answer it and what the answer decides |
| source | an item of the literature: a paper, a book, a standard, a data set or a web page |
| hypothesis | a claim that a test can refute, with its prediction |
| experiment | a plan that makes new data, such as a simulation or a measurement |
| analysis | a plan that makes a result from data that exist, such as a statistic, a fit or a closed form |
| result | data that an experiment or an analysis made, or that a source reports |
| evidence | an observation of a result or a source, and the claims that it supports or opposes |
| decision | what the person or the assistant decided and why, and which items it accepts or rejects |
| answer | the answer to a question, with its caveats and its basis |
| link | a field of an item that holds another item itself |
| author | who made an item: `:person` or `:assistant` |
| id | the short name of an item in its study, such as `H1`, which a person writes in prose |
| status | `:open`, `:accepted` or `:rejected`; only a decision changes it |

### 4.2 The documents

The domain is `ProjecturedResearch`, in `source/domain/research/` (D4). It
depends on the kernel, the platform, `Dates`, the Graph domain (for the map of
§5.2), the Formula domain (for the reference of an expectation, §4.2.1) and the
Markdown domain (for the report, whose verbs make Markdown blocks), and on no
other domain. It declares its root by hand, `abstract type
ResearchDocument`, as Workflow does, because its main view is a widget view. The
nine kinds of item have the abstract type `ResearchItem <: ResearchDocument`,
so a roster, a link and a method can name every item at once.

Every item has four common fields:

- `id::String`: the letter of its kind and a number, such as `H2`. The builder
  gives it: one more than the highest number of its kind in the study.
- `status::Symbol = :open`: `:open`, `:accepted` or `:rejected`. A decision has no
  status.
- `author::Symbol = :person`: who made the item, `:person` or `:assistant`.
- `time::String`: when the item was made, as a UTC text, `"2026-10-22T07:12:00Z"`.

The fields of each kind:

| Type | Id | Own fields |
| --- | --- | --- |
| `ResearchQuestion` | `Q` | `statement`, `criterion` (what would answer it), `purpose` (what the answer decides), `parent` (a wider question, or `nothing`) |
| `ResearchSource` | `S` | `citation`, `link` (a DOI, a URL or a file), `summary` |
| `ResearchHypothesis` | `H` | `statement`, `question` (the question that it answers), `prediction` (what a test must observe if the hypothesis holds), `basis` (items) |
| `ResearchExperiment` | `X` | `title`, `design` (the plan: prose, a workflow of steps, a run selection, an INI configuration), `tests` (hypotheses), `uses` (sources and results) |
| `ResearchAnalysis` | `N` | `title`, `method` (Julia code, a SQL query, a pivot, a formula sheet), `tests`, `uses` |
| `ResearchResult` | `R` | `title`, `content` (a table, a chart, a pivot, a number), `origin` (the experiment, the analysis or the source that made it) |
| `ResearchEvidence` | `E` | `statement` (the observation), `basis` (results and sources), `supports` (claims), `opposes` (claims) |
| `ResearchDecision` | `D` | `statement`, `reason`, `accepts` (items), `rejects` (items), `basis` (items) |
| `ResearchAnswer` | `A` | `statement`, `question` (the question that it answers), `caveats`, `basis` (items) |

- **A text field** (`statement`, `criterion`, `purpose`, `citation`, `summary`,
  `title`, `reason`, `caveats`) holds a `PrimitiveString` or any document, such as
  a Markdown node or a math expression, as the `text` of a workflow entry does. A
  `PrimitiveString` shows as text that takes an edit. Any other document shows
  through the view of its own domain.
- **A content field** (`prediction`, `design`, `method`, `content`) is `::Any`
  and holds a document of any domain, as the content of a workflow card does.
- **A link** holds the item itself. A field of one link holds an item or
  `nothing`. A field of many links is a `CellVector` of items, with no declared
  element type: the load of a file reads a marker into the list before it splices
  the item, and a list typed `ResearchItem` would refuse the marker. The words `basis` and
  `uses` are different on purpose: `basis` is what a claim rests on, and `uses` is
  what an activity reads.

```julia
abstract type ResearchDocument <: Document end
abstract type ResearchItem <: ResearchDocument end

@document struct ResearchHypothesis <: ResearchItem
    id::String                                   # "H1"
    statement::Any                               # a PrimitiveString or any document
    question::Any = nothing                      # the ResearchQuestion that it answers
    prediction::Any = nothing                    # prose, a math expression, a check
    basis::Vector{ResearchItem} = ResearchItem[]
    status::Symbol = :open
    author::Symbol = :person                     # :person or :assistant
    time::String                                 # "2026-10-22T07:31:00Z"
end

@document struct ResearchStudy <: ResearchDocument
    title::Any
    questions::CellVector = CellVector()
    sources::CellVector = CellVector()
    hypotheses::CellVector = CellVector()
    experiments::CellVector = CellVector()
    analyses::CellVector = CellVector()
    results::CellVector = CellVector()
    evidence::CellVector = CellVector()
    decisions::CellVector = CellVector()
    answers::CellVector = CellVector()
    report::Any = nothing                        # a Markdown page that tells the study in order
    author::Symbol = :person
    time::String
end
```

A study saves as one `.pred` file, as a workflow does. A document of a domain
with a file format, such as the Markdown page of the report or a JSON data set,
goes into a file of that format, and the study writes a marker to it. The
`report` is the page of the omnet study (§8): prose, and the items and other
documents that the page holds.

#### 4.2.1 The prediction that a check tests

The expectation of the omnet study moves here as a document that the
`prediction` of a hypothesis holds. It is a bound on recorded values:

```julia
@document struct ResearchExpectation <: ResearchDocument
    result_selection::Any = nothing     # what to read, such as a result selection of omnet-julia
    lower::Any = nothing                # a number, or nothing
    upper::Any = nothing
    reference::Any = nothing            # a FormulaFormula; the bounds are its value times 1 ∓ tolerance
    tolerance::Any = nothing
end
```

`check_predictions!(study, read)` reads the values that each expectation names,
with the function `read` that the caller gives, as `StudyCheck.jl` does today.
For each hypothesis whose prediction is an expectation, it adds evidence: the
statement says the observed mean and the bounds, `supports` holds the hypothesis
when every value is in the bounds, and `opposes` holds it when not. The
expectation keeps no status and no observed value: each check is a new item of
evidence, with its author and its time. So the study keeps every check, and not
only the last one.

### 4.3 Who and when

Each item records who made it and the time, once, when it is made. These are
`wasAttributedTo` and `generatedAtTime` of PROV. The field names and the values
are those of a workflow entry, `author` and `time`, so the two domains use one
vocabulary.

- **The author** is `:person` or `:assistant`, and nothing more. The owner decided
  this on 2026-10-22 (D1). A button of a view writes `:person`, and a verb writes
  `:assistant`, as in the Workflow domain. The record names no person either: my
  recommendation, because a window has one person.
- **The time** is UTC with a `Z`. So records from two places, and from the hour
  that a change of clock repeats, sort right. A view shows the local time. The
  Workflow domain keeps its local time.
- **A change of words is not recorded.** A person can correct the text of an item
  that the assistant made, and undo holds that change for the session. A change of
  sense is a new item or a decision. This is the rule of a lab notebook.
- **The runs of an experiment keep their own record** in their content: the run
  attributes of omnet-julia (`datetime`, the run id, the seed set). A result
  records who added it and when.

### 4.4 A link holds the item

The owner decided on 2026-10-22 that the documents contain each other. So an item
holds the items that it links to: `supports = [h1]` holds the hypothesis itself,
and a change of `h1` shows at once in each place that holds it. The id stays, for
people: a person writes "E3 supports H1" in prose, and a view shows the id beside
the statement.

- **The study owns each item in the list of its kind.** A link is a second place
  of the same object. The save writes an item at the first place that its walk
  reaches, and a marker at each other place (§2.1). The lists come first in the
  order of the work, so a link to an item of an earlier list is a marker to that
  list. A link to an item of a later list, such as the result that an experiment
  `uses`, writes the item in the link and a marker in the list. Both files load
  to the same graph.
- **A file that is saved alone writes the same graph.** Step 1 changes the save of
  one file, so the tab of a study saves its links as markers into itself, and the
  load of one file splices them.
- **A view draws an item once.** A card draws a link as one line, the id and the
  statement of the linked item, and not as a second card. A press on the line
  selects the item in its list.
- **A delete of an item that another item holds is refused**, and the refusal
  names those items. Otherwise the save would write the deleted item in the link,
  outside every list.

### 4.5 Only a decision changes a status

A decision holds the items that it accepts and rejects. The builder of a decision
inserts the decision and writes the status of each item that it holds, in one
`CompoundOperation`, so one undo takes both back. Nothing else writes a status.
The results:

- The status of an item is what the last decision about it said. The list of
  decisions is the history of every status: who decided, when and why.
- The status is on the item, so an item that stands alone, such as a vertex of
  the map or a block of a page, shows it with no search.
- A later decision supersedes an earlier one, as in an ADR. Nobody edits a
  decision to change its sense.
- The person decides with a button, and the assistant with `record_decision!`.
  The owner chose this on 2026-10-22 (D2). The card draws a decision of the
  assistant in the colour of the assistant, and a later decision of the person
  supersedes it.

Accept has one sense for each kind, and the view says it in that sense:

| Kind | accepted | rejected |
| --- | --- | --- |
| question | the study takes it on | out of scope |
| source | relevant and trusted | not used |
| hypothesis | the evidence supports it | refuted, or dropped |
| experiment, analysis | the plan is approved | not done |
| result | valid | not valid, such as a run with a fault |
| evidence | the observation is correct | not correct |
| answer | the answer of the study | not the answer |

### 4.6 An example

A person asks how large the buffer of a router must be. The assistant finds the
closed form, proposes a hypothesis, designs a sweep and runs it. The person
approves the sweep, accepts the hypothesis and writes the answer.

```julia
q1 = ResearchQuestion(id = "Q1",
    statement = "Which buffer is the smallest that keeps the drop rate under 1 % at a load of 0.8?",
    criterion = "the drop rate of each buffer size, with a 95 % confidence interval",
    purpose = "the buffer size that the router ships with",
    author = :person, time = "2026-10-22T07:12:00Z")
s1 = ResearchSource(id = "S1",
    citation = "Kleinrock, Queueing Systems, Volume I, 1975, section 3.6",
    summary = "The blocking of M/M/1/K in closed form.",
    status = :accepted, author = :assistant, time = "2026-10-22T07:20:00Z")
h1 = ResearchHypothesis(id = "H1", question = q1,
    statement = "A buffer of 13 packets is enough.",
    prediction = parse_math("P_block(13) < 0.01"), basis = [s1],
    status = :accepted, author = :assistant, time = "2026-10-22T07:31:00Z")
x1 = ResearchExperiment(id = "X1", title = "Sweep K = 1 … 20, 5 replications",
    design = runner_selection, tests = [h1],
    status = :accepted, author = :assistant, time = "2026-10-22T07:40:00Z")
n1 = ResearchAnalysis(id = "N1", title = "Blocking in closed form",
    method = formula_sheet, tests = [h1], uses = [s1],
    author = :assistant, time = "2026-10-22T07:44:00Z")
r1 = ResearchResult(id = "R1", title = "Drop rate by K",
    content = result_table, origin = x1,
    author = :assistant, time = "2026-10-22T07:46:00Z")
e1 = ResearchEvidence(id = "E1",
    statement = "At K = 13 the drop rate is 0.91 % ± 0.05 %.",
    basis = [r1], supports = [h1],
    status = :accepted, author = :assistant, time = "2026-10-22T07:52:00Z")
d1 = ResearchDecision(id = "D1", statement = "Run the sweep as designed.",
    accepts = [x1], author = :person, time = "2026-10-22T07:41:00Z")
d2 = ResearchDecision(id = "D2", statement = "A buffer of 13 packets is enough.",
    reason = "The interval of E1 is under the bound.",
    accepts = [h1, e1, s1], basis = [e1], author = :person, time = "2026-10-22T07:58:00Z")
a1 = ResearchAnswer(id = "A1", question = q1, statement = "13 packets.",
    caveats = "Poisson arrivals and exponential service only.", basis = [e1, d2],
    author = :person, time = "2026-10-22T08:05:00Z")

ResearchStudy(title = "The buffer of the access router",
    questions = [q1], sources = [s1], hypotheses = [h1], experiments = [x1],
    analyses = [n1], results = [r1], evidence = [e1], decisions = [d1, d2],
    answers = [a1], author = :person, time = "2026-10-22T07:12:00Z")
```

The `prediction` is a math expression, the `method` of `N1` is a formula sheet of
the Formula domain, the `design` of `X1` is a run selection of omnet-julia, and
the `content` of `R1` is a result table. Each one draws through the view of its
own domain inside the card of its item. The save writes `h1` once, in
`hypotheses`, and in `e1.supports` a marker such as
`node(file("buffer.pred"), "hypotheses[1]")`.

The timeline of this study, in local time (UTC+2):

| Time | Who | What |
| --- | --- | --- |
| 09:12 | person | Q1, a question |
| 09:20 | assistant | S1, a source |
| 09:31 | assistant | H1, a hypothesis for Q1 |
| 09:40 | assistant | X1, an experiment that tests H1 |
| 09:41 | person | D1 accepts X1 |
| 09:44 | assistant | N1, an analysis that tests H1 |
| 09:46 | assistant | R1, a result of X1 |
| 09:52 | assistant | E1 supports H1 |
| 09:58 | person | D2 accepts H1, E1 and S1 |
| 10:05 | person | A1 answers Q1 |

A1 and N1 stay open until a decision holds them.

### 4.7 What the model leaves out on purpose

- **A weight of evidence.** The statement of the evidence says how strong it is,
  with its interval.
- **A structured design of experiments** (factors, levels, responses). The design
  is any document. In omnet-julia the INI file and the run selection hold it.
- **A journal of comments on an item.** The statement of an item, the reason of a
  decision and a new item hold the prose.
- **An order of the work.** A plan is a resource and not a program, as in the
  Workflow domain. The person and the assistant add items in any order.

## 5. The views and the explorer

### 5.1 The outline and the card of an item

`ResearchItemToWidget` draws one item as a card, and `ResearchStudyToWidget`
draws a study as the cards of its items, as the outline of a workflow does. The
`__init__` of the module registers both as rows of the renderer. So a tab draws a
study, and an item draws as its card in any document that holds it: a Markdown
page, a workflow card, a dashboard card or a vertex of a graph.

- The card of an item: its first row holds the id, the status as a badge in the
  colour of its role, the statement, the author in a colour of its own, and the
  local time. Under that row stand the links, one line each with the name of the
  link, the id and the statement of the linked item ("supports H1 A buffer of 13
  packets is enough"), and the document of `prediction`, `design`, `method` or
  `content` through the view of its own domain.
- The outline: under the title stands one section for each kind, in the order of
  the work: questions, sources, hypotheses, experiments, analyses, results,
  evidence, decisions, answers. An empty section shows its add button only.
- A card of an item with a status has the buttons "Accept" and "Reject". A press
  makes a decision of the person that holds the item.
- An add button makes an item of the person with an empty statement. A button in
  a card links the new item to the card: "+ hypothesis" in the card of `Q1` makes
  a hypothesis whose `question` is `Q1`.
- A card folds. The fold is view state of the outline and not a field of the
  item, so the file of the study does not save it. Step 4 finds the place where
  the outline keeps it.

### 5.2 The map

`ResearchStudyToGraph` makes a `GraphGraph` of a study, as FSM and Process make
one, and the stages of the Graph domain lay it out and draw it. Each item of the
lists is a vertex whose content is the item, so it draws as its card. Each link
is an edge with the name of the link as its label: "addresses" from a hypothesis
or an answer to its question, "tests", "uses", "from", "supports", "opposes",
"accepts" and "rejects". This is the map of IBIS and of a discourse graph: a
person sees at one look which claims have evidence, and of which kind.

### 5.3 The timeline

The timeline is a roster and not a view of its own. The domain adds a source
and its columns to the roster slice:

- The source `StudyItems(study)` gives the items of the nine lists of one study,
  each once. A link does not give its item again.
- The columns `time`, `author`, `id`, `kind`, `status` and `statement`. The
  domain adds a method of `compute_roster_value` for `kind` and `statement`,
  which are not plain fields, and a method of `get_arrangement_value`, so a sort
  by time compares the times.

So the filter, the sort and the group of the arrangement work on it, as on any
collection:

```julia
show_roster!(StudyItems(study); title = "Timeline",
             columns = ["time", "author", "id", "kind", "status", "statement"],
             sort = ["time"])
```

The source `ItemsWithin(TabDocuments(ResearchStudy), ResearchItem)`, which
exists, gives the items of every study that a tab shows, so the same call gives
"every open hypothesis of every study". Step 6 checks that it gives an item that
two places hold as one row.

### 5.4 The explorer

- `is_explorer_entry_type(::Type{ResearchStudy}) = true`, so the "+" of a section
  offers a study.
- The children of a study in the tree are the items of its lists, in the order of
  the kinds. The label is the id and the statement, such as "H1 A buffer of 13
  packets is enough", and the decoration shows the status. The page of an item in
  the navigator is its card.
- A study opens in a tab of its own from the tree.
- The verb `start_study!` adds the new study to the explorer with
  `AddExplorerEntryOperation`, as `open_simulation_project!` adds a project in
  omnet-julia.

## 6. How a study combines with the other domains

A study does not repeat what another domain does. It holds the documents of the
other domains in its fields, and the other domains hold its items, by the rows of
§2.3. Three rules make this work:

1. **An item draws without its study.** It holds its status and its links (§4.4,
   §4.5), and its card view is a row of the renderer. So an item stands in a
   Markdown page, a workflow card, a dashboard card and a graph vertex, and draws
   the same there.
2. **A field of prose or content takes any document.** So a statement is a
   Markdown paragraph or a math expression when plain text is not enough, and the
   method of an analysis is Julia code, a SQL query, a pivot or a formula sheet.
3. **The general tools apply.** The save writes the graph, the roster and the
   arrangement give the timeline and every table of items, undo takes back every
   edit, and the explorer and the navigator show a study and its items.

**A workflow and a study divide the work.** A workflow records the work: the
steps, who does each one, and a choice of a way of work among options (a
`WorkflowDecision`). A study records the knowledge: the claims, their evidence,
and a judgement of the claims (a `ResearchDecision`). The two decisions are
different: one chooses a way, the other accepts or rejects an item. The two
documents hold each other: the step "Validate the model" of a workflow holds the
cards of `X2` and `E4`, and the `design` of an experiment holds the steps of its
procedure as a workflow.

**A report is a Markdown page.** The `report` of a study holds prose and the
items themselves, and saves a `pred-ref` fence for each item, as the page of the
omnet study does for its blocks. A change of an item shows in the report at once.
A tab of a study shows the outline, and a second tab shows the report.

## 7. The assistant

### 7.1 The verbs

Each verb takes the study, or a `ReferencedDocument` of it, as its subject. It
makes the operation of a builder and lets the readers of the editor carry it from
the item to the root, as the verbs of the workflow do, so undo records it. Each
verb writes `author = :assistant`. A verb that adds an item answers the item, so
that the next call can link to it. Where a verb takes a link, it takes the item
or its id: `supports = ["H1"]` finds `H1` in the study and holds the item. An id
that does not exist is refused with an `ArgumentError` that names it.

| Verb | What it does |
| --- | --- |
| `start_study!(title; question)` | makes a study, opens it in a tab and adds it to the explorer |
| `add_question!(study, statement; criterion, purpose, parent)` | adds a question |
| `add_source!(study, citation; link, summary)` | adds a source |
| `add_hypothesis!(study, statement; question, prediction, basis)` | adds a hypothesis |
| `add_experiment!(study, title; design, tests, uses)` | adds an experiment |
| `add_analysis!(study, title; method, tests, uses)` | adds an analysis |
| `add_result!(study, title, content; origin)` | adds a result |
| `add_evidence!(study, statement; basis, supports, opposes)` | adds evidence |
| `record_decision!(study, statement; accepts, rejects, basis, reason)` | records a decision and writes the statuses |
| `add_answer!(study, statement; question, caveats, basis)` | adds an answer |
| `check_predictions!(study, read)` | checks each expectation and adds evidence (§4.2.1) |
| `add_study_section!(study, heading, prose)`, `add_study_prose!(study, prose)`, `embed_in_study!(study, documents...)` | grow the report, as the verbs of the omnet study grow its page today |
| `add_study_formula!(study, name, text)` | adds a formula to the sheet of the analysis "Closed form" |
| `save_study_folder!(study, directory)`, `load_study_folder(directory)` | write and read a folder: one file for each block, through a `FileProject`, as `StudyFile.jl` does today |
| `describe_study(study)` | the outline as text: one line for each item, with its id, status, statement, links, author and time |
| `find_study_item(study, id)` | the item, as a referenced document |

The docstring of `record_decision!` tells the assistant to record a decision only
when the person asks for it (D2).

The timeline, the tables of items and the map need no verb of their own:
`show_roster!` with the source `StudyItems` gives the first two, and the docstring
of `ResearchStudy` shows the call. An item goes into a Markdown page, a workflow
card or a dashboard card through the verbs of those domains.

`add_study_section!`, `add_study_prose!`, `embed_in_study!` and
`add_study_formula!` are verbs of the omnet study, which move here (§8). No other
name of the table exists in either repository (checked 2026-10-22). One name is
one function: a verb that both repositories need is a function of this domain,
and omnet-julia adds a method to it only for a type of its own. So the names of
the verbs of the window of omnet-julia (`make_study!`, `open_study!`,
`save_study!`, `check_expectations!`) are not names of this domain.

The `__init__` calls `register_assistant_api!(ResearchModule =>
RESEARCH_ASSISTANT_API)` and registers the sentence of the domain for the system
text. Each verb carries its docstring on its generic function, with "Use it to",
an example and "See also". The docstrings say when to record: when a point
matters to the study, not at each turn, as the owner decided for the workflow on
2026-10-09.

### 7.2 Who calls a verb

A verb does not know who calls it (§2.1), and the plan adds no mechanism for it
(D1). A verb writes `author = :assistant`, and a button of a view writes
`:person`, as in the Workflow domain. A person who calls a verb in code records
as the assistant, which is the limit that the Workflow domain has too.

## 8. omnet-julia: the study of the IDE merges into this domain

The owner decided on 2026-10-22 that the study of omnet-julia merges into this
domain (D3). After the merge, omnet-julia has no study documents of its own: a
study in the IDE is a study of this domain, and omnet-julia adds what is about a
simulation.

### 8.1 Where each part of the omnet study goes

| The omnet study today | After the merge |
| --- | --- |
| `StudyStudy(title, question, expectations, findings, formulas, page)` | the study of §4.2 |
| `StudyQuestion(statement, answer, decision)` | a question: `answer` becomes `criterion`, and `decision` becomes `purpose` |
| `StudyExpectation(statement, result_selection, lower, upper, reference, tolerance, status, observed)` | a hypothesis with the `statement`, whose `prediction` is an expectation of §4.2.1; `status` and `observed` become the evidence of each check |
| `StudyFinding(statement, evidence)` | evidence when it states an observation, or an answer when it states a conclusion; each table, plot or run card of its `evidence` becomes a result that its `basis` holds |
| `formulas`, a `FormulaEnvironment` | the `method` of an analysis "Closed form"; an expectation holds a formula of it as its `reference` |
| `page`, a `MarkdownRoot` | the `report` |
| a run card on the page | the `design` of an experiment, and a block of the report |
| a table or a plot on the page | the `content` of a result, and a block of the report |
| a NED or an INI file on the page | a block of the report, as today |

The example of §4.6 is the study of the recorded video in the new form. After
the merge, the prediction of `H1` is an expectation whose `reference` is the
blocking formula of the sheet of `N1`, and a check adds `E1`.

### 8.2 What moves and what stays

**What moves to projectured-julia**, into the domain of this plan:

- the documents, by the table of §8.1;
- the check of `StudyCheck.jl`, as `check_predictions!(study, read)` (§4.2.1);
- the folder of `StudyFile.jl`, as `save_study_folder!(study, directory)` and
  `load_study_folder(directory)`: one file for each block, through a
  `FileProject`;
- the verbs that grow the page, `add_study_section!`, `add_study_prose!` and
  `embed_in_study!`, which take the study and grow its `report`;
- `add_study_formula!(study, name, text)`, which writes into the sheet of the
  analysis "Closed form" and makes that analysis when the study has none;
- the view: the outline of §5.1 replaces `StudyToWidget.jl` and
  `StudyGraphics.jl`.

**What stays in omnet-julia**, in `OmnetIde` (`StudyVerbs.jl`): the verbs of the
study of the window and of the files of a simulation.

- `make_study!(; title, question)` makes a study of this domain in the folder of
  the window, writes the project descriptor, and opens the outline and the report
  beside the conversation.
- `get_study()`, `open_study!()` and `save_study!()` find, load and save the study
  of the window, through the folder functions of the domain. `open_study!()` calls
  `place_study_blocks!`, which now walks the designs of the experiments, the
  contents of the results and the report.
- `check_expectations!()` checks the study of the window: it calls
  `check_predictions!` with the reader of the result files of the window.
- `write_ned_file!`, `write_ini_file!`, `write_study_file!`, `make_run_card` and
  `run_card!` stay as they are.
- `add_expectation!` and `add_finding!` go. The guide writes `add_hypothesis!`
  with an expectation as its prediction, and `add_evidence!` or `add_answer!`.

**One name is one function** (§7.1). The verbs of the window keep their names,
because the guide, the recording script and the tests use them, and the domain
does not use those names. A verb of the domain takes the study as its subject; a
verb of the window finds the study of the window and calls it.

**What goes.** The packages `OmnetStudy`, `OmnetStudyPresentation`,
`OmnetStudyTest` and `OmnetStudyPresentationTest`, and their places in the
environments, the CI and the precompile statements. `OmnetIde` depends on the
package of this domain.

**A folder of the old format does not load.** No loader of the old types is
made. The folders of the examples and of the tests are made again by the
scripted session.

## 9. The decisions

Every decision is made.

- **D1. The agent of a call. Decided by the owner, 2026-10-22: no new
  mechanism.** The record says `:assistant` with no model, provider or version:
  "it's ok storing that the assistant made it, otherwise we open a whole new set
  of worms". I had recommended a scoped value that names the model of the caller.
- **D2. May the assistant record a decision? Decided by the owner, 2026-10-22:
  yes**, option (a): the assistant has `record_decision!`, the record says that the
  assistant decided, and a later decision of the person supersedes it.
- **D3. The study of omnet-julia. Decided by the owner, 2026-10-22: (b), merge it
  in this plan:** "I choose (b), so the old study domain in omnet IDE is merged
  into this one". §8 says how. I had recommended (a), to keep it and merge it in a
  later plan.
- **D4. The name of the domain. Decided by the owner, 2026-10-22: Research.** The
  package is `ProjecturedResearch`, the code is in `source/domain/research/`, the
  root is `ResearchStudy`, and each type carries the prefix `Research`. The owner
  asked first for another name than workbench, then for my suggestion with no
  regard to the users of the old study, and agreed to it. The reasons:
  - The types are the standard terms of the books on method: research question,
    research hypothesis, research design. EXPO has `ResearchHypothesis`. A person
    and a model that searches the API guess a type from a term that they know.
  - The root reads as a phrase, a research study, and does not double the name as
    `StudyStudy` or `InquiryInquiry` would.
  - The word is common for a reader whose first language is not English, and
    "inquiry" is not.
  - It names the content, and not the tool, as "workbench" does.
  - Against it: the word can sound academic. The names of the types say what each
    item is, so a person who looks for the cause of a slow frame finds the same
    types.
  - No type in either repository starts with `Research` (checked 2026-10-22).

## 10. The steps

Each step is a commit in a worktree of projectured-julia, and steps 10 and 11 are
commits in a worktree of omnet-julia. Each step names its narrowest test.

- [x] **1. A file that is saved alone writes a graph.** In the serialization
  slice of the platform: `save_file!` writes a node that its file holds at two
  places, and a cycle, as a marker into the file itself, as `save_project!` does;
  it still refuses a node that another file owns. `load_file` splices the markers
  that name its own file, and keeps the others as leaves. This holds for every
  format, `.pred` included. Test: in `FileProjectTest.jl`, the two tests "a shared
  subtree is rejected" and "a cycle is rejected" become tests that the file saves
  and loads to the same graph, in JSON and in `.pred`; a node of another file is
  still refused.
  **Done (2026-10-22, branch `research`).** `load_file` already loads its file as
  a project of one file, so it splices a marker that names the file itself; it
  needed no change. The save needed one: in `_cut_copy` (`FileCut.jl`), a node met
  a second time is a marker into the file itself in both saves, and only a cut
  into another file stays an error of the strict save. The docstrings of
  `save_file!` and `load_file` and serialization.md say so. `test_file_project()`:
  153 pass, 1 broken (the marker that main has too); the two refusal tests are now
  round trips in JSON, and two new tests save a shared document and a cycle in a
  `.pred` file alone, load them, and save again with no change of the file.
- [x] **2. The package triad and the documents.** `ProjecturedResearch`,
  `…Example` and `…Test`; the types of §4.2 and §4.2.1; the edges to
  `ProjecturedGraph` and `ProjecturedFormula`; the
  lists of the full set that domain-inventory.md names, and the four places that
  the workflow plan found beside them (the CI matrix, `DOMAIN_EDGES`,
  `ProjecturedSuite`, `PROJECTURED_PACKAGES`). Test: `test_research_document()`:
  the example of §4.6 saves alone and in a project with a Markdown summary in a
  file of its own, and loads with `e1.supports[1] === h1`; the layering guard and
  the naming guard.
  **Done (2026-10-22).** `ResearchDocument.jl` holds the eleven types, the kinds
  (`RESEARCH_KINDS`: the field, the type, the letter and the name of each kind), the
  UTC time (`get_research_time`, `format_research_time`, `find_research_time`) and
  `collect_study_items`. What was decided and found:
  - A list of links is an untyped `CellVector`, as §4.2 now says.
  - The package also depends on `ProjecturedMarkdown`, for the report (step 8), so
    `DOMAIN_EDGES` names Formula, Graph and Markdown.
  - In the example, K is the capacity of the queue beside the packet in service,
    so the blocking is (1 - ρ) ρ^(K+1) / (1 - ρ^(K+2)): 0.91 % at K = 13, as the
    evidence says.
  - The registration found no place beyond the ten of the guide and the workflow
    plan. The atoms of the catalog come with the example registry in step 4,
    which needs the projection of that step.
  - The study saves alone and in a project; the second save of the same study
    writes no byte. `test_research_document()`: 45 pass. The naming guard passes.
- [x] **3. The builders and the status.** Insert an item with its id, author and
  time; delete an item, refused when another item holds it; record a decision,
  which inserts it and writes the statuses in one `CompoundOperation`. A builder
  takes `author` and `time`, so a test fixes both. Test: `test_research_edits()`:
  each builder and its undo through an `UndoBuffer`, a refused delete, and a
  decision that supersedes another.
  **Done (2026-10-22).** `ResearchEdits.jl`: `make_research_id`,
  `make_research_item`, `make_add_research_item_operation`,
  `make_delete_research_item_operation`, `make_record_decision_operation`, and the
  readers `find_study_item`, `collect_research_links` and
  `collect_research_item_holders`. What was decided:
  - `make_research_item` takes a link as an item or as its id and holds the item,
    so the buttons of the outline and the verbs of step 8 share one place that
    finds an id. An id that the study does not hold, a field that the kind does not
    have, and an author that is not `:person` or `:assistant` are an
    `ArgumentError`.
  - A delete is refused when another item links to the item or the report holds
    it; the message names the holders, such as "H1 is held by X1, N1, E1, D2".
  - A decision names only items of the study that have a status, and never one
    item both to accept and to reject.
  - `find_study_item(study, id)` answers the item itself; step 8 adds the method
    for a `ReferencedDocument`.
  `test_research_edits()`: 36 pass.
- [x] **4. The card and the outline.** §5.1. Test:
  `test_research_study_to_widget()` through a headless editor that keeps its IO
  map, the printer, reader and REPL drivers on `research_example`, a press on
  "Accept" that makes a decision of the person, a card whose statement is a
  Markdown paragraph, and a change of `h1` that shows in the link line of `e1`.
  **Done (2026-10-22).** `ResearchTheme.jl` and `ResearchToWidget.jl`:
  `ResearchItemToWidget` draws one item as a card, and `ResearchStudyToWidget`
  draws the outline. What was decided and found:
  - The card of an item needs no study. The buttons that need the study (Accept,
    Reject, the fold, an item linked to this one) stand in the row of the outline
    around the card.
  - The fold is the field `folded` of the study, the ids of the folded cards: view
    state, written by `ReplaceViewStateOperation`, which a history does not
    record, and left out of the file by `pred_arguments`, as the omnet study does
    with `follow_end`.
  - A link draws as one line with the word of the link, the id and the text of the
    linked item (`describe_research_link`), and an expectation as one line
    (`describe_research_expectation`).
  - The helpers of the slots follow those of the workflow outline; the two domains
    do not depend on each other.
  - `research_example` joins both registries and the navigation skip list, and the
    atoms of the eleven types join the catalog. The printer, reader and REPL drivers
    pass on `research_example` (30865, 230 and 230 checks). The navigation and the
    type-in drivers do not apply to a widget view, as for the workflow: the sweeps
    run them on the text examples only.
  - The test is `test_research_to_widget()`, not `test_research_study_to_widget()`,
    because it covers the card too.
- [x] **5. The map.** §5.2. Test: `test_research_study_to_graph()`: the vertices
  and the labelled edges of the example, and an edge that follows a new link.
  **Done (2026-10-22).** `ResearchMapToGraph.jl`. The map is a document of its
  own, `ResearchMap(study)`, as the journal of a workflow is, because the renderer
  has one row for each type and the row of a study is its outline.
  `ResearchMapToGraph` makes the graph, `ResearchMapPartToWidget` draws each vertex
  as the id, the status and the text and each edge label as a word, and the stages
  of the Graph domain lay it out (`make_research_map_projection`). A place of an
  item maps from `.study.hypotheses[1]` to `.vertices[3].content` and back.
  `ResearchMapToGraph` is a plain struct: `@projection` on a struct with no field
  gives an expression that a docstring can not document. The atom `map` joins the
  catalog. The test is `test_research_map_to_graph()`, 16 pass.
- [x] **6. The timeline.** §5.3. Test: a roster of `StudyItems` sorted by time
  gives the rows of §4.6 in order, a filter on the author keeps the rows of the
  assistant, and a new item shows as a new row.
  **Done (2026-10-22).** `ResearchRoster.jl`: the source `StudyItems(study)`, and
  the facets `kind` and `text` of an item. The column `text` replaces `statement`
  of §5.3, because an experiment has a title and a source a citation. The `time` is
  a UTC text in ISO form, so it sorts as a text and needs no method of
  `get_arrangement_value`. `ItemsWithin(CollectionItems(…), ResearchItem)` gives
  each item of a study once, an item that a link holds too. `test_research_roster()`:
  11 pass.
- [x] **7. The explorer.** §5.4. Test: a study entry shows its items with their
  ids and statuses, the "+" of a section offers a study, and a study opens in a
  tab.
  **Done (2026-10-22).** `ResearchExplorer.jl`: the children of a study are the
  items of its nine lists (`get_tree_children_steps`); the label is the id and the
  text; the decoration is the glyph of the kind, the status as a count and the
  author as the detail. `"study"` is the alias of the insertion, so the `+` of a
  section offers a new study. `test_research_explorer()` passes; step 9 opens a
  study in a tab of a window.
- [ ] **8. The verbs, the check, the report, the folder and the sentence.** §7.1,
  §4.2.1. Test: `test_research_assistant_api()`: the offered names, a search that
  finds a verb, and code run by `execute_julia_code!` that adds a question, a
  hypothesis, evidence that supports the hypothesis by its id, and a decision,
  each with `author = :assistant`; undo takes them back. `test_research_check()`:
  a check with a stub reader adds evidence that supports a hypothesis whose values
  are in the bounds and opposes one whose values are not, and a second check adds
  a second item of evidence. `test_research_folder()`: a study with a report
  saves to a folder, one file for each block, and loads to the same graph; a
  second save writes no file.
- [ ] **9. The combinations.** §6, in the umbrella test package, because its
  fixtures name several domains. Test: `test_research_combinations()`: a Markdown
  report that holds `H1` saves a `pred-ref` fence, loads and draws the card; a
  workflow step whose card holds `X1`; an analysis whose method is a formula sheet
  and a result whose content is a pivot.
- [ ] **10. omnet-julia: the study of the IDE is a study of this domain.** §8.2:
  `StudyVerbs.jl` keeps the verbs of the window and of the files of a simulation
  over the documents of this domain; `place_study_blocks!` walks the new study;
  the four packages of the old study go, with their places in the environments,
  the CI and the precompile statements. Test: `test_study_verbs()`,
  `test_study_runs()` and `test_assistant_study_by_hand()` pass on the new
  documents, and the study by hand ends with `H1` accepted on evidence from a
  check against the real `opp_run`.
- [ ] **11. omnet-julia: the guide, the system text, the rehearsal and the
  recording script.** The study sections of `assistant-guide.md` write the verbs
  of §7.1 and §8.2; `STUDY_GUIDE_SECTIONS`, `STUDY_TURNS` and
  `tool/assistant/study_rehearsal.jl` follow them. Test:
  `test_study_recording_script()`, and `test_assistant_study()`, which skips
  without a local model.
- [ ] **12. The design documents.** `documentation/package/domain/research/research.md`;
  the change of serialization.md for step 1; the rows of domain-inventory.md; in
  omnet-julia, `documentation/package/study/study.md` says what the IDE adds to a
  study of this domain; the plan to `plan/done/`.

## 11. Not in this plan

A structured design of experiments; a weight of evidence; comments on an item;
the conversation turn that made an item; the model, the provider or the version
of an assistant (D1); the name of a person; an id in prose that a view draws as a
link to its item; the history of the words of an item through the versioning
slice; one type of stamp that the Workflow and the Research domains share; a loader of the
saved folders of the old omnet study; a new recording of the study video.
