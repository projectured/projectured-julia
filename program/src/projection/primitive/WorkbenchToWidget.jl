"""
    WorkbenchToWidgetModule

WorkbenchDocument → WidgetDocument projection. Maps the workbench document
hierarchy to a widget tree.

    WorkbenchWorkbench  → WidgetShell containing a horizontal WidgetSplitPane
                          (navigation | center | control), where the center
                          is itself a vertical split of editing / information
    WorkbenchPage       → WidgetTabbedPane with one tab per panel
    WorkbenchNavigator  → WidgetScrollPane wrapping a WidgetComposite of folders
    WorkbenchConsole    → WidgetScrollPane wrapping projected content
    WorkbenchDescriptor → WidgetScrollPane wrapping a TextText that renders the content reference
    WorkbenchOperator   → empty WidgetScrollPane
    WorkbenchSearcher   → empty WidgetScrollPane
    WorkbenchEvaluator  → WidgetScrollPane wrapping projected content
    WorkbenchAssistant  → WidgetSplitPane (vertical) of conversation + input WidgetScrollPanes
    WorkbenchEditor     → WidgetScrollPane wrapping projected content
"""
module WorkbenchToWidgetModule

import ..ProjectionApiModule: projection_print, projection_read,
                               map_reference_forward, map_reference_backward, Projection
import ..WorkbenchModule: WorkbenchDocument, WorkbenchWorkbench, WorkbenchPage,
                          WorkbenchNavigator, WorkbenchConsole, WorkbenchDescriptor,
                          WorkbenchOperator, WorkbenchSearcher, WorkbenchEvaluator,
                          WorkbenchAssistant,
                          WorkbenchEditor, title
import ..WidgetModule: WidgetDocument, WidgetLabel, WidgetText, WidgetShell, WidgetSplitPane, WidgetTabbedPane,
                       WidgetScrollPane, WidgetComposite, Point2D, Inset, inset_default,
                       SelectTabOperation
import ..LayoutModule: LayoutConstraint
import ..TextModule: TextText, TextString
import ..FontModule: font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_default
import ..IoMapModule: SimpleIoMap, ContentIoMap, ChildrenIoMap
import ..ReactiveModule: Cell
import ..IoMapApiModule: IoMap
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..OperationModule: ReplaceSelectionOperation
import ..OperationApiModule: Operation
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation
import ..KeyboardModule: KeyDown
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, ElementReference, PositionReference, RangeReference, EmptyReferencePath, FieldReference, append_reference
import ..ReferenceBuilderModule: var"@reference"
import ..ProjectionContextModule: child_context
export WorkbenchWorkbenchToWidgetShell,    WorkbenchWorkbenchToWidgetShellIoMap,
       WorkbenchPageToWidgetTabbedPane,    WorkbenchPageToWidgetTabbedPaneIoMap,
       WorkbenchNavigatorToWidgetScrollPane, WorkbenchNavigatorToWidgetScrollPaneIoMap,
       WorkbenchConsoleToWidgetScrollPane,
       WorkbenchDescriptorToWidgetScrollPane,
       WorkbenchOperatorToWidgetScrollPane,
       WorkbenchSearcherToWidgetScrollPane,
       WorkbenchEvaluatorToWidgetScrollPane,
       WorkbenchAssistantToWidgetSplitPane,
       WorkbenchEditorToWidgetScrollPane,
       WorkbenchToWidget

# ── Projection structs ────────────────────────────────────────────────────────

struct WorkbenchWorkbenchToWidgetShell    <: Projection end
struct WorkbenchPageToWidgetTabbedPane    <: Projection end
struct WorkbenchNavigatorToWidgetScrollPane <: Projection end
struct WorkbenchConsoleToWidgetScrollPane   <: Projection end
struct WorkbenchDescriptorToWidgetScrollPane <: Projection end
struct WorkbenchOperatorToWidgetScrollPane  <: Projection end
struct WorkbenchSearcherToWidgetScrollPane  <: Projection end
struct WorkbenchEvaluatorToWidgetScrollPane <: Projection end
struct WorkbenchAssistantToWidgetSplitPane <: Projection end
struct WorkbenchEditorToWidgetScrollPane    <: Projection end

