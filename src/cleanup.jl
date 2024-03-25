function replace_compbarrier_calls!(ir::IRCode, ci, sv::OptimizationState)
    instructions = instrs(ir)

    made_changes = false

    for (i, instruction) in enumerate(instructions)
        if is_invoke(instruction, Symbol(:add))
            ltype = ir.stmts.type[1]

            m = methods(Main.impl_add, Tuple{ltype,ltype}) |> first
            mi = Core.Compiler.specialize_method(m, Tuple{ltype,ltype,ltype}, Core.svec())

            instructions[i].args[1] = mi
            instructions[i].args[2] = GlobalRef(Main, :impl_add)
        end
    end

    return ir, made_changes
end