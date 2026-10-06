# The choice of a backend and the wrappers of `build_editor`. The doubles
# declare outputs and keywords that no real package uses, so a backend or a
# wrapper of this file never joins an editor that another test builds.

import ProjecturedKernel
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.DeviceModule
import ProjecturedKernel.BackendModule
import ProjecturedKernel.BackendModule: Backend
import ProjecturedKernel.OperationModule: QuitEditorOperation
import ProjecturedKernel.EditorModule: Editor, post_operation!, run_editor!,
                                       get_backend_name, get_backend_output,
                                       collect_backend_types, make_default_backend,
                                       EditorParts, wrap_editor!, get_wrapper_layers,
                                       get_excluded_wrappers, is_wrapper_default,
                                       make_document_projection, build_editor, make_editor,
                                       make_editor_parts

@document struct BuildProbe
    value::Int = 0
end

struct BuildProbeProjection <: Projection end
ProjectionModule.print_document(::BuildProbeProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)

# A backend that counts its starts and does nothing else.
mutable struct BuildProbeBackend <: Backend
    starts::Int
end
BuildProbeBackend() = BuildProbeBackend(0)
BackendModule.initialize_backend!(backend::BuildProbeBackend) = (backend.starts += 1; nothing)
BackendModule.quit_backend!(::BuildProbeBackend) = nothing
BackendModule.take_from_devices!(::BuildProbeBackend, devices) = nothing
BackendModule.write_to_devices!(::BuildProbeBackend, devices, output) = nothing

# Two more types, so that one output has two backends.
struct BuildProbeFirstBackend <: Backend end
struct BuildProbeSecondBackend <: Backend end

get_backend_name(::Type{BuildProbeBackend}) = :build_probe
get_backend_output(::Type{BuildProbeBackend}) = :build_probe_single
get_backend_output(::Type{BuildProbeFirstBackend}) = :build_probe_pair
get_backend_output(::Type{BuildProbeSecondBackend}) = :build_probe_pair

# The wrappers, which write what they did into the parts of the editor.
const _BUILD_PROBE_STEPS = Tuple{Symbol,Symbol,Any}[]
const _IS_BUILD_PROBE_DEFAULT_ON = Ref(false)

get_wrapper_layers(::Val{:build_probe_inner}) = (:document => 20,)
get_wrapper_layers(::Val{:build_probe_first}) = (:document => 10,)
get_wrapper_layers(::Val{:build_probe_both}) = (:screen => 5, :document => 30)
get_wrapper_layers(::Val{:build_probe_default}) = (:container => 0,)
get_wrapper_layers(::Val{:build_probe_excluding}) = (:document => 40,)
get_excluded_wrappers(::Val{:build_probe_excluding}) = (:build_probe_inner,)
is_wrapper_default(::Val{:build_probe_default}) = _IS_BUILD_PROBE_DEFAULT_ON[]

for keyword in (:build_probe_inner, :build_probe_first, :build_probe_both,
                :build_probe_default, :build_probe_excluding)
    @eval function wrap_editor!(::Val{$(QuoteNode(keyword))}, layer::Symbol, argument,
                                parts::EditorParts)
        push!(_BUILD_PROBE_STEPS, ($(QuoteNode(keyword)), layer, argument))
        push!(parts.start_steps, editor -> push!(_BUILD_PROBE_STEPS,
                                                 (:started, $(QuoteNode(keyword)), editor)))
        parts
    end
end

# A document type that has a default projection, and one that has none.
@document struct BuildProjectedProbe
    value::Int = 0
end
make_document_projection(::BuildProjectedProbe; _...) = BuildProbeProjection()

# The wrappers of the platform that are on by default, turned off: a process that
# loads the platform has them, and this test checks the root and the steps of the
# probes alone. A keyword that is off and that no loaded package declares is
# ignored, so the kernel alone runs the same test.
const _BUILD_PROBE_PLATFORM_OFF = (; tabs = false, appearance = false, settings = false,
                                    focus_cycling = false)

