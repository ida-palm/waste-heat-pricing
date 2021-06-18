include("setup.jl")
## Self-scheduling waste-heat implementation

## Defining time period and number of refrigeration display cases (RDCs)

constant_COP = false

RDCs = 1:11
delta_t = 15 # no. of minutes in each time step
hours = 24*365
time_intervals = 1:Int(hours*(60/delta_t))

start_date = Dates.DateTime("2019-01-01T00:00:00")
end_date = start_date + Hour(hours)
# create a list of timestamps for plotting or other interesting things
time_list = []
date = Dates.DateTime(start_date)
while date < end_date
    push!(time_list, date)
    date = date + Minute(delta_t)
end
## Importing input data

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
temp_ambient = repeat(temp_ambient_hourly, inner=Int(60/delta_t))
temp_supermarket = transpose(repeat([25+273.15], length(time_intervals), length(RDCs)))

# calculating COP based on ambient temperature
# based on regression from mekanik-data
# assuming that COP is the same for all HPs
# if constant_COP is true, we assume a COP of 2 for all times and RDCs
if constant_COP
    COP = fill(2, (length(RDCs), length(time_intervals)))
else
    COP = []
    current_COP = 0
    for T in temp_ambient
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

# price for waste heat calculated from a simple exponential model
# assuming that the forecasted temperature is close to the actual temperature,
# as the prices depend on the forecasted temperature
price_waste_heat = [(temp_ambient[t]-273.15) < 17.5 ? round(380*0.92^(temp_ambient[t]-273.15), digits=0) : 0 for t in time_intervals]

# electricity price (DKK/MWh for DK2 16/4 2021)
df_elprice = CSV.read("Project\\Data\\elspot_2018-2020_DK2.csv", DataFrame; select=["HourUTC", "SpotPriceDKK"])
df_elprice.HourUTC = DateTime.(df_elprice.HourUTC, "yyyy-mm-ddTHH:MM:SS+00:00")
price_el_hourly = reverse(df_elprice[start_date .<= df_elprice[!,"HourUTC"] .< end_date, :"SpotPriceDKK"])
price_el = repeat(price_el_hourly, inner=Int(60/delta_t))

# from source [1], RDCs 1, 2 and 3
# converted to heat transfer every Δt minutes (converted to seconds)
# assuming that UA is W*K and not W/m²*K, otherwise eq. 3 and 4 don't make sense
heat_transfer = [41.9, 56.3, 57.5, 32.2, 36.1, 58.2, 24.1, 23, 28, 4, 17]*(delta_t*60) # [J/K]
heat_capacity = [1.9, 4.8, 2.7, 4.1, 6.3, 1.7, 4.6, 1.7, 1.9, 0.7, 7.7]/10^5
41.9
# temp and heat limits are totally made up
temp_limit = [4 6; 4 6; 4 6; 4 6; 4 6; 4 6; 4 6; -20 -18; -20 -18; -20 -18; -20 -18].+273.15
heat_limit = [10*10^3, 10*10^3, 10*10^3, 10*10^3, 10*10^3, 10*10^3, 10*10^3, 10*10^3, 20*10^3, 20*10^3, 20*10^3]*delta_t*60

## The model
model = Model(Gurobi.Optimizer)

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
            + heat_transfer[i]/heat_capacity[i] * (temp_supermarket[i,(t-1)] - temp_RDC[i,(t-1)]))
@objective(model, Min, sum(2.778*10^(-10)*(load_el[i,t]*price_el[t] - output_heat[i,t]*price_waste_heat[t]) for i in RDCs, t in time_intervals))

optimize!(model)
## Results

# convert the heat output + el load from J to kWh and then from kWh to avg. power in kW
# over each 15 minute period by multiplying by 4
output_heat_kWh = 2.778*10^(-7)*value.(output_heat)
output_heat_kW = output_heat_kWh*(60/delta_t)
load_el_kWh = 2.778*10^(-7)*value.(load_el)
load_el_kW = load_el_kWh*(60/delta_t)

# gathering results in a dataframe
df_res_ss = DataFrame(HourUTC = time_list)
for i in RDCs
    colname = "QH$i"
    df_res_ss[!, colname] = collect(output_heat_kWh[i,:])
end
for i in RDCs
    colname = "QdotH$i"
    df_res_ss[!, colname] = collect(output_heat_kW[i,:])
end
for i in RDCs
    colname = "LE$i"
    df_res_ss[!, colname] = collect(load_el_kWh[i,:])
end
for i in RDCs
    colname = "TRDC$i"
    df_res_ss[!, colname] = collect(value.(temp_RDC)[i,:].-273.15)
end
df_res_ss[!, "QH_total"] = sum(collect(output_heat_kWh), dims=1)[1,:]
df_res_ss[!, "QdotH_total"] = sum(collect(output_heat_kW), dims=1)[1,:]
df_res_ss[!, "LE_total"] = sum(collect(load_el_kWh), dims=1)[1,:]
df_res_ss[!, "COP"] = COP[1,:]
df_res_ss[!, "TA"] = temp_ambient.-273.15
df_res_ss[!, "λWH"] = price_waste_heat
df_res_ss[!, "λE"] = price_el

# total revenue over the given period for each RDC [DKK]
# converting the heat ouput and el load to MWh
revenue_ss = [sum(10^(-3)*output_heat_kWh[i,:].*price_waste_heat) for i in RDCs]
cost_ss = [sum(10^(-3)*load_el_kWh[i,:].*price_el) for i in RDCs]
profit_ss = round(sum(revenue_ss - cost_ss); digits=1)


## Plots!
plot_heat = plot(time_intervals, [output_heat_kW[8,:] load_el_kW[8,:]],
    title = "Optimal operation for RDC2 in April of 2019",
    palette = DTU_colors,
    label=["Heat output" "Electricity load"], legend=:bottomleft,
    xlab="Time (15 min.)", ylab="Power (kW)",
    tickfontrotation = 0,
    right_margin = 25mm,
    linewidth = 2,
    fontfamily = "arial"
)
plot!(twinx(), [price_el, price_waste_heat],
    palette = DTU_colors_60[8:end],
    label=[L"λ^{E}" L"λ^{WH}"],
    legend=:bottomright, ylab="Price (DKK/MWh)",
    fontfamily = "arial"
)
annotate!(1450, -100, text("Total profit: $profit_ss DKK"))