# ── IoMap structs ─────────────────────────────────────────────────────────────

struct WorkbenchWorkbenchToWidgetShellIoMap <: IoMap
    projection::Any
    input::WorkbenchWorkbench
    output::WidgetShell
    navigation_page_iomap::Any   # IoMap for navigation_page
    editing_page_iomap::Any      # IoMap for editing_page
    information_page_iomap::Any  # IoMap for information_page
    control_page_iomap::Any      # IoMap for control_page
end

struct WorkbenchPageToWidgetTabbedPaneIoMap <: IoMap
    projection::Any
    input::WorkbenchPage
    output::WidgetTabbedPane
    element_iomaps::Vector       # one IoMap per page element
end

struct WorkbenchNavigatorToWidgetScrollPaneIoMap <: IoMap
    projection::Any
    input::WorkbenchNavigator
    output::WidgetScrollPane
    folder_iomaps::Vector        # one IoMap per folder
end


# ── Helpers ───────────────────────────────────────────────────────────────────

const _PAD5  = Inset(5, 5, 5, 5)
const _WHITE = StyleColor(255, 255, 255, 255)

_recurse(recursion, doc, ctx) =
    (recursion !== nothing && doc isa WorkbenchDocument) ? projection_print(recursion, doc, recursion, ctx) : SimpleIoMap(nothing, doc, doc)

_title_widget(doc::WorkbenchDocument) = title(doc)

# ── projection_print ──────────────────────────────────────────────────────────

function projection_print(::WorkbenchWorkbenchToWidgetShell,
                           w::WorkbenchWorkbench, recursion, ctx)
    nav_iomap  = _recurse(recursion, w.navigation_page,  child_context(ctx, @reference ^(ctx.reference).navigation_page))
    edit_iomap = _recurse(recursion, w.editing_page,     child_context(ctx, @reference ^(ctx.reference).editing_page))
    info_iomap = _recurse(recursion, w.information_page, child_context(ctx, @reference ^(ctx.reference).information_page))
    ctrl_iomap = _recurse(recursion, w.control_page,     child_context(ctx, @reference ^(ctx.reference).control_page))
    # Center column: editor fills remaining height, info pane pinned to 200.
    center_split = WidgetSplitPane(:vertical, Any[
        LayoutConstraint(edit_iomap.output; weight_height=1.0),
        LayoutConstraint(info_iomap.output; min_height=200, max_height=200),
    ])
    # Top level: navigator pinned to 200 wide on the left, control pinned to
    # 400 wide on the right (room for the assistant's chat layout), center
    # column fills the rest.
    main_split = WidgetSplitPane(:horizontal, Any[
        LayoutConstraint(nav_iomap.output;  min_width=200, max_width=200),
        LayoutConstraint(center_split;      weight_width=1.0),
        LayoutConstraint(ctrl_iomap.output; min_width=400, max_width=400),
    ])
    # Track the window: the shell fills whatever extent the parent (the
    # WindowDocument's CopyingProjection) seeded on the context, falling
    # back to a sensible default when run outside a window.
    aw, ah = ctx.available_width, ctx.available_height
    shell_size = Point2D(
        Cell(() -> aw === nothing ? 1280 : Int(aw[])),
        Cell(() -> ah === nothing ? 720  : Int(ah[])),
    )
    shell = WidgetShell(main_split;
                        size=shell_size,
                        border=_PAD5)
    WorkbenchWorkbenchToWidgetShellIoMap(nothing, w, shell,
                                         nav_iomap, edit_iomap, info_iomap, ctrl_iomap)
end

