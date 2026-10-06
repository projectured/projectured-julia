# ═══════════════════════════════════════════════════════════════════════════
# visual-example/Examples.jl
#
# The visual-tier `Example` instances: syntax/text documents, the widget
# gallery, layouts, the collection views, and the text decorators. The global
# `examples` registry that interleaves every tier lives in the
# `ProjecturedExample` umbrella.
# ═══════════════════════════════════════════════════════════════════════════

const syntax_example         = Example("syntax",         make_syntax_document_example,         make_syntax_projection_example)
const text_example           = Example("text",           make_text_document_example,           make_text_projection_example)
const plain_text_example     = Example("plain_text",     make_plain_text_document_example,     make_plain_text_projection_example)
const text_with_image_example = Example("text_with_image", make_text_with_image_example,       make_text_projection_example)

# How text layout works: one example for each rule of the line model, and one
# for each line spacing. `run_example(text_spacing_examples)` opens the spacings
# side by side.
const text_baseline_example    = Example("text_baseline",    make_text_baseline_document_example,    make_text_layout_projection_example)
const text_line_height_example = Example("text_line_height", make_text_line_height_document_example, make_text_layout_projection_example)
const text_kerning_example     = Example("text_kerning",     make_text_kerning_document_example,     make_text_layout_projection_example)
const text_selection_example   = Example("text_selection",   make_text_selection_document_example,   make_text_layout_projection_example)
const text_spacing_single_example = Example("text_spacing_single",
    () -> make_text_spacing_document_example("Single spacing",
        "Each line is at the natural distance of its fonts: 23 pixels for Ubuntu at 20."),
    () -> make_text_layout_projection_example(spacing = SingleSpacing()))
const text_spacing_one_and_a_half_example = Example("text_spacing_one_and_a_half",
    () -> make_text_spacing_document_example("One and a half",
        "Each line is 1.5 times the natural distance of its fonts from the next one."),
    () -> make_text_layout_projection_example(spacing = MultipleSpacing(1.5)))
const text_spacing_double_example = Example("text_spacing_double",
    () -> make_text_spacing_document_example("Double spacing",
        "Each line is 2 times the natural distance of its fonts from the next one."),
    () -> make_text_layout_projection_example(spacing = MultipleSpacing(2)))
const text_spacing_exactly_example = Example("text_spacing_exactly",
    () -> make_text_spacing_document_example("Exactly 20 pixels",
        "Each line is 20 pixels from the next one, less than the 23 pixels its fonts ask, so descenders touch the next line."),
    () -> make_text_layout_projection_example(spacing = ExactSpacing(20)))
const text_spacing_at_least_example = Example("text_spacing_at_least",
    () -> make_text_spacing_document_example("At least 30 pixels",
        "Each line is 30 pixels from the next one, because its natural distance is less."),
    () -> make_text_layout_projection_example(spacing = AtLeastSpacing(30)))
const text_layout_examples = Example[text_baseline_example, text_line_height_example,
                                     text_kerning_example, text_selection_example]
const text_spacing_examples = Example[text_spacing_single_example, text_spacing_one_and_a_half_example,
                                      text_spacing_double_example, text_spacing_exactly_example,
                                      text_spacing_at_least_example]
