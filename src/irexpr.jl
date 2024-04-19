using TermInterface
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
    order::Union{Nothing,Integer}
end

function Base.:(==)(a::IRExpr, b::IRExpr)
    a.head == b.head && a.args == b.args
end

TermInterface.istree(e::IRExpr) = true
TermInterface.operation(e::IRExpr) = e.head
TermInterface.exprhead(::IRExpr) = :call
TermInterface.arguments(e::IRExpr) = e.args
TermInterface.metadata(e::IRExpr) = (type=e.type, order=e.order)

function TermInterface.similarterm(
    x::IRExpr, head, args;
    metadata=nothing, exprhead=:call
)
    if metadata !== nothing
        IRExpr(head, args, metadata.type, metadata.order)
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
        IRExpr(op, args, metadata.type, metadata.order)
    else
        IRExpr(op, args, nothing, nothing)
    end
end

function EGraphs.make(::Val{:metadata_analysis}, g, n)
    return (type=Any, order=nothing)
end

function EGraphs.join(::Val{:metadata_analysis}, a, b)
    order = nothing
    if a.order !== nothing
        if b.order !== nothing
            order = min(a.order, b.order)
        else
            order = a.order
        end
    elseif b.order !== nothing
        order = b.order
    end

    a.type != b.type && error("Types do not match")
    return (type=a.type, order=order)
end

mutable struct IrToExpr
    instructions::Vector{Any}
    types::Vector{Any}
    flags::Vector{Any}
    range::CC.StmtRange
    converted::Vector{Bool}
    ssa_index::Integer
    # NOTE: This value is used to order arguments in a function call in cases
    #       like this: add(a, add(b, c)) --> add3(b, c, a)
    #       The order in which the IR for the arguments is generated is
    #       important. It should still be `a, b, c` even though the order
    #       of the arguments is now `b, c, a`.
    current_index::Integer
    has_sideeffects::Bool

    IrToExpr(instrs::CC.InstructionStream, range::CC.StmtRange) = new(
        instrs.stmt,
        instrs.type,
        instrs.flag,
        range,
        fill(false, length(instrs.stmt)),
        1,
        0,
        false
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

    return IRExpr(:theta, reverse(toplevel_exprs), nothing, nothing)
end

function ir_to_expr!(irtoexpr::IrToExpr, s::CC.SSAValue)
    irtoexpr.current_index = s.id

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

function ir_to_expr!(irtoexpr::IrToExpr, p::CC.PiNode, t)
    return IRExpr(
        :pi,
        [ir_to_expr!(irtoexpr, p.val)],
        p.typ,
        irtoexpr.current_index
    )
end

function ir_to_expr!(irtoexpr::IrToExpr, r::CC.ReturnNode, t)
    return IRExpr(
        :ret,
        [ir_to_expr!(irtoexpr, r.val)],
        t,
        irtoexpr.current_index
    )
end

function ir_to_expr!(irtoexpr::IrToExpr, e::Expr, t)
    if e.head == :invoke
        flags = irtoexpr.flags[irtoexpr.current_index]
        effect_free = CC.has_flag(flags, CC.IR_FLAG_EFFECT_FREE)
        irtoexpr.has_sideeffects |= !effect_free

        return IRExpr(
            Symbol(e.args[1].def.name),
            map(enumerate(e.args[3:end])) do (i, x)
                ir_to_expr!(irtoexpr, x)
            end,
            t,
            irtoexpr.current_index
        )
    end

    return IRExpr(
        e.head,
        map(enumerate(e.args)) do (i, x)
            ir_to_expr!(irtoexpr, x)
        end,
        t,
        irtoexpr.current_index
    )
end

struct ExprToIr
    instructions::Vector{Any}
    types::Vector{Any}
    ssa_start::Integer
    mod::Module
    cse_env::OrderedDict{Symbol,CC.SSAValue}

    ExprToIr(mod::Module, range::CC.StmtRange) = new(
        [], [], range.start, mod, OrderedDict())
end

function push_instr!(exprtoir::ExprToIr, instr, type)
    push!(exprtoir.instructions, instr)
    if type === nothing
        push!(exprtoir.types, Any)
    else
        push!(exprtoir.types, type)
    end
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

function last_ssa_id(exprtoir::ExprToIr)
    return SSAValue(length(exprtoir.instructions) + exprtoir.ssa_start - 1)
end

"""
    convert_sorted_args!(exprtoir::ExprToIr, args::Vector{Any})

Emits the instructions for the arguments of an expression in the order
determined by the order field of each argument. This ensures that the arguments
are emitted in the correct order, even when an e-graph optimization has
reordered the arguments.
"""
function convert_sorted_args!(exprtoir::ExprToIr, args::Vector{Any})
    result::Vector{Any} = fill(missing, length(args))
    low = typemin(Int32)

    for _ in 1:length(args)
        # Start at the first index we haven't converted yet
        next_index = findfirst(x -> x === missing, result)

        for (j, arg) in enumerate(args)
            # Skip arguments we've already converted
            result[j] !== missing && continue

            # If the argument doesn't have an order, emit next
            if !isa(arg, IRExpr) || arg.order === nothing
                next_index = j
                break
            end

            # Skip arguments with an order lower than the current low
            arg.order < low && continue

            # If the argument has a lower order than the current next_index
            # update it
            if arg.order < args[next_index].order
                next_index = j
            end
        end

        # Update our low order if the current argument has an order
        if args[next_index] isa Expr
            low = args[next_index].order
        end

        # Emit the argument
        result[next_index] = expr_to_ir!(exprtoir, args[next_index])
    end

    return result
end

function expr_to_ir!(exprtoir::ExprToIr, expr::IRExpr)
    if expr.head == :theta
        convert_sorted_args!(exprtoir, expr.args)

        return (exprtoir.instructions, exprtoir.types)
    end

    if expr.head == :ret
        val = expr_to_ir!(exprtoir, expr.args[1])
        push_instr!(exprtoir, CC.ReturnNode(val), expr.type)
        return
    end

    if expr.head == :pi
        val = expr_to_ir!(exprtoir, expr.args[1])
        push_instr!(exprtoir, CC.PiNode(val, expr.type), expr.type)
        return last_ssa_id(exprtoir)
    end

    if expr.head == :call
        func = expr_to_ir!(exprtoir, expr.args[1])
        args = convert_sorted_args!(exprtoir, expr.args[2:end])
        push_instr!(exprtoir, Expr(:call, func, args...), expr.type)

        return last_ssa_id(exprtoir)
    end

    func_name = expr.head
    args = convert_sorted_args!(exprtoir, expr.args)
    method = GlobalRef(exprtoir.mod, Symbol(func_name))

    push_instr!(exprtoir, Expr(:call, method, args...), expr.type)

    return last_ssa_id(exprtoir)
end
