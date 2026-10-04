# Fragment of `YamlModule`.
#
# YAML → SyntaxDocument projection. Maps each YAML value type to a matching syntax
# tree shape: null, bool, number, and string scalars become leaves; sequences and
# mappings become nodes.
#
# The container rendering is selectable via `YamlToSyntax(; style)`:
#
# - `:block` (default) — idiomatic block YAML: `key: value` lines and `- item`
#   sequences, laid out by indentation, no braces/brackets/commas.
# - `:flow` — flow YAML (a JSON superset): `{key: value}` and `[a, b]` with commas.
#
# String scalars and mapping keys are plain (unquoted) in both styles.
#
# Mappings are rendered through `@projection_template` (the flow/block difference is
# just the wrapper's open/close/separator). Block **sequences** need a `- ` before
# every item, which the template's homogeneous `collection` cannot inject, so the
# block sequence is a hand-written projection (like `FileSystemDirectoryToSyntaxNode`).
# ── YamlNullToSyntaxLeaf ─────────────────────────────────────────────────────

@projection UntrackedCell struct YamlNullToSyntaxLeaf
    style::StyleText = get_yaml_style(nothing, :null_text)
end

@projection_template YamlNullToSyntaxLeaf YamlNull (prj, doc) ->
    SyntaxLeaf(TextString("null", prj.style))

# ── YamlInsertionToSyntaxLeaf ───────────────────────────────────────────────────
#
# The shared typed-name insertion buffer, constrained to the YAML candidates
# (prefix-free: `string` → `YamlString`). The char type-to-replace gestures on
# a whole-selected insertion keep working: the leaf declines without a value
# cursor, so those keys fall through to `@gestures YamlDocument`.

YamlInsertionToSyntaxLeaf(; theme = nothing) = DomainInsertionToSyntaxLeaf(YamlDocument; theme)

# ── YamlBoolToSyntaxLeaf ─────────────────────────────────────────────────────

@projection UntrackedCell struct YamlBoolToSyntaxLeaf
    style::StyleText = get_yaml_style(nothing, :bool_text)
end

# See JsonBoolToSyntaxLeaf: `make_hinted_text` guards the `doc.value ? …` thunk against a
# transient non-`Bool` value produced by mid-edit `bound` reads.
@projection_template YamlBoolToSyntaxLeaf YamlBool (prj, doc) ->
    SyntaxLeaf(bound(:value, Bool,
                     make_hinted_text(() -> doc.value ? "true" : "false";
                                      empty_thunk = () -> !(doc.value isa Bool),
                                      placeholder = "enter yaml bool",
                                      style = prj.style)))

# ── YamlNumberToSyntaxLeaf ───────────────────────────────────────────────────

@projection UntrackedCell struct YamlNumberToSyntaxLeaf
    style::StyleText = get_yaml_style(nothing, :number_text)
end

@projection_template YamlNumberToSyntaxLeaf YamlNumber (prj, doc) ->
    SyntaxLeaf(bound(:value, Real,
                     make_hinted_text(() -> string(doc.value);
                                      empty_thunk = () -> doc.value === nothing,
                                      placeholder = "enter yaml number",
                                      style = prj.style);
                     retype = ReplaceNumberRangeOperation))

# ── YamlStringToSyntaxLeaf ───────────────────────────────────────────────────
#
# A plain scalar: rendered unquoted (the distinctly-YAML choice). The bound value
# lives on the leaf's `.value` span with empty open/close delimiters.

@projection UntrackedCell struct YamlStringToSyntaxLeaf
    style::StyleText = get_yaml_style(nothing, :string_text)
end

@projection_template YamlStringToSyntaxLeaf YamlString (prj, doc) ->
    SyntaxLeaf(bound(:value, String,
                     make_hinted_text(() -> doc.value; empty_thunk = () -> isempty(doc.value),
                                      placeholder = "enter yaml string",
                                      style = prj.style)))

# ── YamlMappingToSyntaxNode (template; flow or block via delimiter fields) ────
#
# Each entry renders `key: value` with an unquoted (plain) key leaf and the value
# delegated to its own projection. The wrapper's open/close/separator are fields so
# the same rule renders flow (`{a: 1, b: 2}`) or block (indented `key: value`
# lines) — see `YamlToSyntax`.

@projection UntrackedCell struct YamlMappingToSyntaxNode
    delimiter_style::StyleText = get_yaml_style(nothing, :delimiter_text)
    separator_style::StyleText = get_yaml_style(nothing, :separator_text)
    key_style::StyleText = get_yaml_style(nothing, :key_text)
    colon_style::StyleText = get_yaml_style(nothing, :separator_text)
    open::String = ""      # "{" flow, "" block
    close::String = ""     # "}" flow, "" block
    sep::String = ""       # ", " flow, "" block (indentation provides the newline)
    # +1 (flow) keeps a trailing newline so the close brace lands on its own line;
    # -1 (block) is block layout WITHOUT that trailing newline, so nested blocks
    # don't leave a blank line before the next sibling.
    indent::Int = -1
