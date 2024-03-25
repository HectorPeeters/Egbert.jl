function replace_compbarrier_calls!(ir::IRCode, interp::CustomInterpreter)
    methods = []

    for (mi, cis) in interp.code_cache.dict
        for ci in cis
            ci = ci.inferred

            if ci.code[begin].head == :call &&
                ci.code[begin].args[begin] == GlobalRef(Base, :compilerbarrier)
                push!(methods, mi)
                break
            end
        end
    end

    instructions = instrs(ir)

    made_changes = false

    for instruction in instructions
        for method in methods
            if is_invoke(instruction, Symbol(method.def.name))        
                impl_ref = GlobalRef(method.def.module, Symbol("impl_", method.def.name))

                instruction.args[1] = method
                instruction.args[2] = impl_ref

                @info "Cleaned up wrapper call `" * string(method.def.name) * "`` to `" * string(impl_ref.name) * "`"

                made_changes = true
            end
        end
    end

    return ir, made_changes
end