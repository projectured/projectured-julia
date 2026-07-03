struct Example
    name::String
    make_document
    make_projection
    document
    projection
    # Optional presentation size for the screenshot harness. Most examples size
    # to their content; a few (e.g. the standalone assistant, which has no window
    # to fill) need a display width seeded so they render at a useful size. This
    # is a *presentation* choice and lives here, not as a fixed size baked into
    # the projection.
    render_width
    render_height
    Example(name, make_document, make_projection; render_width=nothing, render_height=nothing) =
        new(name, make_document, make_projection, make_document(), make_projection(),
            render_width, render_height)
end

const json_example           = Example("json",           make_json_document_example,           make_json_projection_example)
const json_sorted_example    = Example("json_sorted",    make_json_document_example,           make_json_sorted_projection_example)
const json_null_example      = Example("json_null",      make_json_null_document_example,      make_json_null_projection_example)
# A bare `JsonInsertion` ("insert JSON here") under the FULL json projection, so
# the placeholder can be authored into any JSON value (the leaf insertion
# projection cannot render the replacement). Editable counterpart of the scalar
# leaf examples; shares the shape of the non-registry `json_build_example`.
const json_insertion_example = Example("json_insertion", make_json_insertion_document_example, make_json_projection_example)
const json_string_example    = Example("json_string",    make_json_string_document_example,    make_json_string_projection_example)
const json_widget_example    = Example("json_widget",    make_json_document_example,           make_json_widget_projection_example)
const yaml_example           = Example("yaml",           make_yaml_document_example,           make_yaml_projection_example)
const xml_example            = Example("xml",            make_xml_document_example,            make_xml_projection_example)
const xml_widget_example     = Example("xml_widget",     make_xml_document_example,            make_xml_widget_projection_example)
const mixed_example          = Example("mixed",          make_mixed_document_example,          make_mixed_projection_example)
const natural_example        = Example("natural",        make_natural_document_example,        make_natural_projection_example)
const syntax_example         = Example("syntax",         make_syntax_document_example,         make_syntax_projection_example)
const text_example           = Example("text",           make_text_document_example,           make_text_projection_example)
const plain_text_example     = Example("plain_text",     make_plain_text_document_example,     make_plain_text_projection_example)
const text_with_image_example = Example("text_with_image", make_text_with_image_example,       make_text_projection_example)
const object_example         = Example("object",         make_object_document_example,         make_object_projection_example)
const object_to_widget_example = Example("object_to_widget", make_object_to_widget_document_example, make_object_to_widget_projection_example)
const nested_object_to_widget_example = Example("nested_object_to_widget", make_nested_object_to_widget_document_example, make_object_to_widget_projection_example)
const line_numbering_example = Example("line_numbering", make_line_numbering_document_example, make_line_numbering_projection_example)
const word_wrapping_example  = Example("word_wrapping",  make_word_wrapping_document_example,  make_word_wrapping_projection_example)
const text_filtering_example = Example("text_filtering", make_text_filtering_document_example, make_text_filtering_projection_example)
const text_highlighting_example = Example("text_highlighting", make_text_highlighting_document_example, make_text_highlighting_projection_example)
const widget_example         = Example("widget",         make_widget_document_example,         make_widget_projection_example)
const widget_label_example       = Example("widget_label",       make_widget_label_document_example,       make_widget_projection_example)
const widget_text_example        = Example("widget_text",        make_widget_text_document_example,        make_widget_text_projection_example)
const widget_checkbox_example    = Example("widget_checkbox",    make_widget_checkbox_document_example,    make_widget_projection_example)
const widget_button_example      = Example("widget_button",      make_widget_button_document_example,      make_widget_projection_example)
const widget_button_action_example = Example("widget_button_action", make_widget_button_action_document_example, make_widget_projection_example)
const widget_button_image_example  = Example("widget_button_image",  make_widget_button_image_document_example,  make_widget_projection_example)
const widget_tooltip_example     = Example("widget_tooltip",     make_widget_tooltip_document_example,     make_widget_projection_example)
const widget_menu_item_example   = Example("widget_menu_item",   make_widget_menu_item_document_example,   make_widget_projection_example)
const widget_menu_example        = Example("widget_menu",        make_widget_menu_document_example,        make_widget_projection_example)
const widget_toolbar_example     = Example("widget_toolbar",     make_widget_toolbar_document_example,     make_widget_projection_example)
const widget_composite_example   = Example("widget_composite",   make_widget_composite_document_example,   make_widget_projection_example)
const widget_title_pane_example  = Example("widget_title_pane",  make_widget_title_pane_document_example,  make_widget_projection_example)
const widget_split_pane_example  = Example("widget_split_pane",  make_widget_split_pane_document_example,  make_widget_projection_example)
const widget_scroll_bar_example  = Example("widget_scroll_bar",  make_widget_scroll_bar_document_example,  make_widget_projection_example)
const widget_scroll_pane_example = Example("widget_scroll_pane", make_widget_scroll_pane_document_example, make_widget_projection_example)
const widget_transform_pane_example = Example("widget_transform_pane", make_widget_transform_pane_document_example, make_widget_projection_example)
const widget_shell_example       = Example("widget_shell",       make_widget_shell_document_example,       make_widget_projection_example)
const widget_tabbed_pane_example = Example("widget_tabbed_pane", make_widget_tabbed_pane_document_example, make_widget_projection_example)
const widget_badge_example       = Example("widget_badge",       make_widget_badge_document_example,       make_widget_projection_example)
const widget_separator_example   = Example("widget_separator",   make_widget_separator_document_example,   make_widget_projection_example)
const widget_card_example        = Example("widget_card",        make_widget_card_document_example,        make_widget_projection_example)
const widget_switch_example      = Example("widget_switch",      make_widget_switch_document_example,      make_widget_projection_example)
const widget_progress_example    = Example("widget_progress",    make_widget_progress_document_example,    make_widget_projection_example)
const widget_slider_example      = Example("widget_slider",      make_widget_slider_document_example,      make_widget_projection_example)
const widget_radio_group_example = Example("widget_radio_group", make_widget_radio_group_document_example, make_widget_projection_example)
const widget_avatar_example      = Example("widget_avatar",      make_widget_avatar_document_example,      make_widget_projection_example)
const widget_alert_example       = Example("widget_alert",       make_widget_alert_document_example,       make_widget_projection_example)
const widget_skeleton_example    = Example("widget_skeleton",    make_widget_skeleton_document_example,    make_widget_projection_example)
const widget_toggle_example      = Example("widget_toggle",      make_widget_toggle_document_example,      make_widget_projection_example)
const widget_toggle_group_example = Example("widget_toggle_group", make_widget_toggle_group_document_example, make_widget_projection_example)
const widget_select_example      = Example("widget_select",      make_widget_select_document_example,      make_widget_projection_example)
const widget_textarea_example    = Example("widget_textarea",    make_widget_textarea_document_example,    make_widget_projection_example)
const widget_accordion_example   = Example("widget_accordion",   make_widget_accordion_document_example,   make_widget_projection_example)
const widget_table_example       = Example("widget_table",       make_widget_table_document_example,       make_widget_projection_example)
const widget_tree_example        = Example("widget_tree",        make_widget_tree_document_example,        make_widget_projection_example)
const widget_disabled_example    = Example("widget_disabled",    make_widget_disabled_document_example,    make_widget_projection_example)
const widget_focus_example       = Example("widget_focus",       make_widget_focus_document_example,       make_widget_projection_example)
const widget_popup_example       = Example("widget_popup",       make_widget_popup_document_example,       make_widget_popup_projection_example)
const layout_example         = Example("layout",         make_layout_document_example,         make_layout_projection_example)
const constraint_layout_example = Example("constraint_layout", make_constraint_layout_document_example, make_constraint_layout_projection_example)
const book_example           = Example("book",           make_book_document_example,           make_book_projection_example)
const markdown_example       = Example("markdown",       make_markdown_document_example,       make_markdown_projection_example)
const markdown_rendered_example = Example("markdown_rendered", make_markdown_document_example,   make_markdown_rendered_projection_example)
const filesystem_example     = Example("filesystem",     make_filesystem_document_example,     make_filesystem_projection_example)
const filesystem_widget_example = Example("filesystem_widget", make_filesystem_document_example, make_filesystem_widget_projection_example)
const navigator_example      = Example("navigator",      make_navigator_document_example,      make_navigator_projection_example)
const collection_example     = Example("collection",     make_collection_document_example,     make_collection_projection_example)
const reversing_example      = Example("reversing",      make_collection_document_example,     make_reversing_projection_example)
const filtering_example      = Example("filtering",      make_collection_document_example,     make_filtering_projection_example)
const searching_example      = Example("searching",      make_collection_document_example,     make_searching_projection_example)
const sorting_example        = Example("sorting",        make_collection_document_example,     make_sorting_projection_example)
const focusing_example       = Example("focusing",       make_focusing_document_example,       make_focusing_projection_example)
const table_example          = Example("table",          make_table_document_example,          make_table_projection_example)
const math_table_example     = Example("math_table",     make_math_table_document_example,     make_math_table_projection_example)
const graph_example          = Example("graph",          make_graph_document_example,          make_graph_projection_example)
const workbench_example      = Example("workbench",      make_workbench_document_example,      make_workbench_projection_example)
# `lazy_example` / `lazy_bidirectional_example` are deliberately kept OUT of the
# `examples` registry below. Their documents are infinite lazy linked lists, so
# the enumeration-based suites (test_printers / test_readers / test_text_navigations /
# test_repls), which walk a document exhaustively, would never terminate and would
# exhaust memory. Use them directly (e.g. `run_example(lazy_example)`); do not add
# them to `examples`.
const lazy_example           = Example("lazy",           make_lazy_document_example,           make_lazy_projection_example)
const lazy_bidirectional_example = Example("lazy_bidirectional", make_lazy_bidirectional_document_example, make_lazy_bidirectional_projection_example)
const math_example           = Example("math",           make_math_document_example,           make_math_projection_example)
const julia_example          = Example("julia",          make_julia_document_example,          make_julia_projection_example)
const graphics_image_example = Example("graphics_image", make_json_document_example,           make_graphics_image_projection_example)
const primitive_string_example = Example("primitive_string", make_primitive_string_document_example, make_primitive_string_projection_example)
const assistant_example      = Example("assistant",      make_assistant_document_example,      make_assistant_projection_example; render_width=1600, render_height=283)
const conversation_example   = Example("conversation",   make_conversation_document_example,   make_conversation_projection_example; render_width=1200, render_height=600)
const conversation_widget_example = Example("conversation_widget", make_conversation_document_example, make_conversation_widget_projection_example; render_width=1200, render_height=700)
const conversation_editor_example = Example("conversation_editor", make_conversation_editor_document_example, make_conversation_editor_projection_example; render_width=1200, render_height=400)
# The live-database (ODBC) catalog/object/sql_table examples and the native
# AdaptagramsEngine graph examples (graph_adaptagrams, dvdrental_relationship) live
# in the opt-in `ProjecturedExtrasExample` package, so this base package depends on
# neither a database driver nor the native shim.
const sql_syntax_example     = Example("sql_syntax",     make_sql_document_example,            make_sql_syntax_projection_example)
const sql_insert_syntax_example = Example("sql_insert_syntax", make_sql_insert_document_example, make_sql_insert_syntax_projection_example)
const sql_update_syntax_example = Example("sql_update_syntax", make_sql_update_document_example, make_sql_update_syntax_projection_example)
const sql_nested_syntax_example = Example("sql_nested_syntax", make_sql_nested_document_example, make_sql_nested_syntax_projection_example)
const dragging_example       = Example("dragging",        make_dragging_document_example,       make_dragging_projection_example)
# `clipboard_example` is deliberately kept OUT of the `examples` registry below
# (like `lazy_example`). The internal clipboard is stateful: its document is a
# `ClipboardSlice` and its projection carries a mutable display flag. The
# enumeration-based suites (test_printers / test_readers / test_repls /
# test_text_navigations) and `test_example` run every sub-test on one *shared*
# document instance in sequence, so the destructive no-selection `test_repl`
# sweep collapses the small wrapped content before navigation runs (a Ctrl+Home
# seed then finds no caret). Each suite passes on a *fresh* document — run them
# individually, e.g. `test_printer(clipboard_example)` / `test_reader(...)` /
# `test_repl(...)` / `test_text_navigation(...)`. Use it interactively with
# `run_example(clipboard_example)`; the selection-driven copy/cut/paste flow it
# exists to demonstrate is unaffected.
const clipboard_example      = Example("clipboard",       make_clipboard_document_example,      make_clipboard_projection_example)
const formula_example        = Example("formula",         make_formula_document_example,        make_formula_projection_example)
# `versioning_example` is deliberately kept OUT of the `examples` registry below
# (like `clipboard_example`). The version-elimination projection selects one of
# several `ObjectVersion`s by criterion and re-roots edits under
# `versions[idx].value`; the enumeration-based suites (test_printers /
# test_readers / test_repls / test_text_navigations) run every sub-test on one
# *shared* document instance, so a destructive sweep on the eliminated view can
# leave a later sub-test without a caret. Each suite passes on a *fresh*
# document — run them individually, e.g. `test_printer(versioning_example)` /
# `test_reader(...)` / `test_text_navigation(...)`. Use it interactively with
# `run_example(versioning_example)`.
const versioning_example     = Example("versioning",      make_versioning_document_example,     make_versioning_projection_example)

