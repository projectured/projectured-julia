# Fragment of `ResearchModule` — the theme of the outline of a study: the texts of
# an id, a section, a link, a time and an author, and the gaps.

"""
    ResearchTheme

The fonts, the colors and the gaps of the outline of a study: the id of an item
and the title of a section, the names of the links and the times, and the author
of an item. The status of an item is a badge, which takes the colours of its role
from the widget theme.

`@theme` declares it, so `ScaledResearchTheme` holds each value times its scale,
and `ResearchTheme()` is the default theme. The builder gives each projection of
the outline its styles with `get_research_style`, from a theme scaled or not.
"""
@theme struct ResearchTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu", 14)
    "The id of an item, and the title of a section of the outline."
    heading_text::ThemeText = TextRole(:heading; weight = 700)
    "The name of a link, the name of a field, and the time of an item."
    muted_text::ThemeText = TextRole(:text_muted)
    "The author of an item that the assistant made."
    assistant_text::ThemeText = TextRole(:info_text; weight = 700)
    "The author of an item that the person made."
    person_text::ThemeText = TextRole(:text; weight = 700)
    "The gap between the parts of an item."
    gap::Int = 6
end

# The role of the badge that shows `status`: an accepted item draws as a success,
# a rejected one as an error. An open item has none, and its badge draws as an
# outline.
_get_status_badge_role(status::Symbol) =
    status === :accepted ? :success :
    status === :rejected ? :error : nothing
