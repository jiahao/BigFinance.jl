@doc """Garman-Klass volatility

Input:

    times: the time stamps parsed into DateTimes
    data: the raw nxcore trade data
    tpv: time-price-volume DataFrame
    blocklength: length of time interval to find volatility over. Default: Dates.Minute(15)
    interval: time between successive time intervals. Default: Dates.Minute(1))
    res: Time resolution to compute volatilies over. Default: Dates.Millisecond(25)
""" ->
function gkvol(data,  times = parse_times(data),
    tpv::DataFrames.DataFrame=parse_tsv(data, true),
    blocklength=Dates.Minute(15), interval=Dates.Minute(1),
    res=Dates.Millisecond(25))

    tmin, tmax = extrema(times)
    starttimeblock = tmin
    endtimeblock = tmin+blocklength
    blocktimes = Any[]
    volatilities = Float64[]

    const k=2log(2)-1
    while starttimeblock < tmax
        VolGK = 0.0
        pricehi = 0.0
        pricelo = Inf
        pricecl, timecl = 0.0, starttimeblock
        priceop, timeop = 0.0, endtimeblock
        for (i, t) in enumerate(times)
            starttimeblock ≤ t < endtimeblock || continue

            pricehi = max(pricehi, data[i, 31])
            data[i, 32]==0 || (pricelo = min(pricelo, data[i, 32])) #Guard against bad data with price 0
            if abs(t-starttimeblock) < abs(timecl-starttimeblock)
                timeop = t
                priceop = data[i, 30]
            end
            if abs(t-endtimeblock) < abs(timecl-endtimeblock)
                timecl = t
                pricecl = data[i, 33]
            end
        end

        #Average price properly, taking into account that price is not
        #always reported in uniform time intervals
        timeblock = starttimeblock:res:endtimeblock
        pricesblock = tpv[starttimeblock .≤ tpv[:, :time] .< endtimeblock, :]
        lastprice = priceop
        pricesum = 0.0
        tidx = 1
        for i=1:size(pricesblock, 1)
            thistime = pricesblock[i, :time]
            while timeblock[tidx] < thistime
                tidx += 1
                pricesum += lastprice
            end
            lastprice = pricesblock[i, :price]
        end
        while timeblock[tidx] < endtimeblock
            tidx += 1
            pricesum += lastprice
        end
        priceavg = pricesum / length(timeblock)

        if !isfinite(pricelo)
            VolGK = 0.0
        else
            VolGK = √(0.5*(pricehi-pricelo)^2 - k*(pricecl-priceop)^2)/priceavg
        end

        starttimeblock += interval
        endtimeblock += interval

        push!(blocktimes, starttimeblock)
        push!(volatilities, VolGK)
    end
    DataFrames.DataFrame(time = blocktimes, gk_volatility = volatilities)
end

