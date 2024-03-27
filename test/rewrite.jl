using GpuOptim: IRExpr
using Test: @testset, @test
using Metatheory
using Metatheory.EGraphs

t = @theory a b begin
    trace(a * b) --> trace_mul(a, b)
    transpose(a + b) == transpose(a) + transpose(b)
    transpose(a * b) == transpose(b) * transpose(a)
    trace(transpose(a)) == trace(a)
end

# expr = IRExpr(:trace, [IRExpr(:*, [12, 13], 0)], 0)
expr = IRExpr(:trace, [IRExpr(:*, [IRExpr(:transpose, [:A]), IRExpr(:transpose, [:B])])])

g = EGraph(expr) # ; keepmeta = true)

settermtype!(g, IRExpr)

println(saturate!(g, t))

function EGraphs.egraph_reconstruct_expression(::Type{IRExpr}, op, args; metadata = nothing, exprhead = nothing)
  IRExpr(op, args)
end

println(extract!(g, astsize))
