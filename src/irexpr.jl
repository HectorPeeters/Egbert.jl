using Metatheory.TermInterface
using Metatheory.EGraphs
using DataStructures: OrderedDict

"""
    IRExpr

This struct represents the tree structure of an IRCode object. It is used to
perform e-graph optimizations on the IR code. The IRCode is converted to an
IRExpr object, which is then converted back to IRCode after optimizations.
"""
struct IRExpr
    head::Any
    args::Vector{Any}
    type::Any
    mod::Union{Symbol,Nothing}
end

function Base.:(==)(a::IRExpr, b::IRExpr)
    a.head == b.head && a.args == b.args
end

TermInterface.istree(::IRExpr) = true
TermInterface.operation(e::IRExpr) = e.head
TermInterface.exprhead(::IRExpr) = :call
TermInterface.arguments(e::IRExpr) = e.args
TermInterface.metadata(e::IRExpr) = (type=e.type, mod=e.mod)

function TermInterface.similarterm(
    ::IRExpr, head, args;
    metadata=nothing, exprhead=:call
)
    if metadata !== nothing
        IRExpr(head, args, metadata.type, metadata.mod)
    else
        IRExpr(head, args, nothing, nothing)
    end
end

function EGraphs.egraph_reconstruct_expression(
    ::Type{IRExpr}, op, args;
    metadata=nothing,
    exprhead=nothing
)
    if metadata !== nothing
        IRExpr(op, args, metadata.type, metadata.mod)
    else
        IRExpr(op, args, nothing, nothing)
    end
end

function EGraphs.make(::Val{:metadata_analysis}, g, n)
    return (type=Any, mod=nothing)
end

function EGraphs.join(::Val{:metadata_analysis}, a, b)
    mod = nothing
    if a.mod !== nothing
        if a.mod !== nothing
            a.mod != b.mod && error("Different modules")
        else
            mod = b.mod
        end
    elseif a.mod !== nothing
        mod = a.mod
    end

    type = typejoin(a.type, b.type)
    return (type=type, mod=mod)
end

mutable struct IrToExpr
    instructions::Vector{Any}
    types::Vector{Any}
    flags::Vector{Any}
    range::CC.StmtRange
    converted::Vector{Bool}
    ssa_index::Integer

    IrToExpr(instrs::CC.InstructionStream, range::CC.StmtRange) = new(
        instrs.stmt,
        instrs.type,
        instrs.flag,
        range,
        fill(false, length(instrs.stmt)),
        1
    )

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
    sideeffect_exprs = []

    for i in irtoexpr.range
        flags = irtoexpr.flags[i]

        if !CC.has_flag(flags, CC.IR_FLAG_EFFECT_FREE)
            if irtoexpr.instructions[i] === nothing
                continue
            end

            expr = ir_to_expr!(irtoexpr, CC.SSAValue(i))
            push!(sideeffect_exprs, expr)
        end
    end

    return IRExpr(:alpha, sideeffect_exprs, nothing, nothing)
end

function ir_to_expr!(irtoexpr::IrToExpr, s::CC.SSAValue)
    irtoexpr.ssa_index = s.id

    if s.id < irtoexpr.range.start || s.id > irtoexpr.range.stop
        return s
    end

    markinstruction!(irtoexpr, s.id)
    return ir_to_expr!(
        irtoexpr,
        irtoexpr.instructions[s.id],
        irtoexpr.types[s.id]
    )
end

ir_to_expr!(_::IrToExpr, x) = x

function ir_to_expr!(::IrToExpr, r::GlobalRef, t)
    return IRExpr(:ref, [r], GlobalRef, Symbol(r.mod))
end

function ir_to_expr!(irtoexpr::IrToExpr, r::CC.ReturnNode, t)
    if isdefined(r, :val)
        return IRExpr(
            :ret,
            [ir_to_expr!(irtoexpr, r.val)],
            t,
            nothing
        )
    end

    return IRExpr(
        :ret,
        [],
        t,
        nothing
    )
end

