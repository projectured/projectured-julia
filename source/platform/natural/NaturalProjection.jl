# Fragment of `NaturalModule`.
#
# The **natural projection**: one generic factory, [`NaturalToGraphics`](@ref),
# that projects *almost any* document to a `GraphicsCanvas` — recursively and
# bidirectionally — without the caller hand-assembling a per-context dispatch
# table.
#
# It is built entirely from existing, already-bidirectional projections
# (`TypeDispatchingProjection`, `RecursiveProjection`, `ChainingProjection`, and
# the per-domain `*ToSyntax` / `*ToGraphics` projections), so it inherits the
# printer, the reader, and both reference maps for free — there are no new
# `print_document` / `read_intent` / `map_reference_*` methods here.
#
# ## How "render anything, including nestings" works
#
# Two recursion fabrics, tied together by the four-function recursion contract:
#
# - **`natural_to_syntax`** — a `TypeDispatchingProjection` that routes every
#   *syntax-producible* domain to its `*ToSyntax`, collections (`CellVector` /
#   `ListNode`) to `CollectionToSyntax`, and *anything else* to `ObjectToSyntax`'s
#   reflection table (`Cell`/`Nothing`/`Bool`/`Number`/`String`/`Symbol`/`Char`/`Any`).
#   Wrapped in a `RecursiveProjection`, it is the shared element-recursion fabric:
#   a collection of mixed-domain values, or any cross-domain nesting, projects to a
#   single syntax tree because each element re-enters this same fabric by type.
#
# - **the to-graphics dispatcher** — the returned `RecursiveProjection(
#   TypeDispatchingProjection(…))`. It routes layout combinators and widget nodes
#   to their direct graphics renderers (which recurse their embedded content back
#   through this same dispatcher), a domain that draws itself to its own stages
#   (whose content re-enters here, so a diagram node may be a widget or prose or a
#   table), prose `TextDocument` to a text→graphics chain,
#   and **everything else** (`Any`) to `syntax_to_graphics =
#   RecursiveProjection(natural_to_syntax) → SyntaxToText → Text→Graphics`. The
#   `Any` catch-all means the renderer never errors — it degrades to a reflected
#   object tree for genuinely unknown values.
#
# ## No domain is named here
#
# Both tables come from [`NaturalModule`](@ref). A domain registers its
# own row in a file it already has, so this module names no domain and sits below
# all of them. A domain in a package this one cannot see registers the same way.
#
# ## Scope
#
# This renders *content / data* documents. Structural shells (the conversation
# chat bubbles, the pane tabs/splits) are projected to widgets by their own
# panels as a separate top-level stage; a `ConversationDocument` / `PaneDocument`
# reaching a content slot here falls through to the reflective `Any` fallback. A
# caller that wants the real rendering injects an entry via `extra`.
#
# ## Collections render as stacked blocks
#
# A `CellVector` renders as a `VerticalLayout` of independent graphics blocks
# (`CellVectorToVerticalLayout` → `VerticalLayoutToGraphicsCanvas`): each element
# re-enters *this* renderer in its own domain (prose→prose, JSON→JSON,
# widget→widget), rather than the whole collection collapsing to one syntax tree.
# So a `CellVector` of mixed content — including `TextBlock` prose — renders
# naturally.
#
# A `ListNode` is **not** treated this way: it stays in the to-syntax fabric
# (`CollectionToSyntax`), because a list may be lazy/infinite and must not be forced
# into a finite layout. A `TextBlock` placed directly inside a `ListNode` therefore
# still reflects via `ObjectToSyntax` rather than rendering as prose — an accepted
# edge case.
"""
    PhraseToGraphics(message, style, text)

A document drawn as one line of prose. `message(document)` is what the line says,
in `style`, a `StyleText` or a cell that reads the scaled `TextTheme`; `text` is
the `TextToGraphics` that draws the line.

Two rows use it, and neither may need a domain that can reflect a document into a
tree: the empty-document placeholder, and the message a document nothing claimed
draws. Drawing that message is the whole difference between a renderer that is
composed of what a session loaded and one that must carry everything.
"""
struct PhraseToGraphics <: Projection
    message::Any
    style::Any
    text::TextToGraphics
end

function print_document(p::PhraseToGraphics, recursion, document, ctx)
    line = TextBlock(TextString(p.message(document), unwrap_cell(p.style)))
    inner = print_document(p.text, recursion, line, ctx)
    SimpleIoMap(p, document, get_iomap_output(inner))
end

_unsupported_message(document) =
    "no natural rendering for " * String(nameof(typeof(document)))

