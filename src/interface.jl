using .Core: OpaqueClosure, SSAValue

"""
The global cache storing code instances for every compiled method instance.
"""
const global_ci_cache = CodeCache()


"""
A separate cache to store the compiled closures. This almost completely eliminates 
the overhead of using the custom abstract interpreter.
"""
const closure_cache = Dict{Tuple{UInt,DataType},OpaqueClosure}()


"""
    optimize(rules, ex::Expr)

Execute a function call using the e-graph optimization pipeline.
"""
# TODO: this macro should get a better name
macro optimize(options, rules, ex::Expr)
    Meta.isexpr(ex, :call) || error("Not a function call")
    f, args... = ex.args

    quote
        f = $(esc(f))
        @assert sizeof(f) == 0 "OpaqueClosures have different semantics wrt. captures, and cannot be used to implement closures with an environment"

        args = ($(map(esc, args)...),)
        types = map(typeof, args)
        options = $(esc(options))

        # Get the signature of the function to be compiled
        sig = CC.signature_type(f, types)
        world = Base.get_world_counter()

        # Check if the function is already in the closure cache
        cache_entry = get(closure_cache, (world, sig), nothing)
        closure = if cache_entry !== nothing && options.enable_caching
            cache_entry
        else
            rules = $(esc(rules))

            # Invoke the custom compiler
            obj = custom_compiler(f, types, world, options, rules)

            # Store the result in the closure cache
            closure_cache[(world, sig)] = obj

            obj
        end

        if options.dont_run
            # If we are not running the compiled closure, output a closure executing the closure
            () -> closure(args...)
        else
            # Execute the compiled closure
            closure(args...)
        end
    end
end


"""
    custom_compiler(ft, tt, world, options, rules)

Compile a function using the e-graph optimization pipeline.
"""
function custom_compiler(ft, tt, world, options::Options, rules::Any)
    # Create a new abstract interpreter
    interp = CustomInterpreter(world;
        code_cache=global_ci_cache,
        inf_params=CC.InferenceParams(),
        opt_params=CC.OptimizationParams(),
        options=options,
        rules=rules)

    sig = CC.signature_type(ft, tt)

    # If we don't use caching, use the original technique to trigger the compilation pipeline
    if !options.enable_caching
        irs = Base.code_ircode_by_type(sig; interp)
        isempty(irs) && throw(MethodError(ft, tt, world))
        ir, _ = only(irs)
        return OpaqueClosure(ir)
    end

    # Get the method instance for our function signature
    match, _ = CC._findsup(sig, nothing, world)
    match === nothing && throw(MethodError(ft, tt, world))
    mi = CC.specialize_method(match)

    # Trigger the compilation pipeline
    inferred = CC.typeinf_ext_toplevel(interp, mi)
    return OpaqueClosure(inferred)
end
