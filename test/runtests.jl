using GpuOptim: @custom, @rewritetarget
using Test: @testset, @test

struct CustomList
    data::Vector{Int}
end

function add_impl(a::CustomList, b::CustomList)
    CustomList(a.data .+ b.data)
    return error("This is broken to make sure the test rewrites this.")
end

@rewritetarget function add(a::CustomList, b::CustomList)::CustomList
    add_impl(a, b)
end

@rewritetarget function mul(a::CustomList, b::CustomList)::CustomList
    return CustomList(a.data .* b.data)
end

function add_mul(a::CustomList, b::CustomList, c::CustomList)
    return CustomList(a.data .+ b.data .* c.data)
end

function optimizetarget(a, b, c)
    return add(a, mul(b, c))
end

A = CustomList([1, 2, 3])
B = CustomList([4, 5, 6])
C = CustomList([7, 8, 9])

@testset "GpuOptim.jl" begin
    @test (@custom optimizetarget(A, B, C)).data == [29, 42, 57]
end
