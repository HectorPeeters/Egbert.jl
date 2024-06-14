# Tests showing how constant folding can be implemented using rewrite rules

using GpuOptim: @optimize, @rewritetarget, Options
using Test: @testset, @test
using Metatheory

@rewritetarget function add(a::Integer, b::Integer)::Integer
    return a + b
end

@rewritetarget function mul(a::Integer, b::Integer)::Integer
    return a * b
end

@rewritetarget function pow(a::Integer)::Integer
    return a * a
end

function tooptimize(c::Integer)
    a = 2
    b = 3
    d = add(a, b)
    return mul(c, d)
end

rules = @theory a b begin
    mul(a, a) --> pow(a)

    add(a, b) == add(b, a)
    mul(a, b) == mul(b, a)

    # Constant folding rules
    add(a::Integer, b::Integer) => add(a, b)
    mul(a::Integer, b::Integer) => mul(a, b)
    pow(a::Integer) => pow(a)
end

@testset "ConstantFold" begin
    @test tooptimize(12) == 60
    @test (@optimize Options() rules tooptimize(12)) == 60
end