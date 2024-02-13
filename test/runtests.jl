using GpuOptim: @custom
using Test

@noinline intrinsic(@nospecialize(val)) = Base.compilerbarrier(:const, val)

macro rewritetarget(func::Expr)
    func_name = func.args[begin].args[begin]
    args = func.args[begin].args[2:end]

    return esc(quote
        function $func_name($(args...))
            return Base.compilerbarrier(:const, $(func)($(args...)))
        end
    end)
end

function times_two(a)
    a + a
end

struct CustomList
    data::Vector{Int}
end

function add_impl(a::CustomList, b::CustomList)
    CustomList(a.data .+ b.data)
end

@noinline function add(a::CustomList, b::CustomList)
    add_impl(a, b)
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
