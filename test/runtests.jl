using GpuOptim: @custom
using Test

@noinline intrinsic(@nospecialize(val)) = Base.compilerbarrier(:const, val)

function times_two(a)
    a + a
end

struct CustomList
    data::Vector{Int}
end

function add(a::CustomList, b::CustomList)
    CustomList(a.data .+ b.data)
end

function mul(a::CustomList, b::CustomList)
    CustomList(a.data .* b.data)
end

function add_mul(a::CustomList, b::CustomList, c::CustomList)
    CustomList(a.data .+ b.data .* c.data)
end

function optimizetarget(a, b, c)
    return add(a, mul(b, c))
end

A = CustomList([1, 2, 3])
B = CustomList([4, 5, 6])
C = CustomList([7, 8, 9])

@testset "GpuOptim.jl" begin
    # @test (@custom times_two(13)) == 26
    @test (@custom optimizetarget(A, B, C)).data == [29, 42, 57]
end