const rotating_vector_example = Example("rotating_vector", make_rotating_vector_document, IdentityProjection)

const examples = [
    json_example, json_sorted_example, json_null_example, json_insertion_example, json_string_example, json_widget_example,
    yaml_example,
    xml_example, xml_widget_example, mixed_example, natural_example, syntax_example, text_example, plain_text_example, text_with_image_example,
    object_example, object_to_widget_example, nested_object_to_widget_example, line_numbering_example, word_wrapping_example, text_filtering_example, text_highlighting_example,
    widget_example,
    widget_label_example, widget_text_example, widget_checkbox_example, widget_button_example,
    widget_button_action_example, widget_button_image_example,
    widget_tooltip_example, widget_menu_item_example, widget_menu_example, widget_toolbar_example,
    widget_composite_example, widget_title_pane_example, widget_split_pane_example,
    widget_scroll_bar_example, widget_scroll_pane_example, widget_transform_pane_example,
    widget_shell_example,
    widget_tabbed_pane_example,
    widget_badge_example, widget_separator_example, widget_card_example, widget_switch_example,
    widget_progress_example, widget_slider_example, widget_radio_group_example,
    widget_avatar_example, widget_alert_example, widget_skeleton_example,
    widget_toggle_example, widget_toggle_group_example, widget_select_example,
    widget_textarea_example, widget_accordion_example, widget_table_example, widget_tree_example,
    widget_disabled_example, widget_focus_example,
    layout_example, constraint_layout_example, book_example, markdown_example, markdown_rendered_example, filesystem_example, filesystem_widget_example, navigator_example,
    collection_example, reversing_example, filtering_example, searching_example, sorting_example, focusing_example, table_example, math_table_example, graph_example, workbench_example,
    math_example,
    julia_example,
    formula_example,
    graphics_image_example,
    rotating_vector_example,
    primitive_string_example,
    assistant_example,
    conversation_example,
    conversation_widget_example,
    conversation_editor_example,
    sql_syntax_example,
    sql_insert_syntax_example,
    sql_update_syntax_example,
    sql_nested_syntax_example,
    dragging_example,
]

