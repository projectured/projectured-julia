using ProjecturedPlatform.EssentialsModule

Core.eval(@__MODULE__, Expr(:export, filter(!=(:EssentialsModule), names(EssentialsModule))...))
