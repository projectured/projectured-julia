# Written by `ProjecturedBuilder`: a stand-in for the JLL package
# `alsa_plugins_jll` 1.2.13. It has the same name and uuid, and
# no library of its own.
module alsa_plugins_jll
# The libraries that are still needed from the real one.
import libsamplerate_jll
import Libiconv_jll
const artifact_dir = ""
const PATH_list = String[]
const LIBPATH_list = String[]
is_available() = false
end
