using GpuOptim: @custom, @rewritetarget, is_invoke, markdead!
using Test: @testset, @test
using LinearAlgebra: diag, sum
using BenchmarkTools

# This file test the optimization of taking the trace of a matrix multiplication.

struct MyMatrix
    data::Matrix
end

@rewritetarget function trace(A::MyMatrix)::Float64
    return sum(diag(A.data))
end

@rewritetarget Base.:*(A::MyMatrix, B::MyMatrix)::MyMatrix = MyMatrix(A.data * B.data)

function mul_trace_optimized(A::MyMatrix, B::MyMatrix)
    size(A.data, 1) == size(A.data, 2) && 
        size(A.data, 2) == size(B.data, 1) &&
        size(B.data, 1) == size(B.data, 2) || 
        throw(DimensionMismatch("A has dimensions $(size(A, 1))x$(size(A, 2)) and B has dimensions $(size(B, 1))x$(size(B, 2))."))

    N = size(A.data, 2)

    result = 0.0

    for i in 1:N
        for j in 1:N
            result += A.data[i, j] * B.data[j, i]
        end
    end

    return result
end

function rewrite_trace(ir, instructions, instr, i)
    !is_invoke(instr, Symbol(:trace)) && return false

    arg = instr.args[3]

    !(arg isa Core.Compiler.SSAValue) && return false

    instruction2 = instructions[arg.id]

    !is_invoke(instruction2, Symbol(:*)) && return false

    @info "Found trace of matrix multiplication"

    ltype = ir.stmts.type[arg.id]
    
    m = methods(mul_trace_optimized, Tuple{ltype,ltype}) |> first
    mi = Core.Compiler.specialize_method(m, Tuple{Float64,ltype,ltype}, Core.svec())

    instructions[i] = Expr(
        :invoke,
        mi,
        mul_trace_optimized,
        instruction2.args[3],
        instruction2.args[4])

    markdead!(ir, arg.id)

    @info "Rewrite to mul_trace_optimized"

    return true
end

N = 2
A = MyMatrix(rand(N, N))
B = MyMatrix(rand(N, N))

function tooptimize(A::MyMatrix, B::MyMatrix)
    return trace(A * B)
end

function nooptimize1(A::MyMatrix)
    return trace(A)
end

function nooptimize2(A::MyMatrix, B::MyMatrix)
    return A * B
end

rules = [rewrite_trace]

@testset "TraceOfMatMul" begin
    @test isapprox(trace(A * B), mul_trace_optimized(A, B))
    @test (@custom rules nooptimize1(A)) == trace(A)

    # TODO: special characters seem to crash cleanup
    # @test (@custom rules nooptimize2(A, B)) == A * B

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