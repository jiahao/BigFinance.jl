module BigFinance

using Color
using Compat
using DataFrames
using Distributions
using Gadfly
using LsqFit

if VERSION < v"0.4.0-"
    using Dates
    using Docile
end

#File I/O and decoding
export readnxtrade, parse_tpv, showtrade
include("readnanex.jl")

#Analytics
export traj, ssa
include("correlation.jl")
export logreturns, simplereturns, autocorr
include("series.jl")
export gkvol
include("volatility.jl")
export signatureplot, fei, marketshares
include("microstructure.jl")
export gesd
include("gesd.jl")

#Visualizations
export svdexplorer
include("svdexplorer.jl")

end