function projection_print(::WorkbenchPageToWidgetTabbedPane,
                           page::WorkbenchPage, recursion, ctx)
    element_iomaps = Any[_recurse(recursion, page.elements[i],
                             child_context(ctx, @reference ^(ctx.reference).elements[i]))
                         for i in eachindex(page.elements)]
    pairs = Any[(_title_widget(page.elements[i]), element_iomaps[i].output)
                for i in eachindex(page.elements)]
    tabbed = WidgetTabbedPane(pairs; border=_PAD5)
    WorkbenchPageToWidgetTabbedPaneIoMap(nothing, page, tabbed, element_iomaps)
end

function projection_print(::WorkbenchNavigatorToWidgetScrollPane,
                           nav::WorkbenchNavigator, recursion, ctx)
    scroll = WidgetScrollPane(nav.workspace;
                              size=Point2D(224, 655),
                              padding=_PAD5, padding_color=_WHITE)
    WorkbenchNavigatorToWidgetScrollPaneIoMap(nothing, nav, scroll, Any[])
end

function projection_print(::WorkbenchConsoleToWidgetScrollPane,
                           c::WorkbenchConsole, recursion, ctx)
    content_iomap = _recurse(recursion, c.content, child_context(ctx, @reference ^(ctx.reference).content))
    scroll = WidgetScrollPane(content_iomap.output;
                              size=Point2D(1000, 130),
                              padding=_PAD5, padding_color=_WHITE)
    ContentIoMap(nothing, c, scroll, content_iomap)
end

function projection_print(::WorkbenchDescriptorToWidgetScrollPane,
                           d::WorkbenchDescriptor, recursion, ctx)
    text = TextText(
        TextString(() -> string(d.content),
                   font_ubuntu_monospace_regular_24, color_default),
    )
    scroll = WidgetScrollPane(text;
                              size=Point2D(1000, 130),
                              padding=_PAD5, padding_color=_WHITE)
    SimpleIoMap(nothing, d, scroll)
end

function projection_print(::WorkbenchOperatorToWidgetScrollPane,
                           o::WorkbenchOperator, recursion, ctx)
    scroll = WidgetScrollPane(nothing;
                              size=Point2D(1000, 130),
                              padding=_PAD5, padding_color=_WHITE)
    SimpleIoMap(nothing, o, scroll)
end

function projection_print(::WorkbenchSearcherToWidgetScrollPane,
                           s::WorkbenchSearcher, recursion, ctx)
    scroll = WidgetScrollPane(nothing;
                              size=Point2D(1000, 130),
                              padding=_PAD5, padding_color=_WHITE)
    SimpleIoMap(nothing, s, scroll)
end

function projection_print(::WorkbenchEvaluatorToWidgetScrollPane,
                           e::WorkbenchEvaluator, recursion, ctx)
    content_iomap = _recurse(recursion, e.content, child_context(ctx, @reference ^(ctx.reference).content))
    scroll = WidgetScrollPane(content_iomap.output;
                              size=Point2D(1000, 130),
                              padding=_PAD5, padding_color=_WHITE)
    ContentIoMap(nothing, e, scroll, content_iomap)
end

function projection_print(::WorkbenchAssistantToWidgetSplitPane,
                           a::WorkbenchAssistant, recursion, ctx)
    # Both children are WidgetScrollPanes whose `content` is the underlying
    # document. `WidgetScrollPaneToGraphicsCanvas.projection_print` calls
    # `projection_print(recursion, content, …)` directly, so the outer
    # TypeDispatchingProjection routes `ConversationDocument` to
    # `ConversationToWidget` and `PrimitiveDocument` (the input) to the
    # Primitive→Syntax→Text→Graphics chain. This is also what makes the
    # `PrimitiveStringToSyntaxLeaf` reader receive `KeyPress` events.
    conv_pane  = WidgetScrollPane(a.conversation;
                                  size=Point2D(1600, 1600),
                                  padding=_PAD5, padding_color=_WHITE)
    input_pane = WidgetScrollPane(a.input;
                                  size=Point2D(1600, 90),
                                  padding=_PAD5, padding_color=_WHITE)
    # Line height with `font_ubuntu_monospace_regular_24` ≈ 30 px, so the
    # input box reserves 1–6 rows (preferred 3); the conversation pane
    # absorbs the remainder of the parent's available height.
    column = WidgetSplitPane(:vertical, Any[
        LayoutConstraint(conv_pane;  weight_height=1.0),
        LayoutConstraint(input_pane;
                         min_height=30, preferred_height=90, max_height=180),
    ])
    SimpleIoMap(nothing, a, column)
