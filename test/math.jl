# This test is used to verify the e-graph optimization can correctly find
# the most optimal form for a mathematical expression with a complex rule order.
#
# The expression a^2 + 2ab + b^2 should get rewritten to (a + b)^2

using GpuOptim: @optimize, @rewritetarget, Options, math_identities
using Test: @testset, @test
using Metatheory
using BenchmarkTools: @benchmark

global crash_mul = false

@rewritetarget add(a::Integer, b::Integer)::Integer = a + b
@rewritetarget sub(a::Integer, b::Integer)::Integer = a - b

@rewritetarget function mul(a::Integer, b::Integer)::Integer
    if crash_mul
        error("Should be replaced by optimization")
    end
    return a * b
end

@rewritetarget pow(a::Integer, b::Integer)::Integer = a^b

function tooptimize(a::Integer, b::Integer)
    return add(pow(a, 2), add(mul(2, mul(a, b)), pow(b, 2)))
end

@testset "Identities" begin
    @test tooptimize(12, 13) == 625

    @test begin
        global crash_mul = true
        result = (@optimize Options() math_identities tooptimize(12, 13)) == 625
        global crash_mul = false
        result
    end
end
