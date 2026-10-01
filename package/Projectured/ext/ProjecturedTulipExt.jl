"""
    ProjecturedTulipExt

The umbrella with `Tulip` loaded: it loads `ProjecturedTulip` when the environment of the
session has it, and does nothing when it does not.
"""
module ProjecturedTulipExt

import ProjecturedPlatform: load_installed_package!

__init__() = (load_installed_package!("ProjecturedTulip"); nothing)

end # module ProjecturedTulipExt
