"""
    cleanup_wrappers!(ir::IRCode, interp::CustomInterpreter)

Mark calls to wrapper functions using `IR_FLAG_INLINE`. This ensures they
will be inlined by the next inlining pass. As the wrapper just contains a
single call to the implementation function, this results in the call to
the wrapper being replaced by the implementation method.
"""
function cleanup_wrappers!(ir::IRCode, _::CC.CodeInfo, sv::CC.OptimizationState)
    # Track if we made any changes to prevent unnecessary compact pass
    made_changes = false

    candidate_methods = keys(sv.inlining.interp.code_cache.dict)

    cache = IdDict{}()

    # Iterate over every instruction
    for (i, instruction) in enumerate(ir.stmts.stmt)
        # Continue if current instruction is not an invoke
        Meta.isexpr(instruction, :invoke) || continue

        # Get a reference to the method defintion for this invoke
        call_def = instruction.args[begin].def

        # Get the name of the implementation method
        impl_func_name = get_impl_function_name(call_def.name)

        is_cleanupable = false

        # Check if we already encountered a call to this function 
        if haskey(cache, call_def)
            is_cleanupable = cache[call_def]
        else
            # Otherwise, look for it in the candidate methods 
            for mi in candidate_methods
                if mi.def.name == impl_func_name && mi.def.module == call_def.module
                    is_cleanupable = true
                end
            end

            # Cache the result
            cache[call_def] = is_cleanupable
        end

        # If the function can't be cleaned up, continue to the next instruction
        is_cleanupable == false && continue

        # Mark the wrapper method as force-inline
        ir.stmts.flag[i] |= CC.IR_FLAG_INLINE
        made_changes = true

        @debug "Cleaned up wrapper call `" * string(call_def.name) * "` to `" * string(impl_func_name) * "`"
    end

    return ir, made_changes
end
