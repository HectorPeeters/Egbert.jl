using GpuOptim: @custom, @rewritetarget, Options
using Test: @testset, @test
using Metatheory

struct CustomList
    data::Vector{Int}
end

function perform_add(a::CustomList, b::CustomList)::CustomList
    return CustomList(a.data .+ b.data)
end

@rewritetarget function add(a::CustomList, b::CustomList)::CustomList
    return perform_add(a, b)
end

function perform_mul(a::CustomList, b::CustomList)::CustomList
    # return CustomList(a.data .* b.data)
    return error("This is broken to make sure the test rewrites this.")
end

@rewritetarget function mul(a::CustomList, b::CustomList)::CustomList
    return perform_mul(a, b)
end

function perform_add_mul(a::CustomList, b::CustomList, c::CustomList)
    return CustomList(a.data .+ b.data .* c.data)
end

@inline function add_mul(a::CustomList, b::CustomList, c::CustomList)
    return perform_add_mul(a, b, c)
end

function optimizetarget(a, b, c)
    x = mul(b, c)
    return add(a, x)
end

function nooptimizetarget(a, b)
    return add(a, b)
end

@testset "GpuOptim.jl" begin
    A = CustomList([1, 2, 3])
    B = CustomList([4, 5, 6])
    C = CustomList([7, 8, 9])

    rules = @theory a b c begin
        add(a, mul(b, c)) --> add_mul(a, b, c)
    end

    @test (@custom Options() rules optimizetarget(A, B, C)).data == [29, 42, 57]
    @test (@custom Options() rules nooptimizetarget(A, B)).data == [5, 7, 9]
end