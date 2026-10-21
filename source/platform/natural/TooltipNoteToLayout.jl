# Fragment of `NaturalModule` — the natural drawing of a tooltip note.

"""
    TooltipNoteToVerticalLayout(; theme = nothing)

A [`TooltipNote`](@ref) as a column that the natural projection draws: the title,
in bold, with the key caps after it, then the text, the facts as a grid of names
and values, and the hint. The title and the text stand close, and a larger gap
stands between the parts, because a line between them would stop short of the
widest part. A warning and an error
draw a mark of their color before the title. A piece that is a document
re-enters the natural projection in its own domain, and a string breaks its lines
at the edge of the window. A note is read, never edited, so the column maps no
reference of its own.

The texts, the colors and the gaps are those of `theme`, a `TooltipTheme` scaled
or not, or of the default theme.
"""
# Each field is a value of a `TooltipTheme`: a value, or a cell that reads the
# theme. The drawing reads them when it prints, so a change of the appearance
# shows at the next tooltip.
struct TooltipNoteToVerticalLayout <: Projection
    gap::Any
    section_gap::Any
    title_text::Any
    body_text::Any
    muted_text::Any
    value_text::Any
    key_text::Any
    key_fill::Any
    key_line::Any
    key_padding::Any
    key_gap::Any
    line_width::Any
    head_gap::Any
    fact_gap::Any
    fact_row_gap::Any
    warning_mark::Any
    error_mark::Any
    success_mark::Any
    info_mark::Any
    accent_mark::Any
    quiet_mark::Any
end

function TooltipNoteToVerticalLayout(; theme = nothing)
    get_style(name) = get_tooltip_style(theme, name)
    TooltipNoteToVerticalLayout(get_style(:gap), get_style(:section_gap), get_style(:title_text), get_style(:body_text),
                                get_style(:muted_text), get_style(:value_text), get_style(:key_text),
                                get_style(:key_fill), get_style(:key_line), get_style(:key_padding),
                                get_style(:key_gap), get_style(:line_width), get_style(:head_gap),
                                get_style(:fact_gap), get_style(:fact_row_gap), get_style(:warning_mark),
                                get_style(:error_mark), get_style(:success_mark), get_style(:info_mark),
                                get_style(:accent_mark), get_style(:quiet_mark))
end

function print_document(p::TooltipNoteToVerticalLayout, recursion, note::TooltipNote, ctx)
    sections = Any[]
    opening = Any[part for part in (_make_note_head(p, note), _make_note_prose(note.text, unwrap_cell(p.body_text)))
                  if part !== nothing]
    isempty(opening) || push!(sections, length(opening) == 1 ? only(opening) :
                                        VerticalLayout(opening; gap = unwrap_cell(p.gap)))
    facts = _make_note_facts(p, note.facts)
    facts === nothing || push!(sections, facts)
    hint = _make_note_prose(note.hint, unwrap_cell(p.muted_text))
    hint === nothing || push!(sections, hint)
    SimpleIoMap(p, note, VerticalLayout(sections; gap = unwrap_cell(p.section_gap)))
end

# The first line of a note: the mark of its tone, its title and its key caps, or
# `nothing` when it has none of them.
function _make_note_head(p::TooltipNoteToVerticalLayout, note::TooltipNote)
    named = Any[]
    mark = _make_tone_mark(p, note.tone)
    mark === nothing || push!(named, mark)
    title = note.title
    if title isa AbstractString
        isempty(title) || push!(named, WidgetLabel(String(title); text_style = unwrap_cell(p.title_text)))
    elseif title !== nothing
        push!(named, title)
    end
    keys = _make_key_caps(p, note.keys)
    isempty(named) && keys === nothing && return nothing
    parts = Any[]
    isempty(named) || push!(parts, length(named) == 1 ? only(named) :
                                   HorizontalLayout(named; gap = unwrap_cell(p.gap), vertical_align = :center))
    keys === nothing || push!(parts, keys)
    length(parts) == 1 ? only(parts) : HorizontalLayout(parts; gap = unwrap_cell(p.head_gap), vertical_align = :center)
end

# The mark of a tone: the glyph of a warning, in the color of a warning or of an
# error; `nothing` for a plain note.
function _make_tone_mark(p::TooltipNoteToVerticalLayout, tone::Symbol)
    tone in (:warning, :error) || return nothing
    WidgetLabel(string(find_icon_character(:warning));
                text_style = unwrap_cell(tone === :error ? p.error_mark : p.warning_mark))
