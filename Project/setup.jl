using JuMP
using Gurobi
using Printf
using Plots; pyplot()
using Plots.PlotMeasures
using LaTeXStrings
using Dates
using DataFrames
using JSON
using CSV

## Colors
dtured = RGB{Float32}(0.77, 0, 0.05)
white = RGB{Float32}(1, 1, 1)
black = RGB{Float32}(0, 0, 0)
blue = RGB{Float32}(0.12, 0.24, 1)
brightgreen = RGB{Float32}(0.31, 1, 0.34)
navyblue = RGB{Float32}(0, 0, 0.4)
yellow = RGB{Float32}(0.95, 0.83, 0.18)
orange = RGB{Float32}(1, 0.35, 0.14)
pink = RGB{Float32}(1, 0.65, 0.74)
red = RGB{Float32}(1, 0.14, 0.35)
green = RGB{Float32}(0, 0.78, 0)
purple = RGB{Float32}(0.33, 0.04, 1)

DTU_colors = [dtured, blue, brightgreen, navyblue, yellow, orange, pink, red, green, purple]
DTU_colors_60 = [RGBA{Float32}(col, 0.6) for col in DTU_colors]
