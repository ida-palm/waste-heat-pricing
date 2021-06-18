# Modeling a CHP to clear the heating market

## Imports
using JuMP
using Gurobi
using Printf
using CSV
using DataFrames
using Dates
##%

# Let's do 24 hours and 10 generators
time_intervals = 1:24
no_gen = 1:13
## INPUTS: Fetching a lot of data
start_date = Dates.DateTime("2019-01-01T00:00:00")
end_date = start_date + Hour(length(time_intervals))

# Electricity price from NordPool, using UTC time and DKK as price, in DKK/MWh
df_elprice = CSV.read("Project\\Data\\elspot_2018-2020_DK2.csv", DataFrame; select=["HourUTC", "SpotPriceDKK"])
df_elprice.HourUTC = DateTime.(df_elprice.HourUTC, "yyyy-mm-ddTHH:MM:SS+00:00")
price_el = reverse(df_elprice[start_date .<= df_elprice[!,"HourUTC"] .< end_date, :"SpotPriceDKK"])
#price_el[price_el.<=0] .= 0 # if we don't want negative electricity prices uncomment

# heat load  [MWh/h]
# data from Varmelast for the CTR & VEKS areas
df_heatcons = CSV.read("Project\\Data\\heat_consumption_2019-2021.csv", DataFrame)
df_heatcons.HourUTC = DateTime.(df_heatcons.HourUTC, "yyyy-mm-dd HH:MM")
load_heat_hourly = DataFrame(HourUTC = df_heatcons.HourUTC, TotalConsumption = (df_heatcons.TotalConsCTR + df_heatcons.TotalConsVEKS))
load_heat = replace(load_heat_hourly[start_date .<= load_heat_hourly[!,"HourUTC"] .< end_date, :TotalConsumption], missing => 0)

# fuel price for fuel used for each hour for each plant [DKK/MWh]
# taken from Ommen, Markussen & Elmegaard 2013: Heat pumps in district heating networks [€/GJ]
# the €-price is multiplied by 7.5/0.278 to get the DKK-price and the MWh-quantity
price_fuel = [6.5, 2, 7.3, 7.3, 7.3, 2, 3.5, 6.9, 2, 2, 2, 6.5, 6.5]*7.5/0.278


## PARAMETERS
# power-to-heat ratio for each generator, assumed to be 0.45 for all
# (COMBINED HEAT AND POWER (CHP) GENERATION Directive 2012/27/EU of the European
# Parliament and of the Council Commission Decision 2008/952/EC)
phr = repeat([0.45], outer=length(no_gen))

# fuel efficiency for producing heat and electricity per plant [t fuel/MWh el or heat]
# from Ommen, Markussen & Elmegaard 2013: Heat pumps in district heating networks
# assuming ρ_el = 0.2 and ρ_heat = 0.9 for the ones without information
#eff_el = eff_heat = repeat([1], outer=length(no_gen))
eff_heat = [0.9, 0.9, 0.9, 0.9, 0.9, 0.83, 0.91, 0.93, 0.81, 0.99, 0.99, 0.9, 0.9]
eff_el = [0.21, 0.2, 0.18, 0.29, 0.2, 0.19, 0.36, 0.43, 0.18, 0.12, 0.18, 0.2, 0.2]

# max fuel intake per plant [MWh/h] equal to cap. boiler
max_fuel_intake = [365, 550, 180, 300, 125, 131, 600, 1150, 65, 95, 110, 46.5, 56.2]
max_heat_gen = [251, 400, 240, 250, 94, 190, 331, 585, 96.8, 69, 73, 41.8, 53]

## OPTIMIZATION MODEL
model = Model(Gurobi.Optimizer)

# calculate marginal heat prices (DKK/MWh)
cost_heat = [price_el[t] <= price_fuel[i]*eff_el[i] ?
        price_fuel[i]*(eff_el[i]*phr[i]+eff_heat[i]) - price_el[t]*phr[i] :
        price_el[t]*eff_heat[i]/eff_el[i] for i in no_gen, t in time_intervals]
@variable(model, 0 <= gen_heat[i in no_gen, t in time_intervals] <= max_heat_gen[i])
@variable(model, 0 <= fuel_intake[i in no_gen, t in time_intervals] <= max_fuel_intake[i])

@constraint(model, con_fuel_phr[i in no_gen, t in time_intervals],
            fuel_intake[i,t] >= gen_heat[i,t]*(eff_el[i]*phr[i] + eff_heat[i]))
@constraint(model, balance[t in time_intervals], sum(gen_heat[:,t]) - load_heat[t] == 0)

@objective(model, Min, sum(cost_heat[i,t]*gen_heat[i,t] for i in no_gen, t in time_intervals))

optimize!(model)

## Results

# convert the heat output + el load from J to kWh and then from kWh to avg. power in kW
# over each 15 minute period by multiplying by 4
println()
println("Heat generation:")
println(value.(gen_heat))
@printf("Objective value: %s", objective_value(model))
println()
println("Marginal prices (dual):")
println(dual.(balance)) # gives marginal heat price (see pretty drawing)