function run_example(example::Example; kwargs...)
    run_example([example]; kwargs...)
end

"""
    run_example(examples::Vector{Example}; width, height,
                caching=false, scrolling=false, workbench=false, reset=false,
                tooltip=false, inspector=false, introspection=false, selection=nothing,
                profile=false)

Open one window per example, side by side. Each example contributes a
`WindowDocument` with the example's domain document as content; the
composed projection dispatches each window's content to that example's
own projection by **reference path** (so two examples with the same
content type — e.g. both JSON, both wrapped in `WidgetScrollPane` —
still each render through their own pipeline).

Examples no longer carry a pre-set selection. Pass `selection` (a
reference path, e.g. `@reference entries[1].value.value{2}`) to seed the
initial selection; it is applied to the first example's bare domain
document and then lifted to a screen-rooted path (see below). When
`selection === nothing` (the default) the editor opens with no selection.

When `tooltip=true`, each example's content is wrapped in a
`TooltipSource`. While the user has a selection inside that example,
a sibling tooltip window opens (id `:tooltip_<example-name>`) showing
the selection's reference path in two forms: the short, color-coded
shape from `ReferenceToText` on the first line, followed by a blank
line and the multi-line human-readable narrative from
`ReferenceToHumanReadableText`. The tooltip closes when the selection
is cleared.

When `inspector=true`, a secondary `:inspector` window **follows the mouse**
and shows the reference a single left-click *would* create at the current
pointer — without committing it as a selection. Each example window's content
projection is wrapped in a `HoverProbeProjection`, whose reader reverse-projects
each idle `MouseMove` (feeding a synthetic `MousePress` to the wrapped reader)
and drives the follower window via `OpenWindowOperation` / `CloseWindowOperation`.
The window's content is a `ReferenceInspector` rendered the same two ways as the
tooltip (compact `ReferenceToText` + human-readable `ReferenceToHumanReadableText`).
It closes over dead space. Desktop-only (needs the SDL backend's global mouse via
`get_pointer_position`); mutually exclusive with `tooltip` and `workbench`.

When `introspection=true`, each example's content is wrapped in a
`WidgetTabbedPane` with three tabs: the original content (rendered with
the example's own projection), the editor's document, and the editor's
projection (both rendered generically via `ObjectToSyntax`).

When `text_highlighting=true` (or `text_filtering=true`), the example's
projection is replaced by a `ProjectionConfiguringProjection` that stacks an
editable control bar for a `TextHighlighting` (resp. `TextFiltering`)
projection above the projected text. Editing the controls re-highlights /
re-filters live; `Ctrl+F` toggles the bar, `Escape` hides it. Expects a
`TextText` document (the text examples). The two flags are mutually exclusive.

When `clipboard=true`, each example is wrapped in a `ClipboardSlice` and the
clipboard projection is stacked on top of the example's own pipeline (the
introspection wrapper pattern), so the selection-driven copy / cut / note /
paste flow (`Ctrl+C` / `Ctrl+X` / `Ctrl+N` / `Ctrl+V`, `Ctrl+/` to toggle the
stored slice) works over any example. `clipboard_collection=true` uses a
`ClipboardCollection` (the elements view) instead. For a `TextText` example the
wrapper enables **text mode**: copy / cut / paste operate on character ranges,
the ProjecturEd clipboard is the primary store, and the **OS clipboard** is
mirrored on copy/cut and used as the paste fallback (needs `xclip`/`xsel`/`wl-*`).
For other (structured) domains the generic wrapper leaves the OS-clipboard bridge
off (pasting OS text into an arbitrary node domain is not type-safe); the
dedicated `clipboard_example` wires JSON converters for it. Incompatible with
`tooltip` and `inspector`.

When `profile=true`, the read-eval-print loop runs under `Profile.@profile`.
The profile buffer is cleared first; once the editor window is closed (the
loop exits) a sampled backtrace report is printed via `Profile.print`.
"""
function run_example(examples::Vector{Example}; width=nothing, height=nothing,
                     caching=false, scrolling=false, workbench=false, reset=false,
                     tooltip=false, inspector=false, introspection=false,
                     clipboard=false, clipboard_collection=false,
                     text_filtering=false, text_highlighting=false, selection=nothing,
                     profile=false, backend=nothing, partial_render=nothing, debug_dirty=nothing)
    isempty(examples) && error("run_example: empty examples vector")
    if text_filtering && text_highlighting
        error("run_example: text_filtering and text_highlighting are mutually exclusive")
    end
    if inspector && (tooltip || workbench)
        error("run_example: inspector=true is not compatible with tooltip=true or workbench=true")
    end
    clipboard = clipboard || clipboard_collection
    if clipboard && (tooltip || inspector)
        error("run_example: clipboard=true is not compatible with tooltip=true or inspector=true")
    end
    if width === nothing || height === nothing
        sw, sh = get_display_size()
        width  = something(width,  sw)
        height = something(height, sh)
    end
    if tooltip && workbench
        error("run_example: tooltip=true is not compatible with workbench=true")
    end

    # Prepare (document, projection) pairs with the same flags applied as
    # the single-example path.
    docs  = Any[]
    projs = Any[]
    for (i, ex) in enumerate(examples)
        document   = reset ? ex.make_document()   : ex.document
        projection = reset ? ex.make_projection() : ex.projection
        # Apply a caller-supplied selection to the first example's bare domain
        # document, before any workbench/scrolling/introspection wrapping. The
        # selection-lifting step below then promotes it to a screen-rooted path.
        if selection !== nothing && i == 1
            set_selection!(document, selection)
        end
        if workbench
            document   = make_workbench_document(document; title=ex.name)
            projection = make_workbench_projection()
        elseif scrolling
            document   = make_scrolling_document(document; width=width, height=height)
            projection = make_scrolling_projection(projection)
        elseif introspection
            document   = make_introspection_document(document, projection; title=ex.name)
            projection = make_introspection_projection(projection)
        elseif clipboard
            # Wrap the example in a ClipboardSlice (or ClipboardCollection) and stack
            # the clipboard projection on top of the example's own pipeline. The
            # seeded selection (set on the bare document above) now lives behind the
            # clipboard's `content`; the selection-lifting loop below re-roots it.
            # For a TextText document, enable text mode: copy/cut/paste over character
            # ranges, with the OS clipboard mirrored on copy/cut and used as the paste
            # fallback (the projectured slice is the primary store).
            is_text    = document isa TextText
            document   = make_clipboard_document(document; collection=clipboard_collection)
            projection = make_clipboard_projection(projection; collection=clipboard_collection, text=is_text)
        elseif text_highlighting
            # Stack a TextHighlighting control bar above the (text) document; the
            # example's own projection is replaced by the configuring pipeline.
            # A default pattern makes the highlight (and the case_insensitive
            # toggle's effect) visible out of the box. Expects a TextText document.
            projection = make_text_configuring_projection(TextHighlighting("dolor"))
        elseif text_filtering
            projection = make_text_configuring_projection(TextFiltering("dolor"))
        end
        if caching
            projection = make_graphics_caching(projection)
        end
        push!(docs, document)
        push!(projs, projection)
    end

    # When the tooltip flag is on, wrap each window's content in a
    # TooltipSource and pick the tooltip-aware multi-window projection.
    if tooltip
        tt_docs = Any[]
        for (i, ex) in enumerate(examples)
            push!(tt_docs, _make_tooltip_source(docs[i]; id = Symbol("tooltip_", ex.name)))
        end
        docs = tt_docs
    end

    # An explicit `backend` (e.g. the WebBackend from run_web_example) wins;
    # otherwise build the SDL backend, threading the render-control knobs.
    # Built before composing because the inspector pipeline needs a pointer
    # closure over the backend's global mouse position.
    backend === nothing && (backend = make_backend(:sdl; partial_render=partial_render, debug_dirty=debug_dirty))
    # How deep the original (selection-bearing) document sits under `win.content`.
    content_unwrap = tooltip ? :tooltip : clipboard ? :clipboard : :plain
    # `compose(projs, backend)` — the inspector pipeline needs the backend for its
    # pointer closure, hence the second argument.
    compose = inspector ? (p, b) -> _multi_window_projection_inspector(p; pointer = () -> get_pointer_position(b)) :
              tooltip   ? (p, b) -> _multi_window_projection_tooltipped(p) :
                          (p, b) -> _multi_window_projection(p)
    _run_window_scene(docs, projs, String[ex.name for ex in examples];
                      width=width, height=height, backend=backend,
                      compose=compose, profile=profile, content_unwrap=content_unwrap)
