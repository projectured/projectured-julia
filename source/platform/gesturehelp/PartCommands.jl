# Fragment of `GestureHelpModule` — the commands of a part, as a model of an
# assistant lists and runs them.
#
# The selection of the person does not move. The commands are those of the part's
# own table, which is where a route to the part ends: at the end of a route the
# document reads the gesture with its own table, and no projection is asked. The
# chosen command goes to the root along the path of the part, as an operation with
# a route, so every reader on the way lifts it and the history of the window
# records it as it records an edit of the person.

# Every row of the table of `part`, each with the operation that its binding built
# against the part now. A row whose binding reads the keystroke, or whose
# precondition fails, has no operation.
function _collect_part_rows(part::ReferencedDocument)
    document = get_document(part)
    document isa Document || return GestureRow[]
    collect_gesture_rows(read_gesture(document, CollectIntents()))
end

_collect_runnable_rows(part::ReferencedDocument) =
    [row for row in _collect_part_rows(part) if row.operation !== nothing]

"""
    describe_commands(part; editor = get_evaluation_editor()) -> Text

The commands that can run on `part` now, one line each: the words that say what
the command does, and the keys that run it when it has keys. They are the
commands of the part's own document, which F1 lists when the person selects the
part, and [`run_command!`](@ref) runs one of them by its words. A part whose
document has no command says so. The selection of the person does not move.

Use it to find what a part of a document can do before you change it, such as a
new element of a JSON array or the order of the entries of an object.

# Example

    people_1 = get_edited_document(find_pane("people.json"))
    println(describe_commands(people_1))
    println(describe_commands(people_1[1]))

See also `run_command!`, `find_selected_part`.
"""
function describe_commands(part::ReferencedDocument; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "describe_commands") do
        rows = _collect_runnable_rows(part)
        isempty(rows) &&
            return Text("This " * String(nameof(typeof(get_document(part)))) * " has no command now.")
        Text(join([isempty(row.gesture) ? row.description : row.description * ": " * row.gesture
                   for row in rows], "\n"))
    end
end

"""
    run_command!(part, description; editor = get_evaluation_editor()) -> Text

Run the command of `part` whose words are `description`, as [`describe_commands`](@ref)
writes them, as the person runs it from the command palette. The change is an
edit of the window: the tool `undo` takes it back. The selection of the person does
not move. A description that names no command of the part now is refused, and the
refusal lists the commands that the part has.

Use it to change a part with a command of its domain, such as a new element at
the end of a JSON array.

# Example

    people_1 = get_edited_document(find_pane("people.json"))
    run_command!(people_1, "Insert a new element")

See also `describe_commands`, `replace_referenced_value!`.
"""
function run_command!(part::ReferencedDocument, description::AbstractString;
                      editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "run_command!") do
        rows = _collect_runnable_rows(part)
        index = findfirst(row -> row.description == description, rows)
        index === nothing &&
            throw(ArgumentError("The part has no command " * repr(String(description)) *
                                " now. Its commands: " *
                                join([repr(row.description) for row in rows], ", ") * "."))
        rooted = read_rooted_operation(editor, get_reference(part), rows[index].operation;
                                       description = String(description))
        rooted === nothing &&
            throw(ArgumentError("The window can not run " * repr(String(description)) *
                                " on this part."))
        evaluate_operation(editor, rooted)
    end
    Text("Ran " * repr(String(description)) * ".")
end
