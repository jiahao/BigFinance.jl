module BigFinance

using Color
using Compat
using Distributions
using Gadfly

if VERSION < v"0.4.0-"
    using Docile
end

#File I/O and decoding
export showtrade
include("readnanex.jl")

#Analytics
export traj, ssa
include("correlation.jl")

export gesd
include("gesd.jl")

#Visualizations
export svdexplorer
include("svdexplorer.jl")

end
