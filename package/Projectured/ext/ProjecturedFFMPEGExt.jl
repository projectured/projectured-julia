"""
    ProjecturedFFMPEGExt

The umbrella with `FFMPEG` loaded: it loads `ProjecturedVideo` when the environment of the
session has it, and does nothing when it does not.
"""
module ProjecturedFFMPEGExt

import ProjecturedPlatform: load_installed_package!

__init__() = (load_installed_package!("ProjecturedVideo"); nothing)

end # module ProjecturedFFMPEGExt
