include("setup.jl")

## Waste heat producers participating in the market
constant_COP = false

CHPs = 1:13                                     # representing each of the 13 CHPs
no_supermarkets = 21000                          # the number of participating (identocal) supermarkets
RDCs = 1:11                                     # representing each of the 11 RDCs (7 fridges + 4 freezers) per supermarket
delta_t = 15                                    # no. of minutes in each time step for RDCs
hours = 24*365                                  # no. of hours in simulation (also time steps for CHPs)
time_intervals = 1:Int(hours*(60/delta_t))      # total number of time steps for RDCs

start_date = Dates.DateTime("2019-01-01T00:00:00")
end_date = start_date + Hour(hours)

# create a list of timestamps for plotting or other interesting things
time_list_Δt = []
date = Dates.DateTime(start_date)
while date < end_date
    push!(time_list_Δt, date)
    date = date + Minute(delta_t)
end

time_list_hourly = []
date = Dates.DateTime(start_date)
while date < end_date
    push!(time_list_hourly, date)
    date = date + Hour(1)
end


## INPUTS: Fetching a lot of data
# Electricity price from NordPool, using UTC time and DKK as price, in DKK/MWh
df_elprice = CSV.read("Project\\Data\\elspot_2018-2020_DK2.csv", DataFrame; select=["HourUTC", "SpotPriceDKK"])
df_elprice.HourUTC = DateTime.(df_elprice.HourUTC, "yyyy-mm-ddTHH:MM:SS+00:00")
price_el_hourly = reverse(df_elprice[start_date .<= df_elprice[!,"HourUTC"] .< end_date, :"SpotPriceDKK"])
price_el_Δt = repeat(price_el_hourly, inner=Int(60/delta_t))

# heat load  [MWh/h]
# data from Varmelast for the CTR & VEKS areas
df_heatcons = CSV.read("Project\\Data\\heat_consumption_2019-2021.csv", DataFrame)
df_heatcons.HourUTC = DateTime.(df_heatcons.HourUTC, "yyyy-mm-dd HH:MM")
df_heatcons_total = DataFrame(HourUTC = df_heatcons.HourUTC, TotalConsumption = (df_heatcons.TotalConsCTR + df_heatcons.TotalConsVEKS))
load_heat_hourly = replace(df_heatcons_total[start_date .<= df_heatcons_total[!,"HourUTC"] .< end_date, :TotalConsumption], missing => 0)

# median ambient temperatures from the "DMI"-measuring station in Copenhagen
df_temp = DataFrame(HourUTC = [], Temperature = [])
for feature in JSON.parsefile("Project/Data/weather_data/datafixed.json")["features"]
    value = feature["properties"]["value"]
    timestamp = feature["properties"]["observed"]
    push!(df_temp, [timestamp value])
end
df_temp.HourUTC = DateTime.(df_temp.HourUTC, "yyyy-mm-ddTHH:MM:SSZ")
temp_ambient_hourly = reverse(df_temp[start_date .<= df_temp[!,"HourUTC"] .< end_date, :"Temperature"]).+273.15
# getting the ambient temperature in the necessary resolution
temp_ambient_Δt = repeat(temp_ambient_hourly, inner=Int(60/delta_t))
temp_supermarket_Δt = repeat([25+273.15], length(time_intervals))

# calculating COP based on ambient temperature
# based on regression from mekanik-data
# assuming that COP is the same for all HPs
# if constant_COP is true, we assume a COP of 2 for all times and RDCs
if constant_COP
    COP = fill(2, (length(RDCs), length(time_intervals)))
else
    COP = []
    current_COP = 0
    for T in temp_ambient_Δt
        if T < -10
            current_COP = 1.691-0.00425*(T-273.15)
        elseif T >= 20
            current_COP = 1.973+0.00185*(T-273.15)
        else
            current_COP = 1.825+0.0100*(T-273.15)
        end
        push!(COP, round(current_COP, digits=5))
    end
    # duplicating the COP for each RDC
    COP = repeat(transpose(COP), length(RDCs))
end



