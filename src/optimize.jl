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

    made_changes = false

    for (i, instruction) in enumerate(instructions)
        if is_invoke(instruction, Symbol(:add))
            arg1 = instruction.args[3]
            arg2 = instruction.args[4]

            if arg2 isa SSAValue
                instruction2 = instructions[arg2.id]
                if is_invoke(instruction2, Symbol(:mul))
                    @info "Found add and mul invocation"

                    ltype = ir.stmts.type[arg2.id]

                    m = methods(Main.add_mul, Tuple{ltype,ltype,ltype}) |> first
                    mi = Core.Compiler.specialize_method(m, Tuple{ltype,ltype,ltype,ltype}, Core.svec())

                    instructions[i] = Expr(
                        :invoke,
                        mi,
                        Main.add_mul,
                        arg1,
                        instruction2.args[3],
                        instruction2.args[4])

                    markdead!(ir, arg2.id)

                    made_changes = true

                    @info "Rewrote to add_mul"
                end
            end
        end

        if is_invoke(instruction, Symbol(:add_mul))
            @info "Found add_mul invocation"

            ltype = ir.stmts.type[1]

            m = methods(Main.add_mul2, Tuple{ltype,ltype,ltype}) |> first
            mi = Core.Compiler.specialize_method(m, Tuple{ltype,ltype,ltype,ltype}, Core.svec())

            instructions[i].args[1] = mi
            instructions[i].args[2] = Main.add_mul2

            made_changes = true

            @info "Rewrote to add_mul2"
        end
    end

    return ir, made_changes
end
