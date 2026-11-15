# The log of the background work of a session: the rows of two works of the reads
# of folders, one that ended and one that failed, copied from a store as the feed
# of an editor copies them, so a test makes it with no editor.
function make_background_work_log_document_example()
    log = BackgroundWorkModule._make_background_work_log()
    store = BackgroundWorkStore()
    push!(store.records,
          BackgroundWorkRecord(1, "the listings of folders", 2, ["(\"/home/person\", 0)", "(\"/home/person/data\", 0)"],
                               0.0, 0.25, 0, ""),
          BackgroundWorkRecord(2, "the listings of folders", 1, ["(\"/home/person/private\", 0)"],
                               1.0, 1.5, 1, "permission denied"))
    store.change_count = 2
    flush_background_work_log!(log, store)
    log
end
