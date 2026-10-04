"""
    Projectured

The umbrella. It loads the kernel, the platform and AutoIntegration, and
re-exports the names of `ProjecturedPlatform.EssentialsModule`, the few names
that most users call. AutoIntegration then loads each installed package whose triggers are
loaded, as the environment of the user chooses: a domain, a backend or a model
adapter when `Projectured` is loaded, and an integration such as
`ProjecturedSDL` when the package that it joins is loaded too. A loaded package
keeps its names: a session that writes `JsonDocument` loads `ProjecturedJSON`.
"""
module Projectured

import AutoIntegration
import ProjecturedPlatform

include("../../../source/projectured/Projectured.jl")

end # module Projectured
