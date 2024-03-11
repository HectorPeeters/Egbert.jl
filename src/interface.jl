using .Core: OpaqueClosure, SSAValue

const global_ci_cache = CodeCache()

macro custom(ex)
    Meta.isexpr(ex, :call) || error("not a function call")
    f, args... = ex.args

    quote
        f = $(esc(f))
        @assert sizeof(f) == 0 "OpaqueClosures have different semantics wrt. captures, and cannot be used to implement closures with an environment"
        args = ($(map(esc, args)...),)

        ft = typeof(f)
        types = map(typeof, args)
        obj = custom_compiler(ft, types)

        obj(args...)
    end
end

function custom_compiler(ft, types)
    @info "START"

    tt = Tuple{types...}
    sig = Tuple{ft,types...}
    world = Base.get_world_counter()

    interp = CustomInterpreter(world;
        # NOTE: Lets use a new cache for every invocation, makes it easier 
        #       for debugging. Afterwards, the global_ci_cache can be used.
        code_cache=CodeCache(),
        inf_params=CC.InferenceParams(),
        opt_params=CC.OptimizationParams())

    irs = Base.code_ircode_by_type(sig; interp)
    isempty(irs) && throw(MethodError(ft, tt, world))

    # Switch the current pipeline from rewrite to cleanup
    interp.opt_pipeline = cleanup_opt_pipeline()

    # Perform second optimization pass
    for caller in interp.frame_cache
        opt = caller.result.src
        if opt isa OptimizationState
            CC.optimize(caller.interp, opt, caller.result)
        end
    end

    for caller in interp.frame_cache
        CC.finish!(caller.interp, caller)
        if CC.is_cached(caller)
            CC.cache_result!(caller.interp, caller.result)
        end
    end

    @info "END"

    only(irs) |> first |> OpaqueClosure
end
