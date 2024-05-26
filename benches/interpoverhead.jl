using GpuOptim: CodeCache
using BenchmarkTools: @benchmark, mean
using CSV
using Tables
using Random

const CC = Core.Compiler

const test_ci_cache = CodeCache()
const code_cache = Dict{Tuple{UInt,DataType},Core.OpaqueClosure}()

struct TestInterpreterToken end

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
CC.cache_owner(::TestInterpreter) = TestInterpreterToken

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
        types = map(typeof, args)

        sig = CC.signature_type(f, types)
        world = Base.get_world_counter()

        cache_entry = get(code_cache, (world, sig), nothing)
        if cache_entry !== nothing
            cache_entry(args...)
        else
            obj = custom_compiler(sig, world)
            code_cache[(world, sig)] = obj
            obj(args...)
        end
    end
end

function custom_compiler(sig, world)
    interp = TestInterpreter(world;
        code_cache=test_ci_cache,
        inf_params=CC.InferenceParams(),
        opt_params=CC.OptimizationParams())

    match, _ = CC._findsup(sig, nothing, world)
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

function matmul(n)
    A = rand(n, n)
    B = rand(n, n)
    return A * B
end

function sortfunc(n::Int)
    xs = rand(n)
    return sort(xs)
end

function gcd(a::Int, b::Int)
    while a != b
        if a > b
            a -= b
        else
            b -= a
        end
    end

    return a
end

Random.seed!(1234)

name = []
normal = []
custom = []
normal_mem = []
custom_mem = []

println("Benchmarking fibonacci")
push!(name, "fibonacci")
normal_result = mean(@benchmark(fib($35)))
custom_result = mean(@benchmark(@custom fib($35)))
push!(normal, normal_result.time)
push!(custom, custom_result.time)
push!(normal_mem, normal_result.memory)
push!(custom_mem, custom_result.memory)

println("Benchmarking matmul")
push!(name, "matmul")
normal_result = mean(@benchmark(matmul($1024)))
custom_result = mean(@benchmark(@custom matmul($1024)))
push!(normal, normal_result.time)
push!(custom, custom_result.time)
push!(normal_mem, normal_result.memory)
push!(custom_mem, custom_result.memory)

println("Benchmarking sort")
push!(name, "sort")
normal_result = mean(@benchmark(sortfunc($1000000)))
custom_result = mean(@benchmark(@custom sortfunc($1000000)))
push!(normal, normal_result.time)
push!(custom, custom_result.time)
push!(normal_mem, normal_result.memory)
push!(custom_mem, custom_result.memory)

println("Benchmarking gcd")
push!(name, "gcd")
normal_result = mean(@benchmark(gcd($10000000, $9999999)))
custom_result = mean(@benchmark(@custom gcd($10000000, $9999999)))
push!(normal, normal_result.time)
push!(custom, custom_result.time)
push!(normal_mem, normal_result.memory)
push!(custom_mem, custom_result.memory)

CSV.write(
    "interp-overhead-means.csv",
    Tables.table(hcat(name, normal, custom, normal_mem, custom_mem)),
    header=["name", "normal-time", "custom-time", "normal-mem", "custom-mem"]
)

xs = []
ys = []
ys_custom = []

for i in 1:50
    println("Running for n = ", i)
    push!(xs, i)
    push!(ys, mean(@benchmark(fib($i))).time)
    push!(ys_custom, mean(@benchmark(@custom fib($i))).time)

    data = hcat(xs, ys, ys_custom)
    CSV.write("inter-overhead-fib.csv", Tables.table(data), header=["x", "y", "y-custom"])
end