end

@projection_template YamlMappingToSyntaxNode YamlMapping (prj, doc) ->
    SyntaxNode(collection(:entries) do e
                   SyntaxNode(TextString("", prj.delimiter_style),
                              TextString("", prj.delimiter_style),
                              TextString(": ", prj.colon_style),
                              [ SyntaxLeaf(bound(:key, String, make_hinted_text(() -> e.key;
                                                                                empty_thunk = () -> isempty(e.key),
                                                                                placeholder = "enter key",
                                                                                style = prj.key_style))),
                                project(:value) ],
                              0, false, getfield(e, :selection))
               end;
               open=TextString(prj.open, prj.delimiter_style),
               close=TextString(prj.close, prj.delimiter_style),
               sep=TextString(prj.sep, prj.separator_style),
               indentation=prj.indent)

# ── YamlSequenceToSyntaxNode (template; flow style [a, b]) ────────────────────

@projection UntrackedCell struct YamlSequenceToSyntaxNode
    delimiter_style::StyleText = get_yaml_style(nothing, :delimiter_text)
    separator_style::StyleText = get_yaml_style(nothing, :separator_text)
end

@projection_template YamlSequenceToSyntaxNode YamlSequence (prj, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString("[", prj.delimiter_style),
               close=TextString("]", prj.delimiter_style),
               sep=TextString(", ", prj.separator_style),
               indentation=1)

# ── YamlSequenceToBlockSyntaxNode (hand-written; block style `- item`) ────────
#
# The template cannot put a `- ` before each element (a homogeneous `collection`
# projects the bare element with no per-item open), so the block sequence is
# hand-written like `FileSystemDirectoryToSyntaxNode`. Output shape:
#
#   SyntaxNode(indentation=1):                 ← one item per indented line
#     children[i] = SyntaxDelimitation(          ← the "- " marker
#                     opening_delimiter="- ", content = <projected element i>)
#
# Selection: .elements[i].rest ↔ .children[i].content.<child-mapped rest>
# (the `.content` hop steps through the "- " delimitation). The tail is
# delegated through the stored child iomaps (School A); the two mappers are the
# single source of truth for the printer's selection cell and the readers.

@projection UntrackedCell struct YamlSequenceToBlockSyntaxNode
    marker_style::StyleText = get_yaml_style(nothing, :delimiter_text)
end

