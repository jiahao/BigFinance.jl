@doc """
Construct trajectory matrix which is the lag of X with lag m
""" ->
function traj(X, m)
    n = length(X)
    n′ = n - m + 1
    D = hcat([X[i:end-n′+i] for i=1:n′]...)
end

@doc """
Do singular spectrum analysis

X: Raw series
m: Largest order of lag (integer)
"""->
function ssa(X, m)
    D = traj(X, m)
    svdfact(D')
end
