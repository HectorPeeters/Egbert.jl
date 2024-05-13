using GpuOptim: @custom, @rewritetarget, Options, math_identities
using Test: @testset, @test
using Metatheory
using BenchmarkTools: @benchmark, @btime

@rewritetarget add(a, b)::Integer = a + b
@rewritetarget sub(a, b)::Integer = a - b
@rewritetarget mul(a, b)::Integer = a * b
@rewritetarget pow(a, b)::Integer = a^b

macro gen_expression(n::Integer)
    operators = [:add, :sub, :mul, :div]
    operands = [Expr(:ref, Symbol("x"), i) for i in 1:2*n]

    opi = 0

    function rand_expr(nodes)
        if nodes <= 1
            opi += 1
            if opi % 5 <= 2
                return opi
            else
                return operands[opi]
            end
        else
            return Expr(:call, operators[opi%4+1], rand_expr(nodes / 2), rand_expr(nodes / 2))
        end
    end

    expr = rand_expr(n)

    println(opi)

    return esc(quote
        function expression()
            return $(expr)
        end
    end)
end

x = 1:1000

@gen_expression(100)

println("Generated expression, running benchmark..")

@test (@custom Options(print_ast_cost=true) math_identities expression()) == expression()

default_options = Options(opt_pipeline=Core.Compiler.default_opt_pipeline(), enable_caching=false, dont_run=true)
opt_options = Options(enable_caching=false, dont_run=true)

@btime (@custom default_options math_identities expression())
@btime (@custom opt_options math_identities expression())

println("Done!")
