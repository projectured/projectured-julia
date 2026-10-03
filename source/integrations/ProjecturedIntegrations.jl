using Projectured

Core.eval(@__MODULE__, Expr(:export, filter(!=(:Projectured), names(Projectured))...))
