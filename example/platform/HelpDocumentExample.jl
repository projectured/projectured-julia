# The about page of ProjecturedEd, with the version written out so that no project file is read.
make_about_page_document_example() = AboutPage(; version = "1.0.0")

# The help entry of a type that a person cannot create, with one line of description.
make_help_entry_document_example() =
    HelpEntry("Url", Url, false, "", "An address.", "An address.", "", [])
