#Read in data from Nanex Research which has been converted into TSV format.

using DataFrames

#The data dictionary is assumed to be the following:
const fieldnames = [
"System Date",
"System Time",
"System Time Zone",
"DST Indicator",
"Number of Days Since 1883-01-01",
"Day of Week",
"Day of Year",
"Session Date",
"Session DST Indicator",
"Session Number of Days Since 1883-01-01",
"Session Day of Week",
"Session Day of Year",
"Exchange Timestamp",
"Exchange Timestamp Time Zone",
"Symbol",
"Listed Exchange Index",
"Reporting Exchange Index",
"Session ID",
"Trade Price Flags",
"Trade Condition Flag",
"Trade Condition Index",
"Trade Volume Type",
"Trade BATE Code",
"Trade Size",
"Trade Exchange Sequence",
"Trade Records Back",
"Trade Total Volume",
"Trade Tick Volume",
"Trade Price",
"Trade Price (Open)",
"Trade Price (High)",
"Trade Price (Low)",
"Trade Price (Last)",
"Trade Tick",
"Trade Price Net Change",
"Analysis Filter Threshold",
"Analysis Filtered Bool",
"Analysis Filter Level",
"Analysis SigHiLo Type",
"Analysis SigHiLo Seconds",
"Quote Match Distance (RGN)",
"Quote Match Distance (BBO)",
"Quote Match Flags (BBO)",
"Quote Match Flag (RGN)",
"Quote Match Type (BBO)",
"Quote Match Type (RGN)",
];

##########################################################
# High level function for reading in data as a DataFrame #
##########################################################

@doc """
Read NxCore trade data from TSV file
""" ->
function readnxtrade(filename::String)
    gc_disable()
    #Read in raw TSV
    df=readtable(filename, separator='\t', header = false,
        eltypes=[
            UTF8String, UTF8String, Int, Int, Int, Int, Int, #7
            UTF8String, Int, Int, Int, Int, UTF8String, Int, #14
            UTF8String, Int, Int, Int, Int, Int, #20
            Int, Int, UTF8String , Int, Int, #25
            Int, Int, Int, Float64, Float64, #30
            Float64, Float64, Float64, Float64, Float64, #35
            Float64, Int, Int, Int, Int, #40
            Int, Int, Int, Int, Int, #45
            Int
        ], names = [
            :systimed, :systimet, :systimetz, :systimedst, :systimedo, #5
            :systimedow, :systimedoy,
            :sesstimed, :sesstimedst, :sesstimedo, #10
            :sesstimedow, :sesstimedoy, :exgtimet, :exgtimetz, :symbol, #15
            :listexgidx, :repexgidx, :sessid, :tpflag, :tcflag, #20
            :tcidx, :tvoltype, :tbate, :tsize, :texgseq, #25
            :trecsback, :ttotalvol, :ttickvol, :price, :popen, #30
            :phi, :plo, :plast, :ttick, :pchange, #35
            :aft, :af, :afl, :ast, :ass, #40
            :qmdrgn, :qmdbbo, :qmfbbo, :qmfrbn, :qmtbbo, #45
            :qmtrgn #46
        ])

    #Add systime column for properly parsed time
    df[:systime]=BigFinance.parse_times(df, :systimed, :systimet)

    #Delete useless fields
    for field in [:systimed, :systimet, :systimetz, :systimedst, :systimedo, #5
        :systimedow, :systimedoy,
        :sesstimed, :sesstimedst, :sesstimedo, #10
        :sesstimedow, :sesstimedoy, :exgtimet, :exgtimetz,
        :popen, #30
        :phi, :plo, :plast, :ttick, :pchange, #35
        :aft, :af, :afl, :ast, :ass, #40
        :qmdrgn, :qmdbbo, :qmfbbo, :qmfrbn, :qmtbbo, #45
        :qmtrgn #46
    ]
        try delete!(df, field) end
    end
    gc_enable()

    #Return DataFrame sorted by exchange sequence ID
    sort!(df, cols=:texgseq)
end


#############################################
# Low level functions for parsing raw data  #
# Works on input data read in using readdlm #
#############################################

@doc """Convert datetime data to Julia DateTime

#TODO handle time zone and DST
""" ->
function parse_times(data, datefield=1, timefield=2)
    times = Array(Dates.DateTime, size(data, 1))
    #isdefined(:dateformat) || (const dateformat = "yyyy-mm-ddHH:MM:SS.sss")
    @inbounds for i in 1:size(data, 1)
        #times[i] = Dates.DateTime(string(df[i, datefield], df[i, timefield]), dateformat)
        d = convert(ASCIIString, data[i, datefield])
        t = convert(ASCIIString, data[i, timefield])
        times[i] = Dates.DateTime(
            parse(Int, d[1:4]), parse(Int, d[6:7]), parse(Int, d[9:10]),
            parse(Int, t[1:2]), parse(Int, t[4:5]), parse(Int, t[7:8]), parse(Int, t[10:12])
        )
   end
    times
end

@doc """
Extract out time, price and volume series from raw data

Missing entries are not included

If the second argument is true, uniqfy data by time stamp. The price is
overwritten by the weighted average and the tick volume is summed.
""" ->
#parse_tpv(data; uniquetime::Bool=true, filtertrades::Bool=true) = parse_tpv(parse_times(data), sub(data, :, 29), int(sub(data, :, 28)), sub(data, :, 22), uniquetime=uniquetime, filtertrades=filtertrades)
#parse_tpv(data::DataFrame; uniquetime::Bool=true, filtertrades::Bool=true) = parse_tpv(data[:systime], data[:price], data[:ttickvol], data[:tvoltype], data[:tcidx], uniquetime=uniquetime, filtertrades=filtertrades)

