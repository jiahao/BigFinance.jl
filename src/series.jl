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

@doc """
Compute autocorrelation

Uses Wiener-Khinchin theorem and the FFT

Input:
    A series

Return:
    r: Autocorrelation function of the series
    τ: Decay time of r, determined by least-squares fit to simple exponential
    σ: Error in decay time of r, using 95% confidence interval
""" ->
function autocorr(series::AbstractVector)
    nr = length(series)
    r = rfft([series; zero(series)])
    r = r.*conj(r)
    r = real(irfft(r, 2nr))[1:nr]

    model(x, p) = p[1]*exp(-x/p[2])
    modelfit = curve_fit(model, 0:nr-1, r, [r[1], 1.0])
    errors = estimate_errors(modelfit, 0.95)

    r, modelfit.param[2], errors[2]
end



