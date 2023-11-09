using GpuOptim: @custom
using Test

add(a, b) = a + b

@noinline intrinsic() = Base.compilerbarrier(:const, 42)

function foo(a)
    return a + intrinsic()
end

function fib(a)
    if a <= 1
        return 1
    end
    return fib(a - 1) + @noinline fib(a - 2)
end

struct CustomArray
    data::Array{Float64}
end

Base.size(a::CustomArray) = size(a.data)
Base.getindex(a::CustomArray, i...) = getindex(a.data, i...)
Base.setindex!(a::CustomArray, v, i...) = setindex!(a.data, v, i...)

(+)(a::CustomArray, b::CustomArray)::CustomArray = CustomArray((Base.:+).(a.data, b.data))

(*)(a::CustomArray, b::Float64)::CustomArray = CustomArray((Base.:*)(a.data, b))

(==)(a::CustomArray, b::CustomArray)::Bool = (Base.:(==))(a.data, b.data)

specialized_add_mul(a::CustomArray, b::CustomArray, c::Float64)::CustomArray =
    (Base.:+).(a.data, (Base.:*)(b.data, c))

function custom_array_opt(a::CustomArray, b::CustomArray, c::Float64)::CustomArray
    a + b * c
end

const A::CustomArray = CustomArray([1.0, 2.0, 3.0])
const B::CustomArray = CustomArray([4.0, 5.0, 6.0])

@testset "GpuOptim.jl" begin
    # @test (@custom add_const()) == 25
    # @test (@custom add(13, 12)) == 1
    # @test (@custom foo(12)) == 54
    # @test (@custom fib(12)) == 233
    @test (@custom custom_array_opt(A, B, 7.0)) ==
          CustomArray([29.0, 37.0, 45.0])
end
