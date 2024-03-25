using .Core.Compiler: naive_idoms, IRCode, Argument

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

function perform_rewrites!(ir::IRCode, rewrite_rules::Vector{RewriteRule})
    instructions = instrs(ir)

    for (i, instruction) in enumerate(instructions)
        for rule in rewrite_rules
            if rule(ir, instructions, instruction, i)
                return ir, true
            end
        end
    end

    return ir, false
end
