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

@doc """
Compute signature plot

Compute integrated variance estimator as a function of the discretization step
""" ->
function signatureplot(returns)
    r = diff(returns)

    nr = length(r)
    nΔ = round(Int, √nr)
    intσs = zeros(nΔ)
    for Δ = 1:nΔ, i=1:Δ:nr
        intσs[Δ] += r[i]^2
    end

    xtimessec = (1:nΔ)*0.025
    xtimes = (1:nΔ)*Dates.Millisecond(25)

    model(x, p) = p[1]*x.^-p[2]
    modelfit = curve_fit(model, xtimessec, intσs, [1.0, 1.0])
    errors = estimate_errors(modelfit, 0.95)

    plot(Scale.x_log10, Scale.y_log10,
        Theme(default_color=color("black"), highlight_width=0px, default_point_size=0.5px),
        layer(x=xtimes, y=intσs, Geom.point),
        layer(x=xtimes, y=map(x->model(x, modelfit.param), xtimessec, Geom.line)),
        Guide.xlabel("Sampling time"),
        Guide.ylabel("Integrated variance"),
        Guide.title("Power law scaling (α = $(round(modelfit.param[2], 5)) ± $(round(errors[2], 5)))")
    )
end