end

function projection_print(::WorkbenchEditorToWidgetScrollPane,
                           e::WorkbenchEditor, recursion, ctx)
    content_iomap = _recurse(recursion, e.content, child_context(ctx, @reference ^(ctx.reference).content))
    scroll = WidgetScrollPane(content_iomap.output;
                              size=Point2D(1000, 700),
                              padding=_PAD5, padding_color=_WHITE)
    ContentIoMap(nothing, e, scroll, content_iomap)
end

# ── map_reference_forward ─────────────────────────────────────────────────────

function map_reference_forward(::WorkbenchWorkbenchToWidgetShell,
                                iomap::WorkbenchWorkbenchToWidgetShellIoMap,
                                reference)
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    h isa FieldReference || return nothing
    rest = reference.tail
    if h.name == "navigation_page"
        return map_reference_forward(nothing, iomap.navigation_page_iomap, rest)
    elseif h.name == "editing_page"
        return map_reference_forward(nothing, iomap.editing_page_iomap, rest)
    elseif h.name == "information_page"
        return map_reference_forward(nothing, iomap.information_page_iomap, rest)
    elseif h.name == "control_page"
        return map_reference_forward(nothing, iomap.control_page_iomap, rest)
    end
    return nothing
end

function map_reference_forward(::WorkbenchPageToWidgetTabbedPane,
                                iomap::WorkbenchPageToWidgetTabbedPaneIoMap,
                                reference)
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    h isa FieldReference && h.name == "elements" || return nothing
    rest = reference.tail
    rest isa ConcreteReferencePath || return nothing
    h2 = rest.head
    h2 isa RangeReference || return nothing
    idx = h2.start + 1
    1 <= idx <= length(iomap.element_iomaps) || return nothing
    map_reference_forward(nothing, iomap.element_iomaps[idx], rest.tail)
end

function map_reference_forward(::WorkbenchNavigatorToWidgetScrollPane,
                                iomap::WorkbenchNavigatorToWidgetScrollPaneIoMap,
                                reference)
    return nothing
end

function map_reference_forward(::WorkbenchConsoleToWidgetScrollPane,
                                iomap::ContentIoMap,
                                reference)
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    h isa FieldReference && h.name == "content" || return nothing
    map_reference_forward(nothing, iomap.inner_iomap, reference.tail)
end

function map_reference_forward(::WorkbenchDescriptorToWidgetScrollPane,
                                iomap,
                                reference)
    return nothing
end

function map_reference_forward(::WorkbenchOperatorToWidgetScrollPane, iomap, reference)
    return nothing
end

function map_reference_forward(::WorkbenchSearcherToWidgetScrollPane, iomap, reference)
    return nothing
end

function map_reference_forward(::WorkbenchEvaluatorToWidgetScrollPane,
                                iomap::ContentIoMap,
                                reference)
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    h isa FieldReference && h.name == "content" || return nothing
    map_reference_forward(nothing, iomap.inner_iomap, reference.tail)
end

function map_reference_forward(::WorkbenchAssistantToWidgetSplitPane,
                                iomap,
                                reference)
    return nothing
end

function map_reference_forward(::WorkbenchEditorToWidgetScrollPane,
                                iomap::ContentIoMap,
                                reference)
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    h isa FieldReference && h.name == "content" || return nothing
    map_reference_forward(nothing, iomap.inner_iomap, reference.tail)
end

# ── map_reference_backward ────────────────────────────────────────────────────

function map_reference_backward(::WorkbenchWorkbenchToWidgetShell,
                                 iomap::WorkbenchWorkbenchToWidgetShellIoMap,
                                 reference)
    return nothing