#function parse_tpv(times, prices, vols, voltypes, tcidx;
function parse_tpv(data::DataFrame;
        uniquetime=true, filtertrades=true, dosort=false)

    times =    copy(data[:systime].data)
    prices=    copy(data[:price].data)
    vols  =    copy(data[:ttickvol].data)
    voltypes = copy(data[:tvoltype].data)
    tcidx =    copy(data[:tcidx].data)

    if dosort
        sp = sortperm(times)

        voltypes = voltypes[sp]
        vols = vols[sp]
        tcidx = tcidx[sp]
        times = times[sp]
        prices = prices[sp]
    end

    #Diff volumes to get volume size of individual transactions
    #Must handle the possibility that there are different volume types
    n = length(times)
    incrementalvols = zeros(Int, n)
    lastvol = 0
    deleteme=Int[]
    for i=1:n
        if filtertrades && !(tcidx[i]==0 || tcidx[i]==95 || tcidx[i]==115)
            push!(deleteme, i)
            continue
        end

        thisvol = vols[i]
        if voltypes[i] == 0 #Incremental volume, need to diff
            incrementalvols[i] = thisvol - lastvol
            lastvol = thisvol
        elseif voltypes[i]==1 #Non-incremental volume, ignore
            incrementalvols[i] = 0
        elseif voltypes[i] == 2 #Total volume, subtract from previous
            incrementalvols[i] = thisvol - lastvol
            lastvol = thisvol
        else
            error("Type 3 volume type not implemented")
        end
    end

    for idx in sort!(deleteme, rev=true)
        deleteat!(times, idx)
        deleteat!(prices, idx)
        deleteat!(incrementalvols, idx)
    end
    n = length(times)

    if uniquetime
        #Account for the possibility of repeated times
        deleteme = Int[]
        for i=n:-1:2
            if times[i] == times[i-1]
                v2, v1 = incrementalvols[i], incrementalvols[i-1]
                v=v1+v2
                if v>0
                   prices[i-1] = (v1*prices[i-1] + v2*prices[i])/v
                else
                   prices[i-1] = (prices[i-1] + prices[i])/2
                end
                incrementalvols[i-1] += v2
                push!(deleteme, i)
            end
        end

        for idx in deleteme
            deleteat!(times, idx)
            deleteat!(prices, idx)
            deleteat!(incrementalvols, idx)
        end

        #all(incrementalvols .≥ 0) || warn("negative volumes present")
    end

    DataFrame(time=times, price=prices, vol=incrementalvols)
end

##########################################################
# Low level functions for decoding special nxCore fields #
##########################################################

function decode_symbol(symbol::@compat AbstractString)
    msg = String[]
    #Find prefix
    #http://nxcoreapi.com/doc/info_SymbolPrefixes.html
    if     startswith(symbol, "b") push!(msg, "Bond")
    elseif startswith(symbol, "c") push!(msg, "Currency")
    elseif startswith(symbol, "e") push!(msg, "Equity")
    elseif startswith(symbol, "f") push!(msg, "Future")
    elseif startswith(symbol, "i") push!(msg, "Index")
    elseif startswith(symbol, "m") push!(msg, "Mutual Fund")
    elseif startswith(symbol, "o") push!(msg, "Equity or Index Option Root")
    elseif startswith(symbol, "p") push!(msg, "Future Option")
    elseif startswith(symbol, "r") push!(msg, "Futures/FuturesOption Symbol Root")
    elseif startswith(symbol, "s") push!(msg, "Single Stock Futures")
    elseif startswith(symbol, "z") push!(msg, "Spread")
    else throw(ValueError("Symbol $symbol has no known prefix"))
    end
    msg[1] = string("Type: ", msg[1])

    sym = symbol[2:end]
    sym = split(sym, ",")[1] #WTF is field 2??!!
    #Find suffixes
    #http://nxcoreapi.com/doc/info_SymbolSuffixes.html
    while true
        if endswith(sym, ".PR")
            push!(msg, "Preferred Stock")
            sym = sym[1:end-3]
        elseif endswith(sym, ".A")
            push!(msg, "Equity Class or Series 'A' to 'Z'")
            sym = sym[1:end-2]
        elseif endswith(sym, ".WS")
            push!(msg, "Warrants")
            sym = sym[1:end-3]
        elseif endswith(sym, ".WWS")
            push!(msg, "With Warrants")
            sym = sym[1:end-4]
        elseif endswith(sym, "/WI")
            push!(msg, "When Issued")
            sym = sym[1:end-3]
        elseif endswith(sym, "/WD")
            push!(msg, "When Distributed")
            sym = sym[1:end-3]
        elseif endswith(sym, "/CL")
            push!(msg, "Called")
            sym = sym[1:end-3]
        elseif endswith(sym, ".UN")
            push!(msg, "Units")
            sym = sym[1:end-3]
        elseif endswith(sym, ".ID")
            push!(msg, "Index")
            sym = sym[1:end-3]
        elseif endswith(sym, ".IV")
            push!(msg, "Intraday Net Asset Value/Share")
            sym = sym[1:end-3]
        elseif endswith(sym, ".NV")
            push!(msg, "Net Asset Value/Share previous close")
            sym = sym[1:end-3]
        elseif endswith(sym, ".MN")
            push!(msg, "Mini")
            sym = sym[1:end-3]
        elseif endswith(sym, ".SM")
            push!(msg, "Mini Settlement")
            sym = sym[1:end-3]
        elseif endswith(sym, ".PO")
            push!(msg, "Percent Open")
            sym = sym[1:end-3]
        elseif endswith(sym, ".SO")
            push!(msg, "Shares Outstanding (x1000)")
            sym = sym[1:end-3]
        elseif endswith(sym, ".SV")
            push!(msg, "Settlement Value")
            sym = sym[1:end-3]
        elseif endswith(sym, ".TC")
            push!(msg, "Total cash per creation unit (thousands)")
            sym = sym[1:end-3]
        elseif endswith(sym, ".DP")
            push!(msg, "Dividend portion to go ex-distribution")
            sym = sym[1:end-3]
        elseif endswith(sym, ".DV")
            push!(msg, "Accumulative dividend")
            sym = sym[1:end-3]
        elseif endswith(sym, ".EU")
            push!(msg, "Estimated Creation Unit Cash Amount")
            sym = sym[1:end-3]
        elseif endswith(sym, ".F.N")
            push!(msg, "Foreign News")
            sym = sym[1:end-4]
        elseif endswith(sym, ".SD")
            push!(msg, "Stamped")
            sym = sym[1:end-3]
        elseif endswith(sym, ".SP")
            push!(msg, "Special")
            sym = sym[1:end-3]
        elseif endswith(sym, ".VR")
            push!(msg, "Variable Common Rights")
            sym = sym[1:end-3]
        elseif endswith(sym, ".SV")
            push!(msg, "Subordinate Voting")
            sym = sym[1:end-3]
        elseif endswith(sym, ".RV")
            push!(msg, "Restricted Voting")
            sym = sym[1:end-3]
        elseif endswith(sym, ".LV")
            push!(msg, "Limited Voting")
            sym = sym[1:end-3]
        elseif endswith(sym, ".MV")
            push!(msg, "Multiple Voting")
            sym = sym[1:end-3]
        elseif endswith(sym, ".NV")
            push!(msg, "Non-Voting")
            sym = sym[1:end-3]
        elseif endswith(sym, ".NT")
            push!(msg, "Non-convertible Note")
            sym = sym[1:end-3]
        elseif endswith(sym, ".USD")
            push!(msg, "Canadian Listed trading in U.S. Dollars")
            sym = sym[1:end-4]
        elseif endswith(sym, ".CV")
            push!(msg, "Convertible")
            sym = sym[1:end-3]
        elseif endswith(sym, "/CT")
            push!(msg, "Certificate")
            sym = sym[1:end-3]
        elseif endswith(sym, "/CVR")
            push!(msg, "Contingent Value Rights")
            sym = sym[1:end-4]
        elseif endswith(sym, "/EC")
            push!(msg, "Emerging Company")
            sym = sym[1:end-3]
        elseif endswith(sym, "/PP")
            push!(msg, "Part Paid")
            sym = sym[1:end-3]
        elseif endswith(sym, "/PTCL")
            push!(msg, "Part Called")
            sym = sym[1:end-5]
        elseif endswith(sym, "/SC")
            push!(msg, "Small Corporate Offering Registration")
            sym = sym[1:end-3]
        elseif endswith(sym, "/TEST")
            push!(msg, "Test Symbol")
            sym = sym[1:end-5]
        elseif endswith(sym, "/TT")
            push!(msg, "Tier II Symbol")
            sym = sym[1:end-3]
        elseif endswith(sym, "/XD")
            push!(msg, "Ex-Dividend")
            sym = sym[1:end-3]
        elseif endswith(sym, "/XS")
            push!(msg, "Ex-Distribution")
            sym = sym[1:end-3]
        elseif endswith(sym, "/XI")
            push!(msg, "Ex-Interest")
            sym = sym[1:end-3]
        elseif endswith(sym, "/XW")
            push!(msg, "Ex-Warrants")
            sym = sym[1:end-3]
        elseif endswith(sym, "/XR")
            push!(msg, "Ex-Rights")
            sym = sym[1:end-3]
        elseif endswith(sym, "/REG")
            push!(msg, "Regular")
            sym = sym[1:end-3]
        else #No recognized suffixes
            break
        end
    end
    insert!(msg, 1, "Symbol: $sym")
    join(msg, "\n")
