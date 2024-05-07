using GpuOptim: @custom, @rewritetarget, Options
using Test: @testset, @test
using Metatheory
using BenchmarkTools: @benchmark

struct MyInteger
    data::Integer

    @rewritetarget function MyInteger(data::Integer)::MyInteger
        new(data)
    end
end

@rewritetarget function add(a::MyInteger, b::MyInteger)::MyInteger
    return MyInteger(a.data + b.data)
end

@rewritetarget function sub(a::MyInteger, b::MyInteger)::MyInteger
    return MyInteger(a.data - b.data)
end

@rewritetarget function mul(a::MyInteger, b::MyInteger)::MyInteger
    return MyInteger(a.data * b.data)
end

@rewritetarget function pow(a::MyInteger)::MyInteger
    return MyInteger(a.data * a.data)
end

function tooptimize(a::MyInteger, b::MyInteger)
    return add(pow(a), add(mul(MyInteger(2), mul(a, b)), pow(b)))
end

rules = @theory a b c begin
    pow(a) == mul(a, a)

    add(a, b) == add(b, a)
    add(a, add(b, c)) == add(add(a, b), c)
    add(a, 0) == a

    mul(a, b) == mul(b, a)
    mul(a, mul(b, c)) == mul(mul(a, b), c)
    mul(a, 1) == a

    pow(add(a, b)) == add(pow(a), add(mul(2, mul(a, b)), pow(b)))
    pow(sub(a, b)) == add(sub(pow(a), mul(2, mul(a, b))), pow(b))

    # Constant folding rules
    add(a::MyInteger, b::MyInteger) => add(a, b)
    sub(a::MyInteger, b::MyInteger) => sub(a, b)
    mul(a::MyInteger, b::MyInteger) => mul(a, b)
    pow(a::MyInteger) => pow(a)
end

@testset "Identities" begin
    @test tooptimize(MyInteger(12), MyInteger(13)) == MyInteger(625)
    @test (@custom Options() rules tooptimize(MyInteger(12), MyInteger(13))) == MyInteger(625)
end
