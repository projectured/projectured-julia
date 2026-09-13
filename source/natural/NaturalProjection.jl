# ──────────────────────────────────────────────────────────────────────────
# Folded in from NaturalProjection.jl.
"""
    PhraseToGraphics(message, style, measure)

A document drawn as one line of prose. `message(document)` is what the line says.

Two rows use it, and neither may need a domain that can reflect a document into a
tree: the empty-document placeholder, and the message a document nothing claimed
draws. Drawing that message is the whole difference between a renderer that is
composed of what a session loaded and one that must carry everything.
"""
struct PhraseToGraphics <: Projection
    message::Any
    style::StyleText
    measure::Any
end

function print_document(p::PhraseToGraphics, recursion, document, ctx)
    line = TextBlock(TextString(p.message(document), p.style))
    inner = print_document(TextToGraphics(measure = p.measure), recursion, line, ctx)
    SimpleIoMap(p, document, get_iomap_output(inner))
end

_unsupported_message(document) =
    "no natural rendering for " * String(nameof(typeof(document)))

"""
    NaturalToGraphics(; measure, font=font_ubuntu_monospace_regular_20,
                        wrap=true, extra=Pair{Type,Any}[])
        -> RecursiveProjection

Build the natural projection: a recursive type-dispatching projection mapping
almost any document to a `GraphicsCanvas`. `measure(text, font) -> (w, h)` is the
text-measurement function (backend-supplied; e.g. `measure_truetype_text`).

- `font`    — base font for widget/text rendering.
- `wrap`    — word-wrap prose (`TextDocument`). Structured syntax/code is always
              rendered no-wrap (its layout carries meaning; overflow is the
              viewport's job).
- `extra`   — `Pair{Type,Any}` entries prepended to the table, so a caller can
              override or add routing (e.g. a placeholder text chain, or a real
              renderer for a structural document) without forking the table.
              First match wins, so `extra` beats the defaults.
"""
function NaturalToGraphics(; measure::Function,
                           font = font_ubuntu_monospace_regular_20,
                           wrap::Bool = true,
                           extra = Pair{Type,Any}[])
    w2g = WidgetToGraphics(font; measure = measure)

    # Prose: optionally word-wrapped. Structured syntax/code: never wrapped.
    prose_chain = wrap ?
        ChainingProjection(WordWrapping(measure = measure), TextToGraphics(measure = measure)) :
        TextToGraphics(measure = measure)

    style = StyleText(font, color_default)

    # A fallback registers rows for exact types and, usually, one for `Any`. The
    # two go to different places in the table: the exact ones before this
    # package's abstract rows, the `Any` after them.
    registered = get_natural_fallback_entries(measure = measure, font = font, wrap = wrap)
    specific = Pair{Type,Any}[p for p in registered if first(p) !== Any]
    tail     = Pair{Type,Any}[p for p in registered if first(p) === Any]

    table = vcat(
        Pair{Type,Any}[p for p in extra],
        LayoutToGraphics().dispatch,   # layouts before widgets: a WidgetTable builds a GridLayout
        w2g.dispatch,                  # every widget node (incl. WidgetTable)
        # The domains that draw themselves rather than going through the syntax
        # fabric: a page of blocks (markdown, RST), a diagram (graph), a typeset
        # formula (math). Each registers its own rows; none is named here. A row
        # is spliced one type at a time (not as one dispatching projection) so
        # every child re-enters *this* renderer — which is what lets a diagram
        # node be a widget, a page hold a live card, and a number inside a
        # formula render through the shared primitive path.
        get_natural_graphics_entries(measure = measure),
        # A fallback's own rows: the placeholders only it can draw. They name
        # exact types, so they come before the two abstract rows below — a
        # `TextInsertion` is a `TextDocument`, and prose is not what it is.
        specific,
        Pair{Type,Any}[
            # The domain-free placeholder — what a fresh pane tab holds. It draws
            # as prose, so an empty tab needs no reflection.
            DocumentNothing => PhraseToGraphics(_ -> "empty document", style, measure),
            TextDocument    => prose_chain,
            # A collection renders as a stack of independent graphics blocks: each
            # element re-enters this renderer in its own domain (prose→prose,
            # JSON→JSON, widget→widget), instead of collapsing to one syntax tree.
            CellVector      => ChainingProjection(CellVectorToVerticalLayout(),
                                                 VerticalLayoutToGraphicsCanvas()),
        ],
        # The fallback's own tail, then this one. A session that loaded a package
        # that can draw anything reaches its tail; one that did not reaches the
        # message.
        tail,
        Pair{Type,Any}[
            Any => PhraseToGraphics(_unsupported_message, style, measure),
        ],
    )

    RecursiveProjection(TypeDispatchingProjection(table))
end
