"""
    WorkbenchToWidgetModule

WorkbenchDocument → WidgetDocument projection. Maps the workbench document
hierarchy to a widget tree.

    WorkbenchWorkbench  → WidgetShell containing a horizontal WidgetSplitPane
    WorkbenchPage       → WidgetTabbedPane with one tab per panel
    WorkbenchNavigator  → WidgetScrollPane wrapping a WidgetComposite of folders
    WorkbenchConsole    → WidgetScrollPane wrapping projected content
    WorkbenchDescriptor → WidgetScrollPane wrapping a TextText that renders the content reference
    WorkbenchOperator   → empty WidgetScrollPane
    WorkbenchSearcher   → empty WidgetScrollPane
    WorkbenchEvaluator  → WidgetScrollPane wrapping projected content
    WorkbenchAssistant  → WidgetScrollPane wrapping projected content
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
import ..TextModule: TextText, TextString
import ..FontModule: font_ubuntu_monospace_regular_24
import ..ColorModule: StyleColor, color_default
import ..IoMapModule: SimpleIoMap, ContentIoMap, ChildrenIoMap
import ..ReactiveModule: Cell
import ..IoMapApiModule: IoMap
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..OperationModule: ReplaceSelectionOperation
import ..KeyboardModule: KeyDown
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, ElementReference, PositionReference, RangeReference, EmptyReferencePath, FieldReference, append_reference
export WorkbenchWorkbenchToWidgetShell,    WorkbenchWorkbenchToWidgetShellIoMap,
       WorkbenchPageToWidgetTabbedPane,    WorkbenchPageToWidgetTabbedPaneIoMap,
       WorkbenchNavigatorToWidgetScrollPane, WorkbenchNavigatorToWidgetScrollPaneIoMap,
       WorkbenchConsoleToWidgetScrollPane,
       WorkbenchDescriptorToWidgetScrollPane,
       WorkbenchOperatorToWidgetScrollPane,
       WorkbenchSearcherToWidgetScrollPane,
       WorkbenchEvaluatorToWidgetScrollPane,
       WorkbenchAssistantToWidgetScrollPane,
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
struct WorkbenchAssistantToWidgetScrollPane <: Projection end
struct WorkbenchEditorToWidgetScrollPane    <: Projection end

# ── IoMap structs ─────────────────────────────────────────────────────────────

struct WorkbenchWorkbenchToWidgetShellIoMap <: IoMap
    projection::Any
    input::WorkbenchWorkbench
    output::WidgetShell
    navigation_page_iomap::Any   # IoMap for navigation_page
    editing_page_iomap::Any      # IoMap for editing_page
    information_page_iomap::Any  # IoMap for information_page
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

_recurse(recursion, doc, reference) =
    (recursion !== nothing && doc isa WorkbenchDocument) ? projection_print(recursion, doc, recursion, reference) : SimpleIoMap(nothing, doc, doc)

_title_widget(doc::WorkbenchDocument) = title(doc)

# ── projection_print ──────────────────────────────────────────────────────────

function projection_print(::WorkbenchWorkbenchToWidgetShell,
                           w::WorkbenchWorkbench, recursion, reference)
    nav_iomap  = _recurse(recursion, w.navigation_page,  append_reference(reference, FieldReference("navigation_page")))
    edit_iomap = _recurse(recursion, w.editing_page,     append_reference(reference, FieldReference("editing_page")))
    info_iomap = _recurse(recursion, w.information_page, append_reference(reference, FieldReference("information_page")))
    right_split = WidgetSplitPane(:vertical,
                                  WidgetDocument[edit_iomap.output, info_iomap.output];
                                  sizes=[800, 200])
    main_split  = WidgetSplitPane(:horizontal,
                                  WidgetDocument[nav_iomap.output, right_split];
                                  sizes=[200, 1000])
    shell = WidgetShell(main_split;
                        size=Point2D(1280, 720),
                        border=_PAD5)
    WorkbenchWorkbenchToWidgetShellIoMap(nothing, w, shell, nav_iomap, edit_iomap, info_iomap)
end

function projection_print(::WorkbenchPageToWidgetTabbedPane,
                           page::WorkbenchPage, recursion, reference)
    element_iomaps = Any[_recurse(recursion, page.elements[i],
                             append_reference(reference, FieldReference("elements"), ElementReference(i)))
                         for i in eachindex(page.elements)]
    pairs = Any[(_title_widget(page.elements[i]), element_iomaps[i].output)
                for i in eachindex(page.elements)]
    tabbed = WidgetTabbedPane(pairs; border=_PAD5)
    WorkbenchPageToWidgetTabbedPaneIoMap(nothing, page, tabbed, element_iomaps)
end

function projection_print(::WorkbenchNavigatorToWidgetScrollPane,
                           nav::WorkbenchNavigator, recursion, reference)
    folder_iomaps = Any[]
    for i in eachindex(nav.folders)
        folder = nav.folders[i]
        name   = hasproperty(folder, :pathname) ? basename(folder.pathname) : string(folder)
        label  = WidgetLabel(Point2D(0, 0), name)
        push!(folder_iomaps, SimpleIoMap(nothing, folder, label))
    end
    composite = WidgetComposite(Point2D(0, 0),
                                WidgetDocument[fm.output for fm in folder_iomaps])
    scroll = WidgetScrollPane(composite;
                              size=Point2D(224, 655),
                              padding=_PAD5, padding_color=_WHITE)
    WorkbenchNavigatorToWidgetScrollPaneIoMap(nothing, nav, scroll, folder_iomaps)
end

function projection_print(::WorkbenchConsoleToWidgetScrollPane,
                           c::WorkbenchConsole, recursion, reference)
    content_iomap = _recurse(recursion, c.content, append_reference(reference, FieldReference("content")))
    scroll = WidgetScrollPane(content_iomap.output;
                              size=Point2D(1000, 130),
                              padding=_PAD5, padding_color=_WHITE)
    ContentIoMap(nothing, c, scroll, content_iomap)
end

function projection_print(::WorkbenchDescriptorToWidgetScrollPane,
                           d::WorkbenchDescriptor, recursion, reference)
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
                           o::WorkbenchOperator, recursion, reference)
    scroll = WidgetScrollPane(nothing;
                              size=Point2D(1000, 130),
                              padding=_PAD5, padding_color=_WHITE)
    SimpleIoMap(nothing, o, scroll)
end

function projection_print(::WorkbenchSearcherToWidgetScrollPane,
                           s::WorkbenchSearcher, recursion, reference)
    scroll = WidgetScrollPane(nothing;
                              size=Point2D(1000, 130),
                              padding=_PAD5, padding_color=_WHITE)
    SimpleIoMap(nothing, s, scroll)
end

function projection_print(::WorkbenchEvaluatorToWidgetScrollPane,
                           e::WorkbenchEvaluator, recursion, reference)
    content_iomap = _recurse(recursion, e.content, append_reference(reference, FieldReference("content")))
    scroll = WidgetScrollPane(content_iomap.output;
                              size=Point2D(1000, 130),
                              padding=_PAD5, padding_color=_WHITE)
    ContentIoMap(nothing, e, scroll, content_iomap)
end

function projection_print(::WorkbenchAssistantToWidgetScrollPane,
                           a::WorkbenchAssistant, recursion, reference)
    # Both children are WidgetScrollPanes whose `content` is the underlying
    # document. `WidgetScrollPaneToGraphicsCanvas.projection_print` calls
    # `projection_print(recursion, content, …)` directly, so the outer
    # TypeDispatchingProjection routes `ConversationDocument` to
    # `ConversationToWidget` and `PrimitiveDocument` (the input) to the
    # Primitive→Syntax→Text→Graphics chain. This is also what makes the
    # `PrimitiveStringToSyntaxLeaf` reader receive `KeyPress` events.
    conv_pane  = WidgetScrollPane(a.conversation;
                                  size=Point2D(1000, 400),
                                  padding=_PAD5, padding_color=_WHITE)
    input_pane = WidgetScrollPane(a.input;
                                  size=Point2D(1000, 40),
                                  padding=_PAD5, padding_color=_WHITE)
    column = WidgetSplitPane(:vertical,
                             WidgetDocument[conv_pane, input_pane];
                             sizes=[400, 40])
    SimpleIoMap(nothing, a, column)
end

function projection_print(::WorkbenchEditorToWidgetScrollPane,
                           e::WorkbenchEditor, recursion, reference)
    content_iomap = _recurse(recursion, e.content, append_reference(reference, FieldReference("content")))
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
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    h isa FieldReference && h.name == "folders" || return nothing
    rest = reference.tail
    rest isa ConcreteReferencePath || return nothing
    h2 = rest.head
    h2 isa RangeReference || return nothing
    idx = h2.start + 1
    1 <= idx <= length(iomap.folder_iomaps) || return nothing
    map_reference_forward(nothing, iomap.folder_iomaps[idx], rest.tail)
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

function map_reference_forward(::WorkbenchAssistantToWidgetScrollPane,
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

function map_reference_backward(::WorkbenchAssistantToWidgetScrollPane,
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
    for (field_name, page_iomap) in (("navigation_page",  iomap.navigation_page_iomap),
                                      ("editing_page",     iomap.editing_page_iomap),
                                      ("information_page", iomap.information_page_iomap))
        page_iomap isa WorkbenchPageToWidgetTabbedPaneIoMap || continue
        result = projection_read(WorkbenchPageToWidgetTabbedPane(), page_iomap, op)
        result isa ReplaceSelectionOperation || continue
        return ReplaceSelectionOperation(
            ConcreteReferencePath(FieldReference(field_name), result.path))
    end
    op
end

function projection_read(::WorkbenchPageToWidgetTabbedPane,
                          iomap::WorkbenchPageToWidgetTabbedPaneIoMap, op)
    op isa SelectTabOperation || return op
    op.widget === iomap.output || return op
    idx = op.tab_index
    1 <= idx <= length(iomap.input.elements) || return op
    getfield(iomap.output, :selection)[] =
        ConcreteReferencePath(ElementReference(idx), EmptyReferencePath())
    ReplaceSelectionOperation(
        ConcreteReferencePath(FieldReference("elements"),
            ConcreteReferencePath(ElementReference(idx), EmptyReferencePath())))
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

function projection_read(::WorkbenchAssistantToWidgetScrollPane,
                          iomap, op)
    # Return nothing for unhandled events so the Sequential walker keeps
    # searching. The specific KeyPress/KeyDown methods live in
    # `WorkbenchAssistantModule` (loaded later in the include chain) and
    # take precedence via multiple dispatch.
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
        WorkbenchAssistant  => WorkbenchAssistantToWidgetScrollPane(),
        WorkbenchEditor     => WorkbenchEditorToWidgetScrollPane(),
    )
end

end # module
