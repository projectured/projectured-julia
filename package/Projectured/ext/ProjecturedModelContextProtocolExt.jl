"""
    ProjecturedModelContextProtocolExt

The umbrella with `ModelContextProtocol` loaded: it loads `ProjecturedMCP` when the environment of the
session has it, and does nothing when it does not.
"""
module ProjecturedModelContextProtocolExt

import ProjecturedPlatform: load_installed_package!

__init__() = (load_installed_package!("ProjecturedMCP"); nothing)

end # module ProjecturedModelContextProtocolExt
