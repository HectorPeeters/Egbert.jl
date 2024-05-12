using GpuOptim: @custom, @rewritetarget, Options
using Test: @testset, @test
using Metatheory
using BenchmarkTools: @benchmark, @btime

@rewritetarget add(a, b)::Integer = a + b
@rewritetarget sub(a, b)::Integer = a - b
@rewritetarget mul(a, b)::Integer = a * b

macro gen_expression(n::Integer)
    operands = [Expr(:ref, Symbol("x"), i) for i in 1:2*n]

    opi = 0

    function rand_expr(nodes)
        if nodes <= 1
            opi += 1
            return operands[opi]
        else
            return Expr(:call, :add, rand_expr(nodes / 2), rand_expr(nodes / 2))
        end
    end

    expr = rand_expr(n)

    return esc(quote
        function expression()
            return $(expr)
        end
    end)
end

rules = @theory a b c begin
    add(a, b) == add(b, a)
    add(a, add(b, c)) == add(add(a, b), c)
    add(a, 0) == a

    add(a, a) == mul(a, 2)

    mul(a, b) == mul(b, a)
    mul(a, mul(b, c)) == mul(mul(a, b), c)
    mul(a, 1) == a
end

x = 1:400

@gen_expression(200)

println("Generated expression, running benchmark..")

@test (@custom Options() rules expression()) == expression()

default_options = Options(opt_pipeline=Core.Compiler.default_opt_pipeline(), enable_caching=false, dont_run=true)
opt_options = Options(enable_caching=false, dont_run=true)

@btime (@custom default_options rules expression())
@btime (@custom opt_options rules expression())

println("Done!")
