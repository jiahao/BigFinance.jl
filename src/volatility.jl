@doc """
Compute realized volatility

Input:
    tpv: time-price-volume DataFrame

Keyword arguments:
    ftime: which field of the DataFrame contains the time. Default: :time
    fprice: which field of the DataFrame contains the price. Default: :logprice
    blocklength: length of time interval to find volatility over. Default: Dates.Minute(15)
    interval: time between successive time intervals. Default: Dates.Minute(1))
    res: Time resolution to compute volatilities over. Default: Dates.Millisecond(25)
""" ->
function rv(tpv::DataFrame;
    ftime::Symbol=:time, fprice::Symbol=:price,
    blocklength=Dates.Minute(15), interval=Dates.Minute(1),
    res=Dates.Millisecond(25))

    const times=tpv[:, ftime]
    tmin, tmax = extrema(times)
    starttimeblock = tmin
    endtimeblock = tmin+blocklength
    blocktimes = Dates.DateTime[]
    volatilities = Float64[]

    i1=1
    while starttimeblock < tmax
        t1 = sub(times, i1:size(times,1))
        i1 = findfirst(x->x>starttimeblock, t1)+i1-1
        t2 = sub(times, i1:size(times,1))
        i2 = findfirst(x->x≥endtimeblock, t2)+i1-1
        i2==i1-1 && (i2=size(tpv, 1))

        #Compute OHLC in this time interval
        pop = tpv[i1, fprice]
        pcl = tpv[i2, fprice]
        plo, phi = extrema(tpv[i1:i2, fprice])

        #Compute realized volatility over log-returns (log of prices)
        xs = zeros(i2-i1+1)
        r0 = tpv[i1, fprice]
        for i=1:i2-i1+1
            xs[i] = tpv[i+i1-1, fprice] - r0
        end
        thisvol = std(xs)

        #Average price properly, taking into account that price is not
        #always reported in uniform time intervals
        #priceavg = nuavg(tpv, fprice, ftime, res, starttimeblock:res:endtimeblock, i1:i2, pop)
        #volatility /= priceavg

        starttimeblock += interval
        endtimeblock   += interval

        push!(blocktimes, starttimeblock)
        push!(volatilities, thisvol)
    end
    DataFrames.DataFrame(time = blocktimes, rv = volatilities)
end

@doc """
Close-to-close volatility estimator

Takes C'C (previous close and current close) or OHLCC' (previous close)
C' defaults to O
""" ->
volcc{T<:Real}(o::T, h::T, l::T, c::T, c0::T=o) = volp(c0, c)
volcc{T<:Real}(c0::T, c::T) = c-c0

@doc """
Parkinson HL volatility estimator

Takes HL or OHLC (previous close)
""" ->
volp{T<:Real}(o::T, h::T, l::T, c::T) = volp(h, l)
volp{T<:Real}(h::T, l::T) = 0.60056120439322489743*(h-l)

@doc """
Rogers-Satchell OHLC volatility estimator

Takes OHLC
""" ->
function volrs{T<:Real}(o::T, h::T, l::T, c::T)
    √((h-c)*(h-o)+(l-c)*(l-o))
end

@doc """
Garman-Klass's σ̂₄ estimator - most commonly used today

Takes OHLC
""" ->
function volgk4{T<:Real}(o::T, h::T, l::T, c::T)
    const a₁=0.5
    #const a₂=0.0
    const a₃=-(2.0log(2.0)-1.0)
    √(a₁*(h-l)^2 + a₃*(c-o)^2)
end

@doc """
Garman-Klass's σ̂₅ estimator

Takes OHLC
""" ->
function volgk5{T<:Real}(o::T, h::T, l::T, c::T)
    #Constants recomputed from Mathematica
    const a₁= 0.51099508815722471341
    const a₂=-0.01887547791364507094
    const a₃=-0.38332075926803070979
    const a₁=0.5
    √(a₁*(h-l)^2 + a₂*((c-o)*(h-l) - 2(h-o)*(l-o)) + a₃*(c-o)^2)
end

@doc """
Yang-Zhang volatiity estimator

Takes OHLCC'
C' defaults to O
""" ->
function volyz{T<:Real}(o::T, h::T, l::T, c::T, c0::T=o)
    #Constants recomputed from Mathematica
    k = 0.34/(1+1)
    √((o-c0)^2 + k*(c-o)^2 + (1-k)*(h-c)*(h-o)+(l-c)*(l-o))
end

@doc """
Average a series y(x) that is sampled nonuniformly
with x discretized over multiples of dx
""" ->
function nuavg(df, fy, fx, dx, xblock, yblock, y0=0.0)
    ysum = 0.0
    x0 = xblock[1]
    for i in yblock
        x = df[i, ftime]
        ntimes = int((x-x0)÷res)
        x0 += ntimes*res
        ysum += ntimes*y0
        y0 = df[i, fprice]
    end
    ntimes = int((xblock[end]-x0)÷res)
    x0 += ntimes*res
    ysum += ntimes*y0
    ysum/length(xblock)
end

