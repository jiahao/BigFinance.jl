using BigFinance

gc_disable()
data = readdlm("../data/SCHW20140616.txt")
gc_enable()

println("Record 1:")
println(showtrade(data[1,:]))

tpv = parse_tpv(data, true)

using HDF5, JLD
JLD.save("schw20140616.jld", "tpv", tpv)