end

function decode_exchange(exchangeid::Integer)
    #http://nxcoreapi.com/doc/table_NxST_EXCHANGE.html
    const NQEX	= 1	# Nasdaq Exchange
    const NQAD	= 2	# Nasdaq Alternative Display Facility
    const NYSE	= 3	# New York Stock Exchange
    const AMEX	= 4	# American Stock Exchange
    const CBOE	= 5	# Chicago Board Options Exchange
    const ISEX	= 6	# International Securities Exchange
    const PACF	= 7	# NYSE ARCA (Pacific)
    const CINC	= 8	# National Stock Exchange (Cincinnati)
    const PHIL	= 9	# Philidelphia Stock Exchange
    const OPRA	= 10	# Options Pricing Reporting Authority
    const BOST	= 11	# Boston Stock/Options Exchange
    const NQNM	= 12	# Nasdaq Global+Select Market (NMS)
    const NQSC	= 13	# Nasdaq Capital Market (SmallCap)
    const NQBB	= 14	# Nasdaq Bulletin Board
    const NQPK	= 15	# Nasdaq OTC
    const NQAG	= 16	# Nasdaq Aggregate Quote
    const CHIC	= 17	# Chicago Stock Exchange
    const TSE	= 18	# Toronto Stock Exchange
    const CDNX	= 19	# Canadian Venture Exchange
    const CME	= 20	# Chicago Mercantile Exchange
    const NYBT	= 21	# New York Board of Trade
    const NYBA	= 22	# New York Board of Trade Alternate Ticker
    const COMX	= 23	# COMEX (division of NYMEX)
    const CBOT	= 24	# Chicago Board of Trade
    const NYMX	= 25	# New York Mercantile Exchange
    const KCBT	= 26	# Kansas City Board of Trade
    const MGEX	= 27	# Minneapolis Grain Exchange
    const WCE	= 28	# Winnipeg Commodity Exchange
    const ONEC	= 29	# OneChicago Exchange
    const DOWJ	= 30	# Dow Jones Indicies
    const GEMI	= 31	# ISE Gemini
    const SIMX	= 32	# Singapore International Monetary Exchange
    const FTSE	= 33	# London Stock Exchange
    const EURX	= 34	# Eurex
    const ENXT	= 35	# EuroNext
    const DTN	= 36	# Data Transmission Network
    const LMT	= 37	# London Metals Exchange Matched Trades
    const LME	= 38	# London Metals Exchange
    const IPEX	= 39	# Intercontinental Exchange (IPE)
    const MX	= 40	# Montreal Stock Exchange
    const WSE	= 41	# Winnipeg Stock Exchange
    const C2	= 42	# CBOE C2 Option Exchange
    const MIAX	= 43	# Miami Exchange
    const CLRP	= 44	# NYMEX Clearport
    const BARK	= 45	# Barclays
    const TEN4	= 46	# TenFore
    const NQBX	= 47	# OMXBX
    const HOTS	= 48	# HotSpot Eurex US
    const EUUS	= 49	# Eurex US
    const EUEU	= 50	# Eurex EU
    const ENCM	= 51	# Euronext Commodities
    const ENID	= 52	# Euronext Index Derivatives
    const ENIR	= 53	# Euronext Interest Rates
    const CFE	= 54	# CBOE Futures Exchange
    const PBOT	= 55	# Philadelphia Board of Trade
    const HWTB	= 56	# Hannover WTB Exchange
    const NQNX	= 57	# NSX Trade Reporting Facility
    const BTRF	= 58	# BSE Trade Reporting Facility
    const NTRF	= 59	# NYSE Trade Reporting Facility
    const BATS	= 60	# BATS Trading
    const NYLF	= 61	# NYSE LIFFE metals contractsNYSE LIFFE metals contracts
    const PINK	= 62	# Pink Sheets
    const BATY	= 63	# BATS Trading
    const EDGE	= 64	# Direct Edge
    const EDGX	= 65	# Direct Edge
    const RUSL	= 66	# Russell Indexes
    const ISLD	= 67	# Island ECN

    if exchangeid == NQEX
        return "NQEX Nasdaq Exchange"
    elseif exchangeid == NQAD
        return "NQAD Nasdaq Alternative Display Facility"
    elseif exchangeid == NYSE
        return "NYSE New York Stock Exchange"
    elseif exchangeid == AMEX
        return "AMEX American Stock Exchange"
    elseif exchangeid == CBOE
        return "CBOE Chicago Board Options Exchange"
    elseif exchangeid == ISEX
        return "ISEX International Securities Exchange"
    elseif exchangeid == PACF
        return "PACF NYSE ARCA (Pacific)"
    elseif exchangeid == CINC
        return "CINC National Stock Exchange (Cincinnati)"
    elseif exchangeid == PHIL
        return "PHIL Philidelphia Stock Exchange"
    elseif exchangeid == OPRA
        return "OPRA Options Pricing Reporting Authority"
    elseif exchangeid == BOST
        return "BOST Boston Stock/Options Exchange"
    elseif exchangeid == NQNM
        return "NQNM Nasdaq Global+Select Market (NMS)"
    elseif exchangeid == NQSC
        return "NQSC Nasdaq Capital Market (SmallCap)"
    elseif exchangeid == NQBB
        return "NQBB Nasdaq Bulletin Board"
    elseif exchangeid == NQPK
        return "NQPK Nasdaq OTC"
    elseif exchangeid == NQAG
        return "NQAG Nasdaq Aggregate Quote"
    elseif exchangeid == CHIC
        return "CHIC Chicago Stock Exchange"
    elseif exchangeid == TSE
        return "TSE Toronto Stock Exchange"
    elseif exchangeid == CDNX
        return "CDNX Canadian Venture Exchange"
    elseif exchangeid == CME
        return "CME Chicago Mercantile Exchange"
    elseif exchangeid == NYBT
        return "NYBT New York Board of Trade"
    elseif exchangeid == NYBA
        return "NYBA New York Board of Trade Alternate Ticker"
    elseif exchangeid == COMX
        return "COMX COMEX (division of NYMEX)"
    elseif exchangeid == CBOT
        return "CBOT Chicago Board of Trade"
    elseif exchangeid == NYMX
        return "NYMX New York Mercantile Exchange"
    elseif exchangeid == KCBT
        return "KCBT Kansas City Board of Trade"
    elseif exchangeid == MGEX
        return "MGEX Minneapolis Grain Exchange"
    elseif exchangeid == WCE
        return "WCE Winnipeg Commodity Exchange"
    elseif exchangeid == ONEC
        return "ONEC OneChicago Exchange"
    elseif exchangeid == DOWJ
        return "DOWJ Dow Jones Indicies"
    elseif exchangeid == GEMI
        return "GEMI ISE Gemini"
    elseif exchangeid == SIMX
        return "SIMX Singapore International Monetary Exchange"
    elseif exchangeid == FTSE
        return "FTSE London Stock Exchange"
    elseif exchangeid == EURX
        return "EURX Eurex"
    elseif exchangeid == ENXT
        return "ENXT EuroNext"
    elseif exchangeid == DTN
        return "DTN Data Transmission Network"
    elseif exchangeid == LMT
        return "LMT London Metals Exchange Matched Trades"
    elseif exchangeid == LME
        return "LME London Metals Exchange"
    elseif exchangeid == IPEX
        return "IPEX Intercontinental Exchange (IPE)"
    elseif exchangeid == MX
        return "MX Montreal Stock Exchange"
    elseif exchangeid == WSE
        return "WSE Winnipeg Stock Exchange"
    elseif exchangeid == C2
        return "C2 CBOE C2 Option Exchange"
    elseif exchangeid == MIAX
        return "MIAX Miami Exchange"
    elseif exchangeid == CLRP
        return "CLRP NYMEX Clearport"
    elseif exchangeid == BARK
        return "BARK Barclays"
    elseif exchangeid == TEN4
        return "TEN4 TenFore"
    elseif exchangeid == NQBX
        return "NQBX OMXBX"
    elseif exchangeid == HOTS
        return "HOTS HotSpot Eurex US"
    elseif exchangeid == EUUS
        return "EUUS Eurex US"
    elseif exchangeid == EUEU
        return "EUEU Eurex EU"
    elseif exchangeid == ENCM
        return "ENCM Euronext Commodities"
    elseif exchangeid == ENID
        return "ENID Euronext Index Derivatives"
    elseif exchangeid == ENIR
        return "ENIR Euronext Interest Rates"
    elseif exchangeid == CFE
        return "CFE CBOE Futures Exchange"
    elseif exchangeid == PBOT
        return "PBOT Philadelphia Board of Trade"
    elseif exchangeid == HWTB
        return "HWTB Hannover WTB Exchange"
    elseif exchangeid == NQNX
        return "NQNX NSX Trade Reporting Facility"
    elseif exchangeid == BTRF
        return "BTRF BSE Trade Reporting Facility"
    elseif exchangeid == NTRF
        return "NTRF NYSE Trade Reporting Facility"
    elseif exchangeid == BATS
        return "BATS BATS Trading"
    elseif exchangeid == NYLF
        return "NYLF NYSE LIFFE metals contracts"
    elseif exchangeid == PINK
        return "PINK Pink Sheets"
    elseif exchangeid == BATY
        return "BATY BATS Trading"
    elseif exchangeid == EDGE
        return "EDGE Direct Edge"
    elseif exchangeid == EDGX
        return "EDGX Direct Edge"
    elseif exchangeid == RUSL
        return "RUSL Russell Indexes"
    elseif exchangeid == ISLD
        return "ISLD Island ECN"
    else
        throw(ValueError("Invalid exchange ID $exchangeid"))
    end
