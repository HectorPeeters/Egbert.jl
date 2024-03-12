using GpuOptim: @custom, @rewritetarget
using Test: @testset, @test

struct CustomList
    data::Vector{Int}
end

function add_impl(a::CustomList, b::CustomList)::CustomList
    return CustomList(a.data .+ b.data)
end

@rewritetarget function add(a::CustomList, b::CustomList)::CustomList
    add_impl(a, b)
end

function mul_impl(a::CustomList, b::CustomList)::CustomList
    CustomList(a.data .* b.data)
    return error("This is broken to make sure the test rewrites this.")
end

@rewritetarget function mul(a::CustomList, b::CustomList)::CustomList
    return mul_impl(a, b)
end

function add_mul(a::CustomList, b::CustomList, c::CustomList)
    return CustomList(a.data .+ b.data .* c.data)
end

function optimizetarget(a, b, c)
    return add(a, mul(b, c))
end

function nooptimizetarget(a, b)
    return add(a, b)
end

@testset "GpuOptim.jl" begin
    A = CustomList([1, 2, 3])
    B = CustomList([4, 5, 6])
    C = CustomList([7, 8, 9])

    @test (@custom optimizetarget(A, B, C)).data == [29, 42, 57]
    # @test (@custom nooptimizetarget(A, B)).data == [5, 7, 9]
end
