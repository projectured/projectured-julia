# Research domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [workflow.md](../workflow/workflow.md), [roster.md](../../platform/roster/roster.md), [serialization.md](../../platform/serialization/serialization.md)

The Research domain, `ProjecturedResearch`, holds the record of a study: the work on one problem by the scientific approach, from the question to the answer. A study holds questions, sources, hypotheses, experiments, analyses, results, evidence, decisions and answers. Each item records who made it, the person or the assistant, and when. A person and the assistant write into the same record. This document says where the domain differs from the [shape of every domain](../../../design/domain-anatomy.md).

## How it works

### The documents

A study is one document, `ResearchStudy`, that owns each of its items in the list of its kind. The nine kinds come from the literature on scientific argument and provenance: a discourse layer (question, hypothesis, evidence, decision, answer, source) and a process layer (experiment, analysis, result). The plan of the domain gives the sources: `plan/done/a-study-records-questions-evidence-and-decisions.md`.

| Type | Id | Fields that matter |
| --- | --- | --- |
| `ResearchQuestion` | `Q` | `statement`, `criterion` (what would answer it), `purpose` (what the answer decides), `parent` |
| `ResearchSource` | `S` | `citation`, `link`, `summary` |
| `ResearchHypothesis` | `H` | `statement`, `question`, `prediction`, `basis` |
| `ResearchExperiment` | `X` | `title`, `design`, `tests`, `uses` |
| `ResearchAnalysis` | `N` | `title`, `method`, `tests`, `uses` |
| `ResearchResult` | `R` | `title`, `content`, `origin` |
| `ResearchEvidence` | `E` | `statement`, `basis`, `supports`, `opposes` |
| `ResearchDecision` | `D` | `statement`, `reason`, `accepts`, `rejects`, `basis` |
| `ResearchAnswer` | `A` | `statement`, `question`, `caveats`, `basis` |

Every item also has an `id`, such as `H2`, an `author`, `:person` or `:assistant`, and a `time`, a UTC text such as `"2026-10-22T07:12:00Z"`. Every item but a decision has a `status`: `:open`, `:accepted` or `:rejected`. `RESEARCH_KINDS` gives the field, the type, the letter and the name of each kind. The abstract type `ResearchItem` names every item at once.

- **A text field** (`statement`, `title`, `citation`, `criterion`, `purpose`, `summary`, `reason`, `caveats`) holds a `PrimitiveString` or a document of any domain, such as a Markdown paragraph or a math expression.
- **A content field** (`prediction`, `design`, `method`, `content`) holds a document of any domain: a run selection, a workflow of steps, Julia code, a formula sheet, a pivot, a chart.
- **A link** holds the item itself, and a list of links is an untyped `CellVector`. A person writes the id in prose, "E3 supports H1", and a verb takes a link as an item, as the part of the window that another verb answered, or as its id.
- **A prediction that a check tests** is a `ResearchExpectation`: a bound on recorded values, with `lower` and `upper`, or a `reference` formula and a `tolerance`.

The `report` of a study is a Markdown page with the story of the study in order, which holds items and other documents. The `folded` field is view state of the outline and is not saved.

### Who and when

An item records its author and its time once, when it is made. A button of a view writes `:person`, and a verb writes `:assistant`; the record says nothing of the model of an assistant. A change of the words of an item is not recorded, and undo holds it for the session. A change of sense is a new item or a decision.

### Only a decision changes a status

`make_record_decision_operation(study, decision)` inserts the decision and writes the status of each item that it accepts or rejects, in one `CompoundOperation`, so one undo takes both back. Nothing else writes a status. The list of decisions is the history of every status, and a later decision supersedes an earlier one. A decision names only items of the study that have a status.

### The edits

Each edit is a builder over the generic write, as [operation.md](../../kernel/operation.md) asks.

| Builder | What it does |
| --- | --- |
| `make_research_item(study, type; author, time, fields...)` | a new item with the next id of its kind; a link given as an id holds the item; the id and the status are no fields to give |
| `make_add_research_item_operation(study, item)` | appends an item to the list of its kind |
| `make_delete_research_item_operation(study, item)` | removes an item and its fold; it throws an `ArgumentError` when another item holds the item, by a link or inside a document of a field, or when the report holds it |
| `make_record_decision_operation(study, decision)` | records a decision and writes the statuses |

### The file

A study saves as a `.pred` file. An item that a link holds is written once, in its list, and a marker such as `node(file("buffer.pred"), "hypotheses[1]")` stands at each other place; this holds for a file saved alone too. `save_study_folder!(study, directory)` writes a folder: `study.pred` first, so it owns every item and every document that a `.pred` file writes, such as a formula sheet or a workflow of steps; the report as `study.md`; and each node of a text format that an item holds outside the report, such as a Markdown statement or a math prediction, in a file of its format named by the id and the field, such as `h2-statement-1.md`. A file document, such as a configuration file, keeps its own name, and two files of one name are refused. `load_study_folder(directory)` reads the folder back to the same graph. A `.pred` file of its own for each design or result would own the items that it reaches, so the study file would hold only markers to them.

