"""
    AutoIntegrationsTest

The test package of `AutoIntegrations`: the automatic load of a package when its
triggers are loaded, the state that the environment of the user sets, and the
function that writes the state.
"""
module AutoIntegrationsTest

using Test
using TOML
import AutoIntegrations

include("../../../test/autointegrations/AutomaticLoadTest.jl")
include("../../../test/autointegrations/AutoIntegrationsSuite.jl")

end # module AutoIntegrationsTest
