function replace_compbarrier_calls!(ir::IRCode, _::CC.CodeInfo, _::CC.OptimizationState)
    instructions = instrs(ir)

    made_changes = false

    symbols = [:add, :mul]

    for (i, instruction) in enumerate(instructions)
        for symbol in symbols
            if is_invoke(instruction, Symbol(symbol))
                params = instruction.args[begin].def.sig.parameters[begin+1:end]
                ret_type = ir.stmts.type[i]
        
                impl_ref = GlobalRef(Main, Symbol("impl_", symbol))

                m = methods(eval(impl_ref), params) |> first
                mi = Core.Compiler.specialize_method(m, Tuple{params..., ret_type}, Core.svec())

                instruction.args[1] = mi
                instruction.args[2] = impl_ref

                made_changes = true
            end
        end
    end

    return ir, made_changes
end