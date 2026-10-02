"""
    ProjecturedDataFramesExt

The umbrella with `DataFrames` loaded: it loads `ProjecturedDataFrames` when the environment of the
session has it, and does nothing when it does not.
"""
module ProjecturedDataFramesExt

import ProjecturedPlatform: load_installed_package!

__init__() = (load_installed_package!("ProjecturedDataFrames"); nothing)

end # module ProjecturedDataFramesExt