end

function decode_sessionid(id::Number)
    if id == 0
        return "Default Primary Session"
    elseif id == 1
        return "Electronic Session"
    elseif id == 2
        return "Pit Session or Canadian Markets"
    elseif id == 3
        return "European Markets"
    end
end

function decode_priceflags(priceflags::Integer)
    #http://nxcoreapi.com/doc/struct_NxCoreTrade.html
    const NxTPF_SETLAST = 0x01 # Update the 'last' price field with the trade price.
    const NxTPF_SETHIGH	= 0x02	# Update the session high price.
    const NxTPF_SETLOW	= 0x04	# Update the session low price.
    const NxTPF_SETOPEN	= 0x08	# Indicates trade report is a type of opening report. For snapshot indicies, this is the "open" field. See TradeConditions for the types that update this flag.
    const NxTPF_EXGINSERT	= 0x10	# Trade report was inserted, not real-time. Often follows EXGCANCEL for trade report corrections.
    const NxTPF_EXGCANCEL	= 0x20	# Cancel message. The data in this trade report reflects the state of the report when first sent, including the SETLAST/increment volume, etc flags.
    const NxTPF_SETTLEMENT	= 0x40	# price is settlement

    msg = String[]
    if priceflags & NxTPF_SETLAST == 1
        push!(msg, "Update the 'last' price field with the trade price.")
    end; if priceflags & NxTPF_SETHIGH == 1
        push!(msg, "Update the session high price.")
    end; if priceflags & NxTPF_SETLOW == 1
        push!(msg, "Update the session low price.")
    end; if priceflags & NxTPF_SETOPEN == 1
        push!(msg, "Indicates trade report is a type of opening report. For snapshot indicies, this is the \"open\" field. See TradeConditions for the types that update this flag.")
    end; if priceflags & NxTPF_EXGINSERT == 1
        push!(msg, "Trade report was inserted, not real-time. Often follows EXGCANCEL for trade report corrections.")
    end; if priceflags & NxTPF_EXGCANCEL == 1
        push!(msg, "Cancel message. The data in this trade report reflects the state of the report when first sent, including the SETLAST/increment volume, etc flags.")
    end; if priceflags & NxTPF_SETTLEMENT == 1
        push!(msg, "Price is settlement")
    end
    msg == [] && push!(msg, "No special price flags.")
    join(msg, "\n")
