using GpuOptim: @custom, @rewritetarget
using Test: @testset, @test

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

function add_mul(a::CustomList, b::CustomList, c::CustomList)
    return perform_add_mul(a, b, c)
end

@rewritetarget function add_mul_intermediate(a::CustomList, b::CustomList, c::CustomList)::CustomList
    return error("This is broken to make sure the test rewrites this.")
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
    @test (@custom nooptimizetarget(A, B)).data == [5, 7, 9]
end
