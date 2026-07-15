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
const collection_example     = Example("collection",     make_collection_document_example,     make_collection_projection_example)
const reversing_example      = Example("reversing",      make_collection_document_example,     make_reversing_projection_example)
const filtering_example      = Example("filtering",      make_collection_document_example,     make_filtering_projection_example)
const searching_example      = Example("searching",      make_collection_document_example,     make_searching_projection_example)
const sorting_example        = Example("sorting",        make_collection_document_example,     make_sorting_projection_example)
const lazy_example           = Example("lazy",           make_lazy_document_example,           make_lazy_projection_example)
const lazy_bidirectional_example = Example("lazy_bidirectional", make_lazy_bidirectional_document_example, make_lazy_bidirectional_projection_example)
const rotating_vector_example = Example("rotating_vector", make_rotating_vector_document, IdentityProjection)

# The visual tier's slice of the example registry, in registry order.
const visual_examples = Example[
    syntax_example,
    text_example,
    plain_text_example,
    text_with_image_example,
    object_example,
    object_to_widget_example,
    nested_object_to_widget_example,
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
    widget_composite_example,
    widget_title_pane_example,
    widget_split_pane_example,
    widget_scroll_bar_example,
    widget_scroll_pane_example,
    widget_transform_pane_example,
    widget_shell_example,
    widget_tabbed_pane_example,
    widget_badge_example,
    widget_separator_example,
    widget_card_example,
    widget_switch_example,
    widget_progress_example,
    widget_slider_example,
    widget_radio_group_example,
    widget_avatar_example,
    widget_alert_example,
    widget_skeleton_example,
    widget_toggle_example,
    widget_toggle_group_example,
    widget_select_example,
    widget_textarea_example,
    widget_accordion_example,
    widget_table_example,
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
const visual_atomic_documents = AtomicDocument[
    AtomicDocument("string", :primitive, make_primitive_string_document_example),
    AtomicDocument("number", :primitive, make_primitive_number_document_example),
    AtomicDocument("bool",   :primitive, make_primitive_bool_document_example),
]
