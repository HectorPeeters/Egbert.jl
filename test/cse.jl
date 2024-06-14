# This test case is used to ensure that optimization using  common subexpression
# elimination works correctly and still produces the correct result.

using GpuOptim: @optimize, @rewritetarget_ef, Options
using Test: @testset, @test
using LinearAlgebra: diag, sum, transpose
using BenchmarkTools
using Metatheory

struct MyInt
    data::Integer

    @rewritetarget_ef MyInt(x::Integer)::MyInt = new(x)
end

function Base.:(==)(a::MyInt, b::MyInt)
    return a.data == b.data
end

@rewritetarget_ef function add(a::MyInt, b::MyInt)::MyInt
    return MyInt(a.data + b.data)
end

global count = 0

@rewritetarget_ef function mul(a::MyInt, b::MyInt)::MyInt
    global count += 1
    return MyInt(a.data * b.data)
end

function tooptimize(c::MyInt)
    a = mul(c, MyInt(2))
    b = mul(c, MyInt(2))
    return add(a, b)
end

rules = @theory a b begin
    add(a, b) == add(b, a)
end

@testset "CommonSubexpressionElimination" begin
    @test tooptimize(MyInt(2)) == MyInt(8)

    @test (@optimize Options() rules tooptimize(MyInt(2))) == MyInt(8)

    @test begin
        global count = 0
        @optimize Options() rules tooptimize(MyInt(2))
        count == 1
    end
end
