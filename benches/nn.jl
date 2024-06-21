using GpuOptim: @optimize, @rewritetarget_ef, Options
using Test: @testset, @test
using LinearAlgebra: sum, transpose, tr
using LinearAlgebra.BLAS: gemm, gemm!
using BenchmarkTools
using Metatheory
using CSV
using Tables
using Statistics

@rewritetarget_ef add(A::Matrix, B::Matrix)::Matrix = A + B
@rewritetarget_ef mul(A::Matrix, B::Matrix)::Matrix = A * B
@rewritetarget_ef transp(A::Matrix)::Matrix = transpose(A)

mul_optimized(A::Matrix, B::Matrix, ta, tb)::Matrix = gemm(ta, tb, A, B)
@rewritetarget_ef mul_optimizedNN(A::Matrix, B::Matrix)::Matrix = mul_optimized(A, B, 'N', 'N')
@rewritetarget_ef mul_optimizedTN(A::Matrix, B::Matrix)::Matrix = mul_optimized(A, B, 'T', 'N')
@rewritetarget_ef mul_optimizedNT(A::Matrix, B::Matrix)::Matrix = mul_optimized(A, B, 'N', 'T')
@rewritetarget_ef mul_optimizedTT(A::Matrix, B::Matrix)::Matrix = mul_optimized(A, B, 'T', 'T')

function addmul_optimized(A::Matrix, B::Matrix, C::Matrix, ta, tb)::Matrix
    D = similar(C)
    return Matrix(gemm!(ta, tb, 1.0, A, B, 1.0, D))
end
@rewritetarget_ef addmul_optimizedNN(A::Matrix, B::Matrix, C::Matrix)::Matrix = addmul_optimized(A, B, C, 'N', 'N')
@rewritetarget_ef addmul_optimizedNT(A::Matrix, B::Matrix, C::Matrix)::Matrix = addmul_optimized(A, B, C, 'N', 'T')
@rewritetarget_ef addmul_optimizedTN(A::Matrix, B::Matrix, C::Matrix)::Matrix = addmul_optimized(A, B, C, 'T', 'N')
@rewritetarget_ef addmul_optimizedTT(A::Matrix, B::Matrix, C::Matrix)::Matrix = addmul_optimized(A, B, C, 'T', 'T')

function init_layer(input_dim::Int, output_dim::Int, n::Int)
    W = randn(output_dim, input_dim)
    BN = randn(output_dim)
    B = repeat(BN, 1, n)
    return W, B, BN
end

function forward_layer(I::Matrix, W::Matrix, B::Matrix)
    return add(mul(W, I), B)
end

function forward_layer_baseline(I::Matrix, W::Matrix, B::Matrix)
    return W * I + B
end

function forward_layer_normal(I, W, B)
    return W * I .+ B
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
ys_normal = Float64[]

for i in range(0, 1000, step=20)
    n = i
    input_dim = n
    output_dim = 2 * n

    println("Running n = ", n)

    I = randn(n, input_dim)
    W, B, BN = init_layer(input_dim, output_dim, n)

    expected = forward_layer_normal(I, W, BN)
    @test expected == forward_layer_baseline(I, W, B)
    @test expected == forward_layer(I, W, B)

    t = @benchmark (@optimize Options() rules forward_layer($I, $W, $B))
    println(t)
    tslow = @benchmark forward_layer_baseline($I, $W, $B)
    println(tslow)
    tnormal = @benchmark forward_layer_normal($I, $W, $BN)
    println(tnormal)

    push!(xs, n)
    push!(ys, mean(t).time)
    push!(ys_slow, mean(tslow).time)
    push!(ys_normal, mean(tnormal).time)

    data = hcat(xs, ys_slow, ys, ys_normal)
    CSV.write("nn.csv", Tables.table(data), header=["x", "y", "y-custom", "y-normal"])
end