end

# Lay out `docs` as side-by-side WindowDocuments into a ScreenDocument and lift the
# first window-content's selection to a screen-rooted path. Each `names[i]` becomes
# window i's id/title (ids must be unique within the screen). `content_unwrap` says
# how deep the original (selection-bearing) document sits under `win.content`:
# `:plain` (the content itself), `:tooltip` (`.child`), or `:clipboard` (`.content`).
#
# The selection lift matters because the screen and intermediate WindowDocument keep
# `selection = nothing` while the inner document may carry a deep selection; without
# re-rooting it, the next click traverses a different branch and the stale leaf
# selection is never cleared (`_collect_spans` then picks the first cursor it finds,
# so new clicks look ignored). With no seeded selection every document keeps
# `selection = nothing` and this loop is a no-op.
#
# Factored out of `run_example` so other entry points (e.g. `run_file_editor`) share
# the exact same scene assembly. Pure (no backend, no window) so it is testable.
function _build_window_scene(docs, names; width, height, content_unwrap::Symbol=:plain)
    seen_ids = Set{Symbol}()
    windows = WindowDocument[]
    for (i, nm) in enumerate(names)
        id = Symbol(nm)
        id in seen_ids && error("run_example: duplicate example name :$id; window ids must be unique")
        push!(seen_ids, id)
        push!(windows, WindowDocument(;
            id     = id,
            title  = nm,
            x      = 100 + (i - 1) * (width + 40),
            y      = 100,
            width  = width,
            height = height,
            content = docs[i],
        ))
    end
    screen = ScreenDocument(windows)

    for (i, win) in enumerate(windows)
        root_doc = content_unwrap === :tooltip   ? win.content.child :
                   content_unwrap === :clipboard ? win.content.content :
                                                   win.content
        inner_sel = getfield(root_doc, :selection)[]
        inner_sel === nothing && continue
        full_path = content_unwrap === :tooltip   ? (@reference windows[i].content.child.^(inner_sel)) :
                    content_unwrap === :clipboard ? (@reference windows[i].content.content.^(inner_sel)) :
                                                    (@reference windows[i].content.^(inner_sel))
        set_selection!(screen, full_path)
        break
    end
    screen
end

# Build the scene (above), compose the screen projection via `compose(projs, backend)`,
# and run the editor loop on `backend` (optionally under the profiler). The shared tail
# of `run_example` and `run_file_editor`.
function _run_window_scene(docs, projs, names; width, height, backend,
                           compose, profile::Bool=false, content_unwrap::Symbol=:plain,
                           mcp::Bool=false)
    screen = _build_window_scene(docs, names; width=width, height=height, content_unwrap=content_unwrap)
    composed = compose(projs, backend)
    if profile
        Profile.clear()
        try
            Profile.@profile run!(backend, composed, screen; mcp=mcp)
        finally
            Profile.print(; mincount=10)
        end
    else
        run!(backend, composed, screen; mcp=mcp)
    end
