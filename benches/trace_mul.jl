using GpuOptim: @custom, @rewritetarget, Options
using Test: @testset, @test
using LinearAlgebra: sum, transpose, tr
using BenchmarkTools
using Metatheory
using CSV
using Tables
using Statistics

struct MyMatrix
    data::Matrix
end

function Base.:(==)(a::MyMatrix, b::MyMatrix)
    return a.data == b.data
end

@rewritetarget function trace(A::MyMatrix)::Float64
    return tr(A.data)
end

@rewritetarget function mul(A::MyMatrix, B::MyMatrix)::MyMatrix
    return MyMatrix(A.data * B.data)
end

@rewritetarget function transp(A::MyMatrix)::MyMatrix
    return MyMatrix(transpose(A.data))
end

function mul_trace_optimized(A::MyMatrix, B::MyMatrix)::Float64
    size(A.data, 1) == size(A.data, 2) &&
        size(A.data, 2) == size(B.data, 1) &&
        size(B.data, 1) == size(B.data, 2) ||
        throw(DimensionMismatch("A has dimensions $(size(A, 1))x$(size(A, 2)) and B has dimensions $(size(B, 1))x$(size(B, 2))."))

    N = size(A.data, 2)

    result = 0.0

    for i in 1:N
        result += sum(A.data[i, :] .* B.data[:, i])
    end

    return result
end

function tooptimize(A::MyMatrix, B::MyMatrix)
    return trace(mul(A, B))
end

rules = @theory A B begin
    trace(mul(A, B)) --> mul_trace_optimized(A, B)
end

xs = Float64[]
ys = Float64[]
ys_slow = Float64[]

for i in range(1, stop=5000, length=20)
    println("Running for n = ", i)

    n = floor(Int, i)
    A = MyMatrix(rand(n, n))
    B = MyMatrix(rand(n, n))

    t = @benchmark (@custom Options() rules tooptimize($A, $B))
    tslow = @benchmark tooptimize($A, $B)

    push!(xs, n)
    push!(ys, mean(t).time)
    push!(ys_slow, mean(tslow).time)

    data = hcat(xs, ys_slow, ys)
    CSV.write("output.csv", Tables.table(data), header=["x", "y", "y-custom"])
end
