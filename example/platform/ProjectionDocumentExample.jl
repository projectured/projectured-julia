# A fault report of a part that failed while it printed, with no barrier to try it again.
make_fault_report_document_example() =
    FaultReport(site = "print", origin = "JsonToSyntax", message = "no method matching print_document")
