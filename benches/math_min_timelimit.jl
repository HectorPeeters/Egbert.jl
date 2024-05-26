using GpuOptim: @custom, @rewritetarget, Options, math_identities
using Test: @testset, @test
using Metatheory
using BenchmarkTools: @benchmark

@rewritetarget add(a::Integer, b::Integer)::Integer = a + b
@rewritetarget sub(a::Integer, b::Integer)::Integer = a - b
@rewritetarget mul(a::Integer, b::Integer)::Integer = a * b
@rewritetarget div(a::Integer, b::Integer)::Intege = a / b
@rewritetarget pow(a::Integer, b::Integer)::Integer = a^b

function tooptimize(a::Integer, b::Integer)
    asquared = pow(a, 2)
    bsquared = pow(b, 2)
    ab2 = mul(2, mul(a, b))
    return add(asquared, add(ab2, bsquared))
end

@test tooptimize(12, 13) == 625

@test (@custom Options() math_identities tooptimize(12, 13)) == 625

for i in 5:35
    println("Iteration ", i, " limit ", i * 100_000, " ns")
    params = SaturationParams(timelimit=i * 100_000)
    options = Options(
        saturation_params=params,
        enable_caching=false,
        dont_run=true,
        log_ir=true,
        print_sat_info=true
    )

    @custom options math_identities tooptimize(12, 13)
end
