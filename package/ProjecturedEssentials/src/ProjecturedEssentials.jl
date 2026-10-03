"""
    ProjecturedEssentials

The few names of the kernel and the platform that most users call: show a value
in a window, open an editor on a document, make a document from text and draw
it, and make a view with no window. `Projectured`, each integration and each
backend re-export them, so the package that a user names gives them. A program
that needs more names loads `ProjecturedPlatform`.
"""
module ProjecturedEssentials

import ProjecturedKernel
import ProjecturedPlatform

include("../../../source/essentials/ProjecturedEssentials.jl")

end # module ProjecturedEssentials
