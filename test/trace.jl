# A test rewriting the trace of a matrix multiplication to a more efficient
# implementation.

using GpuOptim: @custom, @rewritetarget, @rewritetarget_ef, Options
using Test: @testset, @test
using LinearAlgebra: diag, sum, transpose
using BenchmarkTools
using Metatheory

struct MyMatrix
    data::Matrix
end

function Base.:(==)(a::MyMatrix, b::MyMatrix)
    return a.data == b.data
end

@rewritetarget_ef function trace(A::MyMatrix)::Float64
    return sum(diag(A.data))
end

@rewritetarget_ef function mul(A::MyMatrix, B::MyMatrix)::MyMatrix
    return MyMatrix(A.data * B.data)
end

@rewritetarget_ef function transp(A::MyMatrix)::MyMatrix
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

N = 100
A = MyMatrix(rand(N, N))
B = MyMatrix(rand(N, N))

function tooptimize(A::MyMatrix, B::MyMatrix)
    return trace(mul(transp(A), transp(B)))
end

function nooptimize1(A::MyMatrix)
    return trace(A)
end

function nooptimize2(A::MyMatrix, B::MyMatrix)
    return mul(A, B)
end

rules = @theory A B begin
    mul(transp(B), transp(A)) --> transp(mul(A, B))
    trace(transp(A)) --> trace(A)
    trace(mul(A, B)) --> mul_trace_optimized(A, B)
end

@testset "TraceOfMatMul" begin
    @test isapprox(trace(mul(A, B)), mul_trace_optimized(A, B))

    @test (@custom Options() rules nooptimize1(A)) == trace(A)
    @test (@custom Options() rules nooptimize2(A, B)) == mul(A, B)

    @test begin
        optimized = @custom Options() rules tooptimize(A, B)
        expected = tooptimize(A, B)
        isapprox(optimized, expected)
    end
end
