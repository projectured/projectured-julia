"""
    Projectured

The umbrella. It loads the kernel, the platform and AutoIntegrations, and
re-exports the names of `ProjecturedEssentials`, the few names that most users
call. AutoIntegrations then loads each installed package whose triggers are
loaded, as the environment of the user chooses: a domain, a backend or a model
adapter when `Projectured` is loaded, and an integration such as
`ProjecturedSDL` when the package that it joins is loaded too. A loaded package
keeps its names: a session that writes `JsonDocument` loads `ProjecturedJSON`.
"""
module Projectured

import AutoIntegrations
import ProjecturedEssentials

include("../../../source/projectured/Projectured.jl")

end # module Projectured
