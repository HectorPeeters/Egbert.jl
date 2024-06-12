using Metatheory.EGraphs
using DataStructures: OrderedDict

struct MetadataAnalysis
    type::Any
    mod::Union{Symbol,Unknown,Nothing}
end

function EGraphs.make(g::EGraph{ExpressionType,MetadataAnalysis}, n::IRExpr) where {ExpressionType}
    return (type=Any, mod=Unknown())
end

function EGraphs.join(::Val{:metadata_analysis}, a, b)
    mod = Unknown()
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
        if has_effects(irtoexpr, i)
            if irtoexpr.instructions[i] === nothing
                continue
            end

            expr = ir_to_expr!(irtoexpr, CC.SSAValue(i))
            push!(sideeffect_exprs, expr)
        end
    end

    return AlphaExpr(sideeffect_exprs)
end

function ir_to_expr!(irtoexpr::IrToExpr, s::CC.SSAValue)
    old_ssa_index = irtoexpr.ssa_index
    irtoexpr.ssa_index = s.id

    if s.id < irtoexpr.range.start || s.id > irtoexpr.range.stop
        return s
    end

    markinstruction!(irtoexpr, s.id)
    result = ir_to_expr!(
        irtoexpr,
        irtoexpr.instructions[s.id],
        irtoexpr.types[s.id]
    )

    irtoexpr.ssa_index = old_ssa_index
    return result
end

ir_to_expr!(::IrToExpr, r::GlobalRef, _) = r
ir_to_expr!(::IrToExpr, x) = x

function ir_to_expr!(irtoexpr::IrToExpr, r::CC.ReturnNode, t)
    if isdefined(r, :val)
        return ReturnExpr(ir_to_expr!(irtoexpr, r.val))
    end

    return IRExpr(nothing)
end

function has_effects(irtoexpr::IrToExpr, i)
    flags = irtoexpr.flags[i]
    !CC.has_flag(flags, CC.IR_FLAG_EFFECT_FREE)
end

function ir_to_expr!(irtoexpr::IrToExpr, e::Expr, t)
    if e.head == :invoke
        args = [
            Symbol(e.args[1].def.name),
            map(enumerate(e.args[3:end])) do (i, x)
                ir_to_expr!(irtoexpr, x)
            end...
        ]

        result = IRExpr(
            :call,
            args,
            t,
            Symbol(e.args[1].def.module)
        )

        if has_effects(irtoexpr, irtoexpr.ssa_index)
            result = EffectExpr(result, irtoexpr.ssa_index)
        end

        return result
    end

    if e.head == :new
        return NewExpr(
            map(enumerate(e.args[1:end])) do (i, x)
                ir_to_expr!(irtoexpr, x)
            end
        )
    end

    if e.head == :foreigncall
        # TODO: evaluate expression inside
        return IRExpr(
            :foreigncall,
            [e, irtoexpr.ssa_index],
            nothing,
            nothing
        )
    end

    if e.head == :boundscheck
        return IRExpr(
            :boundscheck,
            [e, irtoexpr.ssa_index],
            nothing,
            nothing
        )
    end

    if e.head == :call
        method = ir_to_expr!(irtoexpr, e.args[1])

        result = if method isa GlobalRef
            IRExpr(
                :call,
                [
                    method.name,
                    map(enumerate(e.args[2:end])) do (i, x)
                        ir_to_expr!(irtoexpr, x)
                    end...
                ],
                t,
                Symbol(method.mod)
            )
        else
            IRExpr(
                :call,
                [
                    e.args[1],
                    map(enumerate(e.args[2:end])) do (i, x)
                        ir_to_expr!(irtoexpr, x)
                    end...
                ],
                t,
                nothing
            )
        end

        if has_effects(irtoexpr, irtoexpr.ssa_index)
            result = EffectExpr(result, irtoexpr.ssa_index)
        end

        return result
    end

    error("Unknown expression: ", e)
end

struct ExprToIr
    instructions::Vector{Any}
    source_ssa_ids::Vector{Any}
    types::Vector{Any}
    ssa_start::Integer
    mod::Module

    ExprToIr(mod::Module, range::CC.StmtRange) = new(
        [], [], [], range.start, mod)
end

function push_instr!(exprtoir::ExprToIr, instr, type, source_ssa_id=nothing)
    push!(exprtoir.instructions, instr)

    if type === nothing
        push!(exprtoir.types, Any)
    else
        push!(exprtoir.types, type)
    end

    push!(exprtoir.source_ssa_ids, source_ssa_id)

    return SSAValue(length(exprtoir.instructions) + exprtoir.ssa_start - 1)
end

expr_to_ir!(::ExprToIr, x) = x

function expr_to_ir!(exprtoir::ExprToIr, alpha::AlphaExpr; no_cse=false)
    for child in alpha.children
        expr_to_ir!(exprtoir, child)
    end
    return (exprtoir.instructions, exprtoir.types)
end

function expr_to_ir!(exprtoir::ExprToIr, ret::ReturnExpr; no_cse=false)
        # TODO: add return type
        if ret.value === nothing
            return push_instr!(exprtoir, CC.ReturnNode(), Any)
        end

        val = expr_to_ir!(exprtoir, ret.value)
        return push_instr!(exprtoir, CC.ReturnNode(val), Any)
end

function expr_to_ir!(exprtoir::ExprToIr, effect::EffectExpr; no_cse=false)
    index = findlast(x -> x == effect.index, exprtoir.source_ssa_ids)
    if index !== nothing
        return SSAValue(exprtoir.ssa_start + index - 1)
    end

    result = expr_to_ir!(exprtoir, effect.value, no_cse=true)
    exprtoir.source_ssa_ids[end] = effect.index
    return result
end

function expr_to_ir!(exprtoir::ExprToIr, expr::NewExpr; no_cse=false)
    args = map(a -> expr_to_ir!(exprtoir, a), expr.args)

    instruction = Expr(:new, args[1], args[2:end]...)

    index = findlast(x -> x == instruction, exprtoir.instructions)
    if index !== nothing && !no_cse
        return SSAValue(exprtoir.ssa_start + index - 1)
    end

    return push_instr!(exprtoir, instruction, expr.type)
end

function expr_to_ir!(exprtoir::ExprToIr, expr::IRExpr; no_cse=false)
    if expr.head == :foreigncall
        ssa_id = expr.args[2]
        return push_instr!(exprtoir, expr.args[1], expr.type; source_ssa_id=ssa_id)
    end

    if expr.head == :boundscheck
        ssa_id = expr.args[2]
        return push_instr!(exprtoir, expr.args[1], expr.type; source_ssa_id=ssa_id)
    end

    if expr.head == :call
        args = map(a -> expr_to_ir!(exprtoir, a), arguments(expr))

        op = first(children(expr))

        method = if expr.mod === nothing
            op
        elseif expr.mod isa Unknown
            GlobalRef(exprtoir.mod, Symbol(op))
        else
            GlobalRef(eval(expr.mod), Symbol(op))
        end

        instruction = Expr(expr.head, method, args...)

        index = findlast(x -> x == instruction, exprtoir.instructions)
        if index !== nothing && !no_cse
            return SSAValue(exprtoir.ssa_start + index - 1)
        end

        return push_instr!(exprtoir, instruction, expr.type)
    end

    error("TODO: ", expr.head)
end
