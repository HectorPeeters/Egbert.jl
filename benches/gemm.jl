using GpuOptim: @custom, @rewritetarget_ef, Options
using Test: @testset, @test
using LinearAlgebra: sum, transpose, tr
using LinearAlgebra.BLAS: gemm
using BenchmarkTools
using Metatheory
using CSV
using Tables
using Statistics

struct MyMatrix
    data::Matrix
end

function Base.:(==)(a::MyMatrix, b::MyMatrix)
    return a.data .== b.data
end

@rewritetarget_ef function add(A::MyMatrix, B::MyMatrix)::MyMatrix
    return MyMatrix(A.data + B.data)
end

@rewritetarget_ef function mul(A::MyMatrix, B::MyMatrix)::MyMatrix
    return MyMatrix(A.data * B.data)
end

@rewritetarget_ef function transp(A::MyMatrix)::MyMatrix
    return MyMatrix(transpose(A.data))
end

@rewritetarget_ef function mul_optimized(A::MyMatrix, B::MyMatrix)::MyMatrix
    return MyMatrix(gemm('T', 'N', A.data, B.data))
end

function tooptimize(A::MyMatrix, B::MyMatrix)
    return mul(transp(A), B)
end

rules = @theory A B begin
    mul(A, B) --> mul_optimized(A, B, 'N', 'N')
    mul(transp(A), B) --> mul_optimized(A, B)
    mul(A, transp(B)) --> mul_optimized(A, B, 'N', 'T')
    mul(transp(A), transp(B)) --> mul_optimized(A, B, 'T', 'T')
end

xs = Float64[]
ys = Float64[]
ys_slow = Float64[]

for i in range(1, stop=5000, length=20)
    println("Running for n = ", i)

    n = floor(Int, i)
    A = rand(n, n)
    B = rand(n, n)
    myA = MyMatrix(A)
    myB = MyMatrix(B)

    # @test tooptimize(myA, myB) == transpose(A) * B
    # @test (@custom Options() tooptimize(myA, myB)) == transpose(A) * B
    t = @benchmark (@custom Options() rules tooptimize($myA, $myB))
    tslow = @benchmark tooptimize($myA, $myB)

    push!(xs, n)
    push!(ys, mean(t).time)
    push!(ys_slow, mean(tslow).time)

    data = hcat(xs, ys_slow, ys)
    CSV.write("gemm.csv", Tables.table(data), header=["x", "y", "y-custom"])
end