end

# The key caps of `keys`: the caps of one key side by side, and an "or" between
# two keys; `nothing` for no key.
function _make_key_caps(p::TooltipNoteToVerticalLayout, keys)
    isempty(keys) && return nothing
    gap = unwrap_cell(p.key_gap)
    groups = Any[]
    for (index, key) in enumerate(keys)
        index > 1 && push!(groups, WidgetLabel("or"; text_style = unwrap_cell(p.muted_text)))
        text = key isa AbstractString ? String(key) : describe_gesture_pattern(key)
        push!(groups, HorizontalLayout(Any[_make_key_cap(p, name) for name in _split_key_names(text)]; gap))
    end
    length(groups) == 1 ? only(groups) : HorizontalLayout(groups; gap = 2 * gap, vertical_align = :center)
end

function _make_key_cap(p::TooltipNoteToVerticalLayout, name::AbstractString)
    width = unwrap_cell(p.line_width)
    fill = unwrap_cell(p.key_fill)
    WidgetLabel(name; text_style = unwrap_cell(p.key_text), border = Inset(width, width, width, width),
                padding = unwrap_cell(p.key_padding),
                style = WidgetStyle(border_color = unwrap_cell(p.key_line), padding_color = fill, content_color = fill))
end

# The names of the keys of a text such as "Ctrl+Shift+P": a plus between two
# names splits them, and a plus at the end is the name of the key "+".
function _split_key_names(text::AbstractString)
    text == "+" && return ["+"]
    endswith(text, "++") && return vcat(_split_key_names(chop(text; tail = 2)), "+")
    String.(split(text, "+"))
end

# A string as lines of text in `style`, which break at the edge of the window; a
# document as it is; nothing for `nothing` and for an empty string.
_make_note_prose(::Nothing, style) = nothing
_make_note_prose(text::AbstractString, style) = isempty(text) ? nothing :
    TextBlock(TextDocument[TextLine(TextString(String(line), style)) for line in split(text, "\n")])
_make_note_prose(document, style) = document

# The facts as a grid of two columns; nothing for no fact.
function _make_note_facts(p::TooltipNoteToVerticalLayout, facts)
    isempty(facts) && return nothing
    cells = Any[]
    for fact in facts
        append!(cells, _make_fact_cells(p, fact))
    end
    GridLayout(cells, 2; horizontal_gap = unwrap_cell(p.fact_gap), vertical_gap = unwrap_cell(p.fact_row_gap))
end

# A fact as its two cells: the name in the quiet text, and the value in the text
# of a value, or as the document that it is.
_make_fact_cells(p::TooltipNoteToVerticalLayout, fact::Pair) =
    Any[WidgetLabel(string(fact.first); text_style = unwrap_cell(p.muted_text)),
        fact.second isa Document ? fact.second :
                                   WidgetLabel(string(fact.second); text_style = unwrap_cell(p.value_text))]

# A condition of a decoration as a fact: the glyph of its look in the color of its
# role, a dot for a look with no glyph, its words, and its count when it has one.
function _make_fact_cells(p::TooltipNoteToVerticalLayout, condition::DocumentCondition)
    look = get_condition_look(Val(condition.name))
    glyph = something(find_icon_character(something(look.glyph, :dot)), find_icon_character(:dot))
    role = something(condition.role, Some(look.role))
    mark = WidgetLabel(string(glyph); text_style = unwrap_cell(_get_role_mark(p, role)))
    words = WidgetLabel(look.words; text_style = unwrap_cell(p.body_text))
    count = WidgetLabel(condition.count === nothing ? "" : string(condition.count);
                        text_style = unwrap_cell(p.value_text))
    Any[HorizontalLayout(Any[mark, words]; gap = unwrap_cell(p.gap), vertical_align = :center), count]
end

# The text of the mark of a role: one of `:error`, `:warning`, `:success`,
# `:info` and `:accent`, or another for a quiet mark.
_get_role_mark(p::TooltipNoteToVerticalLayout, role) =
    role === :error ? p.error_mark : role === :warning ? p.warning_mark :
    role === :success ? p.success_mark : role === :info ? p.info_mark :
    role === :accent ? p.accent_mark : p.quiet_mark
