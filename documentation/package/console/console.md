# Console backend

> **Kind:** design · **Status:** current · **Stands on:** [devices-and-backends.md](../kernel/devices-and-backends.md), [text.md](../text/text.md), [style.md](../style/style.md)

`ProjecturedConsole` holds `ConsoleBackend`, which draws a text document in a terminal with ANSI colour codes and reads the keys of the terminal. It needs no third-party package, so the umbrella `Projectured` holds it. This document says how the backend implements the interface of [devices-and-backends.md](../kernel/devices-and-backends.md), and what a console pipeline must look like.

## How it works

### The pipeline ends in text

`write_to_devices` takes a `TextBlock`, the output of `SyntaxToText`, and not a `ScreenDocument`. A console pipeline has no `TextToGraphics` and no window. The JSON example builds one:

```julia
WindowInputUnwrappingProjection(
    ChainingProjection(RecursiveProjection(JsonToSyntax()),
                       RecursiveProjection(SyntaxToText()),
                       SelectionInverting()))
```

- `SelectionInverting` paints the selection into the colours of the spans as inverse video. The backend draws only colours and has no code for the selection.
- `WindowInputUnwrappingProjection` takes the `WindowInput` off each gesture. In a window pipeline `ScreenToScreen` does that.

For any other output, `write_to_devices` raises an error that says to drop the `TextToGraphics` step.

### Measure and draw

`measure_text` returns `(length(text), 1)`, one cell for each character. No projection of a console pipeline measures text, but the interface requires the method.

`render_console` writes the spans of the block into one buffer:

- A `TextLine` ends the line before it and prints its indentation.
- A `TextString` prints its content with its font colour and its fill colour as 24-bit SGR codes.
- `TextNewline` prints a newline, and `TextSpacing` prints one space.
- `TextGraphics` and any other span print nothing.

`color_default` gets no code, so an empty marker span takes the foreground colour of the terminal and is not black on a dark background. With `ansi = false` the backend writes plain text, and with `clear = true` it clears the screen before each frame. The editor loop writes on every tick, so the backend compares the buffer with the last frame and writes nothing when the two are equal. Without that, the terminal would flicker.

### Events in

`initialize_backend!` puts a TTY into raw mode with `jl_tty_set_mode` and starts a watcher task, and `quit_backend!` restores the mode. An input that is not a TTY, such as an `IOBuffer` in a test, skips both. `read_from_devices` appends the waiting bytes to a buffer and parses one event:

| Bytes | Event |
| --- | --- |
| `ESC [ A`, `B`, `C`, `D` | `KeyDown` of `:up`, `:down`, `:right`, `:left` |
| `ESC [ H`, `ESC [ 1 ~` | `KeyDown(:home)` with Ctrl and Alt, the chord that selects the root |
| `ESC [ F` | `KeyDown(:end)` |
| `ESC [ 3 ~` | `KeyDown(:delete)` |
| CR, LF | `KeyDown(:return)` |
| DEL, BS | `KeyDown(:backspace)` |
| TAB | `KeyDown(:tab)` |
| NUL | `KeyDown(:space)` with Ctrl |
| Ctrl+C, or ESC and a byte that is not `[` | `WindowQuit()` |
| a printable byte, a UTF-8 sequence | `KeyPress(char)` |

Every event is wrapped as `WindowInput(:console, event)`, because the console has no window. An incomplete escape sequence stays in the buffer for the next poll. Home selects the root because the console has no mouse to make a first selection.

### Wait and wake

`wait_for_input` returns at once when bytes wait. Else it waits on an autoreset `Base.Event`, with a `Timer` for the timeout. The watcher task blocks on the TTY with `Base.wait_readnb`, notifies the event when bytes arrive, and then waits until the editor has read them, so it does not spin. `wake_backend!` notifies the same event, from any task. With no watcher, the wait is one poll slice of at most 10 ms.

### What a person can do

Structural navigation works: the arrows move between nodes once a whole element is selected, and Home selects the root. Ctrl+Space switches between the structural selection and the text caret. Character editing works too: insert, Backspace, Delete, left and right. These come from the `@gestures` table of `TextBlock`, which `SyntaxToText` calls when its own reader returns no operation; see [text.md](../text/text.md#from-a-key-to-an-edit). What needs the positions of glyphs stays with `TextToGraphics`: up and down by a visual line, a plain Home or End to the edge of a line, and a click.

## How it fits

`ProjecturedConsole` depends on the kernel for the backend interface and the events, on `ProjecturedStyle` for the colours, and on `ProjecturedText` for the spans. It registers nothing.

`default_backend()` in `example/projectured/DefaultBackend.jl` picks it last, after `SdlBackend` and `WebBackend`. The gallery pipelines end in graphics, so a gallery run on this backend raises the error above; `run_console_example` builds a console pipeline instead. `warm_application()` gives its editor a `ConsoleBackend`, because the warm-up of a build must run with no display and draws nothing.

## Design decisions

- **The pipeline stops at the text domain.** The spans of `SyntaxToText` are already the flat sequence that a terminal needs. See `plan/done/console-backend.md`.
- **The colours are kept.** Every span carries its colours, and the backend writes them as SGR codes.
- **The selection is in the colours.** `SelectionInverting` paints it, so the backend has no code for it.
- **A wrong pipeline raises an error.** The error names the step to drop, so a wrong pipeline does not print a wrong picture.
- **The wait blocks on the terminal.** An idle console uses no processor time, and a test with an `IOBuffer` keeps the poll.

## Usage

```julia
run_console_example()                      # one frame of the JSON example, in colour
run_console_example(interactive = true)    # the editor loop in this terminal
run_console_example(ansi = false)          # plain text
backend = ConsoleBackend(; io = stdout, input = stdin, ansi = true, clear = true)
```

The interactive run gives the editor `Device[Keyboard()]` and a `NullLogger`, because a log line would land on the screen that the backend draws.

- Example: `run_console_example` in `example/projectured/Gallery.jl`, with `make_json_console_projection_example()`.
- Test: `test_console_backend()` in `test/projectured/backend/ConsoleBackendTest.jl`. The package has no test suite of its own.

## Limits

- Escape followed by another key quits the editor. The parser holds a lone ESC until the next byte arrives, then turns the pair into `WindowQuit`. So an Alt chord quits too, and no reader gets Escape, against the rule in [devices-and-backends.md](../kernel/devices-and-backends.md).
- The parser reads only the sequences in the table, and it drops an unknown CSI sequence. It reads no modifier on an arrow. A terminal sends Ctrl+Left as `ESC [ 1 ; 5 D`, and the parser reads that as Home followed by the characters `5` and `D`.
- There is no mouse.
- `TextSpacing` prints one space whatever its width, and an image in the text prints nothing.
