# domain-example/Examples.jl
#
# The domain-tier `Example` instances: the concrete source domains
# (json/yaml/xml/sql/...), the application examples (workbench, conversation,
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
const filesystem_example     = Example("filesystem",     make_filesystem_document_example,     make_filesystem_projection_example)
const filesystem_widget_example = Example("filesystem_widget", make_filesystem_document_example, make_filesystem_widget_projection_example)
const navigator_example      = Example("navigator",      make_navigator_document_example,      make_navigator_projection_example)
const focusing_example       = Example("focusing",       make_focusing_document_example,       make_focusing_projection_example)
const table_example          = Example("table",          make_table_document_example,          make_table_projection_example)
const math_table_example     = Example("math_table",     make_math_table_document_example,     make_math_table_projection_example)
const graph_example          = Example("graph",          make_graph_document_example,          make_graph_projection_example)
const workbench_example      = Example("workbench",      make_workbench_document_example,      make_workbench_projection_example)
# `lazy_example` / `lazy_bidirectional_example` are deliberately kept OUT of the
# `examples` registry below. Their documents are infinite lazy linked lists, so
# the enumeration-based suites (test_printers / test_readers / test_position_navigations /
# test_repls), which walk a document exhaustively, would never terminate and would
# exhaust memory. Use them directly (e.g. `run_example(lazy_example)`); do not add
# them to `examples`.
const math_example           = Example("math",           make_math_document_example,           make_math_projection_example)
const julia_example          = Example("julia",          make_julia_document_example,          make_julia_projection_example)
const graphics_image_example = Example("graphics_image", make_json_document_example,           make_graphics_image_projection_example)
const assistant_example      = Example("assistant",      make_assistant_document_example,      make_assistant_projection_example; render_width=1600, render_height=283)
const conversation_example   = Example("conversation",   make_conversation_document_example,   make_conversation_projection_example; render_width=1200, render_height=600)
const conversation_widget_example = Example("conversation_widget", make_conversation_document_example, make_conversation_widget_projection_example; render_width=1200, render_height=700)
const conversation_editor_example = Example("conversation_editor", make_conversation_editor_document_example, make_conversation_editor_projection_example; render_width=1200, render_height=400)
# The live-database (ODBC) catalog/object/sql_table examples and the native
# AdaptagramsEngine graph examples (graph_adaptagrams, dvdrental_relationship) live
# in the opt-in `ProjecturedOdbcExample` / `ProjecturedAdaptagramsExample` / `ProjecturedTulipExample` packages, so this base package depends on
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
    filesystem_example,
    filesystem_widget_example,
    navigator_example,
    focusing_example,
    table_example,
    math_table_example,
    graph_example,
    workbench_example,
    math_example,
    julia_example,
    graphics_image_example,
    assistant_example,
    conversation_example,
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
    AtomicDocument(:yaml, "null",   make_yaml_null_document_example),
    AtomicDocument(:yaml, "bool",   make_yaml_bool_document_example),
    AtomicDocument(:yaml, "number", make_yaml_number_document_example),
    AtomicDocument(:yaml, "string", make_yaml_string_document_example),
    AtomicDocument(:xml, "text", make_xml_text_document_example),
    AtomicDocument(:markdown, "text",           make_markdown_text_document_example),
    AtomicDocument(:markdown, "code",           make_markdown_code_document_example),
    AtomicDocument(:markdown, "thematic_break", make_markdown_thematic_break_document_example),
    AtomicDocument(:markdown, "insertion",      make_markdown_insertion_document_example),
    AtomicDocument(:math, "variable",  make_math_variable_document_example),
    AtomicDocument(:math, "insertion", make_math_insertion_document_example),
    AtomicDocument(:julia, "bool",       make_julia_bool_document_example),
    AtomicDocument(:julia, "break",      make_julia_break_document_example),
    AtomicDocument(:julia, "char",       make_julia_char_document_example),
    AtomicDocument(:julia, "continue",   make_julia_continue_document_example),
    AtomicDocument(:julia, "float",      make_julia_float_document_example),
    AtomicDocument(:julia, "identifier", make_julia_identifier_document_example),
    AtomicDocument(:julia, "integer",    make_julia_integer_document_example),
    AtomicDocument(:julia, "string",     make_julia_string_document_example),
    AtomicDocument(:julia, "symbol",     make_julia_symbol_document_example),
    AtomicDocument(:book, "paragraph", make_book_paragraph_document_example),
    AtomicDocument(:book, "picture",   make_book_picture_document_example),
    AtomicDocument(:book, "insertion", make_book_insertion_document_example),
    AtomicDocument(:filesystem, "file", make_filesystem_file_document_example),
    AtomicDocument(:sql, "all_columns",  make_sql_all_columns_document_example),
    AtomicDocument(:sql, "column_name",  make_sql_column_name_document_example),
    AtomicDocument(:sql, "table_name",   make_sql_table_name_document_example),
    AtomicDocument(:sql, "scalar_value", make_sql_scalar_value_document_example),
    AtomicDocument(:julia, "nothing",   make_julia_nothing_document_example),
    AtomicDocument(:julia, "insertion", make_julia_insertion_document_example),
]
