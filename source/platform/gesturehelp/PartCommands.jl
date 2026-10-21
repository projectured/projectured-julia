# Fragment of `GestureHelpModule` — the commands of a part, as a model of an
# assistant lists and runs them.
#
# The selection of the person does not move. The commands are those of the part's
# own table, which is where a route to the part ends: at the end of a route the
# document reads the gesture with its own table, and no projection is asked. Then
# come the commands that each document on the path gives to the part below it, as
# an explorer gives the commands of a row of its tree. The chosen command goes to
# the root from the place of the document that gave it, as an operation with a
# route, so every reader on the way lifts it and the history of the window records
# it as it records an edit of the person.

"""
    collect_part_commands(holder, steps) -> Vector{GestureRow}

The commands that the document `holder` gives to its part at `steps`, a tuple of
reference steps from `holder`, beside the commands of the table of the part itself.
The operation of each row is relative to `holder`, and it moves neither the
selection of the person nor the page that the person sees, unless that is what
the command is for. The default answers none.

A document that offers commands for the parts that it holds adds a method, as an
explorer gives the commands of the menu of a row of its tree.
"""
collect_part_commands(holder, steps) = GestureRow[]

# Every command of `part`, each a row and the place from the root that its
# operation is relative to: first the rows of the table of the part, with the
# operation that its binding built against the part now; then the commands that
# each document on the path of the part gives to it, the nearest document first.
# A command whose words a nearer row has is left out, so the nearest wins. The part
# is read again from the root by its reference, so a change at its place since a
# verb found it is seen. A row whose binding reads the keystroke, or whose
# precondition fails, has no operation.
function _collect_part_commands(editor, part::ReferencedDocument)
    root = getfield(editor, :document)
    steps = collect(get_reference_steps(strip_reference_types(get_reference(part))))
    nodes = Any[root]
    for step in steps
        node = try_evaluate_reference(nodes[end], extend_reference(EmptyReference(), step), missing)
        node === missing && return Tuple{GestureRow,Reference}[]
        push!(nodes, node)
    end
    nodes[end] isa Document || return Tuple{GestureRow,Reference}[]
    get_place(count) = annotate_reference_types(root, extend_reference(EmptyReference(), steps[1:count]...))
    place = get_place(length(steps))
    commands = Tuple{GestureRow,Reference}[(row, place)
                                           for row in collect_gesture_rows(read_gesture(nodes[end], CollectIntents()))]
    for count in (length(steps) - 1):-1:0
        holder = nodes[count + 1]
        holder isa Document || continue
        for row in collect_part_commands(holder, Tuple(steps[(count + 1):end]))
            any(command -> first(command).description == row.description, commands) && continue
            push!(commands, (row, get_place(count)))
        end
    end
    commands
end

_collect_runnable_commands(editor, part::ReferencedDocument) =
    [command for command in _collect_part_commands(editor, part) if first(command).operation !== nothing]

"""
    describe_commands(part; editor = get_evaluation_editor()) -> Text

The commands that can run on `part` now, one line each: the words that say what
the command does, and the keys that run it when it has keys. They are the
commands of the part's own document, which F1 lists when the person selects the
part, and then the commands that a document around the part gives to it, such as
the commands of the menu of a row of the explorer. [`run_command!`](@ref) runs one
of them by its words. A part whose document has no command says so. The selection
of the person does not move.

Use it to find what a part of a document can do before you change it, such as a
new element of a JSON array, the order of the entries of an object, or the place
of an entry of the explorer.

# Example

    people_1 = get_edited_document(find_pane("people.json"))
    println(describe_commands(people_1))
    println(describe_commands(people_1[1]))
    println(describe_commands(find_explorer_content().entries[1]))

See also `run_command!`, `find_selected_part`.
"""
function describe_commands end

function describe_commands(part::ReferencedDocument; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "describe_commands") do
        rows = first.(_collect_runnable_commands(editor, part))
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
function run_command! end

function run_command!(part::ReferencedDocument, description::AbstractString;
                      editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "run_command!") do
        commands = _collect_runnable_commands(editor, part)
        rows = first.(commands)
        matches = [command for command in commands if first(command).description == description]
        isempty(matches) &&
            throw(ArgumentError("The part has no command " * repr(String(description)) *
                                " now. Its commands: " *
                                join([repr(row.description) for row in rows], ", ") * "."))
        length(matches) == 1 ||
            throw(ArgumentError(string(length(matches), " commands of the part are called ",
                                       repr(String(description)), ", of ",
                                       join([first(command).domain for command in matches], " and "),
                                       ", and this verb can not tell them apart.")))
        (row, place) = only(matches)
        rooted = read_rooted_operation(editor, place, row.operation; description = String(description))
        rooted === nothing &&
            throw(ArgumentError("The window can not run " * repr(String(description)) *
                                " on this part."))
        evaluate_operation(editor, rooted)
    end
    Text("Ran " * repr(String(description)) * ".")
end
