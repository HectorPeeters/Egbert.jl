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
        types = map(args) do x
            if x isa Symbol || x isa Expr
                typeof(eval(x))
            else
                typeof(x)
            end
        end
        obj = custom_compiler(ft, types)

        obj(args...)
    end
end

function custom_compiler(ft, types)
    tt = Tuple{types...}
    sig = Tuple{ft,types...}
    world = Base.get_world_counter()

    interp = CustomInterpreter(world;
        code_cache=global_ci_cache,
        inf_params=CC.InferenceParams(),
        opt_params=CC.OptimizationParams())

    irs = Base.code_ircode_by_type(sig; interp)
    if isempty(irs)
        throw(MethodError(ft, tt, world))
    end

    # show(interp.code_cache)

    ir, ret = only(irs)

    OpaqueClosure(ir)
end
