using TermInterface
using Metatheory.EGraphs

"""
    IRExpr

This struct represents the tree structure of an IRCode object. It is used to
perform e-graph optimizations on the IR code. The IRCode is converted to an
IRExpr object, which is then converted back to IRCode after optimizations.
"""
struct IRExpr
    head::Any
    args::Vector{Any}
    type::Union{Nothing,Type}
end

function Base.:(==)(a::IRExpr, b::IRExpr)
    a.head == b.head && a.args == b.args
end

TermInterface.istree(e::IRExpr) = true
TermInterface.operation(e::IRExpr) = e.head
TermInterface.exprhead(::IRExpr) = :call
TermInterface.arguments(e::IRExpr) = e.args
TermInterface.metadata(e::IRExpr) = (type = e.type)

function TermInterface.similarterm(x::IRExpr, head, args; metadata=nothing, exprhead=:call)
    IRExpr(head, args, metadata)
end

function EGraphs.egraph_reconstruct_expression(
    ::Type{IRExpr}, op, args;
    metadata=nothing,
    exprhead=nothing
)
    IRExpr(op, args, metadata)
end

struct IrToExpr
    instructions::Vector{Any}
    types::Vector{Any}
    range::CC.StmtRange
    converted::Vector{Bool}
    ssa_index::Integer

    IrToExpr(instructions, types, range) = new(instructions, types, range, fill(false, length(instructions)), 1)
end

"""
    markinstruction!(irtoexpr, id)

Mark the instruction with the given ID as converted. This is used to make sure 
all instructions are converted to an expression tree, not just the ones 
necessary for the last return statement.
"""
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

        instr_index = irtoexpr.range.start + index - 1
        instruction = irtoexpr.instructions[instr_index]
        type = irtoexpr.types[instr_index]

        if instruction !== nothing
            push!(toplevel_exprs, ir_to_expr!(irtoexpr, instruction, type))
        end
    end

    return IRExpr(:theta, reverse(toplevel_exprs), nothing)
end

function ir_to_expr!(irtoexpr::IrToExpr, s::CC.SSAValue)
    if s.id < irtoexpr.range.start || s.id > irtoexpr.range.stop
        return s
    end

    markinstruction!(irtoexpr, s.id)
    return ir_to_expr!(irtoexpr, irtoexpr.instructions[s.id], irtoexpr.types[s.id])
end

ir_to_expr!(_::IrToExpr, n::Nothing) = n
ir_to_expr!(_::IrToExpr, a::CC.Argument) = a
ir_to_expr!(_::IrToExpr, q::QuoteNode) = q
ir_to_expr!(_::IrToExpr, m::MethodInstance) = m
ir_to_expr!(_::IrToExpr, r::GlobalRef) = r
ir_to_expr!(_::IrToExpr, s::String) = s

function ir_to_expr!(irtoexpr::IrToExpr, p::CC.PiNode, t)
    return IRExpr(:pi, [ir_to_expr!(irtoexpr, p.val)], p.typ)
end

function ir_to_expr!(irtoexpr::IrToExpr, p::CC.PhiNode, t)
    # TODO: this nothing is probably incorrect
    return IRExpr(:phi, [ir_to_expr!(irtoexpr, x) for x in p.values], t)
end

function ir_to_expr!(irtoexpr::IrToExpr, p::CC.GotoIfNot, t)
    return IRExpr(:gotoifnot, [ir_to_expr!(irtoexpr, p.cond), p.dest], t)
end

function ir_to_expr!(_::IrToExpr, p::CC.GotoNode, t)
    return IRExpr(:goto, [p.label], t)
end

function ir_to_expr!(irtoexpr::IrToExpr, r::CC.ReturnNode, t)
    return IRExpr(:ret, [ir_to_expr!(irtoexpr, r.val)], t)
end

function ir_to_expr!(irtoexpr::IrToExpr, e::Expr, t)
    if e.head == :invoke
        return IRExpr(Symbol(e.args[1].def.name), map(e.args[3:end]) do x
                ir_to_expr!(irtoexpr, x)
            end, t)
    end

    return IRExpr(e.head, map(e.args) do x
            ir_to_expr!(irtoexpr, x)
        end, t)
end

struct ExprToIr
    instructions::Vector{Any}
    types::Vector{Type}
    ssa_start::Integer
    mod::Module

    ExprToIr(mod::Module, range::CC.StmtRange) = new([], [], range.start, mod)
end

function push_instr!(exprtoir::ExprToIr, instr, type)
    push!(exprtoir.instructions, instr)
    push!(exprtoir.types, type)
end

expr_to_ir!(_::ExprToIr, a::CC.Argument) = a
expr_to_ir!(_::ExprToIr, g::GlobalRef) = g
expr_to_ir!(_::ExprToIr, s::String) = s

function expr_to_ir!(exprtoir::ExprToIr, expr::IRExpr)
    if expr.head == :theta
        for e in expr.args
            expr_to_ir!(exprtoir, e)
        end
        return (exprtoir.instructions, exprtoir.types)
    end

    if expr.head == :ret
        val = expr_to_ir!(exprtoir, expr.args[1])
        push_instr!(exprtoir, CC.ReturnNode(val), expr.type)
        return
    end

    func_name = expr.head
    args = map(expr.args) do x
        expr_to_ir!(exprtoir, x)
    end

    method = GlobalRef(exprtoir.mod, Symbol(func_name))
    push_instr!(exprtoir, Expr(:call, method, args...), expr.type)

    return SSAValue(length(exprtoir.instructions) + exprtoir.ssa_start - 1)
end