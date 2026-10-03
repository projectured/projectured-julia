using ProjecturedEssentials

Core.eval(@__MODULE__, Expr(:export, filter(!=(:ProjecturedEssentials),
                                            names(ProjecturedEssentials))...))
