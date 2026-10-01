"""
    ProjecturedVideo

Video recording, a package of its own because it needs FFMPEG, which no editor
or screenshot carries. `using ProjecturedVideo` gives `record_video` and
`VideoBackend`; the slice is `VideoModule`, in `source/backend/video/`.

The loop below binds every submodule of the kernel and the platform as a
`const`, so a source file here names a module exactly as the module names
itself.
"""
module ProjecturedVideo

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

include("../../../source/backend/video/VideoModule.jl")

# A person loads this package by name, so its names are exported here.
using .VideoModule: record_video, encode_frames_to_video!, VideoBackend
export record_video, encode_frames_to_video!, VideoBackend

end # module ProjecturedVideo