### The views

- **The outline.** `ResearchStudyToWidget` draws the title and a section for each kind, in the order of the work. `ResearchItemToWidget` draws one item as a card: the id, the status as a badge, the text, the author and the local time, a line for each link, and its content through the view of its own domain. The card needs no study, so an item draws the same in a Markdown page, a workflow card, a dashboard card or a vertex of a graph. The buttons that need the study stand in the row of the outline around the card: "Accept" and "Reject", which record a decision of the person, the buttons that add an item linked to the card, and the fold.
- **The map.** `ResearchMap(study)` is a second view. `ResearchMapToGraph` makes a `GraphGraph` with a vertex for each item and an edge for each link, labelled with the word of the link, and the stages of the Graph domain lay it out (`make_research_map_projection`).
- **The timeline.** A roster of `StudyItems(study)`, sorted by the `time`, with the facets `kind` and `text`. The filter, the sort and the group of the arrangement work on it as on any collection.
- **The explorer.** A study is an entry whose children are its items, each named by its id and its text and decorated with the glyph of its kind, its status and its author. A study is one of the kinds that the `+` of a section adds.

### The assistant

The `__init__` calls `register_assistant_api!(ResearchModule => RESEARCH_ASSISTANT_API)` with the sentence of the domain. Each verb takes the study, or a `ReferencedDocument` of it, writes as the assistant, and lets the readers of the editor carry its operation from the study to the root, so the history of the tab records it.

| Verb | What it does |
| --- | --- |
| `start_study!(title; question)` | makes a study, adds it to the explorer, opens it in a tab, and answers the study as the part of the window that the tab shows |
| `add_question!`, `add_source!`, `add_hypothesis!`, `add_experiment!`, `add_analysis!`, `add_result!`, `add_evidence!`, `add_answer!` | add an item and answer it |
| `record_decision!(study, statement; accepts, rejects, basis, reason)` | records a decision; the docstring says to call it only when the person asks |
| `check_predictions!(study, read)` | reads and bounds every expectation, then adds evidence that supports or opposes each hypothesis; an expectation that can not be checked changes nothing |
| `add_study_section!`, `add_study_prose!`, `embed_in_study!` | grow the report |
| `add_study_formula!(study, name, text)` | adds a formula to the sheet of the analysis "Closed form", as an edit of the history |
| `describe_study`, `find_study_item` | read a study |
| `save_study_folder!`, `load_study_folder` | write and read a folder |

A verb names the field of the study that it writes when it reroots its operation, because `find_rooted_operation` needs a place between the root and the edited node, and a study can be the whole content of a history.

## How it fits

`ProjecturedResearch` depends on the kernel, the platform, `Dates`, and the domains Formula (the reference of an expectation, the closed form), Graph (the map), Markdown (the report) and Math (`parse_math`). No domain depends on it; a simulator can build its simulation study on it.

The Workflow domain and this one divide the work. A workflow records the work: the steps, who does each, and a choice of a way among options. A study records the knowledge: the claims, their evidence and a judgement of them. Each holds the other: a workflow card holds an item, and the design of an experiment holds a workflow.

## Design decisions

- **Status is the result of decisions.** A status on the item keeps a view of one item local, and the decisions keep who decided, when and why, as an ADR does.
- **Links hold the items.** The save writes a graph, so a link needs no key to resolve; the id is for people.
- **Evidence is apart from the claim.** An observation supports or opposes a claim; the same result can be the basis of evidence about two hypotheses.
- **No new mechanism.** The author is the kind of agent only; the record names no model.
- **The timeline is a roster.** The general table, filter and sort serve it; no view of its own exists.

## Usage

```julia
study = make_research_study_document_example()
run_example(study, make_research_projection_example(); name = "research")
evidence = make_research_item(study, ResearchEvidence; author = :assistant,
                              statement = "At K = 12 the drop rate is 1.13 %.", basis = ["R1"], opposes = ["H1"])
evaluate_operation(nothing, make_add_research_item_operation(study, evidence))
describe_study(study)
```

- Examples: `research_example`, and the atoms of each type and of the map.
- Test: `test_research()` runs the layering guard, the documents, the edits, the outline, the map, the roster, the explorer and the verbs. `test_research_combinations()` of the umbrella holds items in a report, a workflow card and a window.

## Limits

- A card shows a link as a line; a press on the line does not select the linked item.
- A pivot or a table as content needs a pane with a height around it, as the pivot domain says.
- The navigation and type-in drivers do not apply to the outline, which is a widget view.
- The next item of a kind takes one more than the highest number of its kind, so after a delete of the item with the highest number the id comes back.
