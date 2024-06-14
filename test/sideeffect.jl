using GpuOptim: @optimize, @rewritetarget, @rewritetarget_ef, Options
using Test: @testset, @test
using Metatheory

global check_order = []

@rewritetarget function add(a, b)::Integer
    return a + b
end

@rewritetarget function mul(a, b)::Integer
    return a * b
end

@rewritetarget function do_sideeffect(x)::Integer
    push!(check_order, x)
    return x
end

function tooptimize1()
    return add(do_sideeffect(1), do_sideeffect(1))
end

function tooptimize2(x)
    y = do_sideeffect(x)
    return add(y, y)
end

function tooptimize3(x)
    y = do_sideeffect(x)
    return mul(y, 0)
end

function tooptimize4(x)
    y = do_sideeffect(x)
    return add(mul(y, 0), 2)
end

function tooptimize5(x)
    y = do_sideeffect(x)
    z = do_sideeffect(x)
    return do_sideeffect(add(y, z))
end

rules = @theory a b begin
    add(a, b) --> add(b, a)
    mul(a, 0) => 0
end

@testset "Side Effects" begin
    @test tooptimize1() == 2

    @test begin
        global check_order = []
        tooptimize1()
        check_order == [1, 1]
    end

    @test begin
        global check_order = []
        @optimize Options(enable_caching=false) rules tooptimize1()
        check_order == [1, 1]
    end

    @test tooptimize2(1) == 2

    @test begin
        global check_order = []
        tooptimize2(1)
        check_order == [1]
    end

    @test begin
        global check_order = []
        @optimize Options() rules tooptimize2(1)
        check_order == [1]
    end

    @test tooptimize3(1) == 0

    @test begin
        global check_order = []
        tooptimize3(1)
        check_order == [1]
    end

    @test begin
        global check_order = []
        @optimize Options() rules tooptimize3(1)
        check_order == [1]
    end

    @test tooptimize4(1) == 2

    @test begin
        global check_order = []
        tooptimize4(1)
        check_order == [1]
    end

    @test begin
        global check_order = []
        @optimize Options() rules tooptimize4(1)
        check_order == [1]
    end

    @test tooptimize5(1) == 2

    @test begin
        global check_order = []
        tooptimize5(1)
        check_order == [1, 1, 2]
    end

    @test begin
        global check_order = []
        @optimize Options() rules tooptimize5(1)
        check_order == [1, 1, 2]
    end
end
