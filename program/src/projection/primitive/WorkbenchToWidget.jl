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
import ..ReferenceCaseModule: var"@reference_case"
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

# ── map_reference_backward ──────────────────────────────────────────────
#
# Each panel projection translates a widget-domain reference (what the
# combined widget→graphics chain produced) into a workbench-domain
# reference rooted at this panel's input document. Widget-side readers
# have already prepended their structural steps (`content` for a scroll
# pane, `selector_element_pairs[i]` for a tabbed pane, `elements[i].child`
# for a split pane slot wrapped in a LayoutConstraint); the panel
# projections strip the widget naming and re-root with the panel's own
# workbench field name. The default `projection_read` consults these
# functions to translate `ReplaceSelectionOperation`, and custom
# `projection_read` overrides below extend the same translation to
# `StringReplaceRangeOperation` / `NumberReplaceRangeOperation`.

function map_reference_backward(::WorkbenchEditorToWidgetScrollPane,
                                 iomap::ContentIoMap,
                                 reference)
    @reference_case reference begin
        content.rest... => @reference content.^(rest)
    end
end

function map_reference_backward(::WorkbenchNavigatorToWidgetScrollPane,
                                 iomap::WorkbenchNavigatorToWidgetScrollPaneIoMap,
                                 reference)
    # WorkbenchNavigator stores the workspace in `.workspace`; the widget
    # scroll pane wraps it as `.content`. Rewrite the field name.
    @reference_case reference begin
        content.rest... => @reference workspace.^(rest)
    end
end

function map_reference_backward(::WorkbenchConsoleToWidgetScrollPane,
                                 iomap::ContentIoMap,
                                 reference)
    @reference_case reference begin
        content.rest... => @reference content.^(rest)
    end
end

function map_reference_backward(::WorkbenchEvaluatorToWidgetScrollPane,
                                 iomap::ContentIoMap,
                                 reference)
    @reference_case reference begin
        content.rest... => @reference content.^(rest)
    end
end

# Descriptor/Operator/Searcher render empty or non-document content — no
# referenceable structure to translate into.
function map_reference_backward(::WorkbenchDescriptorToWidgetScrollPane, iomap, reference)
    return nothing
end

function map_reference_backward(::WorkbenchOperatorToWidgetScrollPane, iomap, reference)
    return nothing
end

function map_reference_backward(::WorkbenchSearcherToWidgetScrollPane, iomap, reference)
    return nothing
end

function map_reference_backward(::WorkbenchAssistantToWidgetSplitPane,
                                 iomap,
                                 reference)
    # The assistant projects to a vertical WidgetSplitPane with the
    # conversation pane at slot 0 and the input pane at slot 1, each
    # wrapped in a LayoutConstraint and then a WidgetScrollPane.
    # So bubbled paths look like `elements[i].child.content.<rest>`.
    @reference_case reference begin
        elements{s:e}.child.content.rest... => begin
            i = s + 1
            if i == 1
                @reference conversation.^(rest)
            elseif i == 2
                @reference input.^(rest)
            else
                nothing
            end
        end
    end
end

function map_reference_backward(::WorkbenchPageToWidgetTabbedPane,
                                 iomap::WorkbenchPageToWidgetTabbedPaneIoMap,
                                 reference)
    # A WorkbenchPage projects to a WidgetTabbedPane whose
    # `selector_element_pairs[i]` corresponds 1:1 with `elements[i]` of
    # the page. Recurse via the matching element iomap so the panel's
    # own backward map can re-root its slice of the path.
    @reference_case reference begin
        selector_element_pairs{s:e}.rest... => begin
            i = s + 1
            i <= length(iomap.element_iomaps) || return nothing
            elem_im = iomap.element_iomaps[i]
            inner = _panel_backward(elem_im, rest)
            inner === nothing && return nothing
            @reference elements[i].^(inner)
        end
    end
end

