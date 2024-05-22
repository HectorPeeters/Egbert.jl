using GpuOptim: @custom, @rewritetarget_ef, Options
using Test: @testset, @test
using LinearAlgebra: dot, transpose, tr
using BenchmarkTools
using Metatheory
using CSV
using Tables
using Statistics

@rewritetarget_ef trace(A::Matrix)::Float64 = tr(A)
@rewritetarget_ef mul(A::Matrix, B::Matrix)::Matrix = A * B
@rewritetarget_ef transp(A::Matrix)::Matrix = transpose(A)

function trace_mul_optimized(A::Matrix, B::Matrix)::Float64
    N = size(A, 2)

    result = 0.0
    @inbounds @simd for i in 1:N
        result += dot(A[i, :], B[:, i])
    end

    return result
end

function tooptimize(A::Matrix, B::Matrix)
    return trace(mul(transp(A), transp(B)))
end

function baseline(A::Matrix, B::Matrix)
    return tr(transpose(A) * transpose(B))
end

rules = @theory A B begin
    mul(transp(B), transp(A)) --> transp(mul(A, B))
    trace(transp(A)) --> trace(A)
    trace(mul(A, B)) --> trace_mul_optimized(A, B)
end

xs = Float64[]
ys = Float64[]
ys_slow = Float64[]

for i in range(1, stop=5000, length=30)
    println("Running for n = ", i)

    n = floor(Int, i)
    A = rand(n, n)
    B = rand(n, n)

    t = @benchmark (@custom Options() rules tooptimize($A, $B))
    tslow = @benchmark baseline($A, $B)

    push!(xs, n)
    push!(ys, mean(t).time)
    push!(ys_slow, mean(tslow).time)

    data = hcat(xs, ys_slow, ys)
    CSV.write("tracemul.csv", Tables.table(data), header=["x", "y", "y-custom"])
end