function ir_to_expr!(irtoexpr::IrToExpr, e::Expr, t)
    if e.head == :invoke
        flags = irtoexpr.flags[irtoexpr.ssa_index]
        has_effects = !CC.has_flag(flags, CC.IR_FLAG_EFFECT_FREE)

        if has_effects
            @debug "Function has effects: ", e.args[1].def.name
            return IRExpr(
                :__effect__,
                [e, irtoexpr.ssa_index],
                nothing,
                Symbol(e.args[1].def.module)
            )
        end

        return IRExpr(
            Symbol(e.args[1].def.name),
            map(enumerate(e.args[3:end])) do (i, x)
                ir_to_expr!(irtoexpr, x)
            end,
            t,
            Symbol(e.args[1].def.module)
        )
    end

    if e.head == :foreigncall
        return IRExpr(
            :__foreigncall__,
            [e, irtoexpr.ssa_index],
            nothing,
            nothing
        )
    end

    if e.head == :call || e.head == :new
        return IRExpr(
            e.args[1].name,
            map(enumerate(e.args[2:end])) do (i, x)
                ir_to_expr!(irtoexpr, x)
            end,
            t,
            Symbol(e.args[1].mod)
        )
    end

    if e.head == :boundscheck
        return IRExpr(
            :__boundscheck__,
            [e, irtoexpr.ssa_index],
            nothing,
            nothing
        )
    end

    error("Unknown expression: ", e)
end

struct ExprToIr
    instructions::Vector{Any}
    source_ssa_ids::Vector{Any}
    types::Vector{Any}
    ssa_start::Integer
    mod::Module
    cse_env::OrderedDict{Symbol,CC.SSAValue}

    ExprToIr(mod::Module, range::CC.StmtRange) = new(
        [], [], [], range.start, mod, OrderedDict())
end

function push_instr!(exprtoir::ExprToIr, instr, type; source_ssa_id=nothing)
    push!(exprtoir.instructions, instr)
    if type === nothing
        push!(exprtoir.types, Any)
    else
        push!(exprtoir.types, type)
    end
    push!(exprtoir.source_ssa_ids, source_ssa_id)
    return SSAValue(length(exprtoir.instructions) + exprtoir.ssa_start - 1)
end

expr_to_ir!(_::ExprToIr, x) = x

function expr_to_ir!(exprtoir::ExprToIr, s::Symbol)
    if !haskey(exprtoir.cse_env, s)
        @error "Symbol $s not found in CSE environment"
    end
    return exprtoir.cse_env[s]
end

function cse_expr_to_ir!(exprtoir::ExprToIr, sym::Symbol, expr::IRExpr)
    ssa_val = expr_to_ir!(exprtoir, expr)
    exprtoir.cse_env[sym] = ssa_val
end

function expr_to_ir!(exprtoir::ExprToIr, expr::IRExpr)
    if expr.head == :alpha
        for arg in expr.args
            expr_to_ir!(exprtoir, arg)
        end
        return (exprtoir.instructions, exprtoir.types)
    end

    if expr.head == :__effect__
        source_ssa_id = expr.args[2]

        index = findlast(x -> x == source_ssa_id, exprtoir.source_ssa_ids)
        if index !== nothing
            return SSAValue(exprtoir.ssa_start + index - 1)
        end

        return push_instr!(exprtoir, expr.args[1], expr.type; source_ssa_id=source_ssa_id)
    end

    if expr.head == :__foreigncall__
        source_ssa_id = expr.args[2]
        return push_instr!(exprtoir, expr.args[1], expr.type; source_ssa_id=source_ssa_id)
    end

    if expr.head == :__boundscheck__
        source_ssa_id = expr.args[2]
        return push_instr!(exprtoir, expr.args[1], expr.type; source_ssa_id=source_ssa_id)
    end

    if expr.head == :ret
        if length(expr.args) == 0
            return push_instr!(exprtoir, CC.ReturnNode(), expr.type)
        end

        val = expr_to_ir!(exprtoir, expr.args[1])
        return push_instr!(exprtoir, CC.ReturnNode(val), expr.type)
    end

    if expr.head == :ref
        return push_instr!(exprtoir, expr.args[1], expr.type)
    end

    args = map(a -> expr_to_ir!(exprtoir, a), expr.args)

    method = if expr.mod !== nothing
        GlobalRef(eval(expr.mod), Symbol(expr.head))
    else
        GlobalRef(exprtoir.mod, Symbol(expr.head))
    end

    instruction = Expr(:call, method, args...)

    index = findlast(x -> x == instruction, exprtoir.instructions)
    if index !== nothing
        return SSAValue(exprtoir.ssa_start + index - 1)
    end

    return push_instr!(exprtoir, instruction, expr.type)
end