# Dispatch the panel iomap's backward map by the panel input document's
# type. The panel iomaps were built by the WorkbenchToWidget factory which
# stores `projection = nothing` on the per-panel IoMap structs, so we
# can't dispatch on the stored projection — we dispatch on `input` type
# instead.
_panel_backward(elem_im, rest) = _panel_backward(elem_im.input, elem_im, rest)
_panel_backward(::WorkbenchEditor,     im, ref) = map_reference_backward(WorkbenchEditorToWidgetScrollPane(),     im, ref)
_panel_backward(::WorkbenchNavigator,  im, ref) = map_reference_backward(WorkbenchNavigatorToWidgetScrollPane(),  im, ref)
_panel_backward(::WorkbenchConsole,    im, ref) = map_reference_backward(WorkbenchConsoleToWidgetScrollPane(),    im, ref)
_panel_backward(::WorkbenchEvaluator,  im, ref) = map_reference_backward(WorkbenchEvaluatorToWidgetScrollPane(),  im, ref)
_panel_backward(::WorkbenchDescriptor, im, ref) = map_reference_backward(WorkbenchDescriptorToWidgetScrollPane(), im, ref)
_panel_backward(::WorkbenchOperator,   im, ref) = map_reference_backward(WorkbenchOperatorToWidgetScrollPane(),   im, ref)
_panel_backward(::WorkbenchSearcher,   im, ref) = map_reference_backward(WorkbenchSearcherToWidgetScrollPane(),   im, ref)
_panel_backward(::WorkbenchAssistant,  im, ref) = map_reference_backward(WorkbenchAssistantToWidgetSplitPane(),   im, ref)
_panel_backward(_, _, _)                        = nothing

function map_reference_backward(::WorkbenchWorkbenchToWidgetShell,
                                 iomap::WorkbenchWorkbenchToWidgetShellIoMap,
                                 reference)
    # The workbench shell's widget tree is:
    #   WidgetShell.content (horizontal WidgetSplitPane)
    #     elements[0].child = nav page widget   ← navigation_page
    #     elements[1].child = center (vertical WidgetSplitPane)
    #       elements[0].child = edit page widget   ← editing_page
    #       elements[1].child = info page widget   ← information_page
    #     elements[2].child = ctrl page widget  ← control_page
    @reference_case reference begin
        content.elements{0:1}.child.rest... => begin
            inner = _page_backward(iomap.navigation_page_iomap, rest)
            inner === nothing && return nothing
            @reference navigation_page.^(inner)
        end
        content.elements{1:2}.child.elements{0:1}.child.rest... => begin
            inner = _page_backward(iomap.editing_page_iomap, rest)
            inner === nothing && return nothing
            @reference editing_page.^(inner)
        end
        content.elements{1:2}.child.elements{1:2}.child.rest... => begin
            inner = _page_backward(iomap.information_page_iomap, rest)
            inner === nothing && return nothing
            @reference information_page.^(inner)
        end
        content.elements{2:3}.child.rest... => begin
            inner = _page_backward(iomap.control_page_iomap, rest)
            inner === nothing && return nothing
            @reference control_page.^(inner)
        end
    end
end

_page_backward(page_iomap::WorkbenchPageToWidgetTabbedPaneIoMap, rest) =
    map_reference_backward(WorkbenchPageToWidgetTabbedPane(), page_iomap, rest)
_page_backward(_, _) = nothing

# ── projection_read ───────────────────────────────────────────────────────────