function print_document(p::YamlSequenceToBlockSyntaxNode, recursion, seq::YamlSequence, ctx)
    child_iomaps = Cell(@computation([print_child(recursion, elem,
                                  make_child_context(ctx, FieldReferenceStep("elements"), ElementReferenceStep(i)))
                               for (i, elem) in enumerate(seq.elements)]))

    items = CellVector(@computation(SyntaxDocument[
        SyntaxDelimitation(im.output; opening_delimiter=TextString("- ", p.marker_style))
        for im in child_iomaps[]]))

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(seq, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)

    # indentation=-1: block layout (one item per indented line) without the
    # trailing newline, so a nested sequence leaves no blank line after its items.
    node = SyntaxNode(items; indentation=-1, paths...)
    iomap = ChildrenIoMap(p, seq, node, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

function map_reference_forward(p::YamlSequenceToBlockSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        proj(^(p), inner) => inner
        ::YamlSequence.elements{s:e}.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps
            1 <= child_i <= length(iomaps) || return nothing
            child = iomaps[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::SyntaxNode.children::CellVector[child_i]::SyntaxDelimitation.content.^(inner)
        end
    end
end

function map_reference_backward(p::YamlSequenceToBlockSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::YamlSequence
        ::SyntaxNode.children{s:e}.content.rest... => begin
            child_i = s + 1
            iomaps = iomap.child_iomaps
            1 <= child_i <= length(iomaps) || return make_introduced_reference(p, iomap, reference)
            child = iomaps[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing && return nothing
            @reference ::YamlSequence.elements::CellVector[child_i].^(inner)
        end
        __ => make_introduced_reference(p, iomap, reference)
    end
end

function read_intent(p::YamlSequenceToBlockSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
    result = map_reference_backward(p, iomap, op.path)
    result === nothing && return nothing
    make_path_operation(op, result)
end

function read_intent(p::YamlSequenceToBlockSyntaxNode, iomap::ChildrenIoMap, op::ReplaceStringRangeOperation)
    new_ref = map_reference_backward(p, iomap, op.reference)
    (new_ref === nothing || has_introduced_step(new_ref)) && return nothing
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

# The input step into the focused child plus that child's iomap, derived from the
# sequence's own selection — the reader-side mirror of the recursive printer. A
# non-`.elements[i]` selection yields nothing, so the gesture falls to the
# sequence's own `read_gesture` (its `@gestures`, e.g. `,` to insert an element).
function _block_seq_focused_child(iomap, sel)
    @reference_case sel begin
        ::YamlSequence.elements{s:e}.rest... => begin
            i = s + 1
            ims = iomap.child_iomaps
            1 <= i <= length(ims) || return nothing
            (ims[i], (FieldReferenceStep("elements"), ElementReferenceStep(i)))
        end
    end
end

function read_intent(p::YamlSequenceToBlockSyntaxNode, iomap::ChildrenIoMap, evt::Union{KeyPress, KeyDown})
    seq = iomap.input
    sel = getfield(seq, :selection)[]
    if sel !== nothing
        fc = _block_seq_focused_child(iomap, sel)
        if fc !== nothing
            child, steps = fc
            child_op = read_intent(child.projection, child, evt)
            child_op === nothing || return reroot_operation(child_op, steps)
        end
    end
    return read_gesture(seq, evt)
end

# ── Compound convenience constructor ────────────────────────────────────────

"""
    YamlToSyntax(; style::Symbol = :block, theme = nothing, syntax_theme = nothing)

Build the YAML → Syntax projection. `style` is `:block` (idiomatic block YAML) or
`:flow` (JSON-superset flow YAML). See the module docstring. The builder gives
each projection the style of its role with `get_yaml_style`, from `theme`, a
`YamlTheme` scaled or not, or the default styles for `nothing`; `syntax_theme`
styles the insertion and the empty placeholder, which are the syntax slice's.
"""
function YamlToSyntax(; style::Symbol = :block, theme = nothing, syntax_theme = nothing)
    style in (:block, :flow) || error("YamlToSyntax: style must be :block or :flow, got :$style")
    get_style(name) = get_yaml_style(theme, name)
    sequence = style === :flow ?
        YamlSequenceToSyntaxNode(; delimiter_style = get_style(:delimiter_text),
                                   separator_style = get_style(:separator_text)) :
        YamlSequenceToBlockSyntaxNode(; marker_style = get_style(:delimiter_text))
    mapping  = style === :flow ?
        YamlMappingToSyntaxNode(; open="{", close="}", sep=", ", indent=1,
                                 delimiter_style = get_style(:delimiter_text),
                                 separator_style = get_style(:separator_text),
                                 key_style = get_style(:key_text),
                                 colon_style = get_style(:separator_text)) :
        YamlMappingToSyntaxNode(; delimiter_style = get_style(:delimiter_text),
                                 separator_style = get_style(:separator_text),
                                 key_style = get_style(:key_text),
                                 colon_style = get_style(:separator_text))
    TypeDispatchingProjection(
        YamlNull         => YamlNullToSyntaxLeaf(; style = get_style(:null_text)),
        YamlBool         => YamlBoolToSyntaxLeaf(; style = get_style(:bool_text)),
        YamlNumber       => YamlNumberToSyntaxLeaf(; style = get_style(:number_text)),
        YamlString       => YamlStringToSyntaxLeaf(; style = get_style(:string_text)),
        YamlSequence     => sequence,
        YamlMapping      => mapping,
        YamlInsertion    => YamlInsertionToSyntaxLeaf(; theme = syntax_theme),
        YamlNothing      => InsertionNothingToSyntaxLeaf(; theme = syntax_theme),
        YamlMappingEntry => CopyingProjection(),
        Vector{Cell}     => CopyingProjection(),
    )
end

# ── What this domain's natural notation is ──────────────────────────────────
# YAML was the one source domain that declared none of this, so a caller that
# asked the seam rather than the domain — the assistant's fenced code blocks, for
# one — got nothing for it while JSON, XML, Julia and Markdown worked.

function __init__()
    register_natural_domain!(YamlDocument;
                             rung      = :syntax,
                             make      = (; appearance) -> YamlToSyntax(;
                                 theme = get_scaled_theme!(appearance, YamlTheme),
                                 syntax_theme = get_scaled_theme!(appearance, SyntaxTheme)),
                             format    = :yaml,
                             extension = ".yaml",
                             parse     = parse_yaml)
    # `.yml` is the same format under the other spelling, and a fenced block is
    # written either way.
    register_natural_parser!(:yml, parse_yaml)

    # Both spellings open as the same file document type.
    register_file_document_type!(".yaml", YamlFile)
    register_file_document_type!(".yml",  YamlFile)
end
