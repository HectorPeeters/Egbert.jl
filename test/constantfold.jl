# Simple test set to verify the constant folding functionality of the
# Metatheory.jl library.

using GpuOptim: @optimize, @rewritetarget_ef, Options
using Test: @testset, @test
using Metatheory

global count = 0;

@rewritetarget_ef function add(a::Integer, b::Integer)::Integer
    global count += 1
    return a + b
end

@rewritetarget_ef function mul(a::Integer, b::Integer)::Integer
    global count += 1
    return a * b
end

@rewritetarget_ef function pow(a::Integer)::Integer
    global count += 1
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
    add(a::Integer, b::Integer) => a + b
    mul(a::Integer, b::Integer) => a * b
    pow(a::Integer) => a * a
end

@testset "ConstantFold" begin
    @test tooptimize(12) == 60

    global count = 0
    @test (@optimize Options() rules tooptimize(12)) == 60
    @test count == 1
end
