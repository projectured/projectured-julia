"""
    ProjecturedODBCExt

The umbrella with `ODBC` loaded: it loads `ProjecturedODBC` when the environment of the
session has it, and does nothing when it does not.
"""
module ProjecturedODBCExt

import ProjecturedPlatform: load_installed_package!

__init__() = (load_installed_package!("ProjecturedODBC"); nothing)

end # module ProjecturedODBCExt
