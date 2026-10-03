"""
    ProjecturedIntegrations

Every integration of ProjecturEd at once. It installs each integration and the
package that each one joins, and re-exports the names of `Projectured`. A
package extension loads an integration when the package that it joins is
loaded, such as `ProjecturedSDL` with SimpleDirectMediaLayer. So it loads an
integration that the environment of the user sets to "manual" for
AutoIntegrations too.
"""
module ProjecturedIntegrations

import Projectured

include("../../../source/integrations/ProjecturedIntegrations.jl")

end # module ProjecturedIntegrations
