function make_xml_document_example()
    document = XmlElement("library",
        [XmlAttribute("version", "2.0"), XmlAttribute("lang", "en")],
        [
            XmlElement("book",
                [XmlAttribute("id", "1"), XmlAttribute("genre", "fiction")],
                [
                    XmlElement("title",    [XmlText("The Great Gatsby")]),
                    XmlElement("author",   [XmlText("F. Scott Fitzgerald")]),
                    XmlElement("year",     [XmlText("1925")]),
                    XmlElement("summary",  [XmlText("A portrait of the Jazz Age in all of its decadence and excess.")]),
                ]),
            XmlElement("book",
                [XmlAttribute("id", "2"), XmlAttribute("genre", "science")],
                [
                    XmlElement("title",    [XmlText("A Brief History of Time")]),
                    XmlElement("author",   [XmlText("Stephen Hawking")]),
                    XmlElement("year",     [XmlText("1988")]),
                    XmlElement("summary",  [XmlText("An exploration of cosmology for the general reader.")]),
                ]),
            XmlElement("book",
                [XmlAttribute("id", "3"), XmlAttribute("genre", "fiction")],
                [
                    XmlElement("title",    [XmlText("Nineteen Eighty-Four")]),
                    XmlElement("author",   [XmlText("George Orwell")]),
                    XmlElement("year",     [XmlText("1949")]),
                    XmlElement("summary",  [XmlText("A dystopian novel set in a totalitarian society.")]),
                ]),
            XmlElement("meta",
                [XmlAttribute("updated", "2025-03-01")],
                [
                    XmlElement("curator", [XmlText("Alice")]),
                    XmlElement("count",   [XmlText("3")]),
                ]),
            XmlInsertion(),
        ])

    document
end
