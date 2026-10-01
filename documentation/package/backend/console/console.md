# Console backend

> **Kind:** design · **Status:** current · **Stands on:** [devices-and-backends.md](../../kernel/devices-and-backends.md), [text.md](../../platform/text/text.md), [style.md](../../platform/style/style.md)

`ProjecturedConsole` holds `ConsoleBackend`, which draws a text document in a terminal with ANSI colour codes and reads the keys of the terminal. It needs no third-party package, so the umbrella `Projectured` holds it. This document says how the backend implements the interface of [devices-and-backends.md](../../kernel/devices-and-backends.md), and what a console pipeline must look like.

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

### Draw

The backend has no text measure: a console pipeline ends in `TextBlock` and never reaches `TextToGraphics`, so no projection of a console pipeline measures text.

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
| `ESC [ H`, `ESC [ 1 ~`, `ESC [ 7 ~` | `KeyDown(:home)` with Ctrl and Alt, the chord that selects the root |
| `ESC [ F`, `ESC [ 4 ~`, `ESC [ 8 ~` | `KeyDown(:end)` |
| `ESC [ 2 ~`, `3 ~`, `5 ~`, `6 ~` | `KeyDown` of `:insert`, `:delete`, `:page_up`, `:page_down` |
| `ESC [ P` to `S`, `ESC [ 11 ~` to `ESC [ 24 ~` | `KeyDown` of `:f1` to `:f12` |
| `ESC O` and a letter of the rows above | the same key as `ESC [` and that letter |
| `ESC [ Z` | `KeyDown(:tab)` with Shift |
| `ESC [ 1 ; m X`, `ESC [ n ; m ~` | the key of `X` or of `n`, with the modifiers of `m` |
| a lone ESC | `KeyDown(:escape)` |
| ESC and another key | that key with Alt |
| CR, LF | `KeyDown(:return)` |
| DEL, BS | `KeyDown(:backspace)` |
| TAB | `KeyDown(:tab)` |
| NUL | `KeyDown(:space)` with Ctrl |
| Ctrl+C | `WindowQuit()` |
| another byte of Ctrl+A to Ctrl+Z, 0x01 to 0x1A | `KeyDown` of `:a` to `:z` with Ctrl |
| a printable byte, a UTF-8 sequence | `KeyPress(char)` |

The parameter `m` is 1 plus the sum of 1 for Shift, 2 for Alt, 4 for Ctrl and 8 for Meta, as xterm sends it. So `ESC [ 1 ; 5 D` is Ctrl+Left. Home with a modifier is `KeyDown(:home)` with that modifier, and only a plain Home selects the root. The parser drops a whole control sequence that has no key in the table, such as a mouse report or the marks of a bracketed paste.

A lone ESC is Escape, and ESC followed by a key is that key with Alt. The two differ only in the time between the bytes. A terminal writes a whole escape sequence at once, so its bytes normally arrive in one read. When the bytes end in the start of a sequence, `read_from_devices` waits at most 50 ms for more. When no byte arrives in that time, the bytes are the keys that the user typed: a lone ESC is Escape, and `ESC [` is Alt+`[`. When more bytes arrive, the parser reads the sequence that they complete.

Ctrl+C gives `WindowQuit`, and the editor quits. Escape reaches the readers as a key, as [devices-and-backends.md](../../kernel/devices-and-backends.md) requires, and the editor loop quits on an Escape that no reader handled.

Every event is wrapped as `WindowInput(:console, event)`, because the console has no window. Home selects the root because the console has no mouse to make a first selection.

### Wait and wake

`wait_for_input` returns at once when bytes wait. Else it waits on an autoreset `Base.Event`, with a `Timer` for the timeout. The watcher task blocks on the TTY with `Base.wait_readnb`, notifies the event when bytes arrive, and then waits until the editor has read them, so it does not spin. `wake_backend!` notifies the same event, from any task. With no watcher, the wait is one poll slice of at most 10 ms.

### What a person can do

Structural navigation works: the arrows move between nodes once a whole element is selected, and Home selects the root. Ctrl+Space switches between the structural selection and the text caret. Character editing works too: insert, Backspace, Delete, left and right. These come from the `@gestures` table of `TextBlock`, which `SyntaxToText` calls when its own reader returns no operation; see [text.md](../../platform/text/text.md#from-a-key-to-an-edit). What needs the positions of glyphs stays with `TextToGraphics`: up and down by a visual line, a plain Home or End to the edge of a line, and a click.

## How it fits

`ProjecturedConsole` depends on the kernel and the platform: the style slice for the colours, and the text slice for the spans. It registers nothing.

`default_backend()` in `example/projectured/DefaultBackend.jl` picks it last, after `SdlBackend` and `WebBackend`. The gallery pipelines end in graphics, so a gallery run on this backend raises the error above; `run_console_example` builds a console pipeline instead. `warm_application()` gives its editor a `ConsoleBackend`, because the warm-up of a build must run with no display and draws nothing.

## Design decisions

- **The pipeline stops at the text domain.** The spans of `SyntaxToText` are already the flat sequence that a terminal needs. See [plan/done/console-backend.md](../../../../plan/done/console-backend.md).
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

- A lone Escape reaches the editor 50 ms after the key, because the parser waits for the rest of a sequence. Escape and a key that arrive in one read are one Alt chord.
- The parser reads only the sequences in the table, and it drops any other control sequence.
- There is no mouse.
- `TextSpacing` prints one space whatever its width, and an image in the text prints nothing.
