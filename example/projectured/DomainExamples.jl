# domain-example/Examples.jl
#
# The domain-tier `Example` instances: the concrete source domains
# (json/yaml/xml/sql/...), the application examples (conversation,
# assistant), and the cross-domain compositions (mixed, graph, tables). The
# global `examples` registry that interleaves every tier lives in the
# `ProjecturedExample` umbrella.

const json_example           = Example("json",           make_json_document_example,           make_json_projection_example)
const json_sorted_example    = Example("json_sorted",    make_json_document_example,           make_json_sorted_projection_example)
# A bare `JsonInsertion` (the typed-name insertion buffer) under the FULL json projection, so
# the placeholder can be authored into any JSON value (the leaf insertion
# projection cannot render the replacement). Editable counterpart of the scalar
# leaf examples; shares the shape of the non-registry `json_build_example`.
const json_insertion_example = Example("json_insertion", make_json_insertion_document_example, make_json_projection_example)
const yaml_example           = Example("yaml",           make_yaml_document_example,           make_yaml_projection_example)
const xml_example            = Example("xml",            make_xml_document_example,            make_xml_projection_example)
const mixed_example          = Example("mixed",          make_mixed_document_example,          make_mixed_projection_example)
const natural_example        = Example("natural",        make_natural_document_example,        make_natural_projection_example)
const book_example           = Example("book",           make_book_document_example,           make_book_projection_example)
const markdown_example       = Example("markdown",       make_markdown_document_example,       make_markdown_projection_example)
const markdown_rendered_example = Example("markdown_rendered", make_markdown_document_example,   make_markdown_rendered_projection_example)
const rst_example            = Example("rst",            make_rst_document_example,            make_rst_projection_example)
const rst_rendered_example   = Example("rst_rendered",   make_rst_document_example,            make_rst_rendered_projection_example)
const filesystem_example     = Example("filesystem",     make_filesystem_document_example,     make_filesystem_projection_example)
const filesystem_widget_example = Example("filesystem_widget", make_filesystem_document_example, make_filesystem_widget_projection_example)
const files_example          = Example("files",          make_files_document_example,          make_files_projection_example)
const focusing_example       = Example("focusing",       make_focusing_document_example,       make_focusing_projection_example)
const table_example          = Example("table",          make_table_document_example,          make_table_projection_example)
const math_table_example     = Example("math_table",     make_math_table_document_example,     make_math_table_projection_example)
const graph_example          = Example("graph",          make_graph_document_example,          make_graph_projection_example)
const chart_example          = Example("chart",          make_chart_document_example,          make_chart_projection_example)
const chart_line_example     = Example("chart_line",     make_chart_line_document_example,     make_chart_line_projection_example)
const chart_bar_example      = Example("chart_bar",      make_chart_bar_document_example,      make_chart_bar_projection_example)
const chart_histogram_example = Example("chart_histogram", make_chart_histogram_document_example, make_chart_histogram_projection_example)
const chart_scatter_example  = Example("chart_scatter",  make_chart_scatter_document_example,  make_chart_scatter_projection_example)
const chart_strip_example    = Example("chart_strip",    make_chart_strip_document_example,    make_chart_strip_projection_example)
const chart_inspector_example = Example("chart_inspector", make_chart_inspector_document_example, make_chart_inspector_projection_example)
const sequencechart_example  = Example("sequencechart",  make_sequencechart_document_example,  make_sequencechart_projection_example)
const sequencechart_vertical_example = Example("sequencechart_vertical", make_sequencechart_vertical_document_example, make_sequencechart_vertical_projection_example)
const sequencechart_linear_example = Example("sequencechart_linear", make_sequencechart_linear_document_example, make_sequencechart_linear_projection_example)
const sequencechart_inspector_example = Example("sequencechart_inspector", make_sequencechart_inspector_document_example, make_sequencechart_inspector_projection_example)
const sequencechart_pair_example = Example("sequencechart_pair", make_sequencechart_pair_document_example, make_sequencechart_pair_projection_example)
const fsm_example            = Example("fsm",            make_fsm_document_example,            make_fsm_projection_example)
const fsm_toggle_example     = Example("fsm_toggle",     make_fsm_toggle_document_example,     make_fsm_projection_example)
const fsm_diagram_example    = Example("fsm_diagram",    make_fsm_diagram_document_example,    make_fsm_diagram_projection_example)
const pivot_example          = Example("pivot",          make_pivot_pane_document_example,     make_pivot_projection_example)
const process_example        = Example("process",        make_process_document_example,        make_process_projection_example)
const process_drain_example  = Example("process_drain",  make_process_drain_document_example,  make_process_projection_example)
const process_diagram_example = Example("process_diagram", make_process_diagram_document_example, make_process_diagram_projection_example)
# The visual tier's `pane_example` with real domain documents in its tabs: the
# focused tab holds the json example document, and the renderer is the natural
# projection, so any other domain works in a tab too.
const pane_json_example      = Example("pane_json",      make_pane_json_document_example,      make_pane_json_projection_example; render_width=1000, render_height=700)
# A `WidgetTabbedPane` **as the document**, one domain document per tab. The
# smallest case of a tab group that owns a selection: no projection stage sits
# between the document and the widget, so the selection the tab strip reads is the
# document's own.
const widget_tabs_example    = Example("widget_tabs",    make_widget_tabs_document_example,    make_widget_tabs_projection_example; render_width=900, render_height=600)
# A `WidgetSplitPane` as the document, json on one side and xml on the other. Both
# sides are on the screen at once, so the live caret and a dormant one are visible
# together — which the tabbed pane cannot show.
const widget_split_example   = Example("widget_split",   make_widget_split_document_example,   make_widget_split_projection_example; render_width=900, render_height=500)
# A split pane holding two tab groups. The layout that shows whether a group keeps
# the tab it was showing when the focus moves to the other group.
const widget_split_tabs_example = Example("widget_split_tabs", make_widget_split_tabs_document_example, make_widget_split_tabs_projection_example; render_width=1000, render_height=560)
# `lazy_example` / `lazy_bidirectional_example` are deliberately kept OUT of the
# `examples` registry below. Their documents are infinite lazy linked lists, so
# the enumeration-based suites (test_printers / test_readers / test_position_navigations /
# test_repls), which walk a document exhaustively, would never terminate and would
# exhaust memory. Use them directly (e.g. `run_example(lazy_example)`); do not add
# them to `examples`.
const math_example           = Example("math",           make_math_document_example,           make_math_projection_example)
# The same domain, typeset in two dimensions: the formulas of communication
# network simulation, one per construct the renderer has to get right.
#
# Deliberately kept OUT of the `examples` registry below, for the reason
# `lazy_example` is: one of the sweeps does not apply to it. A two-dimensional
# formula has no line of text to put a caret in — a selection there names a
# whole sub-expression — so `test_typein`, which types a character at every
# rendered caret, has nothing to type into and reports every position as a
# failure. Its printer, reader and navigation are covered by
# `test_math_to_graphics()` in the domain suite; use it directly
# (`run_example(math_display_example)`) for everything else.
const math_display_example   = Example("math_display",   make_math_display_document_example,   make_math_display_projection_example)
const julia_example          = Example("julia",          make_julia_document_example,          make_julia_projection_example)
const graphics_image_example = Example("graphics_image", make_json_document_example,           make_json_projection_example)
const assistant_example      = Example("assistant",      make_assistant_document_example,      make_assistant_projection_example; render_width=1600, render_height=1000)
const conversation_widget_example = Example("conversation_widget", make_conversation_document_example, make_conversation_widget_projection_example; render_width=1200, render_height=700)
const conversation_editor_example = Example("conversation_editor", make_conversation_editor_document_example, make_conversation_editor_projection_example; render_width=1200, render_height=400)
# The live-database (ODBC) catalog/object/sql_table examples and the native
# AdaptagramsLayout graph examples (graph_adaptagrams, dvdrental_relationship) live
# in the opt-in `ProjecturedODBCExample` / `ProjecturedAdaptagramsExample` / `ProjecturedTulipExample` packages, so this base package depends on
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
# test_position_navigations) and `test_example` run every sub-test on one *shared*
# document instance in sequence, so the destructive no-selection `test_repl`
# sweep collapses the small wrapped content before navigation runs (a Ctrl+Home
# seed then finds no caret). Each suite passes on a *fresh* document — run them
# individually, e.g. `test_printer(clipboard_example)` / `test_reader(...)` /
# `test_repl(...)` / `test_position_navigation(...)`. Use it interactively with
# `run_example(clipboard_example)`; the selection-driven copy/cut/paste flow it
# exists to demonstrate is unaffected.
const clipboard_example      = Example("clipboard",       make_clipboard_document_example,      make_clipboard_projection_example)
const formula_example        = Example("formula",         make_formula_document_example,        make_formula_projection_example)
# `versioning_example` is deliberately kept OUT of the `examples` registry below
# (like `clipboard_example`). The version-elimination projection selects one of
# several `ObjectVersion`s by criterion and re-roots edits under
# `versions[idx].value`; the enumeration-based suites (test_printers /
# test_readers / test_repls / test_position_navigations) run every sub-test on one
# *shared* document instance, so a destructive sweep on the eliminated view can
# leave a later sub-test without a caret. Each suite passes on a *fresh*
# document — run them individually, e.g. `test_printer(versioning_example)` /
# `test_reader(...)` / `test_position_navigation(...)`. Use it interactively with
# `run_example(versioning_example)`.
const versioning_example     = Example("versioning",      make_versioning_document_example,     make_versioning_projection_example)
# `undo_example` is deliberately kept OUT of the `examples` registry below, for
# the reason `versioning_example` is: the enumeration-based suites run every
# sub-test on one shared document, and a buffer records what those sweeps do, so
# a later sub-test would start with a history the sweep before it left. Each
# suite passes on a fresh document — run them one at a time, e.g.
# `test_printer(undo_example)`. Use it interactively with `run_example(undo_example)`.
const undo_example           = Example("undo",            make_undo_document_example,           make_undo_projection_example)
# The other half of the pair: the buffer's own history drawn as a panel, rather
# than the document it holds. It is kept out of the `examples` registry for the
# same reason, and for one more — a sweep would edit the history it is showing.
const undo_history_example   = Example("undo history",    make_undo_history_document_example,   make_undo_history_projection_example)

