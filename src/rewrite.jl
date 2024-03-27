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

function TermInterface.similarterm(x::IRExpr, head, args; metadata=nothing, exprhead = :call)
    IRExpr(head, args)
end

# function EGraphs.egraph_reconstruct_expression(::Type{IRExpr}, op, args; metadata = nothing, exprhead = nothing)
#   IRExpr(op, args, metadata)
# end

function ircode_to_irexpr(instructions, range::CC.StmtRange, s::CC.SSAValue)
    if s.id < range.start || s.id > range.stop
        return s
    end

    return ircode_to_irexpr(instructions, range, instructions[s.id])
end

ircode_to_irexpr(instructions, range::CC.StmtRange, a::CC.Argument) = a
ircode_to_irexpr(instructions, range::CC.StmtRange, q::QuoteNode) = q
ircode_to_irexpr(instructions, range::CC.StmtRange, m::MethodInstance) = m
ircode_to_irexpr(instructions, range::CC.StmtRange, r::GlobalRef) = r

function ircode_to_irexpr(instructions, range::CC.StmtRange, p::CC.PiNode)
    return IRExpr(:pi, [ircode_to_irexpr(instructions, range, p.val), p.typ])
end

function ircode_to_irexpr(instructions, range::CC.StmtRange, r::CC.ReturnNode)
    return IRExpr(:return, [ircode_to_irexpr(instructions, range,r.val)])
end

function ircode_to_irexpr(instructions, range::CC.StmtRange, e::Expr)
    if e.head == :invoke
        method = ircode_to_irexpr(instructions, range, e.args[2])
        return IRExpr(method.name, map(e.args[3:end]) do x
            return ircode_to_irexpr(instructions, range, x)
        end)
    elseif e.head == :call
        method = eval(ircode_to_irexpr(instructions, range, e.args[1]))
        return IRExpr(method, map(e.args[2:end]) do x
            return ircode_to_irexpr(instructions, range, x)
        end)
    end

    return IRExpr(e.head, map(e.args) do x
        return ircode_to_irexpr(instructions, range, x)
    end)
end

function ircode_to_irexpr(instructions, range::CC.StmtRange, idx::Integer)
    return ircode_to_irexpr(instructions, range, instructions[idx])
end

function ircode_to_irexpr(instructions, range::CC.StmtRange)
    return ircode_to_irexpr(instructions, range, instructions[range.stop])
end

function irexpr_to_ircode!(expr, instrs::Vector{Any}, ssa_index::Integer=0)
    expr isa CC.Argument && return expr
    expr isa CC.DataType && return expr
    expr isa CC.QuoteNode && return expr
    expr isa CC.GlobalRef && return expr
    expr isa typeof(CC.compilerbarrier) && return expr
    
    if expr.head == :return
        val = irexpr_to_ircode!(expr.args[1], instrs, ssa_index)
        push!(instrs, CC.ReturnNode(val))
        return
    end

    if expr.head == :pi
        val = irexpr_to_ircode!(expr.args[1], instrs, ssa_index)
        push!(instrs, CC.PiNode(val, expr.args[2]))
        ssa_index+=1
        return SSAValue(ssa_index)
    end

    method = irexpr_to_ircode!(expr.head, instrs, ssa_index)

    mapped_args = []
    for arg in expr.args
        val = irexpr_to_ircode!(arg, instrs, ssa_index)
        push!(mapped_args, val)
    end

    push!(instrs, Expr(:invoke, method, mapped_args...))
    return SSAValue(ssa_index + 1)
end