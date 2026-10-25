# Fragment of `LinkModule` — the page of an address: its text line, its pieces, and
# the command that opens it.
#
#     children[1]    the text line of the address, the output of `UrlToSyntax`
#     children[2]    the pieces, a name and a text on each row
#     children[3]    the button that opens the address

"""
    UrlViewToWidget(; gap, syntax_theme)

The page of an address: its text line, where a person edits the address, the list
of its pieces with their names, "none" for a piece that the address does not
have and "empty" for a piece with no text, and a button that opens it, "Open in the browser" or "Open the file". The
button is off for a relative address, which only the page of a link resolves.
`gap` is the space between the parts, and `syntax_theme`, a `SyntaxTheme` scaled
or not, styles the text line.
"""
@projection UntrackedCell struct UrlViewToWidget <: Projection
    gap::Int = get_widget_style(nothing, :label_gap)
    syntax_theme::Any = nothing
end

# The IO map of the page: `line_iomap` is the IO map of the text line, and the
# reader and the maps pass a path in the line through its projection.
@iomap struct UrlViewToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    line_iomap::Any
end

const _URL_LINE_STEPS = (FieldReferenceStep("children"), ElementReferenceStep(1))
const _URL_VIEW_STEP = FieldReferenceStep("url")

function print_document(p::UrlViewToWidget, recursion, view::UrlView, context)
    url = view.url
    line = UrlToSyntax(; host_style = get_syntax_style(p.syntax_theme, :typed_text),
                       piece_style = get_syntax_style(p.syntax_theme, :label_text))
    line_iomap = print_document(line, recursion, url, context)
    pieces = GridLayout(Any[part for piece in _URL_PIECES
                            for part in (WidgetLabel(String(piece)),
                                         WidgetLabel(() -> _format_url_piece(getproperty(url, piece))))], 2;
                        horizontal_gap = p.gap)
    open(_, _) = OpenUrlOperation(url)
    button = WidgetButton("Open in the browser";
                          gestures = GestureBinding[
                              GestureBinding(MouseClickPattern(:left; modifiers = Symbol[]), open;
                                             description = "Open the address", domain = "link"),
                              GestureBinding(KeyPressPattern('\n'; modifiers = Symbol[]), open;
                                             description = "Open the address", domain = "link")])
    set_cell_computation!(button, () -> find_url_file_path(url) === nothing ? "Open in the browser" : "Open the file")
    set_cell_computation!(getfield(button, :enabled), () -> is_absolute_url(url))
    root = VerticalLayout(Any[line_iomap.output, pieces, button]; horizontal_align = :left, gap = p.gap)
    iomap = UrlViewToWidgetIoMap(p, view, root, line_iomap)
    set_output_path_computations!(root, view, path -> map_reference_forward(p, iomap, path); dormant = false)
    set_output_tree_path_computations!(root)
    iomap
end

# A piece in the list: "none" when the address has no such piece, and "empty"
# when it has the piece with no text.
_format_url_piece(text) = text === nothing ? "none" : isempty(text) ? "empty" : String(text)

# A path in the address goes into the text line; the page drew every other part.
function map_reference_forward(p::UrlViewToWidget, iomap::UrlViewToWidgetIoMap, reference)
    reference isa EmptyReference && return reference
    rest = _get_url_view_rest(reference, (_URL_VIEW_STEP,))
    rest === nothing && return find_introduced_path(p, reference)
    line_iomap = iomap.line_iomap
    inner = map_reference_forward(get_iomap_projection(line_iomap), line_iomap, rest)
    inner === nothing ? nothing :
        _attach_url_view_rest(annotate_reference_types(iomap.output, extend_reference(EmptyReference(), _URL_LINE_STEPS...)),
                              inner)
end

function map_reference_backward(p::UrlViewToWidget, iomap::UrlViewToWidgetIoMap, reference)
    rest = _get_url_view_rest(reference, _URL_LINE_STEPS)
    rest === nothing && return make_introduced_reference(p, iomap, reference)
    line_iomap = iomap.line_iomap
    inner = map_reference_backward(get_iomap_projection(line_iomap), line_iomap, rest)
    inner === nothing ? nothing : ConcreteReference(_URL_VIEW_STEP, inner)
end

# A typed edit in the text line goes to the line, which reads the whole address again.
function read_intent(p::UrlViewToWidget, iomap::UrlViewToWidgetIoMap, operation::ReplaceStringRangeOperation)
    rest = _get_url_view_rest(operation.reference, _URL_LINE_STEPS)
    rest === nothing && return nothing
    line_iomap = iomap.line_iomap
    answer = read_intent(get_iomap_projection(line_iomap), line_iomap, ReplaceStringRangeOperation(rest, operation.replacement))
    reroot_operation(answer, (_URL_VIEW_STEP,))
end

# The part of `path` below `steps`, with its types, or `nothing` when `path` does
# not start with `steps`, or names a part that a projection introduced.
function _get_url_view_rest(path, steps)
    is_introduced_reference(path) && return nothing
    for step in steps
        (path isa ConcreteReference && path.head == step) || return nothing
        path = path.tail
    end
    path
end

_attach_url_view_rest(prefix::ConcreteReference, rest) =
    ConcreteReference(prefix.type, prefix.head, _attach_url_view_rest(prefix.tail, rest))
_attach_url_view_rest(::EmptyReference, rest) = rest

make_graphics_projection(::Type{<:UrlView}; measure, appearance) =
    ChainingProjection(UrlViewToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :label_gap),
                                       syntax_theme = get_scaled_theme!(appearance, SyntaxTheme)),
                       VerticalLayoutToGraphicsCanvas())

# An address draws as a link inside any document that a renderer draws.
make_graphics_projection(::Type{<:Url}; measure, appearance) =
    ChainingProjection(LinkToWidget(),
                       WidgetLinkToGraphicsCanvas(get_scaled_theme!(appearance, WidgetTheme); measure))
