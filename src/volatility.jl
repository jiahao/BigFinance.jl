@doc """Garman-Klass volatility

Input:

    times: the time stamps parsed into DateTimes
    data: the raw nxcore trade data
    blocklength: length of time interval to find volatility over. Default: Dates.Minute(15)
    interval: time between successive time intervals. Default: Dates.Minute(1))
    res: Time resolution to compute volatilies over. Default: Dates.Millisecond(25)
""" ->
function gkvol(times, data, blocklength=Dates.Minute(15), interval=Dates.Minute(1), res=Dates.Millisecond(25))
    tmin, tmax = extrema(times)
    starttimeblock = tmin
    endtimeblock = tmin+blocklength
    blocktimes = Any[]
    volatility = Float64[]
    while starttimeblock < tmax
        VolGK = 0.0
        pricehi = 0.0
        pricelo = Inf
        pricecl, timecl = 0.0, starttimeblock
        priceop, timeop = 0.0, endtimeblock
        theseprices = Float64[]
        thesetimes = Any[]
        for (i, t) in enumerate(times)
            starttimeblock ≤ t < endtimeblock || continue

            pricehi = max(pricehi, data[i, 31])
            pricelo = min(pricelo, data[i, 32])
            if abs(t-starttimeblock) < abs(timecl-starttimeblock)
                timeop = t
                priceop = data[i, 30]
            end
            if abs(t-endtimeblock) < abs(timecl-endtimeblock)
                timecl = t
                pricecl = data[i, 33]
            end

            push!(thesetimes, t)
            push!(theseprices, data[i, 29])
        end

        #Average price properly, taking into account that price is not
        #always reported in uniform time intervals
        lastprice = priceop
        pricesum = 0.0
        timeblock = starttimeblock:res:endtimeblock
        for t in timeblock
            idx = findfirst(x->x==t, times)
            idx==0 || (lastprice = prices[idx])
            pricesum += lastprice
        end
        priceavg = pricesum / length(timeblock)

        if length(prices)==0
            VolGK = 0.0
        else
            VolGK = √(0.5*(pricehi-pricelo)^2 - (2log(2)-1)*(pricecl-priceop)^2)/priceavg
        end

        starttimeblock += interval
        endtimeblock += interval

        push!(blocktimes, starttimeblock)
        push!(volatilities, VolGK)
    end
    DataFrame(time = blocktimes, gk_volatility = volatilities)
end
