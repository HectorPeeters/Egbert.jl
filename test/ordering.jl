# Test cases to ensure the evaluation order of arguments is preserved

using GpuOptim: @custom, @rewritetarget, Options
using Test: @testset, @test
using LinearAlgebra: diag, sum, transpose
using BenchmarkTools
using Metatheory

global check_order = []

struct MyInt
    data::Integer

    @rewritetarget function MyInt(x::Integer)::MyInt
        return new(x)
    end
end

@rewritetarget function newval(x::Integer)::MyInt
    push!(check_order, x)
    return MyInt(x)
end

function Base.:(==)(a::MyInt, b::MyInt)
    return a.data == b.data
end

@rewritetarget function add(a::MyInt, b::MyInt)::MyInt
    return MyInt(a.data + b.data)
end

@rewritetarget function add3(a::MyInt, b::MyInt, c::MyInt)::MyInt
    return MyInt(a.data + b.data + c.data)
end

@rewritetarget function mul(a::MyInt, b::MyInt)::MyInt
    return MyInt(a.data * b.data)
end

function tooptimize()
    return add(newval(1), add(newval(2), newval(3)))
end

rules = @theory a b c begin
    add(a, add(b, c)) --> add3(b, c, a)
end

@testset "ArgumentOrdering" begin
    @test tooptimize() == MyInt(6)

    @test begin
        global check_order = []
        tooptimize()
        check_order == [1, 2, 3]
    end

    @test begin
        global check_order = []
        @custom Options() rules tooptimize()
        check_order == [1, 2, 3]
    end
end