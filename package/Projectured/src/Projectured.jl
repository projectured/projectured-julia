"""
    Projectured

The umbrella. It depends on the kernel and the platform, and re-exports their
public API as one flat namespace (`using Projectured`), with their submodules as
`Projectured.XxxModule` for qualified access.

After the load of the session it loads every ProjecturEd package that the user
installed: the domains, the console and PDF backends and the model adapters. Its
extensions load an integration with another package, such as `ProjecturedSDL`,
when that package is loaded too. A loaded package keeps its names: a session that
writes `JsonDocument` loads `ProjecturedJSON`. The flat namespace of every package
is `ProjecturedAll`, a development package that the registry does not hold.
"""
module Projectured

import ProjecturedKernel
import ProjecturedPlatform

include("../../../source/projectured/Projectured.jl")

end # module Projectured