end

"""
    run_web_example(name_or_names="json"; host="127.0.0.1", port=8080, kwargs...)

Run an example (or several side-by-side) through the **web backend** instead of
SDL. Starts an HTTP + WebSocket server; open `http://host:port` in a browser and
the main window appears immediately in that tab — no button to click. Any
additional windows (e.g. a second example, or tooltips) open as browser popups on
the first interaction in the tab. The browser paints the server's draw-list and
forwards input back. Accepts the same keyword arguments as [`run_example`](@ref)
(e.g. `width`, `height`, `workbench`, `selection`).
"""
run_web_example(arg="json"; host="127.0.0.1", port=8080, kwargs...) =
    run_example(arg; backend=make_backend(:web; host=host, port=port), kwargs...)

# Build a projection that projects the screen down to each
# `windows[i].content` reference and applies the matching example's
# projection only at that exact leaf. Dispatch by reference path rather than
# content type so two examples with the same root document type still each
# render through their own pipeline.
#
# `ScreenToScreen` owns the screen spine: it recurses each window's `content`
# (and nothing above it) back through this dispatch, with the content's
# reference being `windows[i].content` (the i-th window is an
# `ElementReference`), which is how the target paths are built.
function _multi_window_projection(projections::Vector; measure=truetype_measure_text)
    n = length(projections)
    targets = Vector{Any}(undef, n)
    for i in 1:n
        targets[i] = @reference windows[i].content
    end
    # One shared open/closed flag for the gesture-help window, threaded into every
    # (per-dispatch, transient) decorator so F1 toggles the same window.
    help_state = GestureHelpState()
    ref_dispatch = ReferenceDispatchingProjection(ref -> begin
        # Exact match — apply that window's example projection here, wrapped in a
        # GestureHelpProjection so F1 in the focused window opens a help window
        # listing the gestures collected from this content's own pipeline. The
        # NestingProjection (recursion=IdentityProjection) lets the inner
        # projection's own recursion take over below this point.
        for i in 1:n
            reference_equal(ref, targets[i]) || continue
            return GestureHelpProjection(
                inner = NestingProjection(projections[i]; recursion=IdentityProjection()),
                state = help_state)
        end
        # The ScreenDocument root is the window-management seam: route it
        # through WindowManagingProjection (window open/close/resize ops are
        # owned there) wrapping ScreenToScreen, which projects the screen
        # shell and recurses each window's content back through this dispatch.
        ref isa EmptyReferencePath &&
            return WindowManagingProjection(inner = ScreenToScreen())
        # Anything outside a window's content target — preserve.
        return IdentityProjection()
    end)
    # A type seam in front of the reference dispatch so dynamically-opened windows
    # render by content type: a `WindowDocument` (re-projected by the manager when
    # a window opens) recurses via ScreenToScreen, and a help `GestureMap` window
    # renders down to graphics. Existing content is `Any` → the reference dispatch,
    # unchanged (TypeDispatching is transparent for the matched arm).
    return RecursiveProjection(
        TypeDispatchingProjection(
            WindowDocument => ScreenToScreen(),
            GestureMap     => ChainingProjection(GestureMapToSyntax(),
                                                   RecursiveProjection(SyntaxToText()),
                                                   WordWrapping(measure=measure),
                                                   TextToGraphics(measure=measure)),
            Any            => ref_dispatch,
        ))
end

# ── Tooltip variant ──────────────────────────────────────────────────────
#
# Wrap a domain document in a `TooltipSource` whose `content` is a
# *reactive* `TextText`: the elements thunk re-reads `doc.selection`
# every frame and rebuilds the colored spans via `ReferenceToText`. The
# `TooltipDecoratorProjection` reader watches the wrapped document and
# emits `OpenWindowOperation` / `CloseWindowOperation` as the selection
# arrives / clears; the `WindowManagingProjection` applies those to the
# screen.

function _make_tooltip_source(doc; id::Symbol)
    short_proj = ReferenceToText()
    long_proj  = ReferenceToHumanReadableText(document = doc)
    content = TextText(() -> begin
        sel = doc.selection
        ctx = PrinterContext()
        short = print_document(short_proj, nothing, sel, ctx).output
        long  = print_document(long_proj,  nothing, sel, ctx).output
        spans = TextDocument[]
        for i in 1:length(short.elements)
            push!(spans, short.elements[i])
        end
        push!(spans, TextNewline(font=short_proj.font))
        push!(spans, TextNewline(font=short_proj.font))
        for i in 1:length(long.elements)
            push!(spans, long.elements[i])
        end
        spans
    end)
    TooltipSource(child = doc, content = content, style = :tooltip, id = id)
end

# Same shape as `_multi_window_projection` but with the four extra type
# entries needed for tooltip support, sitting in front of the existing
# reference-based dispatch for example content.
function _multi_window_projection_tooltipped(projections::Vector; measure=truetype_measure_text)
    n = length(projections)
    targets = Vector{Any}(undef, n)
    for i in 1:n
        targets[i] = @reference windows[i].content
    end
    decorator = TooltipDecoratorProjection(
        trigger  = (source, _evt) -> source.child.selection !== nothing,
        position = _ -> (100, 100, 1200, 600),
        title    = "Selection",
    )
    ref_dispatch = ReferenceDispatchingProjection(ref -> begin
        for i in 1:n
            reference_equal(ref, targets[i]) || continue
            return NestingProjection(projections[i];
                                      recursion=IdentityProjection())
        end
        for t in targets
            is_prefix_of(ref, t) || continue
            return CopyingProjection()
        end
        return IdentityProjection()
    end)
    RecursiveProjection(
        TypeDispatchingProjection(
            ScreenDocument => WindowManagingProjection(inner = ScreenToScreen()),
            WindowDocument => ScreenToScreen(),
            CellVector     => CopyingProjection(),
            TooltipSource  => decorator,
            TextText       => ChainingProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure)),
            Any            => ref_dispatch,
        ),
    )
end