"""
    NaturalToGraphics(; measure, font=nothing,
                        wrap=true, extra=Pair{Type,Any}[], appearance=Appearance())
        -> RecursiveProjection

Build the natural projection: a recursive type-dispatching projection mapping
almost any document to a `GraphicsCanvas`. `measure` is the `TextMeasure` the
layout measures text with (backend-supplied; e.g. `FontFileMeasure()`).

- `font`    — base font for text that no domain styles: the line of prose of a
              placeholder, and the fallback. `nothing`, the default, is the
              `font` of the `TextTheme` of `appearance`, which follows its scale.
- `appearance` — the `Appearance` of the editor. Every widget draws with its
              `WidgetTheme`, the text with its `TextTheme`, and every registered
              row takes the scaled theme of its domain from it. The default is a
              new `Appearance`, which no tab edits.
- `wrap`    — word-wrap prose (`TextDocument`). Structured syntax/code is always
              rendered no-wrap (its layout carries meaning; overflow is the
              viewport's job).
- `extra`   — `Pair{Type,Any}` entries prepended to the table, so a caller can
              override or add routing (e.g. a placeholder text chain, or a real
              renderer for a structural document) without forking the table.
              First match wins, so `extra` beats the defaults.
"""
function NaturalToGraphics(; measure::TextMeasure,
                           font = nothing,
                           wrap::Bool = true,
                           extra = Pair{Type,Any}[],
                           appearance::Appearance = Appearance())
    widget_theme = get_scaled_theme!(appearance, WidgetTheme)
    graphics_theme = get_scaled_theme!(appearance, GraphicsTheme)
    w2g = WidgetToGraphics(; measure, theme = widget_theme, graphics_theme)
    text_theme = get_scaled_theme!(appearance, TextTheme)
    # Prose: a text document, at the prose spacing of the text theme.
    text = TextToGraphics(; measure, theme = text_theme,
                          line_spacing = make_style_field(TextTheme, text_theme, LineSpacing;
                                                          name = :prose_line_spacing))
    # A stack of blocks draws the ring of the graphics theme, as every layout does.
    stack() = VerticalLayoutToGraphicsCanvas(;
        graphics_style = make_theme_values_field(GraphicsTheme, graphics_theme))

    # Prose: optionally word-wrapped. Structured syntax/code: never wrapped.
    prose_chain = wrap ? ChainingProjection(WordWrapping(measure = measure), text) : text

    style = font === nothing ?
        make_theme_cell(StyleText, text_theme, scaled -> scaled.plain_text) :
        StyleText(font, text_theme.plain_text.color)

    # A fallback registers rows for exact types and, usually, one for `Any`. The
    # two go to different places in the table: the exact ones before this
    # package's abstract rows, the `Any` after them.
    registered = get_natural_fallback_entries(measure = measure, font = font, wrap = wrap,
                                              appearance = appearance)
    specific = Pair{Type,Any}[p for p in registered if first(p) !== Any]
    tail     = Pair{Type,Any}[p for p in registered if first(p) === Any]

    table = vcat(
        Pair{Type,Any}[p for p in extra],
        # layouts before widgets: a WidgetTable builds a GridLayout
        LayoutToGraphics(; theme = graphics_theme).dispatch,
        w2g.dispatch,                  # every widget node (incl. WidgetTable)
        # The domains that draw themselves rather than going through the syntax
        # fabric: a page of blocks (markdown, RST), a diagram (graph), a typeset
        # formula (math). Each registers its own rows; none is named here. A row
        # is spliced one type at a time (not as one dispatching projection) so
        # every child re-enters *this* renderer — which is what lets a diagram
        # node be a widget, a page hold a live card, and a number inside a
        # formula render through the shared primitive path. The rows of the
        # seam `make_graphics_projection` come first.
        Pair{Type,Any}[type => make_graphics_projection(type; measure = measure,
                                                        appearance = appearance)
                       for type in collect_graphics_projection_types()],
        get_natural_graphics_entries(measure = measure, appearance = appearance),
        # A primitive document that is no part of a syntax tree draws as plain
        # text, with no quotes: a cell of a table, an element of a collection, a
        # value in a tab. A column or a field says its type, so no quote has to.
        # A primitive inside a syntax tree keeps its syntax leaf, because the
        # syntax table prints that tree, child by child.
        Pair{Type,Any}[PrimitiveDocument => ChainingProjection(PrimitiveToText(; theme = text_theme), text)],
        # A fallback's own rows: the placeholders only it can draw. They name
        # exact types, so they come before the abstract rows below — a
        # `TextInsertion` is a `TextDocument`, and prose is not what it is, and a
        # `DocumentNothing` drawn as a leaf beats the same one drawn as prose.
        specific,
        Pair{Type,Any}[
            # The domain-free placeholder, for a session that can not reflect a
            # document into a tree. A session that loaded the syntax package
            # registers an exact row for it above, and that row wins, so a person
            # there gets the placeholder leaf and the Insert key that goes with
            # it. Without that package there is no leaf, and one line of prose is
            # what an empty tab can say.
            DocumentNothing => PhraseToGraphics(_ -> "empty document", style, text),
            # A graphics document is graphics already, and it draws as itself.
            GraphicsDocument => GraphicsToGraphics(),
            TextDocument    => prose_chain,
            # A collection renders as a stack of independent graphics blocks: each
            # element re-enters this renderer in its own domain (prose→prose,
            # JSON→JSON, widget→widget), instead of collapsing to one syntax tree.
            CellVector      => ChainingProjection(CellVectorToVerticalLayout(;
                                                     gap = make_style_field(GraphicsTheme, graphics_theme, Int;
                                                                            name = :collection_gap)),
                                                 stack()),
            # A tooltip window: a column of what the parts say, each in its own
            # domain.
            TooltipContent  => ChainingProjection(TooltipContentToVerticalLayout(; theme = widget_theme),
                                                 stack()),
        ],
        # The fallback's own tail, then this one. A session that loaded a package
        # that can draw anything reaches its tail; one that did not reaches the
        # message.
        tail,
        Pair{Type,Any}[
            Any => PhraseToGraphics(_unsupported_message, style, text),
        ],
    )

    # A barrier at the one recursion point: a fault costs one widget, one layout
    # or one document of a domain, and it draws as a line of graphics.
    RecursiveProjection(FaultCatchingProjection(inner = TypeDispatchingProjection(table),
                                                substitute = FaultToGraphics()))
end

# The projection of an editor on a document when the caller names none: the
# natural renderer, which draws a document of almost any domain. This package
# adds the one method of the seam, so a session that loads it opens any document
# with no projection named. The renderer takes the `Appearance` of the
# `appearance` wrapper, so the keys and the scales of the editor reach it.
make_document_projection(::Document; appearance = Appearance(), _...) =
    NaturalToGraphics(; measure = FontFileMeasure(),
                      appearance = appearance isa Appearance ? appearance : Appearance())
