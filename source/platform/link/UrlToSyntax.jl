# Fragment of `LinkModule` — the text line of an address: one line of syntax with a
# leaf for each piece and for each delimiter, where a typed edit reads the whole
# address again.
#
#     children[i]    segment i of `_get_url_segments`: a piece, or a delimiter

"""
    UrlToSyntax(; host_style, piece_style)

The projection of a `Url` to one line of syntax: a leaf for each piece that is
there, and a leaf for each delimiter, `:`, `//`, `@`, `?` and `#`. The host draws
in `host_style`, and the other pieces and the delimiters in `piece_style`, as the
address bar of a browser draws them. A selection in a leaf of a piece names the
field, such as `.host{3}`.

A typed edit anywhere in the line, in a piece or on a delimiter, is an edit of the
text of the address at the same place: the line reads the whole address again
with `make_url_text_operation`, and puts the caret at the same place in the new
text. So `/docs` typed after the host goes into the path.
"""
@projection UntrackedCell struct UrlToSyntax
    host_style::StyleText = get_syntax_style(nothing, :typed_text)
    piece_style::StyleText = get_syntax_style(nothing, :label_text)
end

# The children follow `_get_url_segments`, in the same order.
@projection_template UrlToSyntax Url (p, url) ->
    SyntaxConcatenation(() -> begin
        delimiter(text) = SyntaxLeaf(TextString(text, p.piece_style))
        children = Any[]
        if url.scheme !== nothing
            push!(children, SyntaxLeaf(bound(:scheme, String, TextString(() -> url.scheme, p.piece_style))),
                  delimiter(":"))
        end
        if url.host !== nothing
            push!(children, delimiter("//"))
            url.userinfo === nothing ||
                push!(children, SyntaxLeaf(bound(:userinfo, String, TextString(() -> url.userinfo, p.piece_style))),
                      delimiter("@"))
            push!(children, SyntaxLeaf(bound(:host, String, TextString(() -> url.host, p.host_style))))
            url.port === nothing ||
                push!(children, delimiter(":"), SyntaxLeaf(bound(:port, String, TextString(() -> url.port, p.piece_style))))
        end
        push!(children, SyntaxLeaf(bound(:path, String,
                                         make_hinted_text(() -> url.path; empty_thunk = () -> isempty(format_url(url)),
                                                          placeholder = "type an address", style = p.piece_style))))
        url.query === nothing ||
            push!(children, delimiter("?"), SyntaxLeaf(bound(:query, String, TextString(() -> url.query, p.piece_style))))
        url.fragment === nothing ||
            push!(children, delimiter("#"),
                  SyntaxLeaf(bound(:fragment, String, TextString(() -> url.fragment, p.piece_style))))
        children
    end)

# The segments of the text of `url`, in order: `(piece, text)`, where `piece` is
# the name of the field, or `nothing` for a delimiter.
function _get_url_segments(url::Url)
    segments = Tuple{Union{Nothing, Symbol}, String}[]
    url.scheme === nothing || push!(segments, (:scheme, url.scheme), (nothing, ":"))
    if url.host !== nothing
        push!(segments, (nothing, "//"))
        url.userinfo === nothing || push!(segments, (:userinfo, url.userinfo), (nothing, "@"))
        push!(segments, (:host, url.host))
        url.port === nothing || push!(segments, (nothing, ":"), (:port, url.port))
    end
    push!(segments, (:path, url.path))
    url.query === nothing || push!(segments, (nothing, "?"), (:query, url.query))
    url.fragment === nothing || push!(segments, (nothing, "#"), (:fragment, url.fragment))
    segments
end

# An edit in leaf `i` of the line, `.children[i].value{start:stop}`, is an edit of
# the text of the address at the same place.
function read_intent(p::UrlToSyntax, iomap::TemplateIoMap, operation::ReplaceStringRangeOperation)
    url = get_iomap_input(iomap)
    range = _find_url_text_range(url, operation.reference)
    range === nothing && return nothing
    text = format_url(url)
    characters = collect(text)
    edited = String(vcat(characters[1:range[1]], collect(operation.replacement), characters[(range[2] + 1):end]))
    caret = ReplaceSelectionOperation(_make_url_caret_path(Url(edited), range[1] + length(operation.replacement)))
    edit = make_url_text_operation(url, edited)
    edit === nothing ? caret : CompoundOperation(Any[edit.operations..., caret])
end

# The range of characters in the text of `url` that `reference`, a range in a leaf
# of the line, names, as two offsets from the start, or `nothing`. An empty address
# draws a placeholder, and any place in it is the start.
function _find_url_text_range(url::Url, reference)
    steps = get_reference_steps(strip_reference_types(reference))
    length(steps) == 4 && steps[1] == FieldReferenceStep("children") && steps[2] isa RangeReferenceStep &&
        is_element_reference_step(steps[2]) && steps[3] == FieldReferenceStep("value") &&
        steps[4] isa RangeReferenceStep || return nothing
    segments = _get_url_segments(url)
    index = steps[2].stop
    1 <= index <= length(segments) || return nothing
    isempty(format_url(url)) && return (0, 0)
    before = sum((length(segments[k][2]) for k in 1:(index - 1)); init = 0)
    (before + steps[4].start, before + steps[4].stop)
end

# The caret at `offset` in the text of `url`, in the first piece whose text holds
# that place, its start and its end included.
function _make_url_caret_path(url::Url, offset::Integer)
    start = 0
    for (piece, text) in _get_url_segments(url)
        stop = start + length(text)
        if piece !== nothing && start <= offset <= stop
            return extend_reference(EmptyReference(), FieldReferenceStep(String(piece)),
                                    RangeReferenceStep(offset - start, offset - start))
        end
        start = stop
    end
    extend_reference(EmptyReference(), FieldReferenceStep("path"), RangeReferenceStep(0, 0))
end
