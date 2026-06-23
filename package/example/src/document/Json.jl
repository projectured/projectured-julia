function make_json_document_example()
    document = JsonObject(
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
    document
end

function make_json_null_document_example()
    JsonNull()
end

function make_json_string_document_example()
    document = JsonString("Hello, world")
    document
end