# Hover click-reference inspector pipeline. Same shape as the tooltip variant,
# but: each example window's content projection is wrapped in a
# `HoverProbeProjection` (which reverse-projects the pointer into the
# would-be-click reference and drives the follower `:inspector` window), and a
# `ReferenceInspector` type entry renders that window's content (compact +
# human-readable reference) down to graphics. `pointer` is the global-mouse
# closure used to make the follower window track the cursor.
function _multi_window_projection_inspector(projections::Vector; measure=truetype_measure_text, pointer)
    n = length(projections)
    targets = Vector{Any}(undef, n)
    for i in 1:n
        targets[i] = @reference windows[i].content
    end
    ref_dispatch = ReferenceDispatchingProjection(ref -> begin
        for i in 1:n
            reference_equal(ref, targets[i]) || continue
            inner = NestingProjection(projections[i]; recursion=IdentityProjection())
            return HoverProbeProjection(inner = inner, id = :inspector, pointer = pointer)
        end
        for t in targets
            is_prefix_of(ref, t) || continue
            return CopyingProjection()
        end
        return IdentityProjection()
    end)
    RecursiveProjection(
        TypeDispatchingProjection(
            ScreenDocument     => WindowManagingProjection(inner = ScreenToScreen()),
            WindowDocument     => ScreenToScreen(),
            CellVector         => CopyingProjection(),
            ReferenceInspector => ChainingProjection(ReferenceInspectorToText(),
                                                       WordWrapping(measure=measure),
                                                       TextToGraphics(measure=measure)),
            TextText           => ChainingProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure)),
            Any                => ref_dispatch,
        ),
    )
end

function run_example(name="json"; kwargs...)
    idx = findfirst(ex -> ex.name == name, examples)
    if idx === nothing
        available = join(getfield.(examples, :name), ", ")
        error("Unknown example: \"$name\". Available: $available")
    end
    run_example(examples[idx]; kwargs...)
end

"""
    run_example(names::Vector{<:AbstractString}; kwargs...)

Convenience: look up each name in the global `examples` list and open
them side by side. Same semantics as `run_example(::Vector{Example})`.
"""
function run_example(names::Vector{<:AbstractString}; kwargs...)
    selected = Example[]
    for name in names
        idx = findfirst(ex -> ex.name == name, examples)
        idx === nothing && error("Unknown example: \"$name\"")
        push!(selected, examples[idx])
    end
    run_example(selected; kwargs...)
end

function print_example(example::Example)
    iomap = print_document(example.projection, example.document)
    output = iomap.output
    println(print_object(output isa Cell ? output[] : output; open_delimiter="{", close_delimiter="}"))
end

function print_example(name="json")
    idx = findfirst(ex -> ex.name == name, examples)
    if idx === nothing
        available = join(getfield.(examples, :name), ", ")
        error("Unknown example: \"$name\". Available: $available")
    end
    print_example(examples[idx])
end

"""
    run_console_example(; document, projection, ansi=true, clear=nothing, interactive=false)

Render a Text-domain document to the terminal via the `ConsoleBackend`,
preserving the spans' colors. This is the console counterpart to
`run_example`: it bypasses SDL and the `ScreenDocument`/window machinery and
prints the bare `TextText` produced by the projection.

Defaults to the JSON example projected through
`make_json_console_projection_example` — the json pipeline **without** the
`TextToGraphics` step, so its output is a `TextText` the console can render.

Keywords:
  - `document`    — the domain document (default: a fresh JSON example doc).
  - `projection`  — a projection whose output is a `TextText` (default: the
                    json→syntax→text console projection).
  - `ansi`        — emit ANSI color codes (default `true`).
  - `clear`       — clear the screen before each frame. Defaults to `false` for
                    a one-shot render and `true` for the interactive loop.
  - `interactive` — when `true`, run the read-eval-print loop: poll the
                    keyboard, apply operations, repaint. `Home` selects the root
                    node, arrows navigate the tree, `Ctrl+Space` toggles
                    structural ⇄ text selection, `Ctrl+C` quits. Character-level
                    text editing is not available (it lives in `TextToGraphics`,
                    which this pipeline omits). Default `false` (one-shot).
"""
function run_console_example(; document=make_json_document_example(),
                               projection=make_json_console_projection_example(),
                               ansi::Bool=true, clear::Union{Bool,Nothing}=nothing,
                               interactive::Bool=false)
    if interactive
        backend = make_backend(:console; ansi=ansi, clear=something(clear, true))
        # The editor logs each operation and a perf line via @info; on a terminal
        # that lands on the rendered screen and corrupts it (the console owns the
        # display). Discard those logs for the duration of the interactive loop.
        Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
            run!(backend, projection, document; devices=Device[Keyboard()])
        end
    else
        backend = make_backend(:console; ansi=ansi, clear=something(clear, false))
        iomap = print_document(projection, document)
        output = iomap.output
        output = output isa Cell ? output[] : output
        write_to_devices(backend, Device[], output)
    end
    return nothing
end

function write_example_image(example::Example, filename;
                              width=nothing, height=nothing,
                              max_width=1800, max_height=1200, kwargs...)
    write_image(example.document, example.projection, filename;
                width=width, height=height,
                max_width=max_width, max_height=max_height, kwargs...)
end

function write_example_image(name="json", filename=tempname()*".bmp"; kwargs...)
    idx = findfirst(ex -> ex.name == name, examples)
    idx === nothing && error("Unknown example: \"$name\"")
    write_example_image(examples[idx], filename; kwargs...)
end

# Render an example to a vector PDF. Reuses the example's own (SDL-measured)
# projection for layout parity with the on-screen / `write_image` view; unlike
# `write_image`, `write_pdf` does not initialize SDL itself, so we bring it up
# here for the projection's `truetype_measure_text`.
function write_example_pdf(example::Example, filename;
                           width=nothing, height=nothing,
                           max_width=1800, max_height=1200, kwargs...)
    init!(make_backend(:sdl))
    write_pdf(example.document, example.projection, filename;
              width=width, height=height,
              max_width=max_width, max_height=max_height,
              measure=truetype_measure_text, kwargs...)
end

function write_example_pdf(name="json", filename=tempname()*".pdf"; kwargs...)
    idx = findfirst(ex -> ex.name == name, examples)
    idx === nothing && error("Unknown example: \"$name\"")
    write_example_pdf(examples[idx], filename; kwargs...)
end

function record_example_video(example::Example, gestures, filename;
                              width=1200, height=800, fps=30, kwargs...)
    record_video(example.document, example.projection, gestures, filename;
                 width=width, height=height, fps=fps, kwargs...)
end

function record_example_video(name::AbstractString, gestures,
                              filename=tempname()*".mp4"; kwargs...)
    idx = findfirst(ex -> ex.name == name, examples)
    idx === nothing && error("Unknown example: \"$name\"")
    record_example_video(examples[idx], gestures, filename; kwargs...)
end

