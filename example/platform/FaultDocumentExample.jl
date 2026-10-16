# A fault log of two lines: a fault found in three places, and one found once.
function make_fault_log_document_example()
    log = FaultLog()
    push!(log.entries, FaultLogEntry(1, UInt64(1), :print, :JsonToSyntax, "no method matching print_document", 3))
    push!(log.entries, FaultLogEntry(2, UInt64(2), :read, :SyntaxToText, "index out of range", 1))
    log
end