end

function decode_conditionflags(conditionflags::Integer)
    #http://nxcoreapi.com/doc/struct_NxCoreTrade.html
    const NxTCF_NOLAST	= 0x01	# Not eligible to update last price.
    const NxTCF_NOHIGH	= 0x02	# Not eligible to update high price.
    const NxTCF_NOLOW	= 0x04	# Not eligible to update low price.

    msg = String[]
    if conditionflags & NxTCF_NOLAST == 1
        push!(msg, "Not eligible to update last price.")
    elseif conditionflags & NxTCF_NOHIGH == 1
        push!(msg, "Not eligible to update high price.")
    elseif conditionflags & NxTCF_NOLOW == 1
        push!(msg, "Not eligible to update low price.")
    end
    msg == [] && push!(msg, "No special trade conditions.")
    join(msg, "\n")
end

function decode_conditionindex(NxID::Number)
    #http://nxcoreapi.com/doc/info_TradeConditions.html
    if NxID == 0
        return "Regular: Regular Trade"
    elseif NxID == 1
        return "FormT: Form T. Before and After Regular Hours."
    elseif NxID == 2
        return "OutOfSeq: Report was sent Out Of Sequence. Updates last if it becomes only trade (if the trade reports before it are canceled, for example)."
    elseif NxID == 3
        return "AvgPrc: Average Price for a trade. NYSE/AMEX stocks. Nasdaq uses AvgPrc_Nasdaq-- main difference is NYSE/AMEX does not conditionally set high/low/last."
    elseif NxID == 4
        return "AvgPrc_Nasdaq: Average Price. Nasdaq stocks. Similar to AvgPrc, but does not set high/low/last."
    elseif NxID == 5
        return "OpenReportLate: NYSE/AMEX. Market opened Late. Here is the report. It may not be in sequence. Nasdaq uses OpenReportOutOfSeq. *update last if only trade."
    elseif NxID == 6
        return "OpenReportOutOfSeq: Report IS out of sequence. Market was open, and now this report is just getting to us."
    elseif NxID == 7
        return "OpenReportInSeq: Opening report. This is the first price."
    elseif NxID == 8
        return "PriorReferencePrice: Trade references price established earlier. *Update last if this is the only trade report."
    elseif NxID == 9
        return "NextDaySale: NYSE/AMEX:Next Day Clearing. Nasdaq: Delivery of Securities and payment one to four days later."
    elseif NxID == 10
        return "Bunched: Aggregate of 2 or more Regular trades at same price within 60 seconds and each trade size not greater than 10,000."
    elseif NxID == 11
        return "CashSale: Delivery of securities and payment on the same day."
    elseif NxID == 12
        return "Seller: Stock can be delivered up to 60 days later as specified by the seller. After 1995, the number of days can be greater than 60. note: delivery of 3 days would be considered a regular trade."
    elseif NxID == 13
        return "SoldLast: Late Reporting. *Sets Consolidated Last if no other qualifying Last, or same Exchange set previous Trade, or Exchange is Listed Exchange."
    elseif NxID == 14
        return "Rule127: NYSE only. Rule 127 basically denotes the trade was executed as a block trade."
    elseif NxID == 15
        return "BunchedSold: Several trades were bunched into one trade report, and the report is late. *Update last if this is first trade."
    elseif NxID == 16
        return "NonBoardLot: Size of trade is less than a board lot (oddlot). A board lot is usually 1,00 shares. Note this is Canadian markets."
    elseif NxID == 17
        return "POSIT: POSIT Canada is an electronic order matching system that prices trades at the mid-point of the bid and ask in the continuous market."
    elseif NxID == 18
        return "AutoExecution: Transaction executed electronically. Soley for information. Only found in OPRA -- options trades, and quite common."
    elseif NxID == 19
        return "Halt: Temporary halt in trading in a particular security for one or more participants."
    elseif NxID == 20
        return "Delayed: Indicates a delayed opening"
    elseif NxID == 21
        return "Reopen: Reopening of a contract that was previously halted."
    elseif NxID == 22
        return "Acquisition: Transaction on exchange as a result of an Exchange Acquisition"
    elseif NxID == 23
        return "CashMarket: Cash only Market. All trade reports for this session will be settled in cash. note: differs from CashSale in that the trade marked as CashSale is an exception -- that is, most trades are settled using regular conditions."
    elseif NxID == 24
        return "NextDayMarket: Next Day Only Market. All trades reports for this session will be settled the next day. Note: differs from NextDay in that the trade marked as NextDay is an exception -- that is, most trades are settled using regular conditions."
    elseif NxID == 25
        return """BurstBasket: Specialist bought or sold this stock as part of an execution of a specific basket of stocks. NYSE CTA announce here: Modification to the Definition of “Burst Basket Execution” to “Intermarket Sweep Order"""
    elseif NxID == 26
        return "OpenDetail: This trade is one of several trades that made up the open report trade. Often the open report has a large size which was made up of orders placed overnight. After trading has commenced, the individual trades of the open report trade are sent with this condition. Note it doesn't update volume, high, low, or last because it's already been accounted for in the open report."
    elseif NxID == 27
        return "IntraDetail: This trade is one of several trades that made up a previous trade. Similar to OpenDetail but refers to a trade report that was not the opening trade report."
    elseif NxID == 28
        return "BasketOnClose:	A trade consisting of a paired basket order to be executed based on the closing value of an index. These trades are reported after the close when the index closing value is known."
    elseif NxID == 29
        return "Rule155: AMEX only rule 155. Sale of block at one clean-up price."
    elseif NxID == 30
        return "Distribution: Sale of a large block of stock in a way that price is not adversely affected."
    elseif NxID == 31
        return "Split: Execution in 2 markets when the specialist or MM in the market first receiving the order agrees to execute a portion of it at whatever price is realized in another market to which the balance of the order is forwarded for execution."
    elseif NxID == 32
        return "Reserved: Does not set Consolidated Last. *Sets Exg Last if this is the only trade."
    elseif NxID == 33
        return """CustomBasketCross: One of two types:
            2 paired but seperate orders in which a market maker or member facilitates both sides of a remaining portion of a basket."
            A split basket plus an entire basket where the market maker or member facilitates the remaining shares of the split basket."""
    elseif NxID == 34
        return "AdjTerms: Terms have been adjusted to reflect stock split/dividend or similar event."
    elseif NxID == 35
        return "Spread: Spread between 2 options in the same options class."
    elseif NxID == 36
        return "Straddle: Straddle between 2 options in the same options class."
    elseif NxID == 37
        return "BuyWrite: This is the option part of a covered call."
    elseif NxID == 38
        return "Combo: A buy and a sell in 2 or more options in the same class."
    elseif NxID == 39
        return "STPD: Traded at price agreed upon by the floor following a non-stopped trade of the same series at the same price."
    elseif NxID == 40
        return "CANC: a previously reported trade - it will not be the first or last trade record. note: If the most recent report is Out of seq, SoldLast, or a type that does not qualify to set the last, that report can be considered in processing the cancel."
    elseif NxID == 41
        return "CANCLAST: the most recent trade report that is qualified to set the last."
    elseif NxID == 42
        return "CANCOPEN: the opening trade report."
    elseif NxID == 43
        return "CANCONLY: the only trade report. There is only one trade report, cancel it."
    elseif NxID == 44
        return "CANCSTPD: the trade report that has the condition STPD."
    elseif NxID == 45
        return "MatchCross"
    elseif NxID == 46
        return "FastMarket Term used to define unusually hectic market conditions."
    elseif NxID == 47
        return "Nominal: Nominal price. A calculated price primarily generated to represent the fair market value of an inactive instrument for the purpose of determining margin requirements and evaluating position risk. Common in futures and futures options."
    elseif NxID == 48
        return "Cabinet: A trade in a deep out-of-the-money option priced at one-half the tick value. Used by options traders to liquidate positions."
    elseif NxID == 49
        return "BlankPrice: Sent by an exchange to blank out the associated price (bid, ask or trade)."
    elseif NxID == 50
        return "NotSpecified: An unspecified (generalized) condition."
    elseif NxID == 51
        return "MCOfficialClose: The Official closing value as determined by a Market Center."
    elseif NxID == 52
        return "SpecialTerms: Indicates that all trades executed will be settled in other than the regular manner."
    elseif NxID == 53
        return "ContingentOrder: The result of an order placed by a Participating Organization on behalf of a client for one security and contingent on the execution of a second order placed by the same client for an offsetting volume of a related security."
    elseif NxID == 54
        return "InternalCross: A cross between two client accounts of a Participating Organization which are managed by a single firm acting as portfolio manager with discretionary authority to manage the investment portfolio granted by each of the clients. This was originally from Toronto Stock Exchange (TSX)."
    elseif NxID == 55
        return "StoppedRegular Stopped Stock Regular Trade."
    elseif NxID == 56
        return "StoppedSoldLast Stopped Stock SoldLast Trade"
    elseif NxID == 57
        return "StoppedOutOfSeq: Stopped Stock -- Out of Sequence."
    elseif NxID == 58
        return "Basis: A transaction involving a basket of securities or an index participation unit that is transacted at prices achieved through the execution of related exchange-traded derivative instruments, which may include index futures, index options and index participation units in an amount that will correspond to an equivalent market exposure."
    elseif NxID == 59
        return "VWAP: Volume Weighted Average Price. A transaction for the purpose of executing trades at a volume-weighted average price of the security traded for a continuous period on or during a trading day on the exchange."
    elseif NxID == 60
        return "SpecialSession: Occurs when an order is placed by a purchase order on behalf of a client for execution in the Special Trading Session at the last sale price."
    elseif NxID == 61
        return "NanexAdmin: Used to make volume and price corrections to match official exchange values."
    elseif NxID == 62
        return "OpenReport: Indicates an opening trade report."
    elseif NxID == 63
        return "MarketOnClose: The Official opening value as determined by a Market Center."
    elseif NxID == 64
        return "Not Defined: undefined, not used."
    elseif NxID == 65
        return "OutOfSeqPreMkt: An out of sequence trade that exectuted in pre or post market -- a combination of FormT and OutOfSeq."
    elseif NxID == 66
        return "MCOfficialOpen: The Official opening value as determined by a Market Center. The value in this trade will currently set the official Open for the rest of the trading day and will show up for the next day's CAT 16 Open value."
    elseif NxID == 67
        return "FuturesSpread: Execution was part of a spread with another futures contract."
    elseif NxID == 68
        return "OpenRange: Two trade prices are used to indicate an opening range representing the high and low prices during the first 30 seconds or so of trading."
    elseif NxID == 69
        return "CloseRange: Two trade prices are used to indicate an opening range representing the high and low prices during the last 30 seconds or so of trading."
    elseif NxID == 70
        return "NominalCabinet: Nominal Cabinet"
    elseif NxID == 71
        return "ChangingTrans: Changing Transaction"
    elseif NxID == 72
        return "ChangingTransCab: Changing Cabinet Transaction"
    elseif NxID == 73
        return "NominalUpdate: Nominal price update"
    elseif NxID == 74
        return "PitSettlement: Sent with a \"pit session\" settlement price to the electronic session, for the purpose of computing net change from the next day electronic session and the prior session settlement price."
    elseif NxID == 75
        return "BlockTrade: An executed trade of a large number of shares, typically 10,000 shares or more."
    elseif NxID == 76
        return "ExgForPhysical: Exchange Future for Physical"
    elseif NxID == 77
        return "VolumeAdjustment: An adjustment made to the cumulative trading volume for a trading session."
    elseif NxID == 78
        return "VolatilityTrade: Volatility trade"
    elseif NxID == 79
        return "YellowFlag: Appears when reporting exchnge may be experiencing technical difficulties."
    elseif NxID == 80
        return "FloorPrice: Distinguishes a floor Bid/Ask from a member Bid Ask on LME"
    elseif NxID == 81
        return "OfficialPrice: Official bid/ask price used by LME."
    elseif NxID == 82
        return "UnofficialPrice: Unofficial bid/ask price used by LME."
    elseif NxID == 83
        return "MidBidAskPrice: A price halfway between the bid and ask on LME."
    elseif NxID == 84
        return "EndSessionHigh: End of Session High Price."
    elseif NxID == 85
        return "EndSessionLow: End of Session Low Price."
    elseif NxID == 86
        return "Backwardation: A condition where the immediate delivery price is higher than the future delivery price. Opposite of Contango."
    elseif NxID == 87
        return "Contango: A condition where the future delivery price is higher than the immediate delivery price. Opposite of Backwardation."
    elseif NxID == 88
        return "Holiday: In Development"
    elseif NxID == 89
        return "PreOpening: The period of time prior to the market opening time (7:00 A.M. - 9:30 A.M.) during which orders are entered into the market for the Opening."
    elseif NxID == 90
        return "PostFull"
    elseif NxID == 91
        return "PostRestricted"
    elseif NxID == 92
        return "ClosingAuction"
    elseif NxID == 93
        return "Batch"
    elseif NxID == 94
        return "Trading"
    elseif NxID == 95
        return "IntermarketSweep: A trade resulting from an Intermarket Sweep Order Execution due to a better price found on another market."
    elseif NxID == 96
        return "Derivative: Derivatively priced."
    elseif NxID == 97
        return "Reopening: Market center re-opening prints."
    elseif NxID == 98
        return "Closing: Market center closing prints."
    elseif NxID == 99
        return "CAPElection: A trade resulting from an sweep execution where CAP orders were elected and executed outside the best bid or affer and appear as repeat trades."
    elseif NxID == 100
        return "SpotSettlement"
    elseif NxID == 101
        return "BasisHigh"
    elseif NxID == 102
        return "BasisLow"
    elseif NxID == 103
        return "Yield: Applies to bid and ask yield updates for Cantor Treasuries"
    elseif NxID == 104
        return "PriceVariation"
    elseif NxID == 105
        return "StockOption"
    elseif NxID == 106
        return "StoppedIM: Transaction order which was stopped at a price that did not constitute a Trade-Through on another market. Valid trade do not update last"
    elseif NxID == 107
        return "Benchmark"
    elseif NxID == 108
        return "TradeThruExempt"
    elseif NxID == 109
        return "Implied: These trades are result of a spread trade. The exchange sends a leg price on each future for spread transactions. These trades do not update O/H/L/L but they update volume. We are now sending these spread trades for Globex exchanges: CME, NYMEX, COMEX, CBOT, MGE, KCBT and DME."
    elseif NxID == 110
        return "OTC"
    elseif NxID == 115
        return "OddLot: This indicates any trade with size between 1-99."
    elseif NxID == 117
        return "CorrectedCSLast: This allows for a mechanism to correct the official close on the consolidated tape."
    else
        throw(ValueError("Invalid TradeCondition $NxID"))
    end
