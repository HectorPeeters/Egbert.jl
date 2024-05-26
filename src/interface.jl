using .Core: OpaqueClosure, SSAValue

const global_ci_cache = CodeCache()

const closure_cache = Dict{Tuple{UInt,DataType},OpaqueClosure}()

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
        types = map(typeof, args)

        options = $(esc(options))

        sig = CC.signature_type(f, types)
        world = Base.get_world_counter()

        cache_entry = get(closure_cache, (world, sig), nothing)
        closure = if cache_entry !== nothing && options.enable_caching
            cache_entry
        else
            rules = $(esc(rules))

            obj = custom_compiler(f, types, world, options, rules)
            closure_cache[(world, sig)] = obj
            obj
        end

        if options.dont_run
            () -> closure(args...)
        else
            closure(args...)
        end
    end
end

"""
    custom_compiler(ft, tt, world, options, rules)

Compile a function using the e-graph optimization pipeline.
"""
function custom_compiler(ft, tt, world, options::Options, rules::Any)
    interp = CustomInterpreter(world;
        code_cache=global_ci_cache,
        inf_params=CC.InferenceParams(),
        opt_params=CC.OptimizationParams(),
        options=options,
        rules=rules)

    sig = CC.signature_type(ft, tt)

    if !options.enable_caching
        irs = Base.code_ircode_by_type(sig; interp)
        isempty(irs) && throw(MethodError(ft, tt, world))
        ir, _ = only(irs)
        return OpaqueClosure(ir)
    end

    match, _ = CC._findsup(sig, nothing, world)
    match === nothing && throw(MethodError(ft, tt, world))
    mi = CC.specialize_method(match)

    inferred = CC.typeinf_ext_toplevel(interp, mi)
    return OpaqueClosure(inferred)
end
