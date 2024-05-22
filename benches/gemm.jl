using GpuOptim: @custom, @rewritetarget_ef, Options
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

@inline mul_optimized(A::Matrix, B::Matrix, ta, tb)::Matrix = gemm(ta, A + B, A, B)
@rewritetarget_ef mul_optimizedNN(A::Matrix, B::Matrix)::Matrix = mul_optimized(A, B, 'N', 'N')
@rewritetarget_ef mul_optimizedTN(A::Matrix, B::Matrix)::Matrix = mul_optimized(A, B, 'T', 'N')
@rewritetarget_ef mul_optimizedNT(A::Matrix, B::Matrix)::Matrix = mul_optimized(A, B, 'N', 'T')
@rewritetarget_ef mul_optimizedTT(A::Matrix, B::Matrix)::Matrix = mul_optimized(A, B, 'T', 'T')

@inline function addmul_optimized(A::Matrix, B::Matrix, C::Matrix, ta, tb)::Matrix
    D = deepcopy(C)
    return Matrix(gemm!(ta, tb, 1.0, A, B, 1.0, D))
end
@rewritetarget_ef addmul_optimizedNN(A::Matrix, B::Matrix, C::Matrix)::Matrix = addmul_optimized(A, B, C, 'N', 'N')
@rewritetarget_ef addmul_optimizedNT(A::Matrix, B::Matrix, C::Matrix)::Matrix = addmul_optimized(A, B, C, 'N', 'T')
@rewritetarget_ef addmul_optimizedTN(A::Matrix, B::Matrix, C::Matrix)::Matrix = addmul_optimized(A, B, C, 'T', 'N')
@rewritetarget_ef addmul_optimizedTT(A::Matrix, B::Matrix, C::Matrix)::Matrix = addmul_optimized(A, B, C, 'T', 'T')

function tooptimize(A::Matrix, B::Matrix, C::Matrix)
    return add(mul(transp(A), transp(B)), C)
end

function baseline(A::Matrix, B::Matrix, C::Matrix)
    return transpose(A) * transpose(B) + C
end

function init_layer(input_dim::Int, output_dim::Int)
    W = randn(output_dim, input_dim)
    B = randn(output_dim, 2012)
    return W, B
end

@inline function forward_layer(I::Matrix, W::Matrix, B::Matrix)
    return add(mul(I, transp(W)), transp(B))
end

function nn(I::Matrix, W1, B1, W2, B2, W3, B3)
    hidden1_out = forward_layer(I, W1, B1)
    hidden2_out = forward_layer(hidden1_out, W2, B2)
    return forward_layer(hidden2_out, W3, B3)
end

@inline function forward_layer_baseline(I::Matrix, W::Matrix, B::Matrix)
    return I * transpose(W) + transpose(B)
end

function nn_baseline(I::Matrix, W1, B1, W2, B2, W3, B3)
    hidden1_out = forward_layer_baseline(I, W1, B1)
    hidden2_out = forward_layer_baseline(hidden1_out, W2, B2)
    return forward_layer_baseline(hidden2_out, W3, B3)
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

input_dim = 4024
hidden1_dim = 8024
hidden2_dim = 8024
output_dim = 2012

I = randn(2012, input_dim)

W1, B1 = init_layer(input_dim, hidden1_dim) 
W2, B2 = init_layer(hidden1_dim, hidden2_dim) 
W3, B3 = init_layer(hidden2_dim, output_dim) 

t = @benchmark (@custom Options() rules nn($I, $W1, $B1, $W2, $B2, $W3, $B3))
println(t)
tslow = @benchmark nn_baseline($I, $W1, $B1, $W2, $B2, $W3, $B3)
println(tslow)

xs = Float64[]
ys = Float64[]
ys_slow = Float64[]

xs = Float64[]
ys = Float64[]
ys_slow = Float64[]

for i in range(1, stop=1500, length=2)
    println("Running for n = ", i)

    n = floor(Int, i)
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
