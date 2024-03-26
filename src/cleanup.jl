function replace_compbarrier_calls!(ir::IRCode, interp::CustomInterpreter)
    # List of all compilerbarrier wrapper methods
    wrapper_methods = []

    # Loop over all method instances in the code cache
    for (mi, cis) in interp.code_cache.dict
        for ci in cis
            ci = ci.inferred

            # Check if the method starts with a call to `Base.compilerbarrier`
            if ci.code[begin].head == :call &&
                ci.code[begin].args[begin] == GlobalRef(Base, :compilerbarrier)
                push!(wrapper_methods, mi)
                break
            end
        end
    end

    instructions = instrs(ir)

    made_changes = false

    for (i, instruction) in enumerate(instructions)
        for method in wrapper_methods

            # If we call one of the compilerbarrier wrapper methods, replace it with the actual method
            if is_invoke(instruction, Symbol(method.def.name))
                params = instruction.args[begin].def.sig.parameters[begin+1:end]
                ret_type = ir.stmts.type[i]

                # Get a reference to the actual implementation
                impl_func_name = get_impl_function_name(method.def.name)
                # println(method.def.name)
                # println(impl_func_name)

                impl_ref = GlobalRef(method.def.module, impl_func_name)

                m = methods(eval(impl_ref), params) |> first
                mi = Core.Compiler.specialize_method(m, Tuple{ret_type, params...}, Core.svec())

                # Replace the method instance and the 
                instruction.args[1] = mi
                instruction.args[2] = impl_ref

                @info "Cleaned up wrapper call `" * string(method.def.name) * "` to `" * string(impl_ref.name) * "`"

                made_changes = true
            end
        end
    end

    return ir, made_changes
end