@doc """
Generalized extreme Studentized deviate (GESD) test
This is the two-sided version

xin: Input data
k: maximal number of anomalies to find.
   Default: 1000 or the sqrt of the length of xin, whichever is smaller
α: Significance level. Default: 0.05
Returns index set of outliers and their associated Grubbs's statistic values
""" ->
function gesd(xin, k = min(1000, sqrt(length(xin))), α = 0.05)
    x = copy(xin)
    oldidx = collect(1:length(x))
    is = Int[]
    Gs = Float64[]
    Gth = 0.0
    for j=1:k
        N = length(x)
        x̄ = mean(x)
        s = std(x)

        #Grubbs's statistic
        G = maximum(abs(x - x̄))/s

        #Rejection threshold
        p = α/(2(N-j+1))
        t² = (quantile(TDist(N-2), p))^2
        Gth = (N-j)/√(N-j+1) * √(t²/(N-j-1+t²))
        G < Gth && break

        i = indmax(abs(x - x̄))
        deleteat!(x, i)
        push!(is, oldidx[i])
        deleteat!(oldidx, i)
        push!(Gs, G)
    end
    length(is) < k && warn("No k=$k outliers found at the α=$α level of significance; only $(length(is))")
    is, Gs, Gth
end

