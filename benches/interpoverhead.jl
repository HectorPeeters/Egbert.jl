using GpuOptim: CodeCache
using BenchmarkTools: @btime
using Plots

const CC = Core.Compiler

const test_ci_cache = CodeCache()

mutable struct TestInterpreter <: CC.AbstractInterpreter
    world::UInt

    code_cache::CodeCache
    inf_cache::Vector{CC.InferenceResult}

    inf_params::CC.InferenceParams
    opt_params::CC.OptimizationParams

    frame_cache::Vector{CC.InferenceState}
    opt_pipeline::CC.PassManager

    function TestInterpreter(world::UInt;
        code_cache::CodeCache,
        inf_params::CC.InferenceParams,
        opt_params::CC.OptimizationParams)
        @assert world <= Base.get_world_counter()

        inf_cache = Vector{CC.InferenceResult}()

        frame_cache = Vector{CC.InferenceState}()
        opt_pipeline = CC.default_opt_pipeline()

        return new(
            world,
            code_cache,
            inf_cache,
            inf_params,
            opt_params,
            frame_cache,
            opt_pipeline,
        )
    end

end

CC.InferenceParams(interp::TestInterpreter) = interp.inf_params
CC.OptimizationParams(interp::TestInterpreter) = interp.opt_params
CC.get_inference_world(interp::TestInterpreter) = interp.world
CC.get_inference_cache(interp::TestInterpreter) = interp.inf_cache
CC.code_cache(interp::TestInterpreter) = CC.WorldView(interp.code_cache, interp.world)
CC.cache_owner(::TestInterpreter) = TestInterpreter

CC.build_opt_pipeline(interp::TestInterpreter) = interp.opt_pipeline

CC.lock_mi_inference(::TestInterpreter, ::CC.MethodInstance) = nothing
CC.unlock_mi_inference(::TestInterpreter, ::CC.MethodInstance) = nothing

function CC.add_remark!(::TestInterpreter, sv::CC.InferenceState, msg)
    @debug "Inference remark during compilation of $(sv.linfo): $msg"
end

CC.may_optimize(interp::TestInterpreter) = true
CC.may_compress(interp::TestInterpreter) = true
CC.may_discard_trees(interp::TestInterpreter) = true
CC.verbose_stmt_info(interp::TestInterpreter) = false

macro custom(ex::Expr)
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
    tt = Tuple{types...}
    sig = Tuple{ft,types...}
    world = Base.get_world_counter()

    interp = TestInterpreter(world;
        code_cache=test_ci_cache,
        inf_params=CC.InferenceParams(),
        opt_params=CC.OptimizationParams())

    match, _ = CC._findsup(sig, nothing, world)
    match === nothing && throw(MethodError(ft, tt, world))
    mi = CC.specialize_method(match)

    inferred = CC.typeinf_ext_toplevel(interp, mi)
    return Core.OpaqueClosure(inferred)
end

function fib(n)
    if n <= 1
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

xs = []
ys = []
ys_custom = []

for i in 1:34
    println("Running for n = ", i)
    push!(xs, i)
    push!(ys, @btime(fib($i)))
    push!(ys_custom, @btime(@custom fib($i)))
end

plot(xs, [ys, ys_custom])
