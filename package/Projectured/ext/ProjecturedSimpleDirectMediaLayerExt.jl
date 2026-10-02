"""
    ProjecturedSimpleDirectMediaLayerExt

The umbrella with `SimpleDirectMediaLayer` loaded: it loads `ProjecturedSDL` when the environment of the
session has it, and does nothing when it does not.
"""
module ProjecturedSimpleDirectMediaLayerExt

import ProjecturedPlatform: load_installed_package!

__init__() = (load_installed_package!("ProjecturedSDL"); nothing)

end # module ProjecturedSimpleDirectMediaLayerExt