"""
    make_typein_gestures(text; hold=0.15, jitter=0.6) -> Vector

Turn `text` into a list of timed `record_video` gestures: one
`(event = KeyPress(char), hold = …)` per character, in order. Feed the result to
`record_video`/`record_example_video` to record someone typing `text`. The
recording needs an `initial_selection` (a text caret) for the keypresses to land.

To mimic human typing, each hold is `hold` scaled by a random factor in
`[1-jitter, 1+jitter]` (so `hold` is the *average* per-key duration and `jitter`
∈ `[0,1]` is how irregular the rhythm is). `jitter=0` gives a perfectly even
machine cadence. Holds are drawn fresh on every call.
"""
function make_typein_gestures(text::AbstractString; hold::Real=0.15, jitter::Real=0.6)
    j = clamp(Float64(jitter), 0.0, 1.0)
    [(event = KeyPress(c), hold = hold * (1 + j * (2 * rand() - 1))) for c in text]
end

"""
    record_assistant_conversation_video(filename=tempname()*".mp4"; reply, kwargs...) -> String

Record a headless MP4 of someone composing a multi-part message in the workbench
assistant and waiting for the reply. The recorded session, driven entirely
through the live `make_assistant_projection_example` chain
(`KeyPress`/`KeyDown` → composer operations), is:

1. type the prose `"Look what I can do!"`;
2. `TAB` to start a new part, type `julia`, `ENTER` to turn it into a Julia
   source part, type `factorial(6)`, then `ALT+ENTER` to evaluate it into an
   `EvaluatorForm` (code + result `720`);
3. type the prose `"Can you do the same?"`;
4. `ENTER` to submit the draft turn, then wait for the assistant to reply.

The assistant uses a `FakeLlm` so the reply (`reply`) is deterministic and needs
no network. The default reply contains a fenced ```` ```julia ```` block, which
`parse_markdown_blocks` parses into a real `JuliaDocument` part — so the recorded
reply renders the code as a parsed Julia document in the conversation, not plain
text. The reply is streamed on an `@async` task that the recording lets settle
(via `record_video`'s `wait_for`) before holding the final frames for
`final_hold` seconds (longer than the default so the answer lingers on screen).
"""
function record_assistant_conversation_video(filename::AbstractString = tempname() * ".mp4";
                                              reply::AbstractString = """
                                                  Sure! Here's a recursive factorial in Julia:

                                                  ```julia
                                                  fact(n) = n <= 1 ? 1 : n * fact(n - 1)
                                                  ```

                                                  Calling `fact(6)` returns 720 — same as yours.""",
                                              width=1600, height=900, fps=30, final_hold=4.0, kwargs...)
    # A fresh assistant with a deterministic canned reply. The composer edits the
    # draft's active part (cursor defaults to end-of-value), so no selection seed
    # is needed for the keypresses to land.
    assistant  = WorkbenchAssistant(; llm = FakeLlm(reply))
    projection = make_assistant_projection_example()

    # A composer part-break: commit the active part and start the next one.
    tab   = (event = KeyDown(:tab, Modifiers()),              hold = 0.5)
    enter = (event = KeyDown(:return, Modifiers()),           hold = 0.6)
    alt_enter = (event = KeyDown(:return, Modifiers(alt=true)), hold = 0.8)

    gestures = vcat(
        make_typein_gestures("Look what I can do!"),
        [tab],
        make_typein_gestures("julia"),               # name the kind in the chooser
        [enter],                                      # commit chooser → Julia source part
        make_typein_gestures("factorial(6)"),
        [alt_enter],                                  # evaluate → EvaluatorForm (720)
        make_typein_gestures("Can you do the same?"),
        [enter],                                      # submit the draft turn
    )

    record_video(assistant, projection, gestures, filename;
                 width=width, height=height, fps=fps, final_hold=final_hold,
                 wait_for = () -> assistant.status === :idle, kwargs...)
end

"""
    generate_example_screenshots(; filter=nothing, max_width=1920, max_height=1080,
                                 image_dir=joinpath(@__DIR__, "..", "..", "..", "asset", "image", "example"))

Generate a PNG screenshot for every example in `examples` into `image_dir`.
Filename pattern: `{example-name-with-hyphens}.png`. One failure does not
abort the batch.

Each screenshot is sized to its content, capped at `max_width`/`max_height`, so
compact examples (e.g. individual widgets) produce small images rather than a
fixed full-screen canvas.

Pass `filter` (a `Regex` or string compiled to one with `occursin`) to restrict
generation to examples whose name matches, e.g. `filter=r"^widget"` regenerates
only the widget screenshots.
"""
# Export scale for generated screenshots: PNGs are rendered at this many device
# pixels per logical pixel so they stay crisp on HiDPI displays (e.g. GitHub
# viewed on a retina screen) independent of the machine that generates them.
# Guide embeds pin the *displayed* width to the logical size (png width ÷ this)
# via `<img width>`, so the on-page size is unchanged while the extra pixels are
# available for sharp rendering.
const SCREENSHOT_SCALE = 2

function generate_example_screenshots(; filter=nothing, max_width=1920, max_height=1080, supersample=3,
                                      scale=SCREENSHOT_SCALE,
                                      image_dir=joinpath(@__DIR__, "..", "..", "..", "asset", "image", "example"))
    mkpath(image_dir)
    # The default widget theme's background (slate-100); widget screenshots use
    # it so the canvas matches the themed surfaces rather than showing white.
    widget_bg = (0xf1, 0xf5, 0xf9, 0xff)
    pattern = filter isa AbstractString ? Regex(filter) : filter
    for ex in examples
        if pattern !== nothing && !occursin(pattern, ex.name)
            continue
        end
        safe_name = replace(ex.name, "_" => "-")
        png = joinpath(image_dir, "$safe_name.png")
        @info "Generating $(ex.name)..."
        # Widgets render on the light theme background, so screenshot them on
        # the themed surface rather than the default solarized canvas.
        bg = startswith(ex.name, "widget") ? widget_bg : (0xfd, 0xf6, 0xe3, 0xff)
        try
            write_example_image(ex, png; width=ex.render_width, height=ex.render_height,
                                max_width=max_width, max_height=max_height,
                                background=bg, supersample=supersample, scale=scale)
            @info "  ✓ $png"
        catch e
            @warn "  ✗ $(ex.name): $e"
        end
    end
end

"""
    update_guide_screenshots(; repo_root=joinpath(@__DIR__, "..", "..", ".."))

Inject `![...](...)` image references into the guide files and `README.md`.
Idempotent: re-running produces no changes once images are in place.
"""
function update_guide_screenshots(; repo_root=joinpath(@__DIR__, "..", "..", ".."))
    _update_examples_tour(joinpath(repo_root, "documentation", "examples-tour.md"))
    _update_domain_guides(joinpath(repo_root, "documentation", "document"))
    _update_readme(joinpath(repo_root, "README.md"))
    # Convert any remaining plain Markdown example-images (thumbnail tables, the
    # README hero, etc.) to width-pinned <img> tags.
    md_files = String[joinpath(repo_root, "README.md")]
    guide_dir = joinpath(repo_root, "documentation")
    if isdir(guide_dir)
        for (root, _, files) in walkdir(guide_dir), f in files
            endswith(f, ".md") && push!(md_files, joinpath(root, f))
        end
    end
    foreach(_migrate_example_image_embeds, md_files)
