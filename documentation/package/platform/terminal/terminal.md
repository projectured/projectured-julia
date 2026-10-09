# Terminal

> **Kind:** design · **Status:** current · **Stands on:** [editor.md](../../kernel/editor.md), [agent.md](../../kernel/agent.md)

The terminal slice of `ProjecturedPlatform` runs one program and shows it as a document: the lines that the program writes, a line that the person types and sends with Return, the status of the program, and a stop button. The first use is the sign-in of an agent, whose program prints a URL, reads a code, and ends with the status 0 when the sign-in worked.

The terminal is simple on purpose. It has no terminal device (pseudo terminal) and draws no screen: no colours of the program, no cursor moves, no program with a full screen such as an editor. A program that reads a line works in it.

## How it works

**The document.** `TerminalDocument(command; on_exit = nothing, line_capacity = 2000)` holds:

- `command`, the `Cmd` that it runs;
- `lines`, the `TerminalLine`s so far, each a `text` and a `kind`: `:output` for the standard output, `:error` for the standard error, `:input` for a line that the person sent, and `:status` for a line of the terminal itself; at most `line_capacity`, the oldest go first;
- `is_line_open`, whether the program can still add to the last line, so a prompt with no line end shows before the person answers it;
- `input`, a `PrimitiveString`, the line that the person types;
- `status`: `:new`, `:running`, the exit status, or `:failed` when the program could not start;
- `control`, the `TerminalControl` (the process, and whether a stop was asked) while the program runs;
- `on_exit`, a function that the terminal calls on the editor task with the editor and the exit status.

**The text.** `add_terminal_text!(terminal, kind, text)` adds what a stream wrote. Text goes on the open last line when the same stream wrote that line, a line end closes a line, and the text after the last carriage return of a line replaces the text before it, so a progress line does not repeat. The escape sequences of colour and cursor are removed. `add_terminal_line!(terminal, kind, text)` adds a whole line of the kind `:input` or `:status`.

**The program.** `start_terminal!(editor, terminal)` runs on the editor task, as an operation or an action does. It starts the command with pipes for its standard input, output and error, in a process group of its own. Two reader tasks read what is available, not whole lines, and post it with `run_on_editor_task!(…; wait = false)`. A character that a read cuts in two waits for the rest of its bytes. When both streams end, the terminal posts the exit status (128 and the number of the signal, when a signal ended the program), a status line, and the call of `on_exit`. The reader tasks keep the editor to post their writes; the document does not keep it.

`send_terminal_input!(terminal, text)` writes the text and a line end to the standard input. A program with no terminal device does not echo what it reads, so the terminal adds the text as an `:input` line. `stop_terminal!(terminal)` sends SIGINT to the process group, as Ctrl+C does in a terminal; a second stop sends SIGKILL. On Windows a stop ends the process. `release_document!` sends SIGTERM to the group when the tab of the terminal closes.

**The view.** `TerminalToWidget` draws a row with the command, the status and the stop button; the lines in a pane that follows the end, each in the style of its kind; and the input line in a pane of its own. The input line is the `PrimitiveString` of the document, which the renderer draws as plain text and the text layer edits, so typing and paste work as in any text.

A key reaches the input line by selection. The view maps `input.<rest>` to the path of the pane of the input line and back, and the column and that pane carry the selection down. A press on the text of the input line puts the caret where it was aimed. A press that nothing in the terminal takes, on the lines or beside the input line, puts the caret at the end of the input line, as a press in a terminal gives it the keys. Return with no modifier, while the caret is in the input line and the program runs, gives `SendTerminalInputOperation`, which sends the line and empties it, and a caret at the start of the line. The send writes to a running program, so an undo does not take it back.

### The theme

`TerminalTheme` holds the font (Ubuntu Mono), the texts of the four kinds of line, the height of the pane of the lines and of the pane of the input line, and the gap between the parts. `make_terminal_projection(; theme)` fills the styles of the projection with `get_terminal_style`.

## How it fits

The slice depends on the domain, layout, natural, primitive, projection, style and widget slices, and on the kernel for `run_on_editor_task!` and the events. Its `__init__` registers the view with `register_natural_graphics!(:terminal, …)`, so a tab, or a card that embeds a terminal, draws it.

The assistant uses it for the sign-in of an agent: an `AgentSignInMethod` holds the `Cmd` of the sign-in, and a terminal runs it.

## Tests

`test_terminal()` in `ProjecturedPlatformTest`: the text becomes lines; a cut character waits; a `sh` program shows a prompt with no line end, gets a line, writes both streams and ends with its status; a stop ends a program with SIGINT; a program that does not exist gives `:failed`; and in an editor, a press, keys and Return send a line and keep the caret in the input line.
