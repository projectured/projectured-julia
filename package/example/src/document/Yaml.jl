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
