using .Core.Compiler: naive_idoms, IRCode, Argument

@inline function instrs(ir)
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

function perform_rewrites!(ir::IRCode)
    instructions = instrs(ir)

    for (i, instruction) in enumerate(instructions)
        if is_invoke(instruction, Symbol(:add))
            println("Found add invocation")
            arg1 = instruction.args[3]
            arg2 = instruction.args[4]

            if arg2 isa SSAValue
                instruction2 = instructions[arg2.id]
                if is_invoke(instruction2, Symbol(:mul))
                    println("Found add_mul invocation")

                    ltype = ir.stmts.type[arg2.id]

                    m = first(methods(Main.add_mul, Tuple{ltype,ltype,ltype}))
                    mi = Core.Compiler.specialize_method(m, Tuple{ltype,ltype,ltype,ltype}, Core.svec())

                    instructions[i] = Expr(
                        :invoke,
                        mi,
                        Main.add_mul,
                        arg1,
                        instruction2.args[3],
                        instruction2.args[4])

                    markdead!(ir, arg2.id)

                    println("Rewrote to add_mul")
                end
            end
        end
    end

    return ir
end
