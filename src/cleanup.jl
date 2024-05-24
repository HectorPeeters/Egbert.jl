"""
    cleanup_wrappers!(ir::IRCode, interp::CustomInterpreter)

Mark calls to wrapper functions using `IR_FLAG_INLINE`. This ensures they
will be inlined by the next inlining pass. As the wrapper just contains a
single call to the implementation function, this results in the call to
the wrapper being replaced by the implementation method.
"""
function cleanup_wrappers!(ir::IRCode, ci::CC.CodeInfo, sv::CC.OptimizationState)
    # Track if we made any changes to prevent unnecessary compact pass
    made_changes = false

    # Iterate over every instruction
    for (i, instruction) in enumerate(ir.stmts.stmt)

        for (method, _) in sv.inlining.interp.code_cache.dict

            # If we call one of the compilerbarrier wrapper methods, replace it with the actual method
            if Meta.isexpr(instruction, :invoke)
                call_def =  instruction.args[begin].def

                # Get the name of the implementation method
                impl_func_name = get_impl_function_name(call_def.name)

                if impl_func_name != method.def.name || method.def.module != call_def.module
                    continue
                end

                # Mark the wrapper method as force-inline
                ir.stmts.flag[i] |= CC.IR_FLAG_INLINE
                made_changes = true

                @debug "Cleaned up wrapper call `" * string(call_def.name) * "` to `" * string(impl_ref.name) * "`"

                break
            end
        end
    end

    return ir, made_changes
end
