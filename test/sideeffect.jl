using GpuOptim: @custom, @rewritetarget, @rewritetarget_ef, Options
using Test: @testset, @test
using Metatheory

global check_order = []

@rewritetarget function add(a, b)::Integer
    return a + b
end

@rewritetarget function do_sideeffect(x)::Integer
    push!(check_order, x)
    return x
end

function tooptimize2()
    return add(do_sideeffect(1), do_sideeffect(1))
end

function tooptimize3(x)
    y = do_sideeffect(x)
    return add(y, y)
end

rules = @theory a b begin
    add(a, b) --> add(b, a)
end

@testset "Side Effects" begin
    @test tooptimize2() == 2

    @test begin
        global check_order = []
        tooptimize2()
        check_order == [1, 1]
    end

    @test begin
        global check_order = []
        @custom Options(enable_caching=false) rules tooptimize2()
        check_order == [1, 1]
    end

    @test tooptimize3(1) == 2

    @test begin
        global check_order = []
        tooptimize3(1)
        check_order == [1]
    end

    @test begin
        global check_order = []
        @custom Options() rules tooptimize3(1)
        check_order == [1]
    end
end