## PARAMETERS
# fuel price for fuel used for each hour for each plant [DKK/MWh]
# taken from Ommen, Markussen & Elmegaard 2013: Heat pumps in district heating networks [€/GJ]
# the €-price is multiplied by 7.5/0.278 to get the DKK-price and the MWh-quantity
price_fuel = [6.5, 2, 7.3, 7.3, 7.3, 2, 3.5, 6.9, 2, 2, 2, 6.5, 6.5]*7.5/0.278

# power-to-heat ratio for each generator, assumed to be 0.45 for all
# (COMBINED HEAT AND POWER (CHP) GENERATION Directive 2012/27/EU of the European
# Parliament and of the Council Commission Decision 2008/952/EC)
phr = repeat([0.45], outer=length(CHPs))

# fuel efficiency for producing heat and electricity per plant [t fuel/MWh el or heat]
# from Ommen, Markussen & Elmegaard 2013: Heat pumps in district heating networks
# assuming ρ_el = 0.2 and ρ_heat = 0.9 for the ones without information
#eff_el = eff_heat = repeat([1], outer=length(CHPs))
eff_heat = [0.9, 0.9, 0.9, 0.9, 0.9, 0.83, 0.91, 0.93, 0.81, 0.99, 0.99, 0.9, 0.9]
eff_el = [0.21, 0.2, 0.18, 0.29, 0.2, 0.19, 0.36, 0.43, 0.18, 0.12, 0.18, 0.2, 0.2]

# max fuel intake per plant [MWh/h] equal to cap. boiler
max_fuel_intake = [365, 550, 180, 300, 125, 131, 600, 1150, 65, 95, 110, 46.5, 56.2]
max_heat_gen = [251, 400, 240, 250, 94, 190, 331, 585, 96.8, 69, 73, 41.8, 53]

# from source [1], RDCs 1, 2 and 3
# converted to heat transfer every Δt minutes (converted to seconds)
# assuming that UA is W*K and not W/m²*K, otherwise eq. 3 and 4 don't make sense
heat_transfer = no_supermarkets*[41.9, 56.3, 57.5, 32.2, 36.1, 58.2, 24.1, 23, 28, 4, 17]*(delta_t*60) # [J/K]
heat_capacity = [1.9, 4.8, 2.7, 4.1, 6.3, 1.7, 4.6, 1.7, 1.9, 0.7, 7.7]/10^5

# temp and heat limits are totally made up
temp_limit = [4 6; 4 6; 4 6; 4 6; 4 6; 4 6; 4 6; -20 -18; -20 -18; -20 -18; -20 -18].+273.15
heat_limit = no_supermarkets*[10*10^3, 10*10^3, 10*10^3, 10*10^3, 10*10^3, 10*10^3, 10*10^3, 10*10^3, 20*10^3, 20*10^3, 20*10^3]*delta_t*60


## OPTIMIZATION MODEL
model = Model(Gurobi.Optimizer)

# for CHPs
cost_heat = [price_el_hourly[t] <= price_fuel[i]*eff_el[i] ?
        price_fuel[i]*(eff_el[i]*phr[i]+eff_heat[i]) - price_el_hourly[t]*phr[i] :
        price_el_hourly[t]*eff_heat[i]/eff_el[i] for i in CHPs, t in 1:hours]
@variable(model, 0 <= gen_heat[i in CHPs, t in 1:hours] <= max_heat_gen[i])
@variable(model, 0 <= fuel_intake[i in CHPs, t in 1:hours] <= max_fuel_intake[i])

@constraint(model, con_fuel_phr[i in CHPs, t in 1:hours],
            fuel_intake[i,t] >= gen_heat[i,t]*(eff_el[i]*phr[i] + eff_heat[i]))

# for RDCs
@variable(model, output_heat[RDCs, time_intervals] >= 0)
@variable(model, load_el[RDCs, time_intervals] >= 0)
@variable(model, temp_RDC[RDCs, time_intervals])

# set all RDCs to have a temperature of 5 deg. C to start
# set the HP to be turned off during the first interval
for i in RDCs
    fix(temp_RDC[i,1], temp_limit[i,1]; force=true)
    fix(output_heat[i,1], 0; force=true)
end

@constraint(model, con_COP[i in RDCs, t in time_intervals],
            output_heat[i,t] == COP[i,t]*load_el[i,t])
