"""
    ResearchModule

The research document domain: the record of a study, the work on one problem by
the scientific approach, from the question to the answer. A study holds nine
kinds of item: questions, sources, hypotheses, experiments, analyses, results,
evidence, decisions and answers. Each item records who made it, the person or the
assistant, and when. An item holds the items that it links to, and only a
decision changes the status of an item.

The domain includes:
- **The study**: `ResearchStudy`, which owns each item in the list of its kind
- **The items**: `ResearchQuestion`, `ResearchSource`, `ResearchHypothesis`,
  `ResearchExperiment`, `ResearchAnalysis`, `ResearchResult`, `ResearchEvidence`,
  `ResearchDecision`, `ResearchAnswer`
- **The prediction that a check tests**: `ResearchExpectation`
- **The views**: the outline of a study and the card of an item, and
  `ResearchMap`, the items of a study as a graph
"""
module ResearchModule

import Dates

using ..KernelModule
using ..PlatformModule
using ..FormulaModule
using ..GraphModule
using ..MarkdownModule
using ..MathModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title, get_view_state_fields
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..RosterModule: collect_roster_parts, collect_roster_items, get_roster_item_type,
                       get_item_facets, compute_item_facet
import ..TreeModule: get_tree_children_steps, format_tree_node_label, is_explorer_entry_type
import ..DomainModule: get_document_decoration, get_insertion_aliases, make_insertion_document,
                       make_pasted_document_operation, insertable

export ResearchDocument, ResearchItem, ResearchStudy, ResearchQuestion, ResearchSource,
       ResearchHypothesis, ResearchEvidence, ResearchDecision, ResearchAnswer, ResearchExperiment,
       ResearchAnalysis, ResearchResult, ResearchExpectation, ResearchDecisionDraft, RESEARCH_KINDS, RESEARCH_STATUSES,
       RESEARCH_AUTHORS, get_research_kind, has_research_status, collect_study_items,
       format_research_time, get_research_time, find_research_time, get_research_item_text
export find_study_item, collect_research_links, make_research_id, make_research_item,
       make_add_research_item_operation, collect_research_item_holders,
       make_delete_research_item_operation, make_record_decision_operation
export ResearchTheme, ScaledResearchTheme
export ResearchItemToWidget, ResearchStudyToWidget, make_research_projections, make_research_graphics_entries,
       ResearchToWidgetIoMap, describe_research_link, describe_research_expectation
export ResearchMap, ResearchMapToGraph, ResearchMapToGraphIoMap,
       make_research_map_projection
export StudyItems
export RESEARCH_ASSISTANT_API, start_study!, add_question!, add_source!, add_hypothesis!,
       add_experiment!, add_analysis!, add_result!, add_evidence!, add_answer!, record_decision!,
       get_expectation_bounds, check_predictions!, add_study_section!, add_study_prose!,
       embed_in_study!, add_study_formula!, describe_study
export RESEARCH_STUDY_FILE_NAME, RESEARCH_REPORT_FILE_NAME, RESEARCH_CONVERSATION_FILE_NAME, collect_study_blocks,
       save_study_folder!, load_study_folder

include("ResearchDocument.jl")
include("ResearchEdits.jl")
include("ResearchTheme.jl")
include("ResearchToWidget.jl")
include("ResearchMapToGraph.jl")
include("ResearchRoster.jl")
include("ResearchExplorer.jl")
include("ResearchVerbs.jl")
include("ResearchFolder.jl")

function __init__()
    # The rows that let the renderer draw a study as its outline, and an item of
    # one as its card inside any other document.
    register_natural_graphics!(:research, make_research_graphics_entries)

    # What the model of an assistant may write about a study: the documents, the
    # verbs that write it as the assistant, and the reads of a study. Each verb is
    # an edit of the editor, which a person takes back with Ctrl+Z.
    register_assistant_api!(ResearchModule => RESEARCH_ASSISTANT_API;
        description = "A study records the work on one problem by the scientific approach: " *
                      "questions, sources, hypotheses, experiments, analyses, results, evidence, " *
                      "decisions and answers, each with an id such as H1, its author and its time. " *
                      "`start_study!` makes one; `add_question!`, `add_hypothesis!`, `add_evidence!` " *
                      "and the other `add_` verbs add an item that links to others by item or id; " *
                      "`record_decision!` accepts or rejects items, only when the person asks; " *
                      "`add_element!` adds a document of any domain, such as code or a table, to an item; " *
                      "`describe_study` reads it, and `show_roster!(StudyItems(study); sort = [\"time\"])` " *
                      "shows its timeline.")
end

end # module
