# The workflow "Ship the CSV importer" at its last stage, with elements of three
# other domains: the settings of the importer as JSON under the goal, the design
# note as a Markdown page under the parser, and the entry point of the parser as
# Julia code under the chosen option. Each element draws through the view of its
# own domain inside the outline, and an edit in an element edits its document.
function make_workflow_complete_document_example()
    workflow = make_workflow_elements_document_example()
    parser = workflow.children[2]
    chosen = parser.children[1].options[2]
    note = parse_markdown("""
        # Design

        A row ends at a line break **outside** quotes. The tokenizer reads one field at a
        time, so a large file never sits in memory whole.
        """)
    settings = parse_json("""{"separator": ";", "header": true, "encoding": "UTF-8"}""")
    entry = parse_julia("read_csv(path; separator = ',', header = true) = CsvTable(path, separator, header)")
    push!(workflow.elements, settings)
    push!(parser.elements, note)
    push!(chosen.elements, entry)
    workflow
end