end

function decode_volumetype(volumetype::Number)
    #http://nxcoreapi.com/doc/struct_NxCoreTrade.html
    const NxTVT_INCRVOL		 = 0	# Most frequent -- incremental volume, updates trading session's TotalVolume. Note: it may be zero -- which updates the TickVolume but leaves TotalVolume unchanged
    const NxTVT_NONINCRVOL	 = 1	# Non-incremental volume. Rarely used outside of indexes. Intraday and Open detail in NYSE stocks. Indicates the Size member does not update the total volume: because that volume has already been added. This type is rarely used: Trade Conditions -- Open Detail, and Intraday Detail in NYSE and AMEX stocks, and certain indexes that are updated in a snapshot fashion and do not have volume or do not have volume available.
    const NxTVT_TOTALVOL	 = 2	# Size *is* the total volume -- as used by a few indexes that are updated as snapshots of the current values, and this volume type indicates the Size member represents the total volume of the session. The value of Size member will grow with each successive update. Symbols that update in a snapshot fashion will have all trade messages with this VolumeType.
    const NxTVT_TOTALVOLx100 = 3	# Size *is* the total volume/100. Size should be multiplied by 100 to get the true volume. This is very RARE -- only one or two Dow Jones Indexes currently use this type.
    if volumetype == NxTVT_INCRVOL
        return "Incremental volume, updates trading session's TotalVolume."
    elseif volumetype == NxTVT_NONINCRVOL
        return "Non-incremental volume. Indicates the Size member does not update the total volume: because that volume has already been added."
    elseif volumetype == NxTVT_TOTALVOL
        return "Size *is* the total volume"
    elseif volumetype == NxTVT_TOTALVOLx100
        return "Size *is* the total volume/100."
    else
        throw(ValueError("Invalid VolumeType: $volumetype"))
    end
