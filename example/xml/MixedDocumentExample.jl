function make_mixed_document_example()
    JsonObject(
        "meta" => JsonObject(
            "title"   => JsonString("Q1 Report"),
            "author"  => JsonString("Alice"),
            "version" => JsonNumber(1),
            "tags"    => JsonArray(
                JsonString("draft"),
                JsonString("internal"),
            ),
        ),
        "body" => XmlElement("article",
            [XmlAttribute("lang", "en")],
            [
                XmlElement("head", [
                    XmlElement("title",  [XmlText("Q1 Report")]),
                    XmlElement("author", [XmlText("Alice")]),
                ]),
                XmlElement("body", [
                    XmlElement("section",
                        [XmlAttribute("id", "intro")],
                        [
                            XmlElement("h1", [XmlText("Introduction")]),
                            XmlElement("p",  [XmlText("Overview of Q1 results.")]),
                        ]),
                    XmlElement("section",
                        [XmlAttribute("id", "results")],
                        [
                            XmlElement("h1", [XmlText("Results")]),
                            XmlElement("p",  [XmlText("Revenue grew 12% year-on-year.")]),
                            XmlElement("p",  [XmlText("Three new markets opened.")]),
                        ]),
                ]),
            ]),
    )
end
