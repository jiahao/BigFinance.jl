@doc """Garman-Klass volatility

Input:
    tpv: time-price-volume DataFrame
    blocklength: length of time interval to find volatility over. Default: Dates.Minute(15)
    interval: time between successive time intervals. Default: Dates.Minute(1))
    res: Time resolution to compute volatilities over. Default: Dates.Millisecond(25)
""" ->
function gkvol(tpv::DataFrame;
    blocklength=Dates.Minute(15), interval=Dates.Minute(1),
    res=Dates.Millisecond(25))

    const times=tpv[:, :time]
    tmin, tmax = extrema(times)
    starttimeblock = tmin
    endtimeblock = tmin+blocklength
    blocktimes = Dates.DateTime[]
    volatilities = Float64[]

    const k=2log(2)-1
    i1=1
    while starttimeblock < tmax
        t1 = sub(times, i1:size(times,1))
        i1 = findfirst(x->x>starttimeblock, t1)+i1-1
        t2 = sub(times, i1:size(times,1))
        i2 = findfirst(x->x≥endtimeblock, t2)+i1-1
        i2==i1-1 && (i2=size(tpv, 1))
        priceop = tpv[i1, :price]
        pricecl = tpv[i2, :price]
        pricelo, pricehi = extrema(tpv[i1:i2, :price])

        #Average price properly, taking into account that price is not
        #always reported in uniform time intervals
        timeblock = starttimeblock:res:endtimeblock
        lastprice = priceop
        pricesum = 0.0
        lasttime = starttimeblock
        for i=i1:i2
            thistime = tpv[i, :time]
            ntimes = int((thistime-lasttime)÷res)
            lasttime += ntimes*res
            pricesum += ntimes*lastprice
            lastprice = tpv[i, :price]
        end
        ntimes = int((endtimeblock-lasttime)÷res)
        lasttime += ntimes*res
        pricesum += ntimes*lastprice
        priceavg = pricesum/length(timeblock)

        VolGK = √(0.5*(pricehi-pricelo)^2 - k*(pricecl-priceop)^2)/priceavg

        starttimeblock += interval
        endtimeblock   += interval

        push!(blocktimes, starttimeblock)
        push!(volatilities, VolGK)
    end
    DataFrames.DataFrame(time = blocktimes, gk_volatility = volatilities)
end
