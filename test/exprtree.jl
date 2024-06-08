using GpuOptim: IRExpr, IrToExpr, get_root_expr!, ExprToIr, expr_to_ir!
using Test
using Metatheory

# Perform a round-trip from ircode -> irexpr -> e-graph -> irexpr -> ircode
function assert_conversion(expr)
    ir, _ = Base.code_ircode(expr) |> first
    println(ir)

    if length(ir.cfg.blocks) != 1
        @warn "Test not supported: multiple basic blocks"
        return
    end

    block = first(ir.cfg.blocks)

    irtoexpr = IrToExpr(ir.stmts, block.stmts)
    irexpr = get_root_expr!(irtoexpr)

    g = EGraph(irexpr; keepmeta=true)
    result = extract!(g, astsize)

    exprtoir = ExprToIr(Main, block.stmts)
    (result_instr, _) = expr_to_ir!(exprtoir, result)

    @test ir.stmts.stmt == result_instr
end

doeffect() = println("Side effect!")

add(a::Int, b::Int) = a + b
assert_conversion(add)

broadcast(a) = max.(a)
assert_conversion(broadcast)

nested(a) = a.b().c.d()
assert_conversion(nested)

sideeffect() = doeffect()
assert_conversion(sideeffect)

function multiple_sideeffect()
    doeffect()
    doeffect()
end
assert_conversion(multiple_sideeffect)

unreachable() = unreachable()
assert_conversion(unreachable)

callexpr(a, b) = a + b
assert_conversion(callexpr)

base_func(a) = Base.code_ircode(a)
assert_conversion(base_func)
