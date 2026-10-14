# The tests of `WebBackend`. Most of them need no server: a client message goes
# through `_decode_and_enqueue!`, as the receive task sends it, and the test reads
# the queue, waits and wakes. One test starts the server on a free port of
# 127.0.0.1, connects a WebSocket client and stops the server at the end.

const _WEB = ProjecturedWeb.WebModule

# The page sends the time of each event as `t`, in milliseconds: 1.5 s here.
const _WEB_ESCAPE_MESSAGE =
    """{"type":"keydown","window":"main","key":"Escape","code":"Escape","mods":{},"t":1500}"""

# A port of 127.0.0.1 that no socket holds now.
function _find_free_web_port()
    port, server = _WEB.HTTP.Sockets.listenany(_WEB.HTTP.Sockets.localhost, 49152)
    close(server)
    Int(port)
end

function test_web_backend()
@testset "WebBackend" begin

    @testset "a text goes to the browser as the layout measured it" begin
        # The browser draws each character at its pen position on the baseline,
        # so the node carries the ascent of the box, one offset per character,
        # and the fonts in the order the other backends fall back in.
        font = StyleModule.StyleFont("Ubuntu", 20)
        node = _WEB._serialize_node(GraphicsText("AV→", 10, 20; font, color = color_black))
        _, ascent, _ = compute_text_extent("AV→", font)
        @test node["b"] == ascent
        offsets = compute_caret_offsets(FontFileMeasure(), "AV→", font)
        @test node["o"] ≈ offsets atol = 0.01
        @test length(node["o"]) == 4
        # The kerning of A–V moves the V: it starts before the advance of A alone.
        @test node["o"][2] < measure_string(FontFileMeasure(), "A", font).width
        @test node["f"][1] == "Ubuntu-R"
        @test node["f"][2:end] == [splitext(basename(file))[1]
                                   for file in get_fallback_font_files(font)]
    end

    @testset "an arc goes to the browser with its angles in degrees" begin
        node = _WEB._serialize_node(GraphicsArc(50, 40, 20; width = 4, start_angle = 12.5, sweep_angle = 90,
                                                color = color_black))
        @test node["t"] == "arc"
        @test (node["cx"], node["cy"], node["r"], node["w"]) == (50, 40, 20, 4)
        @test (node["start"], node["sweep"]) == (12.5, 90.0)
        @test node["c"] == _WEB._rgba(color_black)
    end

    @testset "a decoded message is read from the queue" begin
        backend = WebBackend(port = 0)
        @test backend.server === nothing
        @test take_from_devices!(backend, Device[]) === nothing
        _WEB._decode_and_enqueue!(backend, _WEB_ESCAPE_MESSAGE)
        window_input = take_from_devices!(backend, Device[])
        @test window_input isa WindowInput
        @test window_input.window_id === :main
        @test window_input.event == KeyDown(:escape, ModifierKeys(); time = 1.5)
        @test take_from_devices!(backend, Device[]) === nothing
    end

    @testset "a letter key has the name of its lower-case letter" begin
        backend = WebBackend(port = 0)
        _WEB._decode_and_enqueue!(backend,
            """{"type":"keydown","window":"main","key":"z","code":"KeyZ",
                "mods":{"ctrl":true}}""")
        @test take_from_devices!(backend, Device[]).event.key === :z
        _WEB._decode_and_enqueue!(backend,
            """{"type":"keydown","window":"main","key":"Z","code":"KeyZ",
                "mods":{"ctrl":true,"shift":true}}""")
        @test take_from_devices!(backend, Device[]).event.key === :z
    end

    @testset "Return and Tab give their KeyPress after their KeyDown" begin
        backend = WebBackend(port = 0)
        _WEB._decode_and_enqueue!(backend,
            """{"type":"keydown","window":"main","key":"Enter","code":"Enter","repeat":true}""")
        _WEB._decode_and_enqueue!(backend,
            """{"type":"keydown","window":"main","key":"Tab","code":"Tab",
                "mods":{"shift":true}}""")
        events = [take_from_devices!(backend, Device[]).event for _ in 1:4]
        @test events[1] isa KeyDown && events[1].key === :return && events[1].repeat
        @test events[2] isa KeyPress && events[2].char == '\n'
        @test events[3] isa KeyDown && events[3].key === :tab
        @test events[4] isa KeyPress && events[4].char == '\t' && events[4].modifiers.shift
        @test take_from_devices!(backend, Device[]) === nothing
    end

    @testset "the backslash key has the name that the SDL backend gives it" begin
        # The JSON of the page holds the key `\` as "\\".
        backend = WebBackend(port = 0)
        _WEB._decode_and_enqueue!(backend,
            """{"type":"keydown","window":"main","key":"\\\\","code":"Backslash",
                "mods":{"ctrl":true}}""")
        down = take_from_devices!(backend, Device[]).event
        @test down.key === :backslash
        @test down.modifiers.ctrl
    end

    @testset "a button with no name in the event layer makes no event" begin
        backend = WebBackend(port = 0)
        _WEB._decode_and_enqueue!(backend,
            """{"type":"mousedown","window":"main","button":"fifth","x":5,"y":6}""")
        _WEB._decode_and_enqueue!(backend,
            """{"type":"mouseup","window":"main","button":"fifth","x":5,"y":6}""")
        @test take_from_devices!(backend, Device[]) === nothing
        _WEB._decode_and_enqueue!(backend,
            """{"type":"mousedown","window":"main","button":"right","x":5,"y":6}""")
        @test take_from_devices!(backend, Device[]).event.button === :right
    end

    @testset "letters, buttons and the wheel have the names of the event layer" begin
        backend = WebBackend(port = 0)
        # Each letter key has the name of its lower-case letter, with or without Shift.
        for letter in 'a':'z', key in (string(letter), uppercase(string(letter)))
            code = "Key" * uppercase(string(letter))
            _WEB._decode_and_enqueue!(backend,
                """{"type":"keydown","window":"main","key":"$key","code":"$code"}""")
            @test take_from_devices!(backend, Device[]).event.key === Symbol(letter)
        end
        # The page names the left, the middle and the right button, and the side
        # buttons back and forward. The server drops another name.
        for (button, name) in (("left", :left), ("middle", :middle), ("right", :right),
                               ("back", :back), ("forward", :forward), ("fifth", nothing))
            _WEB._decode_and_enqueue!(backend,
                """{"type":"mousedown","window":"main","button":"$button","x":5,"y":6}""")
            down = take_from_devices!(backend, Device[])
            @test name === nothing ? down === nothing : down.event.button === name
        end
        # A turn of the wheel away from the user: the page sends a positive `dy`.
        _WEB._decode_and_enqueue!(backend,
            """{"type":"scroll","window":"main","dx":0,"dy":1,"x":5,"y":6}""")
        scroll = take_from_devices!(backend, Device[]).event
        @test scroll isa MouseScroll && scroll.dy > 0
    end

    @testset "the zoom of the display goes to the browser, and a new zoom sends each window in full" begin
        # The client draws at the zoom, and sends sizes and places divided by it,
        # so the server works in logical pixels at every zoom.
        backend = WebBackend(port = 0)
        backend.conn = _WEB.WebConnection(nothing)
        canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(100)), Cell(Int32(50)),
                                CellVector(Any[GraphicsRect(0, 0, 10, 10; color = color_black)]),
                                layout_none, true, Cell(nothing))
        screen = ScreenDocument([WindowDocument(; id = :main, content = canvas)])
        display = Display(zoom = 1.5)
        devices = Device[display, Keyboard(), Mouse()]
        take_message() = _WEB.JSON3.read(take!(backend.conn.outbox))
        write_to_devices!(backend, devices, screen)
        first_message = take_message()
        @test first_message[:zoom] == 1.5
        @test length(first_message[:full]) == 1
        # With no change, nothing is sent.
        write_to_devices!(backend, devices, screen)
        @test !isready(backend.conn.outbox)
        # A new zoom sends the window in full, with the new zoom.
        display.zoom = 2.0
        write_to_devices!(backend, devices, screen)
        message = take_message()
        @test message[:zoom] == 2.0
        @test length(message[:full]) == 1
        # With no `Display`, the zoom is 1.
        write_to_devices!(backend, Device[Keyboard()], screen)
        @test take_message()[:zoom] == 1.0
    end

    @testset "the canvas under the pointer takes the cursor of the shape there" begin
        backend = WebBackend(port = 0)
        backend.conn = _WEB.WebConnection(nothing)
        canvas = GraphicsCanvas([GraphicsPointerShape(0, 0, 50, 50, :ibeam),
                                 GraphicsPointerShape(50, 0, 10, 50, :double_arrow_horizontal)];
                                w = 100, h = 50)
        screen = ScreenDocument([WindowDocument(; id = :main, content = canvas)])
        take_message() = _WEB.JSON3.read(take!(backend.conn.outbox))
        function move_to!(x)
            _WEB._decode_and_enqueue!(backend,
                """{"type":"mousemove","window":"main","x":$x,"y":10,"buttons":0}""")
            take_from_devices!(backend, Device[])
            write_to_devices!(backend, Device[], screen)
        end
        write_to_devices!(backend, Device[], screen)
        @test take_message()[:type] == "update"
        # No pointer event was read yet, so no cursor goes.
        @test !isready(backend.conn.outbox)
        move_to!(10)
        message = take_message()
        @test (message[:type], message[:window], message[:cursor]) == ("pointer", "main", "text")
        # The same shape sends nothing.
        move_to!(20)
        @test !isready(backend.conn.outbox)
        move_to!(55)
        @test take_message()[:cursor] == "col-resize"
        move_to!(80)
        @test take_message()[:cursor] == "default"
        # A new client gets every window in full, and the cursor again: the receive
        # task asks, and the next frame resets and sends.
        _WEB._ask_for_full_send!(backend)
        write_to_devices!(backend, Device[], screen)
        @test take_message()[:type] == "update"
        @test take_message()[:cursor] == "default"
        # Every shape has a CSS cursor.
        @test all(shape -> haskey(_WEB._CSS_CURSOR_OF_SHAPE, shape), POINTER_SHAPES)
    end

    @testset "a motion holds every button that the mask of the browser holds" begin
        backend = WebBackend(port = 0)
        # In the mask of a browser, 1 is the left, 2 the right and 4 the middle button.
        _WEB._decode_and_enqueue!(backend,
            """{"type":"mousemove","window":"main","x":5,"y":6,"buttons":3}""")
        move = take_from_devices!(backend, Device[]).event
        @test move isa MouseMove
        @test move.buttons == MouseButtons(:left, :right)
        # A motion with no button held goes on too, so the part under the
        # pointer lights in the browser.
        _WEB._decode_and_enqueue!(backend,
            """{"type":"mousemove","window":"main","x":7,"y":8,"buttons":0}""")
        free = take_from_devices!(backend, Device[]).event
        @test free isa MouseMove
        @test (free.x, free.y) == (7, 8)
        @test free.buttons == MouseButtons()
    end

    @testset "the pointer that leaves a window is a window event of that window" begin
        backend = WebBackend(port = 0)
        _WEB._decode_and_enqueue!(backend, """{"type":"leave","window":"main","t":2500}""")
        window_input = take_from_devices!(backend, Device[])
        @test window_input.window_id === :main
        @test window_input.event == WindowLeave(; time = 2.5)
    end

    # Timing assertions are one-sided and generous: a bound says "far less
    # than the full timeout", never "exactly this fast".
    @testset "wait and wake" begin
        backend = WebBackend(port = 0)

        # The timeout ends the wait when nothing else does.
        elapsed = @elapsed wait_for_input(backend, Device[], 0.2)
        @test elapsed >= 0.15
        @test elapsed < 5.0

        # An event in the queue ends the wait before it starts.
        # A message with no `t` has the time when it arrives.
        before = time()
        _WEB._decode_and_enqueue!(backend, """{"type":"keypress","window":"main","text":"a"}""")
        after = time()
        @test (@elapsed wait_for_input(backend, Device[], 30.0)) < 5.0
        typed = take_from_devices!(backend, Device[]).event
        @test typed == KeyPress('a'; time = typed.time)
        @test before <= typed.time <= after
        # With the queue read, the next wait lasts until its timeout.
        @test (@elapsed wait_for_input(backend, Device[], 0.2)) >= 0.15

        # A message that the receive task decodes ends a long wait.
        receiver = @async (sleep(0.05); _WEB._decode_and_enqueue!(backend, _WEB_ESCAPE_MESSAGE))
        elapsed = @elapsed wait_for_input(backend, Device[], 30.0)
        wait(receiver)
        @test elapsed < 5.0
        @test take_from_devices!(backend, Device[]).event == KeyDown(:escape, ModifierKeys(); time = 1.5)

        # A resync makes no event, but it ends the wait, so that a frame sends
        # every window in full.
        receiver = @async (sleep(0.05); _WEB._decode_and_enqueue!(backend, """{"type":"resync"}"""))
        elapsed = @elapsed wait_for_input(backend, Device[], 30.0)
        wait(receiver)
        @test elapsed < 5.0
        @test backend.is_full_send_asked[]
        @test take_from_devices!(backend, Device[]) === nothing

        # A wake from another task ends a long wait.
        waker = @async (sleep(0.05); wake_backend!(backend))
        elapsed = @elapsed wait_for_input(backend, Device[], 30.0)
        wait(waker)
        @test elapsed < 5.0

        # A wake from another thread ends a wait with no timeout.
        waker = Threads.@spawn (sleep(0.05); wake_backend!(backend))
        elapsed = @elapsed wait_for_input(backend, Device[], Inf)
        wait(waker)
        @test elapsed < 5.0

        # A wake that arrives before the wait is not lost.
        @test wake_backend!(backend) === nothing
        @test (@elapsed wait_for_input(backend, Device[], 30.0)) < 5.0
    end

    @testset "the server wakes the editor for a client and its events" begin
        port = _find_free_web_port()
        backend = WebBackend(host = "127.0.0.1", port = port)
        initialize_backend!(backend)
        send = Base.Event()
        done = Base.Event()
        client = @async _WEB.HTTP.WebSockets.open("ws://127.0.0.1:$(port)/ws") do socket
            wait(send)
            _WEB.HTTP.WebSockets.send(socket, _WEB_ESCAPE_MESSAGE)
            wait(done)
        end
        try
            # The connection ends the wait, so that a frame sends every window in full.
            # The first connection also compiles the handshake, which takes seconds
            # on a busy machine; the bound stays far below the timeout, so a wait
            # that only the timeout ends still fails.
            @test (@elapsed wait_for_input(backend, Device[], 60.0)) < 30.0
            @test backend.conn !== nothing
            @test backend.is_full_send_asked[]
            notify(send)
            @test (@elapsed wait_for_input(backend, Device[], 60.0)) < 30.0
            window_input = take_from_devices!(backend, Device[])
            @test window_input isa WindowInput
            @test window_input.event == KeyDown(:escape, ModifierKeys(); time = 1.5)
            response = _WEB.HTTP.get("http://127.0.0.1:$(port)/client.js")
            @test response.status == 200
        finally
            notify(send)
            notify(done)
            timedwait(() -> istaskdone(client), 5.0)
            quit_backend!(backend)
        end
        @test backend.server === nothing
    end

    # While a code unit runs, a held frame keeps the keys and the window events,
    # drops the pointer input that starts in the hold (a release of an earlier
    # press stays), and answers the stop, the close and the confirm to quit.
    @testset "held frames keep the keys, drop the pointer of the hold, and take the stop" begin
        backend = WebBackend(port = 0)
        run(seconds; is_quit_asked = false) =
            run_held_frame!(backend, Device[], HeldFrameState(seconds, 1, false, is_quit_asked))
        send(message) = _WEB._decode_and_enqueue!(backend, message)
        prepare_held_frames!(backend, Device[], ["Run the code: sleep(10)"])
        now = round(Int, time() * 1000)
        early = now - 10_000
        send("""{"type":"mousedown","window":"main","button":"left","x":5,"y":6,"t":$early}""")
        send("""{"type":"keydown","window":"main","key":"a","code":"KeyA","t":$(now + 1)}""")
        send("""{"type":"mousedown","window":"main","button":"right","x":5,"y":6,"t":$(now + 2)}""")
        send("""{"type":"mouseup","window":"main","button":"right","x":5,"y":6,"t":$(now + 3)}""")
        send("""{"type":"mouseup","window":"main","button":"left","x":5,"y":6,"t":$(now + 4)}""")
        send("""{"type":"keydown","window":"main","key":"Escape","code":"Escape","t":$(now + 5)}""")
        @test run(0.2) === :none                    # an Escape before the bar is a key
        @test run(0.6) === :none                    # the bar shows from this frame on
        later = round(Int, time() * 1000) + 1
        send("""{"type":"keydown","window":"main","key":"Escape","code":"Escape","t":$later}""")
        @test run(0.7) === :stop
        send("""{"type":"close","window":"main","t":$later}""")
        @test run(0.8) === :close
        send("""{"type":"stop"}""")
        @test run(0.9) === :stop
        send("""{"type":"quitconfirm"}""")
        @test run(1.0) === :none                    # no question, no quit
        send("""{"type":"quitconfirm"}""")
        @test run(3.5; is_quit_asked = true) === :quit
        end_held_frames!(backend, Device[])
        events = Any[]
        while (input = take_from_devices!(backend, Device[])) !== nothing
            push!(events, input.event)
        end
        @test [typeof(event) for event in events if !(event isa KeyPress)] ==
              [MouseDown, KeyDown, MouseUp, KeyDown]
        @test [event.key for event in events if event isa KeyDown] == [:a, :escape]
    end

end
end
