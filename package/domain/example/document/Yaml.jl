# ── Atomic YAML scalars — one meaningful instance per leaf type, for the catalog. ──
function make_yaml_null_document_example()
    YamlNull()
end

function make_yaml_bool_document_example()
    YamlBool(true)
end

function make_yaml_number_document_example()
    YamlNumber(42)
end

function make_yaml_string_document_example()
    YamlString("Hello, world")
end

# Minimal non-empty compound (node) document — for the catalog.
# (yaml/sequence is deferred — a minimal sequence's graphics Ctrl+Home seed returns
# nothing; see plan/done/catalog-compound-atoms.md.)
make_yaml_mapping_document_example()  = YamlMapping("a" => YamlString("x"))

function make_yaml_document_example()
    YamlMapping(
        "name"    => YamlString("Alice"),
        "age"     => YamlNumber(30),
        "active"  => YamlBool(true),
        "address" => YamlMapping(
            "street" => YamlString("123 Main St"),
            "city"   => YamlString("Wonderland"),
            "zip"    => YamlString("12345"),
        ),
        "scores"  => YamlSequence(
            YamlNumber(95),
            YamlNumber(87),
            YamlNumber(100),
        ),
        "tags"    => YamlSequence(
            YamlString("admin"),
            YamlString("editor"),
            YamlString("reviewer"),
        ),
        "meta"    => YamlMapping(
            "created" => YamlString("2025-01-15"),
            "version" => YamlNumber(2),
            "draft"   => YamlBool(false),
        ),
        "placeholder" => YamlInsertion(),
    )
end