const object_example         = Example("object",         make_object_document_example,         make_object_projection_example)
const object_to_widget_example = Example("object_to_widget", make_object_to_widget_document_example, make_object_to_widget_projection_example)
const nested_object_to_widget_example = Example("nested_object_to_widget", make_nested_object_to_widget_document_example, make_object_to_widget_projection_example)
const object_field_form_example = Example("object_field_form", make_object_field_form_document_example, make_object_field_form_projection_example)
const object_field_syntax_example = Example("object_field_syntax", make_object_field_document_example, make_object_field_syntax_projection_example)
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
const widget_toolbar_item_example = Example("widget_toolbar_item", make_widget_toolbar_item_document_example, make_widget_projection_example)
const widget_composite_example   = Example("widget_composite",   make_widget_composite_document_example,   make_widget_projection_example)
const widget_title_pane_example  = Example("widget_title_pane",  make_widget_title_pane_document_example,  make_widget_projection_example)
const widget_split_pane_example  = Example("widget_split_pane",  make_widget_split_pane_document_example,  make_widget_projection_example)
const widget_scroll_bar_example  = Example("widget_scroll_bar",  make_widget_scroll_bar_document_example,  make_widget_projection_example)
const widget_scroll_pane_example = Example("widget_scroll_pane", make_widget_scroll_pane_document_example, make_widget_projection_example)
const widget_offered_example = Example("widget_offered", make_widget_offered_document_example, make_widget_projection_example)
const widget_transform_pane_example = Example("widget_transform_pane", make_widget_transform_pane_document_example, make_widget_projection_example)
const widget_shell_example       = Example("widget_shell",       make_widget_shell_document_example,       make_widget_projection_example)
const widget_tabbed_pane_example = Example("widget_tabbed_pane", make_widget_tabbed_pane_document_example, make_widget_projection_example)
const pane_example           = Example("pane",           make_pane_document_example,           make_pane_projection_example)
const empty_pane_example     = Example("empty_pane",     make_empty_pane_document_example,     make_pane_projection_example)
const widget_badge_example       = Example("widget_badge",       make_widget_badge_document_example,       make_widget_projection_example)
const widget_separator_example   = Example("widget_separator",   make_widget_separator_document_example,   make_widget_projection_example)
const widget_card_example        = Example("widget_card",        make_widget_card_document_example,        make_widget_projection_example)
const widget_collapsible_card_example = Example("widget_collapsible_card", make_widget_collapsible_card_document_example, make_widget_projection_example)
const widget_switch_example      = Example("widget_switch",      make_widget_switch_document_example,      make_widget_projection_example)
const widget_progress_bar_example = Example("widget_progress_bar", make_widget_progress_bar_document_example, make_widget_projection_example)
const widget_progress_ring_example = Example("widget_progress_ring", make_widget_progress_ring_document_example, make_widget_projection_example)
const widget_slider_example      = Example("widget_slider",      make_widget_slider_document_example,      make_widget_projection_example)
const widget_radio_group_example = Example("widget_radio_group", make_widget_radio_group_document_example, make_widget_projection_example)
const widget_avatar_example      = Example("widget_avatar",      make_widget_avatar_document_example,      make_widget_projection_example)
const widget_alert_example       = Example("widget_alert",       make_widget_alert_document_example,       make_widget_projection_example)
const widget_skeleton_example    = Example("widget_skeleton",    make_widget_skeleton_document_example,    make_widget_projection_example)
const widget_swatch_example      = Example("widget_swatch",      make_widget_swatch_document_example,      make_widget_projection_example)
const widget_toggle_example      = Example("widget_toggle",      make_widget_toggle_document_example,      make_widget_projection_example)
const widget_toggle_group_example = Example("widget_toggle_group", make_widget_toggle_group_document_example, make_widget_projection_example)
const widget_select_example      = Example("widget_select",      make_widget_select_document_example,      make_widget_projection_example)
const widget_textarea_example    = Example("widget_textarea",    make_widget_textarea_document_example,    make_widget_projection_example)
const widget_accordion_example   = Example("widget_accordion",   make_widget_accordion_document_example,   make_widget_projection_example)
const widget_table_example       = Example("widget_table",       make_widget_table_document_example,       make_widget_projection_example)
const widget_table_offered_example = Example("widget_table_offered", make_widget_table_offered_document_example, make_widget_projection_example)
const widget_table_frozen_example = Example("widget_table_frozen", make_widget_table_frozen_document_example, make_widget_projection_example)
const widget_tree_example        = Example("widget_tree",        make_widget_tree_document_example,        make_widget_projection_example)
const widget_disabled_example    = Example("widget_disabled",    make_widget_disabled_document_example,    make_widget_projection_example)
const widget_focus_example       = Example("widget_focus",       make_widget_focus_document_example,       make_widget_projection_example)
const widget_popup_example       = Example("widget_popup",       make_widget_popup_document_example,       make_widget_popup_projection_example)
const layout_example         = Example("layout",         make_layout_document_example,         make_layout_projection_example)
const constraint_layout_example = Example("constraint_layout", make_constraint_layout_document_example, make_constraint_layout_projection_example)
const collection_example     = Example("collection",     make_collection_document_example,     make_collection_projection_example)
const reversing_example      = Example("reversing",      make_collection_document_example,     make_reversing_projection_example)
const filtering_example      = Example("filtering",      make_collection_document_example,     make_filtering_projection_example)
const searching_example      = Example("searching",      make_collection_document_example,     make_searching_projection_example)
const sorting_example        = Example("sorting",        make_collection_document_example,     make_sorting_projection_example)
const lazy_example           = Example("lazy",           make_lazy_document_example,           make_lazy_projection_example)
const lazy_bidirectional_example = Example("lazy_bidirectional", make_lazy_bidirectional_document_example, make_lazy_bidirectional_projection_example)
const rotating_vector_example = Example("rotating_vector", make_rotating_vector_document, IdentityProjection)

