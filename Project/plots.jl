include("setup.jl")
## Plots!
plot_hours = 24*365
plot_start_date = Dates.DateTime("2019-01-01T00:00:00")
plot_end_date = plot_start_date + Hour(plot_hours)

plot_time_list = []
d = Dates.DateTime(plot_start_date)
while d < plot_end_date
    push!(plot_time_list, d)
    d = d + Minute(15)
end
plot_time = 1:length(plot_time_list)

df_plot_RDC = df_res_RDC[plot_start_date .<= df_res_RDC[!,"HourUTC"] .< plot_end_date, :]
df_plot_CHP = df_res_CHP[plot_start_date .<= df_res_CHP[!,"HourUTC"] .< plot_end_date, :]
#df_plot_ss = df_res_ss[plot_start_date .<= df_res_ss[!,"HourUTC"] .< plot_end_date, :]

#QdotH_total_daily = reshape(df_plot_ss[!,  "QdotH_total"], 24,
#                Int(length(df_plot_ss[!, "QdotH_total"])/24))


plot(1:plot_hours, [df_plot_CHP[!, "GH_total"], df_plot_CHP[!, "LH"]],
    title = "",
    xticks = (0:24*7*4:plot_hours*4),
    #ylims = (19,22),
    palette = DTU_colors,
    label=["GH" "LH"], legend=:topleft,
    xlab="Time (4 weeks)", ylab="Power (MWh)",
    tickfontrotation = 0,
    right_margin = 0mm,
    linewidth = 1,
    fontfamily = "arial"
)
##
plot!(twinx(),  [df_plot_CHP[!, "GH_total"]],
    xticks = :none,
    palette = DTU_colors_60[9:end],
    #ylims = (-20.5,-10.5),
    label=[L"λH" L"λE"],
    #label = [L"T^R_1" L"T^A"],
    legend=:topright, ylab="Price (DKK/MWh)",
    fontfamily = "arial",
    linewidth = 0
)

##

plot(plot_time, [df_plot_RDC[!, "QdotH_total"]],
    title = "",
    xticks = (0:96*7:plot_hours*4),
    ylims = (19,22),
    palette = DTU_colors,
    label="Heat output for the 8th RDC", legend=:topleft,
    xlab="Time (weeks)", ylab="Power (MW)",
    tickfontrotation = 0,
    right_margin = 20mm,
    linewidth = 2,
    fontfamily = "arial"
)
plot!(twinx(),  [df_plot_RDC[!, "λH"], df_plot_RDC[!, "λE"]],
    xticks = :none,
    palette = DTU_colors_60[9:end],
    #ylims = (-20.5,-10.5),
    label=[L"λH" L"λE"],
    #label = [L"T^R_1" L"T^A"],
    legend=:topright, ylab="Price (DKK/MWh)",
    fontfamily = "arial"
)
#plot!(size=(500,250))
#annotate!(10650, -100, text("Total profit: $profit_ss DKK"))


###############
## Scatter plot
###############

plot([10^3*df_plot_RDC[!, "QdotH_total"]], df_plot_RDC[!, "TA"],
        linewidth = 0,
        markershape = :circle,
        markersize = 5,
        markerstrokewidth = 0,
        markerstrokecolor = :white,
        xlims = (17,20),
        xlab = "Heat output (kW)", ylab = L"T^A (° C)",
        fontfamily = "arial",
        legend = :bottomleft,
        label = "Market participation",
        palette = DTU_colors_60[7:end],
        markerstrokestyle = :dot
)
plot!(df_plot_ss[!, "QdotH_total"], df_plot_ss[!, "TA"],
        linewidth = 0,
        markershape = :utriangle,
        markersize = 4,
        markerstrokewidth = 0,
        markerstrokecolor = :white,
        xlims = (17,20),
        xlab = "Heat output (kW)", ylab = L"T^A (° C)",
        fontfamily = "arial",
        label = "Self-scheduling",
        palette = DTU_colors_60[1:end],
        markerstrokestyle = :dot)
plot!(size=(300,400))
