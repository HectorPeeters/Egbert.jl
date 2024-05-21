using GpuOptim: @custom, @rewritetarget, Options, math_identities
using Test: @testset, @test
using Metatheory
using BenchmarkTools: @benchmark

@rewritetarget function add(a::Integer, b::Integer)::Integer
    return a + b
end

@rewritetarget function sub(a::Integer, b::Integer)::Integer
    return a - b
end

@rewritetarget function mul(a::Integer, b::Integer)::Integer
    return a * b
end

@rewritetarget function div(a::Integer, b::Integer)::Integer
    return a / b
end

@rewritetarget function pow(a::Integer, b::Integer)::Integer
    return a^b
end

function tooptimize(a::Integer, b::Integer)
    asquared = pow(a, 2)
    bsquared = pow(b, 2)
    ab2 = mul(2, mul(a, b))
    return add(asquared, add(ab2, bsquared))
end

@test tooptimize(12, 13) == 625

@test (@custom Options() math_identities tooptimize(12, 13)) == 625

for i in 25:35
    println("Iteration ", i, " limit ", i * 100_000, " ns")
    params = SaturationParams(timelimit=i * 100_000)
    options = Options(
        saturation_params=params,
        enable_caching=false,
        dont_run=true,
        log_ir=true
    )

    @custom options math_identities tooptimize(12, 13)
end
