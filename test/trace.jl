using GpuOptim: @custom, @rewritetarget, is_invoke, markdead!
using Test: @testset, @test
using LinearAlgebra: diag, sum
using BenchmarkTools
using Metatheory

struct MyMatrix
    data::Matrix
end

function Base.:(==)(a::MyMatrix, b::MyMatrix)
    return a.data == b.data
end

@rewritetarget function trace(A::MyMatrix)::Float64
    return sum(diag(A.data))
end

@rewritetarget function mul(A::MyMatrix, B::MyMatrix)::MyMatrix
    return MyMatrix(A.data * B.data)
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

N = 1000
A = MyMatrix(rand(N, N))
B = MyMatrix(rand(N, N))

function tooptimize(A::MyMatrix, B::MyMatrix)
    return trace(mul(A, B))
end

function nooptimize1(A::MyMatrix)
    return trace(A)
end

function nooptimize2(A::MyMatrix, B::MyMatrix)
    return mul(A, B)
end

rules = @theory A B begin
    trace(mul(A, B)) --> mul_trace_optimized(A, B)
end

@testset "TraceOfMatMul" begin
    # @test isapprox(trace(mul(A, B)), mul_trace_optimized(A, B))

    # @test (@custom rules nooptimize1(A)) == trace(A)
    # @test (@custom rules nooptimize2(A, B)) == mul(A, B)

    @test begin
        optimized = @custom rules tooptimize(A, B)
        expected = tooptimize(A, B)
        isapprox(optimized, expected)
    end
end

# io = IOContext(stdout, :logbins=>true)

# noopt = @benchmark tooptimize($A, $B)
# show(io, MIME("text/plain"), noopt)

# opt = @benchmark (@custom rules tooptimize($A, $B))
# show(io, MIME("text/plain"), opt)