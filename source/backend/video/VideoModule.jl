"""
    VideoModule

Video recording. `record_video` plays a document and its gestures into an
`.mp4` file, and `VideoBackend` plays a scripted timeline through the real
editor loop, so a recording carries every tool that the loop offers. Both draw
each frame with the offscreen renderer of `ProjecturedSDL` and encode the frames
with FFMPEG. The method of `record_video` extends the generic function of
`BackendModule`.
"""
module VideoModule

using ..KernelModule
using ..PlatformModule
using ProjecturedSDL
import FFMPEG

# Imported to extend: this module adds a method to each of these.
import ..BackendModule: record_video, initialize_backend!, quit_backend!,
       write_to_devices!, take_from_devices!, wait_for_input, get_pointer_position,
       get_display_size, configure_devices!
import ..EditorModule: get_frame_clock_time
import ..SettingsModule: apply_settings!, read_settings!

export record_video, encode_frames_to_video!

export VideoBackend

include("VideoRecording.jl")
include("VideoBackend.jl")

end # module VideoModule
