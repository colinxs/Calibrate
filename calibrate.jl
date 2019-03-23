doc = """MuSHR Calibration.

Usage:
  calibrate.jl <wheelbase> <straight_samples_csv_path> <turn_samples_csv_path>

Options:
  -h --help     Show this screen.
"""

using DocOpt
using JuliaDB: loadtable, table
using LsqFit: curve_fit


linemodel(x, p) = p[1] .* x .+ p[2]

# fit the model servo_pos = delta (rad) * gain + offset
# steering_samples is an array of (servo_position, steering_diameter (m))
# assumes ackermann geometry
function calibrate_steering(steering_samples, wheelbase)
    x, y = Float64[], Float64[]
    for (servo, diam) in steering_samples
        delta = atan(wheelbase, abs(diam / 2)) # magnitude
        delta = diam < 0 ? -delta : delta # sign
        push!(x, delta)
        push!(y, servo)
    end
    # initial guess: no gain/offset
    fit = curve_fit(linemodel, x, y, [1.0, 0.0])
    gain, offset = fit.param
    return gain, offset
end

# fit the model erpm = speed (m/s) * gain + offset
# straight_samples is an array of (erpm, elapsed_distance (m), elapsed_time (s))
function calibrate_speed(straight_samples)
    x, y = Float64[], Float64[]
    for (erpm, d, dt) in straight_samples
        push!(x, d / dt)
        push!(y, erpm)
    end
    fit = curve_fit(linemodel, x, y, [1.0, 0.0])
    gain, offset = fit.param
    return gain, offset
end

args = docopt(doc, version=v"2.0.0")

# erpm,distance,dt
straight = loadtable(args["<straight_samples_csv_path>"])
turn = loadtable(args["<turn_samples_csv_path>"])
wheelbase = parse(Float64, args["<wheelbase>"])

speed2erpm_gain, speed2erpm_offset = calibrate_speed(straight)
steering2servo_gain, steering2servo_offset = calibrate_steering(turn, wheelbase)
println("speed2erpm_gain: ", speed2erpm_gain)
println("speed2erpm_offset: ", speed2erpm_offset)
println("steering2servo_gain: ", steering2servo_gain)
println("steering2servo_offset: ", steering2servo_offset)

# TODO roll into tsuite
function test()
    # generate fake data
    speed2erpm_gain, speed2erpm_offset = 2, 0.2
    speed = [0.5, 0.5, 1.0, 1.0]
    dt = [2, 3, 0.3, 2]
    d = [s * t for (s, t) in zip(speed, dt)]
    erpm = linemodel(speed, [speed2erpm_gain, speed2erpm_offset])
    straight_samples = table((erpm=erpm,
                             elapsed_distance=d,
                             elapsed_time=dt))

    gain, offset = calibrate_speed(straight_samples)
    @assert isapprox(gain, speed2erpm_gain)
    @assert isapprox(offset, speed2erpm_offset)


    steering2servo_gain, steering2servo_offset, wheelbase = 2, 0.5, 0.33
    delta = [0.34, 0.34, -0.34, -0.34]
    diam = [2 * wheelbase / tan(d) for d in delta]
    servo = linemodel(delta, [steering2servo_gain, steering2servo_offset])
    steering_samples = table((servo_pos=servo,
                              diam=diam))

    gain, offset = calibrate_steering(steering_samples, wheelbase)
    @assert isapprox(gain, steering2servo_gain)
    @assert isapprox(offset, steering2servo_offset)

end






