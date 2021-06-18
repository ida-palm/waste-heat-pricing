using JuMP
using Gurobi
using Printf
using Plots; pyplot()
using Plots.PlotMeasures
using LaTeXStrings

## Self-scheduling waste-heat implementation
# Trying out 6 hours for 1 heat pump

RDCs = 1:3
delta_t = 15 # no. of minutes in each time step
time_intervals = 1:Int(24*(60/delta_t))


# ambient temperatures (°C from Stockholm 16/4 2021) converted to K
temp_ambient_hourly = [0.5, 0.5, 0.5, 0.5, 0.5, 1.5, 2.5, 3.5, 5.5, 7.5, 9.5,
                        10.5, 10.5, 11.5, 11.5, 10.5, 10.5, 9.5, 8.5, 7.5, 6.5,
                        5.5, 5.5, 4.5].+273.15

# getting the ambient temperature in the necessary resolution
temp_ambient = repeat(temp_ambient_hourly, inner=Int(60/delta_t))
temp_supermarket = transpose(repeat([25+273.15], length(time_intervals), length(RDCs)))

# price for waste heat calculated from a simple exponential model
price_waste_heat = [round(380*0.92^(temp_ambient[t]-273.15), digits=0) for t in time_intervals]

# electricity price (DKK/MWh for DK2 16/4 2021)
price_el_hourly = [366.43, 371.86, 374.61, 387.92, 393.35, 409.78, 515.17, 640.26,
                    714.71, 475.97, 383.68, 375.57, 367.91, 368.21, 349.47, 341.81,
                    343.59, 359.96, 372.60, 402.57, 359.44, 402.20, 368.36, 359.96]
price_el = repeat(price_el_hourly, inner=Int(60/delta_t))

COP = transpose(repeat([2 3 3.5], length(time_intervals)))

# from source [1], RDCs 1, 2 and 3
# converted to heat transfer every Δt minutes (converted to seconds)
# assuming that UA is W*K and not W/m²*K, otherwise eq. 3 and 4 don't make sense
heat_transfer = [41.9, 56.3, 57.5]*(delta_t*60) # [J/K]
heat_capacity = [1.9, 4.8, 2.7]/10^5

# temp and heat limits are totally made up
temp_limit = [2 7; 2 7; 5 7].+273.13
heat_limit = [200*10^3, 300*10^3, 700*10^3]*delta_t*60


## The model
model = Model(Gurobi.Optimizer)

@variable(model, output_heat[RDCs, time_intervals] >= 0)
@variable(model, load_el[RDCs, time_intervals] >= 0)
@variable(model, temp_RDC[RDCs, time_intervals])

# set all RDCs to have a temperature of 5 deg. C to start
# set the HP to be turned off during the first interval
for i in RDCs
    fix(temp_RDC[i,1], 5.0+273.15; force=true)
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
