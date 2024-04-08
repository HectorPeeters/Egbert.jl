using GpuOptim: @custom, @rewritetarget, Options
using Test: @testset, @test
using LinearAlgebra: diag, sum, transpose
using BenchmarkTools
using Metatheory

struct MyInt
    data::Integer

    @rewritetarget MyInt(x::Integer)::MyInt = new(x)
end

function Base.:(==)(a::MyInt, b::MyInt)
    return a.data == b.data
end

@rewritetarget function add(a::MyInt, b::MyInt)::MyInt
    return MyInt(a.data + b.data)
end

@rewritetarget function mul(a::MyInt, b::MyInt)::MyInt
    return MyInt(a.data * b.data)
end

function tooptimize()
    a = MyInt(2)
    b = MyInt(2)
    return add(a, b)
end

rules = @theory a b begin
    add(a, b) == add(b, a)
end

@testset "TraceOfMatMul" begin
    @test tooptimize() == MyInt(4)

    @test (@custom Options(use_cse=true) rules tooptimize()) == MyInt(4)
end