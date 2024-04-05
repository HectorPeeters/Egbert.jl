using TermInterface
using Metatheory.EGraphs

struct IRExpr
    head::Any
    args::Vector{Any}
end

function Base.:(==)(a::IRExpr, b::IRExpr)
    a.head == b.head && a.args == b.args
end

TermInterface.istree(e::IRExpr) = true
TermInterface.operation(e::IRExpr) = e.head
TermInterface.exprhead(::IRExpr) = :call
TermInterface.arguments(e::IRExpr) = e.args

function TermInterface.similarterm(x::IRExpr, head, args; metadata=nothing, exprhead=:call)
    IRExpr(head, args)
end

# function EGraphs.egraph_reconstruct_expression(::Type{IRExpr}, op, args; metadata = nothing, exprhead = nothing)
#   IRExpr(op, args, metadata)
# end

struct IrToExpr
    instructions::Vector{Any}
    range::CC.StmtRange
    converted::Vector{Bool}
    ssa_index::Integer

    IrToExpr(instructions, range) = new(instructions, range, fill(false, length(instructions)), 1)
end

function markinstruction!(irtoexpr::IrToExpr, id::Integer)
    irtoexpr.converted[id-irtoexpr.range.start+1] = true
end

function get_root_expr!(irtoexpr::IrToExpr)
    toplevel_exprs = []

    while true
        index = findlast(x -> !x, irtoexpr.converted)
        if index === nothing
            break
        end

        markinstruction!(irtoexpr, index)

        instruction = irtoexpr.instructions[irtoexpr.range.start+index-1]
        push!(toplevel_exprs, ir_to_expr!(irtoexpr, instruction))
    end

    return IRExpr(:theta, toplevel_exprs)
end

function ir_to_expr!(irtoexpr::IrToExpr, s::CC.SSAValue)
    if s.id < irtoexpr.range.start || s.id > irtoexpr.range.stop
        return s
    end

    markinstruction!(irtoexpr, s.id)
    return ir_to_expr!(irtoexpr, irtoexpr.instructions[s.id])
end

ir_to_expr!(_::IrToExpr, n::Nothing) = n
ir_to_expr!(_::IrToExpr, a::CC.Argument) = a
ir_to_expr!(_::IrToExpr, q::QuoteNode) = q
ir_to_expr!(_::IrToExpr, m::MethodInstance) = m
ir_to_expr!(_::IrToExpr, r::GlobalRef) = r

function ir_to_expr!(irtoexpr::IrToExpr, p::CC.PiNode)
    return IRExpr(:pi, [ir_to_expr!(irtoexpr, p.val), p.typ])
end

function ir_to_expr!(irtoexpr::IrToExpr, p::CC.PhiNode)
    return IRExpr(:phi, [ir_to_expr!(irtoexpr, x) for x in p.values])
end

function ir_to_expr!(irtoexpr::IrToExpr, p::CC.GotoIfNot)
    return IRExpr(:gotoifnot, [ir_to_expr!(irtoexpr, p.cond), p.dest])
end

function ir_to_expr!(_::IrToExpr, p::CC.GotoNode)
    return IRExpr(:goto, [p.label])
end

function ir_to_expr!(irtoexpr::IrToExpr, r::CC.ReturnNode)
    return IRExpr(Symbol(:ret), [ir_to_expr!(irtoexpr, r.val)])
end

function ir_to_expr!(irtoexpr::IrToExpr, e::Expr)
    if e.head == :invoke
        return IRExpr(Symbol(e.args[1].def.name), map(e.args[3:end]) do x
            ir_to_expr!(irtoexpr, x)
        end)
    end

    return IRExpr(e.head, map(e.args) do x
        ir_to_expr!(irtoexpr, x)
    end)
end

struct ExprToIr
    instructions::Vector{Any}
    ssa_start::Integer
    mod::Module

    ExprToIr(mod::Module, range::CC.StmtRange) = new([], range.start, mod)
end

expr_to_ir!(_::ExprToIr, a::CC.Argument) = a
expr_to_ir!(_::ExprToIr, g::GlobalRef) = g

function expr_to_ir!(exprtoir::ExprToIr, expr::IRExpr)
    if expr.head == :theta
        for e in expr.args
            expr_to_ir!(exprtoir, e)
        end
        return exprtoir.instructions
    end

    if expr.head == :ret
        val = expr_to_ir!(exprtoir, expr.args[1])
        push!(exprtoir.instructions, CC.ReturnNode(val))
        return
    end

    func_name = expr.head
    args = map(expr.args) do x
        expr_to_ir!(exprtoir, x)
    end

    method = GlobalRef(exprtoir.mod, Symbol(func_name))
    push!(exprtoir.instructions, Expr(:call, method, args...))

    return SSAValue(length(exprtoir.instructions) + exprtoir.ssa_start - 1)
end