end

function map_reference_backward(::WorkbenchPageToWidgetTabbedPane,
                                 iomap::WorkbenchPageToWidgetTabbedPaneIoMap,
                                 reference)
    return nothing
end

function map_reference_backward(::WorkbenchNavigatorToWidgetScrollPane,
                                 iomap::WorkbenchNavigatorToWidgetScrollPaneIoMap,
                                 reference)
    return nothing
end

function map_reference_backward(::WorkbenchConsoleToWidgetScrollPane,
                                 iomap::ContentIoMap,
                                 reference)
    return nothing
end

function map_reference_backward(::WorkbenchDescriptorToWidgetScrollPane, iomap, reference)
    return nothing
end

function map_reference_backward(::WorkbenchOperatorToWidgetScrollPane, iomap, reference)
    return nothing
end

function map_reference_backward(::WorkbenchSearcherToWidgetScrollPane, iomap, reference)
    return nothing
end

function map_reference_backward(::WorkbenchEvaluatorToWidgetScrollPane,
                                 iomap::ContentIoMap,
                                 reference)
    return nothing
end

function map_reference_backward(::WorkbenchAssistantToWidgetSplitPane,
                                 iomap,
                                 reference)
    return nothing
end

function map_reference_backward(::WorkbenchEditorToWidgetScrollPane,
                                 iomap::ContentIoMap,
                                 reference)
    return nothing
end

# ── projection_read ───────────────────────────────────────────────────────────

function projection_read(::WorkbenchWorkbenchToWidgetShell,
                          iomap::WorkbenchWorkbenchToWidgetShellIoMap, op)
    # 1. Tab-selection forwarding (e.g. a click that maps to selecting a tab).
    for (field_name, page_iomap) in (("navigation_page",  iomap.navigation_page_iomap),
                                      ("editing_page",     iomap.editing_page_iomap),
                                      ("information_page", iomap.information_page_iomap),
                                      ("control_page",     iomap.control_page_iomap))
        page_iomap isa WorkbenchPageToWidgetTabbedPaneIoMap || continue
        result = projection_read(WorkbenchPageToWidgetTabbedPane(), page_iomap, op)
        result isa ReplaceSelectionOperation || continue
        return ReplaceSelectionOperation(
            ConcreteReferencePath(FieldReference(field_name), result.path))
    end
    # 2. If the op is already an Operation produced by an inner reader
    # (e.g. `ScrollWidgetOperation` from `WidgetScrollPaneToGraphicsCanvas`),
    # pass it through unchanged. These ops target widgets/documents
    # directly, not document paths, so they need no further translation.
    op isa Operation && return op
    # 3. Route raw events (e.g. KeyPress / KeyDown) into each panel reader so
    # focus-sensitive handlers (currently only the assistant) can pick them
    # up. The first reader that returns an Operation wins. Path-bearing
    # operations get prefixed with the panel's location so
    # `evaluate_operation` can walk the path against the workbench root.
    wb2w = WorkbenchToWidget()
    for (field_name, page_iomap) in (("navigation_page",  iomap.navigation_page_iomap),
                                      ("editing_page",     iomap.editing_page_iomap),
                                      ("information_page", iomap.information_page_iomap),
                                      ("control_page",     iomap.control_page_iomap))
        page_iomap isa WorkbenchPageToWidgetTabbedPaneIoMap || continue
        for (elem_idx, elem_iomap) in enumerate(page_iomap.element_iomaps)
            result = projection_read(wb2w, elem_iomap, op)
            result isa Operation || continue
            prefix = (FieldReference(field_name),
                      FieldReference("elements"),
                      RangeReference(elem_idx - 1, elem_idx))
            return _prefix_operation(result, prefix)
        end
    end
    return nothing
end