# The domain tier's slice of the example registry, in registry order.
const domain_examples = Example[
    json_example,
    json_sorted_example,
    json_insertion_example,
    yaml_example,
    xml_example,
    mixed_example,
    natural_example,
    book_example,
    markdown_example,
    markdown_rendered_example,
    rst_example,
    rst_rendered_example,
    filesystem_example,
    filesystem_widget_example,
    files_example,
    focusing_example,
    table_example,
    math_table_example,
    graph_example,
    chart_example,
    chart_line_example,
    chart_bar_example,
    chart_histogram_example,
    chart_scatter_example,
    chart_strip_example,
    chart_inspector_example,
    sequencechart_example,
    sequencechart_vertical_example,
    sequencechart_linear_example,
    sequencechart_inspector_example,
    sequencechart_pair_example,
    fsm_example,
    process_example,
    process_drain_example,
    process_diagram_example,
    fsm_toggle_example,
    fsm_diagram_example,
    pivot_example,
    pane_json_example,
    widget_tabs_example,
    widget_split_example,
    widget_split_tabs_example,
    math_example,
    julia_example,
    graphics_image_example,
    assistant_example,
    conversation_widget_example,
    conversation_editor_example,
    sql_syntax_example,
    sql_insert_syntax_example,
    sql_update_syntax_example,
    sql_nested_syntax_example,
    dragging_example,
    clipboard_example,
    formula_example,
    versioning_example,
    undo_example,
    undo_history_example,
]