# The visual tier's slice of the example registry, in registry order.
const platform_examples = Example[
    syntax_example,
    text_example,
    plain_text_example,
    text_with_image_example,
    text_layout_examples...,
    text_spacing_examples...,
    object_example,
    object_to_widget_example,
    nested_object_to_widget_example,
    object_field_form_example,
    object_field_syntax_example,
    line_numbering_example,
    word_wrapping_example,
    text_filtering_example,
    text_highlighting_example,
    widget_example,
    widget_label_example,
    widget_text_example,
    widget_checkbox_example,
    widget_button_example,
    widget_button_action_example,
    widget_button_image_example,
    widget_tooltip_example,
    widget_menu_item_example,
    widget_menu_example,
    widget_toolbar_example,
    widget_toolbar_item_example,
    widget_composite_example,
    widget_title_pane_example,
    widget_split_pane_example,
    widget_scroll_bar_example,
    widget_scroll_pane_example,
    widget_offered_example,
    widget_transform_pane_example,
    widget_shell_example,
    widget_tabbed_pane_example,
    pane_example,
    empty_pane_example,
    widget_badge_example,
    widget_separator_example,
    widget_card_example,
    widget_collapsible_card_example,
    widget_switch_example,
    widget_progress_bar_example,
    widget_progress_ring_example,
    widget_slider_example,
    widget_radio_group_example,
    widget_avatar_example,
    widget_alert_example,
    widget_skeleton_example,
    widget_swatch_example,
    widget_toggle_example,
    widget_toggle_group_example,
    widget_select_example,
    widget_textarea_example,
    widget_accordion_example,
    widget_table_example,
    widget_table_offered_example,
    widget_table_frozen_example,
    widget_tree_example,
    widget_disabled_example,
    widget_focus_example,
    widget_popup_example,
    layout_example,
    constraint_layout_example,
    collection_example,
    reversing_example,
    filtering_example,
    searching_example,
    sorting_example,
    lazy_example,
    lazy_bidirectional_example,
    rotating_vector_example,
]