function projection_read(p::WorkbenchWorkbenchToWidgetShell,
                          iomap::WorkbenchWorkbenchToWidgetShellIoMap, op)
    # 1. Tab-strip click: a SelectTabOperation produced by the widget
    # tabbed pane. Find which page owns the tab strip (by matching
    # `op.widget` against each page's output) and convert via the page
    # reader, then re-root under that page's workbench field name.
    if op isa SelectTabOperation
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
        return nothing
    end
    # 2. Path-bearing op from a deeper reader: translate its widget-domain
    # reference into workbench-domain via `map_reference_backward`.
    if op isa ReplaceSelectionOperation
        new_path = map_reference_backward(p, iomap, op.path)
        return new_path === nothing ? nothing : ReplaceSelectionOperation(new_path)
    end
    if op isa StringReplaceRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : StringReplaceRangeOperation(new_ref, op.replacement)
    end
    if op isa NumberReplaceRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : NumberReplaceRangeOperation(new_ref, op.replacement)
    end
    # 3. Other operation types (e.g. ScrollWidgetOperation) target widgets
    # directly, not paths — pass through.
    op isa Operation && return op
    # 4. Raw events (KeyPress / KeyDown). Route them through each panel's
    # reader so focus-sensitive handlers (currently only the assistant) can
    # pick them up. Path-bearing results get re-rooted via the panel's
    # location so `evaluate_operation` can walk the path against the
    # workbench root.
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

function projection_read(p::WorkbenchPageToWidgetTabbedPane,
                          iomap::WorkbenchPageToWidgetTabbedPaneIoMap, op)
    # Convert a tab-strip click into a workbench-domain selection move.
    if op isa SelectTabOperation
        op.widget === iomap.output || return op
        idx = op.tab_index
        1 <= idx <= length(iomap.input.elements) || return op
        getfield(iomap.output, :selection)[] = @reference [idx]
        return ReplaceSelectionOperation(@reference elements[idx])
    end
    _retarget_panel_op(p, iomap, op)
end

function projection_read(p::WorkbenchNavigatorToWidgetScrollPane,
                          iomap::WorkbenchNavigatorToWidgetScrollPaneIoMap, op)
    _retarget_panel_op(p, iomap, op)
end

function projection_read(p::WorkbenchConsoleToWidgetScrollPane,
                          iomap::ContentIoMap, op)
    _retarget_panel_op(p, iomap, op)
end

function projection_read(p::WorkbenchDescriptorToWidgetScrollPane, iomap, op)
    _retarget_panel_op(p, iomap, op)
end

function projection_read(p::WorkbenchOperatorToWidgetScrollPane, iomap, op)
    _retarget_panel_op(p, iomap, op)
end

function projection_read(p::WorkbenchSearcherToWidgetScrollPane, iomap, op)
    _retarget_panel_op(p, iomap, op)
end

function projection_read(p::WorkbenchEvaluatorToWidgetScrollPane,
                          iomap::ContentIoMap, op)
    _retarget_panel_op(p, iomap, op)
end

function projection_read(p::WorkbenchAssistantToWidgetSplitPane,
                          iomap, op)
    # The specific KeyPress / KeyDown handlers live in
    # `WorkbenchAssistantModule` (loaded later in the include chain) and
    # take precedence via multiple dispatch. For everything else that
    # reaches us, translate path-bearing ops to the assistant's input
    # domain and let widget-target ops (e.g. ScrollWidgetOperation) pass
    # through; unhandled raw events return `nothing`.
    if op isa Operation
        return _retarget_panel_op(p, iomap, op)
    end
    nothing
end

function projection_read(p::WorkbenchEditorToWidgetScrollPane,
                          iomap::ContentIoMap, op)
    _retarget_panel_op(p, iomap, op)
end

# Translate a path-bearing op via `map_reference_backward`; pass other ops
# through unchanged. Used by each workbench panel projection so the path
# walks up into the workbench-domain reference space one layer at a time.
function _retarget_panel_op(p, iomap, op)
    op === nothing && return nothing
    if op isa ReplaceSelectionOperation
        new_path = map_reference_backward(p, iomap, op.path)
        return new_path === nothing ? nothing : ReplaceSelectionOperation(new_path)
    elseif op isa StringReplaceRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : StringReplaceRangeOperation(new_ref, op.replacement)
    elseif op isa NumberReplaceRangeOperation
        new_ref = map_reference_backward(p, iomap, op.reference)
        return new_ref === nothing ? nothing : NumberReplaceRangeOperation(new_ref, op.replacement)
    else
        return op
    end
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
