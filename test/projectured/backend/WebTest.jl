# The tests of `WebBackend`. Most of them need no server: a client message goes
# through `_decode_and_enqueue!`, as the receive task sends it, and the test reads
# the queue, waits and wakes. One test starts the server on a free port of
# 127.0.0.1, connects a WebSocket client and stops the server at the end.

const _WEB = ProjecturedWeb

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
        font = StyleModule.font_ubuntu_regular_20
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
                                   for file in get_fallback_font_files(font.filename)]
    end

    @testset "a decoded message is read from the queue" begin
        backend = WebBackend(port = 0)
        @test backend.server === nothing
        @test read_from_devices(backend, Device[]) === nothing
        _WEB._decode_and_enqueue!(backend, _WEB_ESCAPE_MESSAGE)
        window_input = read_from_devices(backend, Device[])
        @test window_input isa WindowInput
        @test window_input.window_id === :main
        @test window_input.event == KeyDown(:escape, ModifierKeys(); time = 1.5)
        @test read_from_devices(backend, Device[]) === nothing
    end

    @testset "a letter key has the name of its lower-case letter" begin
        backend = WebBackend(port = 0)
        _WEB._decode_and_enqueue!(backend,
            """{"type":"keydown","window":"main","key":"z","code":"KeyZ",
                "mods":{"ctrl":true}}""")
        @test read_from_devices(backend, Device[]).event.key === :z
        _WEB._decode_and_enqueue!(backend,
            """{"type":"keydown","window":"main","key":"Z","code":"KeyZ",
                "mods":{"ctrl":true,"shift":true}}""")
        @test read_from_devices(backend, Device[]).event.key === :z
    end

    @testset "a button with no name in the event layer makes no event" begin
        backend = WebBackend(port = 0)
        _WEB._decode_and_enqueue!(backend,
            """{"type":"mousedown","window":"main","button":"back","x":5,"y":6}""")
        _WEB._decode_and_enqueue!(backend,
            """{"type":"mouseup","window":"main","button":"back","x":5,"y":6}""")
        @test read_from_devices(backend, Device[]) === nothing
        _WEB._decode_and_enqueue!(backend,
            """{"type":"mousedown","window":"main","button":"right","x":5,"y":6}""")
        @test read_from_devices(backend, Device[]).event.button === :right
    end

    @testset "the letters, the buttons and the wheel have the names of the event layer" begin
        backend = WebBackend(port = 0)
        # Each letter key has the name of its lower-case letter, with or without Shift.
        for letter in 'a':'z', key in (string(letter), uppercase(string(letter)))
            code = "Key" * uppercase(string(letter))
            _WEB._decode_and_enqueue!(backend,
                """{"type":"keydown","window":"main","key":"$key","code":"$code"}""")
            @test read_from_devices(backend, Device[]).event.key === Symbol(letter)
        end
        # The page names the left, the middle and the right button. The server
        # drops another name, as the page sends none for a side button.
        for (button, name) in (("left", :left), ("middle", :middle), ("right", :right),
                               ("forward", nothing))
            _WEB._decode_and_enqueue!(backend,
                """{"type":"mousedown","window":"main","button":"$button","x":5,"y":6}""")
            down = read_from_devices(backend, Device[])
            @test name === nothing ? down === nothing : down.event.button === name
        end
        # A turn of the wheel away from the user: the page sends a positive `dy`.
        _WEB._decode_and_enqueue!(backend,
            """{"type":"scroll","window":"main","dx":0,"dy":1,"x":5,"y":6}""")
        scroll = read_from_devices(backend, Device[]).event
        @test scroll isa MouseScroll && scroll.dy > 0
    end

    @testset "a motion holds every button that the mask of the browser holds" begin
        backend = WebBackend(port = 0)
        # In the mask of a browser, 1 is the left, 2 the right and 4 the middle button.
        _WEB._decode_and_enqueue!(backend,
            """{"type":"mousemove","window":"main","x":5,"y":6,"buttons":3}""")
        move = read_from_devices(backend, Device[]).event
        @test move isa MouseMove
        @test move.buttons == MouseButtons(:left, :right)
        # A motion with no button held is not sent on.
        _WEB._decode_and_enqueue!(backend,
            """{"type":"mousemove","window":"main","x":5,"y":6,"buttons":0}""")
        @test read_from_devices(backend, Device[]) === nothing
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
        typed = read_from_devices(backend, Device[]).event
        @test typed == KeyPress('a'; time = typed.time)
        @test before <= typed.time <= after
        # With the queue read, the next wait lasts until its timeout.
        @test (@elapsed wait_for_input(backend, Device[], 0.2)) >= 0.15

        # A message that the receive task decodes ends a long wait.
        receiver = @async (sleep(0.05); _WEB._decode_and_enqueue!(backend, _WEB_ESCAPE_MESSAGE))
        elapsed = @elapsed wait_for_input(backend, Device[], 30.0)
        wait(receiver)
        @test elapsed < 5.0
        @test read_from_devices(backend, Device[]).event == KeyDown(:escape, ModifierKeys(); time = 1.5)

        # A resync makes no event, but it ends the wait, so that a frame sends
        # every window in full.
        receiver = @async (sleep(0.05); _WEB._decode_and_enqueue!(backend, """{"type":"resync"}"""))
        elapsed = @elapsed wait_for_input(backend, Device[], 30.0)
        wait(receiver)
        @test elapsed < 5.0
        @test backend.force_full
        @test read_from_devices(backend, Device[]) === nothing

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
            @test (@elapsed wait_for_input(backend, Device[], 10.0)) < 5.0
            @test backend.conn !== nothing
            @test backend.force_full
            notify(send)
            @test (@elapsed wait_for_input(backend, Device[], 10.0)) < 5.0
            window_input = read_from_devices(backend, Device[])
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

end
end
