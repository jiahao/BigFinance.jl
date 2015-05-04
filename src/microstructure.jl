@doc """
Compute market shares over the entire data
Reference: Market Microstructure in practice, Ch. 1.
Monitoring the fragmentation at any scale, definition 1
""" ->
function marketshares(data)
    tpv = parse_tpv(data, false)
    marketids = int(sort!([Set(data[:, 17])...]))

    mktshares = Dict{Int,Float64}()
    for id in marketids
        idxs=data[:,17].==id
        mktshares[id] = sum(tpv[idxs,:price].*tpv[idxs,:vol])
    end
    shares = collect(values(mktshares))
    totalmktshare = sum(shares)

    DataFrames.DataFrame(
        id=marketids,
        market=map(BigFinance.decode_exchange, marketids),
        marketvalue=shares,
        marketshare=shares/totalmktshare
    )
end

@doc "Fragmentation Efficiency Index" ->
function fei(data)
    #Compute market entropy
    H = 0.0
    for m in marketshares(data)[:,:marketshare]
        m==0 && continue
        H -= m*log(m)
    end

    # The reference goes on to renormalize the entropy relative to the maximal
    # possible entropy. Basically divide by the log number of possible markets
    Hrenorm = H/log(67)
end