end

function decode_batecode(code::AbstractString)
    #http://nxcoreapi.com/doc/struct_NxCoreTrade.html#BATECode
    if code == "\0" || code == ""
        return "None"
    elseif code == "B"
        return "Bid"
    elseif code == "A"
        return "Ask"
    elseif code == "T"
        return "Trade"
    elseif code == "E"
        return "Exception"
    end
end

function decode_sighilotype(NxRTA::Number)
    #http://nxcoreapi.com/doc/struct_NxCTAnalysis.html
    const NxRTA_SIGHL_EQ = 0
    const NxRTA_SIGHL_LOWEST = 1
    const NxRTA_SIGHL_LOW = 2
    const NxRTA_SIGHL_HIGH = 3
    const NxRTA_SIGHL_HIGHEST = 4

    if NxRTA == NxRTA_SIGHL_EQ
        return "Indicates the trade price matches the preceding trade price. The Analysis Engine continues to look at trades with matching prices and sets SigHiLoSeconds to the difference between the earliest matching trade and analyzed trade."
    elseif NxRTA == NxRTA_SIGHL_LOWEST
        return "Indicates this trade has the lowest trade price of the session for all eligible trades that do not have the Filtered set to 1. SigHiLoSeconds is the elapsed seconds-bucket since the first trade of the session. In effect, the price for this type is the Filtered Low for the session."
    elseif NxRTA == NxRTA_SIGHL_LOW
        return "Indicates the trade price is lower than the preceding trade but is not a new session low. SigHiLoSeconds is the elapsed seconds-bucket since the trade that was first equal to or lower than price. In effect, this tells you the trade price sets a low that has not been reached since SigHiLoSeconds ago. The Analysis Engine uses this in evaluating mitigating factors for the real-time filter."
    elseif NxRTA == NxRTA_SIGHL_HIGH
        return "Indicates the trade price is higher than the preceding trade but is not a new session high. SigHiLoSeconds is the elapsed seconds-bucket since the trade that was first equal to or lower than price. In effect, this tells you the trade price sets a high that has not been reached since SigHiLoSeconds ago. The Analysis Engine uses this in evaluating mitigating factors for the real-time filter."
    elseif NxRTA == NxRTA_SIGHL_HIGHEST
        return "Indicates this trade has the highest trade price of the session for all eligible trades that do not have the Filtered set to 1. SigHiLoSeconds is the elapsed seconds-bucket since the first trade of the session. In effect, the price for this type is the Filtered High for the session."
    else
        throw(ValueError("Invalid SigHiLoType: $NxRTA"))
    end
