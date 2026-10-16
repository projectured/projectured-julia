# A message log of two records: an information and a warning.
function make_message_log_document_example()
    log = MessageLog()
    record_message!(log, "Info", "The editor started.")
    record_message!(log, "Warn", "The settings file was not found.")
    log
end