@constraint(model, con_heat_limit[i in RDCs, t in time_intervals],
            output_heat[i,t] <= heat_limit[i])
@constraint(model, con_temp_limit[i in RDCs, t in time_intervals],
            temp_limit[i,1] <= temp_RDC[i,t] <= temp_limit[i,2])
@constraint(model, con_temp[i in RDCs, t in 2:length(time_intervals)],
            temp_RDC[i,t] == temp_RDC[i,(t-1)]
            - (output_heat[i,t] - load_el[i,t])/heat_capacity[i]
            + heat_transfer[i]/heat_capacity[i] * (temp_supermarket_Δt[t-1] - temp_RDC[i,(t-1)]))


# balancing load with both RDCs and CHPs
# for the RDCs, we sum the outputs for 4 timesteps of 15 minutes
# the output_heat for RDCs is in Joules, and is converted to MWh
@constraint(model, balance[t in 1:hours], sum(gen_heat[:,t]) + 2.778*10^(-10)*sum(output_heat[:,(4*t-3):4*t]) - load_heat_hourly[t] <= 0)

# objective function!
@objective(model, Min, sum(cost_heat[i,t]*gen_heat[i,t] for i in CHPs, t in 1:hours))

optimize!(model)


## Results

# convert the heat output + el load from J to kWh and then from kWh to avg. power in kW
# over each 15 minute period by multiplying by 4
output_heat_MWh = 2.778*10^(-10)*value.(output_heat)
output_heat_MW = output_heat_MWh*(60/delta_t)
load_el_MWh = 2.778*10^(-10)*value.(load_el)
load_el_MW = load_el_MWh*(60/delta_t)
market_clearing_price_hourly = dual.(balance)
market_clearing_price_Δt = repeat(market_clearing_price_hourly, inner=Int(60/delta_t))

# gathering results for the RDCs
df_res_RDC = DataFrame(HourUTC = time_list_Δt)
for i in RDCs
    colname = "QH$i"
    df_res_RDC[!, colname] = collect(output_heat_MWh[i,:])
end
for i in RDCs
    colname = "QdotH$i"
    df_res_RDC[!, colname] = collect(output_heat_MW[i,:])
end
for i in RDCs
    colname = "LE$i"
    df_res_RDC[!, colname] = collect(load_el_MWh[i,:])
end
for i in RDCs
    colname = "TRDC$i"
    df_res_RDC[!, colname] = collect(value.(temp_RDC)[i,:].-273.15)
end
df_res_RDC[!, "QH_total"] = sum(collect(output_heat_MWh), dims=1)[1,:]
df_res_RDC[!, "QdotH_total"] = sum(collect(output_heat_MW), dims=1)[1,:]
df_res_RDC[!, "LE_total"] = sum(collect(load_el_MWh), dims=1)[1,:]
df_res_RDC[!, "COP"] = COP[1,:]
df_res_RDC[!, "TA"] = temp_ambient_Δt.-273.15
df_res_RDC[!, "λH"] = market_clearing_price_Δt
df_res_RDC[!, "λE"] = price_el_Δt

# gathering results for the CHPs
df_res_CHP = DataFrame(HourUTC = time_list_hourly)
for i in CHPs
    colname = "GH$i"
    df_res_CHP[!, colname] = collect(value.(gen_heat))[i,:]
end
for i in CHPs
    colname = "F$i"
    df_res_CHP[!, colname] = collect(value.(fuel_intake))[i,:]
end
df_res_CHP[!, "GH_total"] = sum(collect(value.(gen_heat)), dims=1)[1,:]
df_res_CHP[!, "F_total"] = sum(collect(value.(fuel_intake)), dims=1)[1,:]
df_res_CHP[!, "λH"] = market_clearing_price_hourly
df_res_CHP[!, "λE"] = price_el_hourly
df_res_CHP[!, "LH"] = load_heat_hourly

# total revenue over the given period for each RDC [DKK]
revenue = [sum(output_heat_MWh[i,:].*market_clearing_price_Δt) for i in RDCs]
cost = [sum(load_el_MWh[i,:].*price_el_Δt) for i in RDCs]
profit = round(sum(revenue - cost); digits=1)