end

function decode_qtematchflags(NxRTA::Number)
    #http://nxcoreapi.com/doc/struct_NxCTAnalysis.html
    const NxRTA_QTEMATCHFLAG_OLDER = 0x01
    const NxRTA_QTEMATCHFLAG_CROSSED = 0x02

    msg = String[]
    if NxRTA & NxRTA_QTEMATCHFLAG_OLDER == 1
        push!(msg, "Set if the Analysis Engine had to look at a large number of quotes over a period of time and indicates that the match result is not very accurate, possibly stale.")
    end; if NxRTA & NxRTA_QTEMATCHFLAG_CROSSED == 1
        push!(msg, "Set if the matched quote is crossed: a crossed quote is when the bid price is greater than the ask price. Crossed markets can only happen with Best Bid/Ask quote records or regional quotes that include competing entities. Usually pre-market and post-market quotes are found in a crossed state, but recently, crossed market have become more common.")
    end
    join(msg, "\n")
end

function decode_qtematchtype(NxRTA::Number)
    #http://nxcoreapi.com/doc/struct_NxCTAnalysis.html
    const NxRTA_QMTYPE_NONE = 0
    const NxRTA_QMTYPE_BID = 1
    const NxRTA_QMTYPE_ASK = 2
    const NxRTA_QMTYPE_INSIDE = 3
    const NxRTA_QMTYPE_BELOWBID = 4
    const NxRTA_QMTYPE_ABOVEASK = 5

    if NxRTA == NxRTA_QMTYPE_NONE
        return "Indicates that no quote records were found. This can occur at the opening on NYSE and AMEX stocks for the regional match. Often the NYSE will not issue a quote until the opening trades are sent. Those opening trades will not have any quote records to compare against."
    elseif NxRTA == NxRTA_QMTYPE_BID
        return "Indicates the trade price was closer to the Bid. If the QteMatchDistance is zero, the trade price was equal to the Bid Price."
    elseif NxRTA == NxRTA_QMTYPE_ASK
        return "Indicates the trade price was closer to the Ask. If the QteMatchDistance is zero, the trade price was equal to the Ask Price."
    elseif NxRTA == NxRTA_QMTYPE_INSIDE
        return "Indicates the trade price was exactly between the bid and ask. If QteMatchDistance is zero, it indicates a locked market where the bid and ask prices are equal. Note, only markets with Best Quotes can be locked, unless the regional quote includes competing entities."
    elseif NxRTA == NxRTA_QMTYPE_BELOWBID
        return "Indicates the trade price was found below the bid price. QteMatchDistance will indicate how far away the price was. Finding no quotes where the trade is between the bid and ask is most common in two scenarios: the trade price is suspect -- either being a very late report/bad print, or the market is moving into new territory: breaking below a significant low. The Analysis engine uses this together with the Significant HiLo when determining mitigating circumstances in the real-time filter."
    elseif NxRTA == NxRTA_QMTYPE_ABOVEASK
        return "Indicates the trade price was found above the ask price. QteMatchDistance will indicate how far away the price was. Finding no quotes where the trade is between the bid and ask is most common in two scenarios: the trade price is suspect -- either being a very late report/bad print, or the market is moving into new territory: breaking above a significant high. The Analysis engine uses this together with the Significant HiLo when determining mitigating circumstances in the real-time filter."
    end
end

function showtrade(traderecord)
    msg = String[]
    for (i, t) in enumerate(traderecord)
        if i==15
            toprint = string("(", t, ") ", decode_symbol(t))
        elseif i==16 || i==17
            toprint = string("(", int(t), ") ", decode_exchange(int(t)))
        elseif i==18
            toprint = string("(", int(t), ") ", decode_sessionid(int(t)))
        elseif i==19
            toprint = string("(", uint8(t), ") ", decode_priceflags(int(t)))
        elseif i==20
            toprint = string("(", uint8(t), ") ", decode_conditionflags(int(t)))
        elseif i==21
            toprint = string("(", int(t), ") ", decode_conditionindex(int(t)))
        elseif i==22
            toprint = string("(", int(t), ") ", decode_volumetype(int(t)))
        elseif i==23
            toprint = string(t, " ", decode_batecode(t))
        elseif i==4 || i== 9 || i==37
            #Fields that really should have been parsed as booleans
            toprint = string(bool(t))
        elseif i==39
            toprint = string("(", int(t), ") ", decode_sighilotype(int(t)))
        elseif i==43 || i==44
            toprint = string("(", uint8(t), ") ", decode_qtematchflags(int(t)))
        elseif i==45 || i==46
            toprint = string("(", int(t), ") ", decode_qtematchtype(int(t)))
        elseif i==5 || i==6 || i==7 || i==11 || i==12 || i==25
            #Fields that really should have been parsed as integers
            toprint = string(int(t))
        else
            toprint = t
        end
        push!(msg, string(i, "\t", fieldnames[i], "\t", toprint))
    end
    join(msg, "\n")
end

