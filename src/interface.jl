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

    match, _ = CC._findsup(sig, nothing, world)
    match === nothing && throw(MethodError(ft, tt, world))
    mi = CC.specialize_method(match)

    wvc = CC.code_cache(interp)

    cached = CC.get(wvc, mi, nothing)
    if cached !== nothing
        src = @atomic :monotonic cached.inferred
        if isa(src, String)
            src = CC._uncompressed_ir(mi.def, src)
        else
            isa(src, CC.CodeInfo) || return nothing
        end
        ir = CC.inflate_ir(src, mi)
        return OpaqueClosure(ir)
    end

    inferred = CC.typeinf_ext_toplevel(interp, mi)
    return OpaqueClosure(inferred)
end
