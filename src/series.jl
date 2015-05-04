@doc """
Compute log returns from a DataFrame with a price field
""" ->
function logreturns(tpv::DataFrame)
    const P0 = tpv[1, :price]
    nP = size(tpv, 1)
    R = zeros(nP)
    const R0 = log(P0)
    for i=2:nP
        R[i] = log(tpv[i, :price]) - R0
    end
    DataFrame(logreturn=R)
end

@doc """
Compute simple returns from a DataFrame with a price field
""" ->
function simplereturns(tpv::DataFrame)
    R = zeros(nP)
    for i=2:nP
        R[i] = tpv[i, :price]/tpv[i-1, :price] - 1
    end
    DataFrame(simplereturn=R)
end

