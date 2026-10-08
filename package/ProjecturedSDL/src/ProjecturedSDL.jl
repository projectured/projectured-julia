"""
    ProjecturedSDL

The SDL backend, a package of its own because it needs SimpleDirectMediaLayer
and SDL2. `using ProjecturedSDL` gives `SdlBackend`, `write_image` and the
offscreen renderer; the slice is `SdlModule`, in `source/backend/sdl/`.

The loop below binds every submodule of the kernel and the platform as a
`const`, so a source file here names a module exactly as the module names
itself.
"""
module ProjecturedSDL

using ProjecturedKernel
using ProjecturedPlatform

for _src in (ProjecturedKernel, ProjecturedPlatform)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
    end
end

include("../../../source/backend/sdl/SdlModule.jl")

# A person loads this package by name, so its names are exported here, with
# `write_image`, the generic function of the kernel that this backend extends.
using .SdlModule: SdlBackend, open_offscreen_renderer, close_offscreen_renderer, with_offscreen_zoom,
                  GraphicsCanvasToImageFile, write_offscreen_frames!,
                  make_offscreen_paint_state, render_offscreen_changes!,
                  write_offscreen_frame_with_overlay!, write_offscreen_picture_with_overlay!
export SdlBackend, write_image, open_offscreen_renderer, close_offscreen_renderer, with_offscreen_zoom,
       GraphicsCanvasToImageFile, write_offscreen_frames!, make_offscreen_paint_state,
       render_offscreen_changes!, write_offscreen_frame_with_overlay!,
       write_offscreen_picture_with_overlay!

# A person who names this package gets the names that most users call.
using ProjecturedPlatform.EssentialsModule
Core.eval(@__MODULE__, Expr(:export, filter(!=(:EssentialsModule), names(EssentialsModule))...))

# The first window of a session in SDL, offscreen, so that this image holds the
# code that draws a window.
using PrecompileTools: @setup_workload, @compile_workload
@setup_workload begin
    @compile_workload begin
        withenv("SDL_VIDEODRIVER" => "offscreen") do
            ProjecturedPlatform.run_display_workload(
                ProjecturedPlatform.WidgetModule.WidgetLabel("ProjecturEd"); backend = SdlBackend())
        end
    end
end

end # module ProjecturedSDL
