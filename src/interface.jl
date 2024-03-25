using .Core: OpaqueClosure, SSAValue

const global_ci_cache = CodeCache()

macro custom(rules, ex::Expr)
    Meta.isexpr(ex, :call) || error("not a function call")
    f, args... = ex.args

    quote
        f = $(esc(f))
        @assert sizeof(f) == 0 "OpaqueClosures have different semantics wrt. captures, and cannot be used to implement closures with an environment"
        args = ($(map(esc, args)...),)

        ft = typeof(f)
        types = map(typeof, args)
        rules::Vector{RewriteRule} = $(esc(rules))
        obj = custom_compiler(ft, types, rules)

        obj(args...)
    end
end

function custom_compiler(ft, types, rewrite_rules::Vector{RewriteRule})
    tt = Tuple{types...}
    sig = Tuple{ft,types...}
    world = Base.get_world_counter()

    interp = CustomInterpreter(world;
        # NOTE: Lets use a new cache for every invocation, makes it easier 
        #       for debugging. Afterwards, the global_ci_cache can be used.
        code_cache=CodeCache(),
        inf_params=CC.InferenceParams(),
        opt_params=CC.OptimizationParams(),
        rewrite_rules=rewrite_rules)

    # Trigger the optimization pipeline
    irs = Base.code_ircode_by_type(sig; interp)
    isempty(irs) && throw(MethodError(ft, tt, world))

    ir, _ = only(irs)

    OpaqueClosure(ir)
end
