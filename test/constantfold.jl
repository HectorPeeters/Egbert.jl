using GpuOptim: @custom, @rewritetarget, Options
using Test: @testset, @test
using Metatheory

struct MyInt
    data::Integer

    @rewritetarget function MyInt(x::Integer)::MyInt
        return new(x)
    end
end

@rewritetarget function add(a::MyInt, b::MyInt)::MyInt
    return MyInt(a.data + b.data)
end

@rewritetarget function mul(a::MyInt, b::MyInt)::MyInt
    return MyInt(a.data * b.data)
end

@rewritetarget function pow(a::MyInt)::MyInt
    return mul(a, a)
end

function tooptimize(c::MyInt)
    a = MyInt(2)
    b = MyInt(3)
    d = add(a, b)
    return mul(c, d)
end

rules = @theory a b begin
    mul(a, a) --> pow(a)

    add(a, b) == add(b, a)
    mul(a, b) == mul(b, a)

    # Constant folding rules
    MyInt(a::Integer) => MyInt(a)
    add(a::MyInt, b::MyInt) => add(a, b)
    mul(a::MyInt, b::MyInt) => mul(a, b)
    pow(a::MyInt) => pow(a)
end

@testset "ConstantFold" begin
    @test tooptimize(MyInt(12)) == MyInt(60)
    @test (@custom Options() rules tooptimize(MyInt(12))) == MyInt(60)
end