# Prepend `prefix_steps` to the path inside `op`, if the op carries a path.
# Operations that target a captured Julia value (e.g. SubmitProseOperation
# holds its WorkbenchAssistant directly) need no prefixing.
function _prefix_operation(op, prefix_steps::Tuple)
    if op isa StringReplaceRangeOperation
        return StringReplaceRangeOperation(_prepend_path(prefix_steps, op.reference),
                                           op.replacement)
    elseif op isa NumberReplaceRangeOperation
        return NumberReplaceRangeOperation(_prepend_path(prefix_steps, op.reference),
                                           op.replacement)
    elseif op isa ReplaceSelectionOperation
        return ReplaceSelectionOperation(_prepend_path(prefix_steps, op.path))
    else
        return op
    end
end

function _prepend_path(steps::Tuple, path::ReferencePath)
    result = path
    for step in reverse(steps)
        result = ConcreteReferencePath(step, result)
    end
    result
end

function projection_read(::WorkbenchPageToWidgetTabbedPane,
                          iomap::WorkbenchPageToWidgetTabbedPaneIoMap, op)
    op isa SelectTabOperation || return op
    op.widget === iomap.output || return op
    idx = op.tab_index
    1 <= idx <= length(iomap.input.elements) || return op
    getfield(iomap.output, :selection)[] = @reference [idx]
    ReplaceSelectionOperation(@reference elements[idx])
end

function projection_read(::WorkbenchNavigatorToWidgetScrollPane,
                          iomap::WorkbenchNavigatorToWidgetScrollPaneIoMap, op)
    op
end

function projection_read(::WorkbenchConsoleToWidgetScrollPane,
                          iomap::ContentIoMap, op)
    op
end

function projection_read(::WorkbenchDescriptorToWidgetScrollPane, iomap, op)
    op
end

function projection_read(::WorkbenchOperatorToWidgetScrollPane, iomap, op)
    op
end

function projection_read(::WorkbenchSearcherToWidgetScrollPane, iomap, op)
    op
end

function projection_read(::WorkbenchEvaluatorToWidgetScrollPane,
                          iomap::ContentIoMap, op)
    op
end

function projection_read(::WorkbenchAssistantToWidgetSplitPane,
                          iomap, op)
    # Operations produced by an inner reader (e.g. ScrollWidgetOperation
    # from the conversation scroll pane) pass through unchanged.
    # Unhandled raw events return `nothing` so the Sequential walker
    # keeps searching. The specific KeyPress / KeyDown handlers live in
    # `WorkbenchAssistantModule` (loaded later in the include chain) and
    # take precedence via multiple dispatch.
    op isa Operation && return op
    nothing
end

function projection_read(::WorkbenchEditorToWidgetScrollPane,
                          iomap::ContentIoMap, op)
    op
end

# ── Factory ───────────────────────────────────────────────────────────────────

"""
    WorkbenchToWidget()

Build a type-dispatching projection that maps any `WorkbenchDocument`
subtree to the corresponding `WidgetDocument` tree.

The compound projections (`WorkbenchWorkbench`, `WorkbenchPage`,
`WorkbenchNavigator`) recurse back through this same projection for their
child documents. Wrap the result in `RecursiveProjection` at the call site
to enable that recursion.
"""
function WorkbenchToWidget()
    TypeDispatchingProjection(
        WorkbenchWorkbench  => WorkbenchWorkbenchToWidgetShell(),
        WorkbenchPage       => WorkbenchPageToWidgetTabbedPane(),
        WorkbenchNavigator  => WorkbenchNavigatorToWidgetScrollPane(),
        WorkbenchConsole    => WorkbenchConsoleToWidgetScrollPane(),
        WorkbenchDescriptor => WorkbenchDescriptorToWidgetScrollPane(),
        WorkbenchOperator   => WorkbenchOperatorToWidgetScrollPane(),
        WorkbenchSearcher   => WorkbenchSearcherToWidgetScrollPane(),
        WorkbenchEvaluator  => WorkbenchEvaluatorToWidgetScrollPane(),
        WorkbenchAssistant  => WorkbenchAssistantToWidgetSplitPane(),
        WorkbenchEditor     => WorkbenchEditorToWidgetScrollPane(),
    )
end

end # module
