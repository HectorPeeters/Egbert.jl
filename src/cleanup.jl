"""
    is_invoke(instr, name)

Check if an instruction is an invoke instruction with a specific name.
"""
function is_invoke(instr, name)
    return Meta.isexpr(instr, :invoke) &&
           instr.args[begin].def.module == parentmodule(Module()) &&
           instr.args[begin].def.name == name
end

"""
    replace_compbarrier_calls!(ir::IRCode, interp::CustomInterpreter)

Replace calls to compilerbarrier wrapper methods with the actual
implementation. This removes the additional indirection in cases where
@rewritetarget functions were not optimized.
"""
function replace_compbarrier_calls!(ir::IRCode, ci::CC.CodeInfo, sv::CC.OptimizationState)
    interp = sv.inlining.interp

    # List of all compilerbarrier wrapper methods
    wrapper_methods = []

    # Loop over all method instances in the code cache
    for (mi, cis) in interp.code_cache.dict
        for ci in cis
            ci = ci.inferred
            if ci isa Nothing
                continue
            end

            if ci isa String
                ci = CC._uncompressed_ir(mi.def, ci)
            end

            first_instr = ci.code[begin]

            # Check if the method starts with a call to `Base.compilerbarrier`
            if first_instr isa Expr &&
               first_instr.head == :invoke &&
               get_impl_function_name(mi.def.name) == first_instr.args[begin].def.name
                push!(wrapper_methods, mi)
                break

            end
        end
    end

    # Track if we made any changes to prevent unnecessary compact pass
    made_changes = false

    for (i, instruction) in enumerate(ir.stmts.stmt)
        for method in wrapper_methods

            # If we call one of the compilerbarrier wrapper methods, replace it with the actual method
            if is_invoke(instruction, Symbol(method.def.name))
                params = instruction.args[begin].def.sig.parameters[begin+1:end]
                ret_type = ir.stmts.type[i]
                if ret_type isa Core.Const
                    ret_type = typeof(ret_type.val)
                elseif ret_type isa Core.PartialStruct
                    ret_type = ret_type.typ
                end

                ir.stmts.type[i] = ret_type

                # Get a reference to the actual implementation
                impl_func_name = get_impl_function_name(method.def.name)
                # println(method.def.name)
                # println(impl_func_name)

                impl_ref = GlobalRef(method.def.module, impl_func_name)

                m = methods(eval(impl_ref), params) |> first
                mi = Core.Compiler.specialize_method(m, Tuple{ret_type,params...}, Core.svec())

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
