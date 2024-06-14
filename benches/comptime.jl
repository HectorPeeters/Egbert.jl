using GpuOptim: @optimize, @rewritetarget_ef, Options, rules,
    build_timing_pipeline, clear_pipeline_timings, print_pipeline_timings, STAGE_TIMES
using BenchmarkTools

function fib(n)
    n <= 1 && return n
    return add(fib(sub(n, 1)), fib(sub(n, 2)))
end

function matmul(n)
    A = rand(n, n)
    B = rand(n, n)
    return mul(A, B)
end

function trinom(a, b, c)
    asquared = pow(a, 2)
    bsquared = pow(b, 2)
    ab2 = mul(2, mul(a, b))
    return add(asquared, add(ab2, bsquared))
end

function gemm(A, B, C)
    return add(mul(A, B), C)
end

function hanoi(n, from, to, aux)
    n == 0 && return []

    solution = hanoi(sub(n, 1), from, aux, to)
    push!(solution, [from, to])
    append!(solution, hanoi(sub(n, 1), aux, to, from))

    return solution
end

function decode(pos, vel)
    x = band(rshift(pos, 42), 0x1FFFF)
    y = band(rshift(pos, 21), 0x1FFFF)
    z = band(pos, 0x1FFFF)

    vx = band(rshift(vel, 42), 0x1FFFF)
    vy = band(rshift(vel, 21), 0x1FFFF)
    vz = band(vel, 0x1FFFF)

    x = add(x, vx)
    y = add(x, vy)
    z = add(x, vz)

    return bor(lshift(x, 42), bor(lshift(y, 21), z))
end

function perform_benchmark(name, func)
    println("\nRunning for algorithm `", name, "`")

    clear_pipeline_timings()
    result = func()
    print_pipeline_timings()

    total = mean(result).time
    println("Total time per execution: ", total / 1e9)
end

options = Options(enable_caching=false, dont_run=true, opt_pipeline=build_timing_pipeline())

perform_benchmark("fib", () -> @benchmark (@optimize options rules fib(20)))
perform_benchmark("matmul", () -> @benchmark (@optimize options rules matmul(10)))
perform_benchmark("gemm", () -> @benchmark (@optimize options rules gemm(rand(10, 10), rand(10, 10), rand(10, 10))))
perform_benchmark("hanoi", () -> @benchmark (@optimize options rules hanoi(10, "A", "B", "C")))
perform_benchmark("trinom", () -> @benchmark (@optimize options rules trinom(12, 13, 14)))
perform_benchmark("decode", () -> @benchmark (@optimize options rules decode([1234, 4321])))