# ── The visual tier's slice of the atomic-document registry ───────────────────
# Hand-authored leaf documents whose (auto-derived) projections the discovered
# catalog turns into `domain/name/variant` examples. The primitives project
# directly to text (a single-step `Primitive*ToText*`), so they exercise the
# catalog's "direct single-step to text" path; the umbrella concatenates every
# tier's slice into `atomic_documents`.
const platform_atomic_documents = AtomicDocument[
    AtomicDocument(:appearance, "appearance", make_appearance_document_example),
    AtomicDocument(:primitive, "string", make_primitive_string_document_example),
    AtomicDocument(:primitive, "number", make_primitive_number_document_example),
    AtomicDocument(:primitive, "bool",   make_primitive_bool_document_example),
    AtomicDocument(:primitive, "insertion", make_primitive_insertion_document_example),
    # Text atoms are already at the `:text` level, so the catalog derives their
    # identity `:text` variant plus the `:graphics` variant (WordWrapping →
    # TextToGraphics, the default text projection). Each is a minimal `TextBlock`
    # exercising one span/structure type.
    AtomicDocument(:text, "string",   make_text_string_document_example),
    AtomicDocument(:text, "newline",  make_text_newline_document_example),
    AtomicDocument(:text, "spacing",  make_text_spacing_document_example),
    AtomicDocument(:text, "graphics", make_text_graphics_document_example),
    AtomicDocument(:text, "line",     make_text_line_document_example),
    # Bare span documents — the type on its own, not wrapped in a `TextBlock`
    # (the entries above wrap it as one element of a block instead). Named
    # `bare_*` rather than reusing the name above: an atom's `domain/name` is
    # what the catalog filters on and what the known-broken registries match by
    # prefix, so two atoms answering to one name would make both ambiguous.
    AtomicDocument(:text, "bare_string",  make_text_string_atom_document_example),
    AtomicDocument(:text, "bare_newline", make_text_newline_atom_document_example),
    AtomicDocument(:text, "bare_line",    make_text_line_atom_document_example),
    # Widget atoms: one bare instance per widget type with a printer and no
    # atom above. Reuses whichever `make_widget_*_document_example` already
    # returns the bare type; `_atom` names the ones disambiguated from an
    # existing same-named multi-state showcase (see document/Widget.jl).
    AtomicDocument(:widget, "accordion",            make_widget_accordion_document_example),
    AtomicDocument(:widget, "alert",                make_widget_alert_atom_document_example),
    AtomicDocument(:widget, "avatar",                make_widget_avatar_document_example),
    AtomicDocument(:widget, "badge",                make_widget_badge_atom_document_example),
    AtomicDocument(:widget, "button",                make_widget_button_document_example),
    AtomicDocument(:widget, "card",                  make_widget_card_document_example),
    AtomicDocument(:widget, "checkbox",              make_widget_checkbox_document_example),
    AtomicDocument(:widget, "composite",             make_widget_composite_document_example),
    AtomicDocument(:widget, "context_menu",          make_widget_context_menu_document_example),
    AtomicDocument(:widget, "dialog",                make_widget_dialog_document_example),
    AtomicDocument(:widget, "insertion",             make_widget_insertion_document_example),
    AtomicDocument(:widget, "label",                 make_widget_label_document_example),
    AtomicDocument(:widget, "list",                  make_widget_list_document_example),
    AtomicDocument(:widget, "menu",                  make_widget_menu_document_example),
    AtomicDocument(:widget, "menu_item",             make_widget_menu_item_document_example),
    AtomicDocument(:widget, "option",                make_widget_option_document_example),
    AtomicDocument(:widget, "progress_bar",          make_widget_progress_bar_document_example),
    AtomicDocument(:widget, "progress_ring",         make_widget_progress_ring_document_example),
    AtomicDocument(:widget, "radio_group",           make_widget_radio_group_document_example),
    AtomicDocument(:widget, "scroll_bar",            make_widget_scroll_bar_document_example),
    AtomicDocument(:widget, "scroll_pane",           make_widget_scroll_pane_document_example),
    AtomicDocument(:widget, "select",                make_widget_select_document_example),
    AtomicDocument(:widget, "separator",             make_widget_separator_atom_document_example),
    AtomicDocument(:widget, "shell",                 make_widget_shell_document_example),
    AtomicDocument(:widget, "skeleton",              make_widget_skeleton_atom_document_example),
    AtomicDocument(:widget, "slider",                make_widget_slider_document_example),
    AtomicDocument(:widget, "spin_box",              make_widget_spin_box_document_example),
    AtomicDocument(:widget, "split_pane",            make_widget_split_pane_document_example),
    AtomicDocument(:widget, "status_bar",            make_widget_status_bar_document_example),
    AtomicDocument(:widget, "swatch",                make_widget_swatch_atom_document_example),
    AtomicDocument(:widget, "switch",                make_widget_switch_atom_document_example),
    AtomicDocument(:widget, "tabbed_pane",           make_widget_tabbed_pane_atom_document_example),
    AtomicDocument(:widget, "table",                 make_widget_table_document_example),
    AtomicDocument(:widget, "text",                  make_widget_text_document_example),
    AtomicDocument(:widget, "textarea",              make_widget_textarea_document_example),
    AtomicDocument(:widget, "title_pane",            make_widget_title_pane_document_example),
    AtomicDocument(:widget, "toggle",                make_widget_toggle_atom_document_example),
    AtomicDocument(:widget, "toggle_group",          make_widget_toggle_group_document_example),
    AtomicDocument(:widget, "toolbar",               make_widget_toolbar_document_example),
    AtomicDocument(:widget, "tooltip",               make_widget_tooltip_document_example),
    AtomicDocument(:widget, "transform_pane",        make_widget_transform_pane_document_example),
    AtomicDocument(:widget, "tree",                  make_widget_tree_document_example),
    AtomicDocument(:widget, "tooltip_source",        make_tooltip_source_document_example),
    AtomicDocument(:widget, "clipboard_collection",  make_clipboard_collection_document_example),
    AtomicDocument(:widget, "clipboard_slice",       make_clipboard_slice_document_example),
    AtomicDocument(:widget, "reference_inspector",   make_reference_inspector_document_example),
    AtomicDocument(:widget, "screen_document",       make_screen_document_document_example),
    AtomicDocument(:widget, "window_document",       make_window_document_document_example),
    AtomicDocument(:graphics, "canvas", make_graphics_canvas_document_example),
    # Layout atoms.
    AtomicDocument(:layout, "anchored",          make_anchored_layout_document_example),
    AtomicDocument(:layout, "constraint",        make_constraint_layout_document_example),
    AtomicDocument(:layout, "flow",              make_flow_layout_document_example),
    AtomicDocument(:layout, "grid",              make_grid_layout_document_example),
    AtomicDocument(:layout, "horizontal",        make_horizontal_layout_document_example),
    AtomicDocument(:layout, "stack",             make_stack_layout_document_example),
    AtomicDocument(:layout, "vertical",          make_vertical_layout_document_example),
    AtomicDocument(:layout, "layout_constraint", make_layout_constraint_document_example),
    # Syntax atom.
    AtomicDocument(:syntax, "leaf", make_syntax_leaf_document_example),
    # Base-tier collections. They live in this slice because the example-package
    # DAG is kernel ← visual ← domain with no base tier of its own, and this is
    # the lowest one that can name them.
    AtomicDocument(:collection, "vector",    make_collection_document_example),
    AtomicDocument(:collection, "table",     make_cell_table_document_example),
    AtomicDocument(:collection, "list_node", make_list_node_document_example),
]