# A wrapper that adds a stop step, which writes the editor it is given.
const _BUILD_PROBE_STOPPED = Any[]
get_wrapper_layers(::Val{:build_probe_stop}) = (:screen => 9,)
function wrap_editor!(::Val{:build_probe_stop}, layer::Symbol, argument, parts::EditorParts)
    push!(parts.stop_steps, editor -> push!(_BUILD_PROBE_STOPPED, editor))
    parts
end

function _build_probe_steps()
    [(keyword, layer) for (keyword, layer, _) in _BUILD_PROBE_STEPS if keyword !== :started]
end

function test_build_editor()
@testset "build_editor" begin
    @testset "a backend type with a method of get_backend_output is loaded" begin
        loaded = collect_backend_types()
        @test BuildProbeBackend in loaded
        @test BuildProbeFirstBackend in loaded && BuildProbeSecondBackend in loaded
        @test get_backend_name(BuildProbeBackend) === :build_probe
    end

    @testset "the one backend of an output is made; two or none is an error" begin
        @test make_default_backend(:build_probe_single) isa BuildProbeBackend
        @test_throws "More than one loaded backend draws build_probe_pair: BuildProbeFirstBackend and BuildProbeSecondBackend" make_default_backend(:build_probe_pair)
        @test_throws "No loaded backend draws build_probe_none" make_default_backend(:build_probe_none)
    end

    @testset "make_editor applies no wrapper, and names its backend" begin
        empty!(_BUILD_PROBE_STEPS)
        _IS_BUILD_PROBE_DEFAULT_ON[] = true
        backend = BuildProbeBackend()
        editor = make_editor(BuildProbe(), BuildProbeProjection(); backend, devices = Device[])
        _IS_BUILD_PROBE_DEFAULT_ON[] = false
        @test editor.backend === backend && backend.starts == 1
        @test isempty(_BUILD_PROBE_STEPS)
    end

    @testset "the wrappers apply layer by layer, and in order inside a layer" begin
        empty!(_BUILD_PROBE_STEPS)
        editor = build_editor(BuildProbe(), BuildProbeProjection();
                              backend = BuildProbeBackend(), devices = Device[], _BUILD_PROBE_PLATFORM_OFF...,
                              build_probe_both = (; level = 2), build_probe_inner = true,
                              build_probe_first = true)
        @test _build_probe_steps() == [(:build_probe_first, :document),
                                       (:build_probe_inner, :document),
                                       (:build_probe_both, :document),
                                       (:build_probe_both, :screen)]
        # The argument is the value of the keyword.
        @test (:build_probe_both, :screen, (; level = 2)) in _BUILD_PROBE_STEPS
        # Each start step runs once the editor exists, with the editor.
        started = [(keyword, argument) for (tag, keyword, argument) in _BUILD_PROBE_STEPS
                   if tag === :started]
        @test length(started) == 4 && all(argument === editor for (_, argument) in started)
    end

    @testset "make_editor_parts applies the wrappers, and makes and starts no editor" begin
        empty!(_BUILD_PROBE_STEPS)
        parts = make_editor_parts(BuildProbe(), BuildProbeProjection();
                                  _BUILD_PROBE_PLATFORM_OFF..., build_probe_first = true)
        @test parts isa EditorParts && parts.backend === nothing
        @test _build_probe_steps() == [(:build_probe_first, :document)]
        @test length(parts.start_steps) == 1
        @test !any(tag === :started for (tag, _, _) in _BUILD_PROBE_STEPS)
    end

    @testset "a wrapper on by default joins unless its keyword is false" begin
        _IS_BUILD_PROBE_DEFAULT_ON[] = true
        try
            empty!(_BUILD_PROBE_STEPS)
            build_editor(BuildProbe(), BuildProbeProjection();
                         backend = BuildProbeBackend(), devices = Device[], _BUILD_PROBE_PLATFORM_OFF...)
            @test _build_probe_steps() == [(:build_probe_default, :container)]
            empty!(_BUILD_PROBE_STEPS)
            build_editor(BuildProbe(), BuildProbeProjection();
                         backend = BuildProbeBackend(), devices = Device[], _BUILD_PROBE_PLATFORM_OFF...,
                         build_probe_default = false)
            @test isempty(_build_probe_steps())
        finally
            _IS_BUILD_PROBE_DEFAULT_ON[] = false
        end
    end

    @testset "an unknown keyword is an error when it is on, and nothing when it is off" begin
        @test_throws "No loaded package declares the wrapper `build_probe_unknown`" build_editor(
            BuildProbe(), BuildProbeProjection(); backend = BuildProbeBackend(),
            devices = Device[], _BUILD_PROBE_PLATFORM_OFF..., build_probe_unknown = true)
        @test build_editor(BuildProbe(), BuildProbeProjection(); backend = BuildProbeBackend(),
                           devices = Device[], _BUILD_PROBE_PLATFORM_OFF..., build_probe_unknown = false) isa Editor
    end

    @testset "two wrappers that exclude each other are an error" begin
        @test_throws "`build_probe_excluding` and `build_probe_inner` can not be on together" build_editor(
            BuildProbe(), BuildProbeProjection(); backend = BuildProbeBackend(),
            devices = Device[], _BUILD_PROBE_PLATFORM_OFF..., build_probe_excluding = true, build_probe_inner = true)
    end

    @testset "a pinned task stays on its thread" begin
        # The pinning call is internal to Julia, so this test fails when a
        # release changes it.
        thread = last(Threads.threadpooltids(:default))
        seen = Int[]
        task = ProjecturedKernel.EditorModule._spawn_pinned(thread) do
            for _ in 1:50
                push!(seen, Threads.threadid())
                yield()
            end
        end
        wait(task)
        @test task.sticky
        @test all(==(thread), seen)
    end

    @testset "with wait = false, the editor is built and runs on a task of its own" begin
        backend = BuildProbeBackend()
        editor = run_editor!(BuildProbe(), BuildProbeProjection(); wait = false,
                             backend, devices = Device[], _BUILD_PROBE_PLATFORM_OFF...)
        task = editor.loop_task
        @test task isa Task && task !== current_task()
        @test backend.starts == 1
        post_operation!(editor, QuitEditorOperation())
        wait(task)
        @test istaskdone(task) && editor.loop_task === nothing
    end

    @testset "with wait = false, the function that builds the editor runs on the task of the loop" begin
        built_on = Ref{Any}(nothing)
        make = function ()
            built_on[] = current_task()
            build_editor(BuildProbe(), BuildProbeProjection(); backend = BuildProbeBackend(),
                         devices = Device[], _BUILD_PROBE_PLATFORM_OFF...)
        end
        editor = run_editor!(make; wait = false)
        task = editor.loop_task
        @test task isa Task && task !== current_task()
        @test built_on[] === task
        post_operation!(editor, QuitEditorOperation())
        wait(task)
        @test istaskdone(task)
        @test_throws ErrorException run_editor!(() -> error("no editor"); wait = false)
    end

    @testset "the stop steps of a wrapper run when the loop ends, and not before" begin
        empty!(_BUILD_PROBE_STOPPED)
        editor = run_editor!(BuildProbe(), BuildProbeProjection(); wait = false,
                             backend = BuildProbeBackend(), devices = Device[],
                             _BUILD_PROBE_PLATFORM_OFF..., build_probe_stop = true)
        @test length(editor.stop_steps) == 1
        @test isempty(_BUILD_PROBE_STOPPED)
        task = editor.loop_task
        post_operation!(editor, QuitEditorOperation())
        wait(task)
        @test length(_BUILD_PROBE_STOPPED) == 1 && only(_BUILD_PROBE_STOPPED) === editor
    end

    @testset "with no projection, the document's default projection is used" begin
        editor = build_editor(BuildProjectedProbe(); backend = BuildProbeBackend(),
                              devices = Device[], _BUILD_PROBE_PLATFORM_OFF...)
        @test editor.projection isa BuildProbeProjection
        # A package that draws any document, such as Natural, gives every
        # document a default, so the error needs a process without one.
        if hasmethod(make_document_projection, Tuple{BuildProbe})
            @test build_editor(BuildProbe(); backend = BuildProbeBackend(),
                               devices = Device[], _BUILD_PROBE_PLATFORM_OFF...) isa Editor
        else
            @test_throws "No projection is given for a document of type" build_editor(
                BuildProbe(); backend = BuildProbeBackend(), devices = Device[], _BUILD_PROBE_PLATFORM_OFF...)
        end
    end
end
end
