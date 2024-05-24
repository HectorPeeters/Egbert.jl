# Test cases to ensure the evaluation order of arguments is preserved

using GpuOptim: @custom, @rewritetarget, Options
using Test: @testset, @test
using Metatheory

global check_order = []

@rewritetarget function newval(x::Int)::Int
    push!(check_order, x)
    return x
end

@rewritetarget add(a::Int, b::Int)::Int = a + b
@rewritetarget add3(a::Int, b::Int, c::Int)::Int = a + b + c
@rewritetarget mul(a::Int, b::Int)::Int = a * b

function tooptimize(a, b, c)
    return add(newval(a), add(newval(b), newval(c)))
end

rules = @theory a b c begin
    add(a, add(b, c)) --> add3(b, c, a)
end

@testset "ArgumentOrdering" begin
    @test tooptimize(1, 2, 3) == 6

    @test begin
        global check_order = []
        tooptimize(1, 2, 3)
        check_order == [1, 2, 3]
    end

    @test begin
        global check_order = []
        @custom Options() rules tooptimize(1, 2, 3)
        check_order == [1, 2, 3]
    end
end
