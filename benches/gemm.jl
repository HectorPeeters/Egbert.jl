using GpuOptim: @custom, @rewritetarget_ef, Options
using Test: @testset, @test
using LinearAlgebra: sum, transpose
using LinearAlgebra.BLAS: gemm, gemm!
using BenchmarkTools
using Metatheory
using CSV
using Tables
using Statistics

@rewritetarget_ef add(A::Matrix, B::Matrix)::Matrix = A + B
@rewritetarget_ef mul(A::Matrix, B::Matrix)::Matrix = A * B
@rewritetarget_ef transp(A::Matrix)::Matrix = transpose(A)

@inline mul_optimized(A::Matrix, B::Matrix, ta, tb)::Matrix = gemm(ta, tb, A, B)
@rewritetarget_ef mul_optimizedNN(A::Matrix, B::Matrix)::Matrix = mul_optimized(A, B, 'N', 'N')
@rewritetarget_ef mul_optimizedTN(A::Matrix, B::Matrix)::Matrix = mul_optimized(A, B, 'T', 'N')
@rewritetarget_ef mul_optimizedNT(A::Matrix, B::Matrix)::Matrix = mul_optimized(A, B, 'N', 'T')
@rewritetarget_ef mul_optimizedTT(A::Matrix, B::Matrix)::Matrix = mul_optimized(A, B, 'T', 'T')

function tooptimize(A::Matrix, B::Matrix, C::Matrix)
    return mul(transp(A), transp(B))
end

function baseline(A::Matrix, B::Matrix, C::Matrix)
    return transpose(A) * transpose(B)
end

rules = @theory A B C begin
    add(A, B) == add(B, A)
    add(A, add(B, C)) == add(add(A, B), C)
    mul(A, mul(B, C)) == mul(mul(A, B), C)

    transp(transp(A)) --> A

    add(transp(A), transp(B)) --> transp(add(A, B))
    mul(transp(A), transp(B)) --> transp(mul(B, A))

    add(mul(A, B), C) --> addmul_optimizedNN(A, B, C)
    add(mul(transp(A), B), C) --> addmul_optimizedTN(A, B, C)
    add(mul(A, transp(B)), C) --> addmul_optimizedNT(A, B, C)
    add(mul(transp(A), transp(B)), C) --> addmul_optimizedTT(A, B, C)

    mul(A, B) --> mul_optimizedNN(A, B)
    mul(transp(A), B) --> mul_optimizedTN(A, B)
    mul(A, transp(B)) --> mul_optimizedNT(A, B)
    mul(transp(A), transp(B)) --> mul_optimizedTT(A, B)
end

xs = Float64[]
ys = Float64[]
ys_slow = Float64[]

for i in range(0, stop=2000, length=2)
    n = floor(Int, i)
    println("Running for n = ", n)

    A = rand(n, n)
    B = rand(n, n)
    C = rand(n, n)

    t = @benchmark (@custom Options() rules tooptimize($A, $B, $C))
    tslow = @benchmark baseline($A, $B, $C)

    push!(xs, n)
    push!(ys, mean(t).time)
    push!(ys_slow, mean(tslow).time)

    data = hcat(xs, ys_slow, ys)
    CSV.write("gemm.csv", Tables.table(data), header=["x", "y", "y-custom"])
end
