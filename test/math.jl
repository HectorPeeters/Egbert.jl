using GpuOptim: @custom, @rewritetarget, Options
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

@rewritetarget function pow(a::Integer)::Integer
    return a * a
end

function tooptimize(c::Integer)
    return add(pow(2), add(mul(sub(3, 1), mul(2, c)), pow(c)))
end

rules = @theory a b c begin
    pow(a) == mul(a, a)

    add(a, b) == add(b, a)
    add(a, add(b, c)) == add(add(a, b), c)
    add(a, 0) == a

    mul(a, b) == mul(b, a)
    mul(a, mul(b, c)) == mul(mul(a, b), c)
    mul(a, 1) == a

    pow(add(a, b)) == add(pow(a), add(mul(2, mul(a, b)), pow(b)))
    pow(sub(a, b)) == add(sub(pow(a), mul(2, mul(a, b))), pow(b))

    # Constant folding rules
    add(a::Integer, b::Integer) => add(a, b)
    sub(a::Integer, b::Integer) => sub(a, b)
    mul(a::Integer, b::Integer) => mul(a, b)
    pow(a::Integer) => pow(a)
end

@testset "Identities" begin
    @test tooptimize(12) == 196
    @test (@custom Options() rules tooptimize(12)) == 196
end

@benchmark (@custom Options() rules tooptimize(12))