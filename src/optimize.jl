using .Core.Compiler: naive_idoms, IRCode, Argument
using Metatheory
using Metatheory.EGraphs

const RewriteRule = Function

"""
    instrs(ir::IRCode)

Get the instructions from an IRCode object.
"""
@inline function instrs(ir::IRCode)
    @static if VERSION > v"1.10.0"
        return ir.stmts.stmt
    else
        return ir.stmts.inst
    end
end

"""
    is_call(instr, name)

Check if an instruction is an call instruction with a
specific name.
"""
function is_call(instr, fname)
    return Meta.isexpr(instr, :call) &&
           instr.args[begin] isa GlobalRef &&
           instr.args[begin].name == fname
end

"""
    is_invoke(instr, name)

Check if an instruction is an invoke instruction with a
specific name.
"""
function is_invoke(instr, name)
    return Meta.isexpr(instr, :invoke) &&
           instr.args[begin].def.module == parentmodule(Module()) &&
           instr.args[begin].def.name == name
end

"""
    markdead!(ir::IRCode, id)

Mark an instruction as dead. It will be replaced by a load
of a `nothing` value. This will then later be removed by the
`compact` IR pass.
"""
function markdead!(ir::IRCode, id)
    # TODO: This is still somewhat flawed, computation of arguments
    #       for the removed call might not be necessary.
    instrs(ir)[id] = Main.nothing
    ir.stmts.type[id] = Core.Const(nothing)
end


function EGraphs.egraph_reconstruct_expression(::Type{IRExpr}, op, args; metadata=nothing, exprhead=nothing)
    IRExpr(op, args)
end

function perform_rewrites!(ir::IRCode, ci::CC.CodeInfo, rewrite_rules::Vector{RewriteRule})
    # TODO: remove this
    if ci.parent.def.module != Main || ci.parent.def.name != :optimizetarget
        return ir, false
    end

    instructions = instrs(ir)
    types = ir.stmts.type

    cfg = CC.compute_basic_blocks(instructions)

    if length(cfg.blocks) != 1
        @warn "Skipping function with multiple blocks: $(size(cfg.blocks))"
        return ir, false
    end

    # TODO: setting the IR_FLAG_REFINED might result in better code analysis

    made_changes = false

    for (i, block) in enumerate(cfg.blocks)
        @info "Processing block $i"

        irtoexpr = IrToExpr(instructions, block.stmts)
        irexpr = get_root_expr!(irtoexpr)

        g = EGraph(irexpr)
        settermtype!(g, IRExpr)

        t = @theory a b c begin
            add(a, mul(b, c)) --> add_mul(a, b, c)
        end

        saturate!(g, t)

        result = extract!(g, astsize)

        if result == irexpr
            continue
        end

        made_changes = true

        exprtoir = ExprToIr(ci.parent.def.module, block.stmts)
        optimized_instrs = expr_to_ir!(exprtoir, result)

        if length(optimized_instrs) > length(block.stmts)
            error("New block is larger than old block: ", size(block.stmts), " -> ", size(optimized_instrs))
        end

        for (i, instr) in enumerate(optimized_instrs)
            instructions[i+block.stmts.start-1] = instr
        end

        for i in length(optimized_instrs)+block.stmts.start:length(block.stmts)
            instructions[i] = nothing
            types[i] = nothing
        end
    end

    return ir, made_changes
end
