# Fragment of `ResearchModule` — a study in the explorer: an entry whose children
# are its items, in the order of the kinds, each named by its id and its text and
# decorated with its kind, its status and its author.

get_tree_children_steps(::ResearchStudy) =
    Tuple((FieldReferenceStep(String(kind.field)),) for kind in RESEARCH_KINDS)

format_tree_node_label(study::ResearchStudy) = get_document_title(study)
format_tree_node_label(item::ResearchItem) =
    item.id * " " * _get_plain_text(get_research_item_text(item))

# The glyph of each kind of item, from the table of the icons.
const _RESEARCH_ICONS = Dict(:questions => :circle_help, :sources => :scroll_text,
                             :hypotheses => :diamond, :experiments => :circle_play,
                             :analyses => :sigma, :results => :chart, :evidence => :crosshair,
                             :decisions => :check, :answers => :circle_check)

get_document_decoration(study::ResearchStudy) =
    DocumentDecoration(; icon = :layers,
                       counts = [DocumentCount(string(length(collect_study_items(study))))],
                       tooltip = () -> TooltipNote(; title = get_document_title(study),
                           facts = [_get_section_title(kind) => string(length(getproperty(study, kind.field)))
                                    for kind in RESEARCH_KINDS]))

function get_document_decoration(item::ResearchItem)
    kind = get_research_kind(item)
    counts = has_research_status(item) && item.status !== :open ?
             [DocumentCount(string(item.status); role = _get_status_badge_role(item.status))] :
             DocumentCount[]
    DocumentDecoration(; icon = _RESEARCH_ICONS[kind.field], counts, detail = string(item.author),
                       tooltip = () -> TooltipNote(; title = format_tree_node_label(item),
                           facts = ["Kind" => kind.name, "Author" => string(item.author),
                                    "Time" => _format_local_time(item.time)]))
end

# A person adds a new empty study by name, as an entry of an explorer or in a tab.
get_insertion_aliases(::Type{ResearchStudy}) = ["study"]
make_insertion_document(::Type{ResearchStudy}) =
    ResearchStudy(title = PrimitiveString("New study"), time = get_research_time())
is_explorer_entry_type(::Type{ResearchStudy}) = true
