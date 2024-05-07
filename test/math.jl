using GpuOptim: @custom, @rewritetarget, Options
using Test: @testset, @test
using Metatheory
using BenchmarkTools: @benchmark

global crash_mul = false

@rewritetarget function add(a::Integer, b::Integer)::Integer
    return a + b
end

@rewritetarget function sub(a::Integer, b::Integer)::Integer
    return a - b
end

@rewritetarget function mul(a::Integer, b::Integer)::Integer
    if crash_mul
        error("Should be replaced by optimization")
    end
    return a * b
end

@rewritetarget function pow(a::Integer)::Integer
    return a * a
end

function tooptimize(a::Integer, b::Integer)
    return add(pow(a), add(mul(Integer(2), mul(a, b)), pow(b)))
end

rules = @theory a b c begin
    pow(a) == mul(a, a)

    add(a, a) == mul(a, 2)
    add(a, b) == add(b, a)
    add(a, add(b, c)) == add(add(a, b), c)
    add(a, 0) == a

    mul(a, b) == mul(b, a)
    mul(a, mul(b, c)) == mul(mul(a, b), c)
    mul(a, 1) == a

    add(pow(a), add(mul(2, mul(a, b)), pow(b))) == pow(add(a, b))
    add(sub(pow(a), mul(Integer(2), mul(a, b))), pow(b)) == pow(sub(a, b))

    # Constant folding rules
    add(a::Integer, b::Integer) => a + b
    sub(a::Integer, b::Integer) => a - b
    mul(a::Integer, b::Integer) => a * b
    pow(a::Integer) => a * a
end

@testset "Identities" begin
    @test tooptimize(12, 13) == 625

    @test begin
        global crash_mul = true
        (@custom Options() rules tooptimize(12, 13)) == 625
    end
end
