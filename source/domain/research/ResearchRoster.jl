# Fragment of `ResearchModule` — the items of a study as the rows of a roster. The
# timeline of a study is a roster of its items, sorted by their time: the filter,
# the sort and the group of the arrangement work on it as on any collection.

"""
    StudyItems(study)

The source of a roster of the items of `study`: the items of its lists, in the
order of `collect_study_items`. A link does not give its item again. The row of an item holds the study as
`within`. Beside its fields, an item has the facets `kind`, the name of its kind,
and `text`, its statement, title or citation as a text. The `time` of an item is a
UTC text that sorts in the order of time.

Use it to show the timeline of a study, or any table of its items.

# Example

    show_roster!(StudyItems(study_1); title = "Timeline",
                 columns = ["time", "author", "id", "kind", "status", "text"], sort = ["time"])

See also `ResearchStudy`, `collect_study_items`.
"""
struct StudyItems
    study::Any
end

get_roster_item_type(::StudyItems) = ResearchItem

# The study is the one part, so an edit of the study gathers its items again.
collect_roster_parts(source::StudyItems, link) = Any[get_document(source.study)]

collect_roster_items(source::StudyItems, link, study::ResearchStudy) =
    RosterItem[RosterItem(item, study) for item in collect_study_items(study)]

get_item_facets(::Type{ResearchItem}) =
    ["kind" => "the kind of the item, such as hypothesis",
     "text" => "the statement, the title or the citation of the item, as a text"]

compute_item_facet(item::ResearchItem, ::Val{:kind}) = get_research_kind(item).name
compute_item_facet(item::ResearchItem, ::Val{:text}) = _format_plain_text(get_research_item_text(item))
