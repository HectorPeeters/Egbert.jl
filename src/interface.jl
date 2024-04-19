using .Core: OpaqueClosure, SSAValue

const global_ci_cache = CodeCache()

"""
    custom(rules, ex::Expr)

Execute a function call using the e-graph optimization pipeline.
"""
# TODO: this macro should get a better name
macro custom(options, rules, ex::Expr)
    Meta.isexpr(ex, :call) || error("not a function call")
    f, args... = ex.args

    quote
        f = $(esc(f))
        @assert sizeof(f) == 0 "OpaqueClosures have different semantics wrt. captures, and cannot be used to implement closures with an environment"
        args = ($(map(esc, args)...),)

        ft = typeof(f)
        types = map(typeof, args)
        rules = $(esc(rules))
        options = $(esc(options))
        obj = custom_compiler(ft, types, options, rules)

        obj(args...)
    end
end

"""
    custom_compiler(ft, types, rules)

Compile a function using the e-graph optimization pipeline.
"""
function custom_compiler(ft, types, options::Options, rules::Any)
    tt = Tuple{types...}
    sig = Tuple{ft,types...}
    world = Base.get_world_counter()

    interp = CustomInterpreter(world;
        code_cache=global_ci_cache,
        inf_params=CC.InferenceParams(),
        opt_params=CC.OptimizationParams(),
        options=options,
        rules=rules)

    # Trigger the optimization pipeline
    irs = Base.code_ircode_by_type(sig; interp)
    isempty(irs) && throw(MethodError(ft, tt, world))

    ir, _ = only(irs)

    OpaqueClosure(ir)
end
