# A gesture log of a run of typed characters, folded into one entry, and a key that does something else.
function make_gesture_log_document_example()
    log = GestureLog()
    for character in "ab"
        record_gesture!(log, KeyPress(character; time = 0.0), DoNothingOperation(); fold_typing = true)
    end
    record_gesture!(log, KeyPress('\t'; time = 0.0), DoNothingOperation())
    log
end
