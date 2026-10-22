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
"""
module ResearchModule

import Dates

using ..KernelModule
using ..PlatformModule
using ..FormulaModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title

export ResearchDocument, ResearchItem, ResearchStudy, ResearchQuestion, ResearchSource,
       ResearchHypothesis, ResearchEvidence, ResearchDecision, ResearchAnswer, ResearchExperiment,
       ResearchAnalysis, ResearchResult, ResearchExpectation, RESEARCH_KINDS, RESEARCH_STATUSES,
       RESEARCH_AUTHORS, get_research_kind, has_research_status, collect_study_items,
       format_research_time, get_research_time, find_research_time, get_research_item_text
export find_study_item, collect_research_links, make_research_id, make_research_item,
       make_add_research_item_operation, collect_research_item_holders,
       make_delete_research_item_operation, make_record_decision_operation

include("ResearchDocument.jl")
include("ResearchEdits.jl")

end # module
