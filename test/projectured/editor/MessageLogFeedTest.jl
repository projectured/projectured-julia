# The message log as a feed — a logger on any task writes the store, and the
# editor moves the lines into the `MessageLog` document once per frame. No
# task other than the editor's writes a cell of the document.

function test_message_log_feed()
@testset "the message log feed" begin
    @testset "a captured line reaches the document through the drain" begin
        store = MessageLogStore()
        log = MessageLog()
        feed = MessageLogFeed(store = store, log = log)
        editor = Editor(log, MessageLogToSyntax(); backend = HeadlessBackend(),
                        devices = Device[], feeds = Feed[feed])
        previous = Base.CoreLogging.global_logger()
        # The wrapper defers filtering to the logger it wraps, so wrap one
        # that accepts Info and prints nowhere.
        Base.CoreLogging.global_logger(
            MessageLogLogger(store, Base.CoreLogging.SimpleLogger(devnull)))
        try
            @info "a line from the test"
        finally
            Base.CoreLogging.global_logger(previous)
        end
        @test length(log.entries) == 0        # nothing wrote the document yet
        @test editor.wake_pending[]           # the capture woke the editor
        @test drain_feeds!(editor) >= 1
        @test length(log.entries) == 1
        @test log.entries[1].message == "a line from the test"
        @test drain_feeds!(editor) == 0       # drained means drained
    end

    @testset "a line from a foreign task stays out of the document until the drain" begin
        store = MessageLogStore()
        log = MessageLog()
        feed = MessageLogFeed(store = store, log = log)
        editor = Editor(log, MessageLogToSyntax(); backend = HeadlessBackend(),
                        devices = Device[], feeds = Feed[feed])
        producer = @async record_message!(store, "Info", "from another task")
        wait(producer)
        @test length(log.entries) == 0
        drain_feeds!(editor)
        @test length(log.entries) == 1
    end

    @testset "the store bounds what two frames can hold" begin
        store = MessageLogStore(capacity = 3)
        log = MessageLog()
        feed = MessageLogFeed(store = store, log = log)
        editor = Editor(log, MessageLogToSyntax(); backend = HeadlessBackend(),
                        devices = Device[], feeds = Feed[feed])
        for index in 1:5
            record_message!(store, "Info", "line $(index)")
        end
        drain_feeds!(editor)
        # Three lines survived, plus the one warning about the two that fell.
        @test length(log.entries) == 4
        @test occursin("dropped 2 lines", log.entries[1].message)
        @test log.entries[end].message == "line 5"
    end
end
end
