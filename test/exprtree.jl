using GpuOptim: IRExpr, IrToExpr, get_root_expr!, ExprToIr, expr_to_ir!
using Test
using Metatheory

function instr_equal(a, b)
    if length(a) != length(b)
        println("Lengths differ: ", length(a), " ", length(b))
        println(a)
        println(b)
        return false
    end

    for (ai, bi) in zip(a, b)
        if ai isa Expr && ai.head == :invoke &&
           bi isa Expr && bi.head == :call

            ai.args[1].def.name == bi.args[1].name && continue
        end

        if ai != bi
            println("Instructions differ: ")
            println(ai)
            println(bi)
            return false
        end
    end

    return true
end

# Perform a round-trip from ircode -> irexpr -> e-graph -> irexpr -> ircode
function assert_conversion(expr)
    ir, _ = Base.code_ircode(expr) |> first

    if length(ir.cfg.blocks) != 1
        @warn "Test `" * String(Symbol(expr)) * "` not supported: multiple basic blocks"
        return
    end

    block = first(ir.cfg.blocks)

    irtoexpr = IrToExpr(ir.stmts, block.stmts)
    irexpr = get_root_expr!(irtoexpr)

    g = EGraph(irexpr; keepmeta=true)
    result = extract!(g, astsize)

    exprtoir = ExprToIr(Main, block.stmts)
    (result_instr, _) = expr_to_ir!(exprtoir, result)

    result = instr_equal(ir.stmts.stmt, result_instr)
    if !result
        println(Symbol(expr))
        println(ir)
    end
    @test result
end

@testset "ExprTree" begin
    doeffect() = println("Side effect!")
    function doeffect2(x)
        println("Side effect!")
        return x
    end
    combine(a, b) = (a, b)

    integer_add(a::Int, b::Int) = a + b
    assert_conversion(integer_add)

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

    function sideeffect2(a, b)
        x = doeffect2(a)
        y = doeffect2(b)
        return combine(x, y)
    end
    assert_conversion(sideeffect2)

    unreachable() = unreachable()
    assert_conversion(unreachable)

    callexpr(a, b) = a + b
    assert_conversion(callexpr)

    base_func(a) = Base.code_ircode(a)
    assert_conversion(base_func)

    apply(a) = a()
    assert_conversion(apply)

    closure(a) = () -> a
    assert_conversion(closure)

    arrayindex(a, b) = a[b]
    assert_conversion(arrayindex)
end