# ── The domain tier's slice of the atomic-document registry ───────────────────
# Hand-authored leaf documents (meaningful content, not `minimal()` stand-ins);
# the discovered catalog derives each one's trivial single-step projection plus
# the composite projections that reach `:text` and `:graphics`, under hierarchical
# `domain/name/variant` names. The umbrella concatenates every tier's slice into
# `atomic_documents`. json / yaml / xml / markdown reach text+graphics through the
# whole-tree bridges; math currently yields only the `:syntax` variant.
const domain_atomic_documents = AtomicDocument[
    AtomicDocument(:json, "null",   make_json_null_document_example),
    AtomicDocument(:json, "bool",   make_json_bool_document_example),
    AtomicDocument(:json, "number", make_json_number_document_example),
    AtomicDocument(:json, "string", make_json_string_document_example),
    AtomicDocument(:json, "array",        make_json_array_document_example),
    AtomicDocument(:json, "object",       make_json_object_document_example),
    AtomicDocument(:json, "object_entry", make_json_object_entry_document_example),
    AtomicDocument(:yaml, "null",   make_yaml_null_document_example),
    AtomicDocument(:yaml, "bool",   make_yaml_bool_document_example),
    AtomicDocument(:yaml, "number", make_yaml_number_document_example),
    AtomicDocument(:yaml, "string", make_yaml_string_document_example),
    AtomicDocument(:yaml, "sequence", make_yaml_sequence_document_example),
    AtomicDocument(:yaml, "mapping",  make_yaml_mapping_document_example),
    AtomicDocument(:xml, "text", make_xml_text_document_example),
    AtomicDocument(:xml, "element",   make_xml_element_document_example),
    AtomicDocument(:xml, "attribute", make_xml_attribute_document_example),
    AtomicDocument(:markdown, "text",           make_markdown_text_document_example),
    AtomicDocument(:markdown, "code",           make_markdown_code_document_example),
    AtomicDocument(:markdown, "thematic_break", make_markdown_thematic_break_document_example),
    AtomicDocument(:markdown, "insertion",      make_markdown_insertion_document_example),
    AtomicDocument(:markdown, "heading",   make_markdown_heading_document_example),
    AtomicDocument(:markdown, "paragraph", make_markdown_paragraph_document_example),
    AtomicDocument(:markdown, "list",      make_markdown_list_document_example),
    AtomicDocument(:markdown, "emphasis",  make_markdown_emphasis_document_example),
    AtomicDocument(:markdown, "link",      make_markdown_link_document_example),
    AtomicDocument(:markdown, "strong",     make_markdown_strong_document_example),
    AtomicDocument(:markdown, "code_block", make_markdown_code_block_document_example),
    AtomicDocument(:markdown, "image",      make_markdown_image_document_example),
    AtomicDocument(:markdown, "list_item",  make_markdown_list_item_document_example),
    AtomicDocument(:markdown, "quote",      make_markdown_quote_document_example),
    AtomicDocument(:markdown, "table_row",  make_markdown_table_row_document_example),
    AtomicDocument(:markdown, "table",      make_markdown_table_document_example),
    AtomicDocument(:markdown, "root",       make_markdown_root_document_example),
    AtomicDocument(:rst, "text",                     make_rst_text_document_example),
    AtomicDocument(:rst, "literal",                  make_rst_literal_document_example),
    AtomicDocument(:rst, "transition",               make_rst_transition_document_example),
    AtomicDocument(:rst, "comment",                  make_rst_comment_document_example),
    AtomicDocument(:rst, "target",                   make_rst_target_document_example),
    AtomicDocument(:rst, "insertion",                make_rst_insertion_document_example),
    AtomicDocument(:rst, "math_block",               make_rst_math_block_document_example),
    AtomicDocument(:rst, "role",                     make_rst_role_document_example),
    AtomicDocument(:rst, "reference",                make_rst_reference_document_example),
    AtomicDocument(:rst, "substitution_reference",   make_rst_substitution_reference_document_example),
    AtomicDocument(:rst, "footnote_reference",       make_rst_footnote_reference_document_example),
    AtomicDocument(:rst, "emphasis",                 make_rst_emphasis_document_example),
    AtomicDocument(:rst, "strong",                   make_rst_strong_document_example),
    AtomicDocument(:rst, "paragraph",                make_rst_paragraph_document_example),
    AtomicDocument(:rst, "literal_block",            make_rst_literal_block_document_example),
    AtomicDocument(:rst, "line_block",               make_rst_line_block_document_example),
    AtomicDocument(:rst, "list_item",                make_rst_list_item_document_example),
    AtomicDocument(:rst, "bullet_list",              make_rst_bullet_list_document_example),
    AtomicDocument(:rst, "enumerated_list",          make_rst_enumerated_list_document_example),
    AtomicDocument(:rst, "definition_item",          make_rst_definition_item_document_example),
    AtomicDocument(:rst, "definition_list",          make_rst_definition_list_document_example),
    AtomicDocument(:rst, "field",                    make_rst_field_document_example),
    AtomicDocument(:rst, "field_list",               make_rst_field_list_document_example),
    AtomicDocument(:rst, "block_quote",              make_rst_block_quote_document_example),
    AtomicDocument(:rst, "footnote",                 make_rst_footnote_document_example),
    AtomicDocument(:rst, "substitution_definition",  make_rst_substitution_definition_document_example),
    AtomicDocument(:rst, "table_cell",               make_rst_table_cell_document_example),
    AtomicDocument(:rst, "table_row",                make_rst_table_row_document_example),
    AtomicDocument(:rst, "grid_table",               make_rst_grid_table_document_example),
    AtomicDocument(:rst, "directive_option",         make_rst_directive_option_document_example),
    AtomicDocument(:rst, "literal_include",          make_rst_literal_include_document_example),
    AtomicDocument(:rst, "figure",                   make_rst_figure_document_example),
    AtomicDocument(:rst, "code_block",               make_rst_code_block_document_example),
    AtomicDocument(:rst, "image",                    make_rst_image_document_example),
    AtomicDocument(:rst, "video",                    make_rst_video_document_example),
    AtomicDocument(:rst, "audio",                    make_rst_audio_document_example),
    AtomicDocument(:rst, "admonition",               make_rst_admonition_document_example),
    AtomicDocument(:rst, "toctree",                  make_rst_toctree_document_example),
    AtomicDocument(:rst, "raw_block",                make_rst_raw_block_document_example),
    AtomicDocument(:rst, "role_definition",          make_rst_role_definition_document_example),
    AtomicDocument(:rst, "directive",                make_rst_directive_document_example),
    AtomicDocument(:rst, "section",                  make_rst_section_document_example),
    AtomicDocument(:rst, "root",                     make_rst_root_document_example),
    AtomicDocument(:math, "variable",  make_math_variable_document_example),
    AtomicDocument(:math, "insertion", make_math_insertion_document_example),
    AtomicDocument(:math, "binary_operation", make_math_binary_operation_document_example),
    AtomicDocument(:math, "assignment",       make_math_assignment_document_example),
    AtomicDocument(:math, "parenthesized",    make_math_parenthesized_document_example),
    AtomicDocument(:math, "symbol",           make_math_symbol_document_example),
    AtomicDocument(:math, "text",             make_math_text_document_example),
    AtomicDocument(:math, "space",            make_math_space_document_example),
    AtomicDocument(:math, "row",              make_math_row_document_example),
    AtomicDocument(:math, "unary_operation",  make_math_unary_operation_document_example),
    AtomicDocument(:math, "fraction",         make_math_fraction_document_example),
    AtomicDocument(:math, "script",           make_math_script_document_example),
    AtomicDocument(:math, "radical",          make_math_radical_document_example),
    AtomicDocument(:math, "big_operator",     make_math_big_operator_document_example),
    AtomicDocument(:math, "differential",     make_math_differential_document_example),
    AtomicDocument(:math, "derivative",       make_math_derivative_document_example),
    AtomicDocument(:math, "function",         make_math_function_document_example),
    AtomicDocument(:math, "accent",           make_math_accent_document_example),
    AtomicDocument(:math, "matrix",           make_math_matrix_document_example),
    AtomicDocument(:math, "case",             make_math_case_document_example),
    AtomicDocument(:math, "cases",            make_math_cases_document_example),
    AtomicDocument(:julia, "bool",       make_julia_bool_document_example),
    AtomicDocument(:julia, "break",      make_julia_break_document_example),
    AtomicDocument(:julia, "char",       make_julia_char_document_example),
    AtomicDocument(:julia, "continue",   make_julia_continue_document_example),
    AtomicDocument(:julia, "float",      make_julia_float_document_example),
    AtomicDocument(:julia, "identifier", make_julia_identifier_document_example),
    AtomicDocument(:julia, "integer",    make_julia_integer_document_example),
    AtomicDocument(:julia, "string",     make_julia_string_document_example),
    AtomicDocument(:julia, "symbol",     make_julia_symbol_document_example),
    AtomicDocument(:julia, "binary_op",  make_julia_binary_op_document_example),
    AtomicDocument(:julia, "call",       make_julia_call_document_example),
    AtomicDocument(:julia, "assignment", make_julia_assignment_document_example),
    AtomicDocument(:julia, "block",      make_julia_block_document_example),
    AtomicDocument(:julia, "function",   make_julia_function_document_example),
    AtomicDocument(:julia, "array",            make_julia_array_document_example),
    AtomicDocument(:julia, "begin",             make_julia_begin_document_example),
    AtomicDocument(:julia, "field_access",      make_julia_field_access_document_example),
    AtomicDocument(:julia, "for",                make_julia_for_document_example),
    AtomicDocument(:julia, "for_iterator",       make_julia_for_iterator_document_example),
    AtomicDocument(:julia, "if",                 make_julia_if_document_example),
    AtomicDocument(:julia, "index",              make_julia_index_document_example),
    AtomicDocument(:julia, "lambda",             make_julia_lambda_document_example),
    AtomicDocument(:julia, "range",              make_julia_range_document_example),
    AtomicDocument(:julia, "return",             make_julia_return_document_example),
    AtomicDocument(:julia, "ternary",            make_julia_ternary_document_example),
    AtomicDocument(:julia, "try",                make_julia_try_document_example),
    AtomicDocument(:julia, "tuple",               make_julia_tuple_document_example),
    AtomicDocument(:julia, "type_annotation",    make_julia_type_annotation_document_example),
    AtomicDocument(:julia, "unary_op",           make_julia_unary_op_document_example),
    AtomicDocument(:julia, "using",              make_julia_using_document_example),
    AtomicDocument(:julia, "while",              make_julia_while_document_example),
    AtomicDocument(:julia, "abstract_type",             make_julia_abstract_type_document_example),
    AtomicDocument(:julia, "anonymous_type_annotation", make_julia_anonymous_type_annotation_document_example),
    AtomicDocument(:julia, "broadcast",                 make_julia_broadcast_document_example),
    AtomicDocument(:julia, "comprehension",             make_julia_comprehension_document_example),
    AtomicDocument(:julia, "const",                     make_julia_const_document_example),
    AtomicDocument(:julia, "curly",                     make_julia_curly_document_example),
    AtomicDocument(:julia, "do",                        make_julia_do_document_example),
    AtomicDocument(:julia, "docstring",                 make_julia_docstring_document_example),
    AtomicDocument(:julia, "empty",                     make_julia_empty_document_example),
    AtomicDocument(:julia, "function_declaration",      make_julia_function_declaration_document_example),
    AtomicDocument(:julia, "interpolation",             make_julia_interpolation_document_example),
    AtomicDocument(:julia, "let",                       make_julia_let_document_example),
    AtomicDocument(:julia, "macro_call",                make_julia_macro_call_document_example),
    AtomicDocument(:julia, "module_def",                make_julia_module_def_document_example),
    AtomicDocument(:julia, "named_tuple",               make_julia_named_tuple_document_example),
    AtomicDocument(:julia, "splat",                     make_julia_splat_document_example),
    AtomicDocument(:julia, "string_chunk",              make_julia_string_chunk_document_example),
    AtomicDocument(:julia, "string_interpolation",      make_julia_string_interpolation_document_example),
    AtomicDocument(:julia, "struct",                    make_julia_struct_document_example),
    AtomicDocument(:julia, "subtype",                   make_julia_subtype_document_example),
    AtomicDocument(:julia, "where",                     make_julia_where_document_example),
    AtomicDocument(:julia, "where_parameters",          make_julia_where_parameters_document_example),
    AtomicDocument(:book, "paragraph", make_book_paragraph_document_example),
    AtomicDocument(:book, "picture",   make_book_picture_document_example),
    AtomicDocument(:book, "insertion", make_book_insertion_document_example),
    AtomicDocument(:book, "chapter", make_book_chapter_document_example),
    AtomicDocument(:book, "list",    make_book_list_document_example),
    AtomicDocument(:book, "book",    make_book_book_document_example),
    AtomicDocument(:filesystem, "file", make_filesystem_file_document_example),
    AtomicDocument(:filesystem, "directory", make_filesystem_directory_document_example),
    AtomicDocument(:sql, "all_columns",  make_sql_all_columns_document_example),
    AtomicDocument(:sql, "column_name",  make_sql_column_name_document_example),
    AtomicDocument(:sql, "table_name",   make_sql_table_name_document_example),
    AtomicDocument(:sql, "scalar_value", make_sql_scalar_value_document_example),
    AtomicDocument(:sql, "comparison",       make_sql_comparison_document_example),
    AtomicDocument(:sql, "select_item",      make_sql_select_item_document_example),
    AtomicDocument(:sql, "select_statement", make_sql_select_statement_document_example),
    AtomicDocument(:sql, "and",                    make_sql_and_document_example),
    AtomicDocument(:sql, "or",                     make_sql_or_document_example),
    AtomicDocument(:sql, "not",                    make_sql_not_document_example),
    AtomicDocument(:sql, "where_filter_condition", make_sql_where_filter_condition_document_example),
    AtomicDocument(:sql, "where_clause",           make_sql_where_clause_document_example),
    AtomicDocument(:sql, "select_clause",          make_sql_select_clause_document_example),
    AtomicDocument(:sql, "from_item",              make_sql_from_item_document_example),
    AtomicDocument(:sql, "from_clause",            make_sql_from_clause_document_example),
    AtomicDocument(:sql, "join_on_condition",      make_sql_join_on_condition_document_example),
    AtomicDocument(:sql, "join_using_condition",   make_sql_join_using_condition_document_example),
    AtomicDocument(:sql, "raw_expression",         make_sql_raw_expression_document_example),
    AtomicDocument(:sql, "raw_condition",          make_sql_raw_condition_document_example),
    AtomicDocument(:sql, "joined_from_item",       make_sql_joined_from_item_document_example),
    AtomicDocument(:sql, "subquery_from_item",     make_sql_subquery_from_item_document_example),
    AtomicDocument(:sql, "column_definition",      make_sql_column_definition_document_example),
    AtomicDocument(:sql, "create_table_statement", make_sql_create_table_statement_document_example),
    AtomicDocument(:sql, "create_schema_statement", make_sql_create_schema_statement_document_example),
    AtomicDocument(:sql, "statement_list",         make_sql_statement_list_document_example),
    AtomicDocument(:sql, "insert_statement",       make_sql_insert_statement_document_example),
    AtomicDocument(:sql, "update_assignment",      make_sql_update_assignment_document_example),
    AtomicDocument(:sql, "update_statement",       make_sql_update_statement_document_example),
    AtomicDocument(:julia, "nothing",   make_julia_nothing_document_example),
    AtomicDocument(:julia, "insertion", make_julia_insertion_document_example),
    AtomicDocument(:fsm, "component",  make_fsm_component_document_example),
    AtomicDocument(:fsm, "event",      make_fsm_event_document_example),
    AtomicDocument(:fsm, "machine",    make_fsm_machine_document_example),
    AtomicDocument(:fsm, "state",      make_fsm_state_document_example),
    AtomicDocument(:fsm, "timer",      make_fsm_timer_document_example),
    AtomicDocument(:fsm, "transition", make_fsm_transition_document_example),
    AtomicDocument(:fsm, "variable",   make_fsm_variable_document_example),
    AtomicDocument(:process, "step",       make_process_step_document_example),
    AtomicDocument(:process, "sequence",   make_process_sequence_document_example),
    AtomicDocument(:process, "decision",   make_process_decision_document_example),
    AtomicDocument(:process, "while",      make_process_while_document_example),
    AtomicDocument(:process, "foreach",    make_process_foreach_document_example),
    AtomicDocument(:process, "break",      make_process_break_document_example),
    AtomicDocument(:process, "continue",   make_process_continue_document_example),
    AtomicDocument(:process, "return",     make_process_return_document_example),
    AtomicDocument(:process, "insertion",  make_process_insertion_document_example),
    AtomicDocument(:process, "model",      make_process_model_document_example),
    AtomicDocument(:process, "terminal",   make_process_terminal_document_example),
    AtomicDocument(:process, "edge_label", make_process_edge_label_document_example),
    AtomicDocument(:pivot, "table",        make_pivot_document_example),
    AtomicDocument(:conversation, "conversation", make_conversation_conversation_document_example),
    AtomicDocument(:conversation, "draft",        make_conversation_draft_document_example),
    AtomicDocument(:conversation, "part",         make_conversation_part_document_example),
    AtomicDocument(:conversation, "turn",         make_conversation_turn_document_example),
    AtomicDocument(:dbcatalog, "column",   make_db_catalog_column_document_example),
    AtomicDocument(:dbcatalog, "database", make_db_catalog_database_document_example),
    AtomicDocument(:dbcatalog, "rdbms",    make_db_catalog_rdbms_document_example),
    AtomicDocument(:dbcatalog, "schema",   make_db_catalog_schema_document_example),
    AtomicDocument(:dbcatalog, "table",    make_db_catalog_table_document_example),
    AtomicDocument(:formula, "environment", make_formula_environment_document_example),
    AtomicDocument(:formula, "formula",     make_formula_formula_document_example),
    AtomicDocument(:formula, "insertion",   make_formula_insertion_document_example),
    AtomicDocument(:formula, "reference",   make_formula_reference_document_example),
    AtomicDocument(:graph, "graph",  make_graph_graph_document_example),
    AtomicDocument(:graph, "layout", make_graph_layout_document_example),
    AtomicDocument(:chart, "plot",        make_chart_plot_document_example),
    AtomicDocument(:sequencechart, "plot", make_sequence_chart_plot_document_example),
    AtomicDocument(:sql, "column_reference", make_sql_column_reference_document_example),
    AtomicDocument(:sql, "table_expression", make_sql_table_expression_document_example),
    AtomicDocument(:workspace, "folder",    make_workspace_folder_document_example),
    AtomicDocument(:workspace, "workspace", make_workspace_document_example),
    AtomicDocument(:gesture, "map", make_gesture_map_document_example),
    AtomicDocument(:database, "instance", make_database_instance_document_example),
    # Two base-tier documents whose only example lives here, because the wrapper
    # is only interesting around a domain document: a `DraggingState` over a
    # JSON array, a `VersionedObject` over a JSON object.
    AtomicDocument(:dragging, "state", make_dragging_document_example),
    AtomicDocument(:versioning, "object", make_versioning_document_example),
    AtomicDocument(:undo, "buffer", make_undo_document_example),
]