end

const _TOUR_HEADER_RE = r"^## \d+\. .*`run_example\(\"(\w+)\"\)`"

function _example_title(name::AbstractString)
    titlecase(replace(name, "_" => " "))
end

# Width field of a PNG's IHDR header (bytes 16-19, big-endian). Avoids a decode.
function _png_pixel_width(path::AbstractString)
    open(path) do io
        seek(io, 16)
        Int(ntoh(read(io, UInt32)))
    end
end

# Markdown embed for a screenshot. Screenshots are `SCREENSHOT_SCALE`× their
# logical size, so we pin the displayed width to the logical size with an HTML
# `<img width>` (honored by GitHub): compact on the page, sharp on HiDPI. Falls
# back to a plain Markdown image if the PNG is missing (so docs still build).
function _img_embed(title::AbstractString, rel_path::AbstractString, md_dir::AbstractString)
    _img_embed_raw("$title example", rel_path, md_dir, "![$title example]($rel_path)")
end

# True when a line already holds a screenshot embed (Markdown image or <img>).
_is_image_embed(line) = (s = strip(line); startswith(s, "![") || startswith(s, "<img"))

# Any Markdown image pointing at an example screenshot: ![alt](…image/example/X.png)
const _MD_EXAMPLE_IMG_RE = r"!\[([^\]]*)\]\(([^)]*image/example/[^)]+\.png)\)"

# Convert every plain Markdown example-image in a file to an `<img width>` tag
# pinned to the logical size — covers embeds the heading inserters don't touch
# (thumbnail tables, the README hero). Idempotent: `<img>` tags aren't matched.
function _migrate_example_image_embeds(path::AbstractString)
    isfile(path) || return
    md_dir = dirname(path)
    text = read(path, String)
    new_text = replace(text, _MD_EXAMPLE_IMG_RE => function (s)
        mm = match(_MD_EXAMPLE_IMG_RE, s)
        alt, rel = mm.captures[1], mm.captures[2]
        _img_embed_raw(alt, rel, md_dir, s)
    end)
    new_text != text && write(path, new_text)
end

# Like `_img_embed` but with an explicit alt string and a literal fallback.
function _img_embed_raw(alt::AbstractString, rel::AbstractString, md_dir::AbstractString, fallback::AbstractString)
    abs_png = normpath(joinpath(md_dir, rel))
    isfile(abs_png) || return fallback
    w = max(1, _png_pixel_width(abs_png) ÷ SCREENSHOT_SCALE)
    "<img width=\"$w\" alt=\"$alt\" src=\"$rel\">"
end

function _update_examples_tour(path::AbstractString)
    isfile(path) || (@warn "Missing $path"; return)
    lines = readlines(path; keep=false)
    out = String[]
    i = 1
    while i <= length(lines)
        line = lines[i]
        push!(out, line)
        m = match(_TOUR_HEADER_RE, line)
        if m !== nothing
            name = m.captures[1]
            safe_name = replace(name, "_" => "-")
            img_line = _img_embed(_example_title(name), "../asset/image/example/$safe_name.png", dirname(path))
            j = i + 1
            while j <= length(lines) && isempty(strip(lines[j]))
                push!(out, lines[j])
                j += 1
            end
            if j <= length(lines) && _is_image_embed(lines[j])
                # Replace the existing embed (migrates Markdown ↔ <img>).
                push!(out, img_line)
                i = j + 1
            else
                push!(out, img_line)
                push!(out, "")
                i = j
            end
            continue
        end
        i += 1
    end
    new_text = join(out, "\n") * "\n"
    new_text = replace(new_text,
        "Screenshots are in [image/](../image/)." =>
        "Screenshots for each example are embedded inline below.")
    if read(path, String) != new_text
        write(path, new_text)
    end
end

const _DOMAIN_GUIDE_EXAMPLE = Dict(
    "json.md"       => "json",
    "xml.md"        => "xml",
    "text.md"       => "text",
    "syntax.md"     => "syntax",
    "graphics.md"   => "graphics_image",
    "widget.md"     => "widget",
    "workbench.md"  => "workbench",
    "collection.md" => "collection",
)

function _update_domain_guides(dir::AbstractString)
    isdir(dir) || (@warn "Missing $dir"; return)
    for (filename, example_name) in _DOMAIN_GUIDE_EXAMPLE
        path = joinpath(dir, filename)
        isfile(path) || continue
        lines = readlines(path; keep=false)
        heading_idx = findfirst(l -> startswith(l, "# "), lines)
        heading_idx === nothing && continue
        safe_name = replace(example_name, "_" => "-")
        img_line = _img_embed(_example_title(example_name), "../../asset/image/example/$safe_name.png", dirname(path))
        existing = findfirst(_is_image_embed, lines[1:min(end, 15)])
        new_lines = if existing !== nothing
            # Replace the existing embed in place (migrates Markdown ↔ <img>).
            vcat(lines[1:existing-1], [img_line], lines[existing+1:end])
        else
            blank_idx = findnext(l -> isempty(strip(l)), lines, heading_idx + 1)
            insert_after = blank_idx === nothing ? heading_idx : blank_idx
            vcat(lines[1:insert_after], [img_line, ""], lines[insert_after+1:end])
        end
        new_text = join(new_lines, "\n") * "\n"
        if read(path, String) != new_text
            write(path, new_text)
        end
    end
end

function _readme_screenshots_block(md_dir::AbstractString)
    cell(name, title) = _img_embed(title, "asset/image/example/$name.png", md_dir)
    """
    ## Screenshots

    | JSON editor | Widget forms | Table view |
    |---|---|---|
    | $(cell("json", "JSON")) | $(cell("widget", "Widget")) | $(cell("table", "Table")) |

    | Syntax tree | Julia AST | Workbench |
    |---|---|---|
    | $(cell("syntax", "Syntax")) | $(cell("julia", "Julia AST")) | $(cell("workbench", "Workbench")) |

    ---
    """
end

function _update_readme(path::AbstractString)
    isfile(path) || (@warn "Missing $path"; return)
    text = read(path, String)
    block_re = r"## Screenshots\n(?:.*\n)*?(?=\n## )"
    new_text = if occursin(block_re, text)
        replace(text, block_re => _readme_screenshots_block(dirname(path)))
    else
        text
    end
    if new_text != text
        write(path, new_text)
    end
end

