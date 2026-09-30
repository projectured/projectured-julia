function make_json_document_example()
    JsonObject(
        "name"    => JsonString("Alice"),
        "age"     => JsonNumber(30),
        "active"  => JsonBool(true),
        "address" => JsonObject(
            "street" => JsonString("123 Main St"),
            "city"   => JsonString("Wonderland"),
            "zip"    => JsonString("12345"),
        ),
        "scores"  => JsonArray(
            JsonNumber(95),
            JsonNumber(87),
            JsonNumber(100),
        ),
        "tags"    => JsonArray(
            JsonString("admin"),
            JsonString("editor"),
            JsonString("reviewer"),
        ),
        "meta"    => JsonObject(
            "created" => JsonString("2025-01-15"),
            "version" => JsonNumber(2),
            "draft"   => JsonBool(false),
        ),
        "placeholder" => JsonInsertion(),
    )
end

function make_json_null_document_example()
    JsonNull()
end

function make_json_bool_document_example()
    JsonBool(true)
end

function make_json_number_document_example()
    JsonNumber(42)
end

function make_json_insertion_document_example()
    JsonInsertion()
end

function make_json_string_document_example()
    JsonString("Hello, world")
end

# Minimal non-empty compound (node) documents — one leaf child each, for the catalog.
make_json_array_document_example()        = JsonArray(JsonNumber(1))
make_json_object_document_example()       = JsonObject("a" => JsonString("x"))
make_json_object_entry_document_example() = JsonObjectEntry("a", JsonString("x"))
