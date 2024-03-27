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


function EGraphs.egraph_reconstruct_expression(::Type{IRExpr}, op, args; metadata = nothing, exprhead = nothing)
    IRExpr(op, args)
end

function perform_rewrites!(ir::IRCode, rewrite_rules::Vector{RewriteRule})
    instructions = instrs(ir)

    # cfg = CC.compute_basic_blocks(instructions)

    # println(ir)

    # for (i, block) in enumerate(cfg.blocks)
    #     @info "Processing block $i"

    #     irexpr = ircode_to_irexpr(instructions, block.stmts)
    #     # println(irexpr)

    #     g = EGraph(irexpr)
    #     settermtype!(g, IRExpr)

    #     t = @theory a b c begin
    #         add(a, mul(b, c)) --> add_mul(a, b, c)
    #     end

    #     saturate!(g, t)

    #     result = extract!(g, astsize)
    #     println(result)

    #     optimized_instr = []
    #     irexpr_to_ircode!(result, optimized_instr, block.stmts.start)
        
    #     size(optimized_instr) < size(block.stmts) || error("Rewrite rule did not reduce the size of the block")

    #     println("Instructions ", optimized_instr)
    #     for (i, instr) in enumerate(optimized_instr)
    #         instructions[i + block.stmts.start] = instr
    #     end

    #     println(ir)
    # end

    for (i, instruction) in enumerate(instructions)
        for rule in rewrite_rules
            if rule(ir, instructions, instruction, i)
                return ir, true
            end
        end
    end

    return ir, false
end
