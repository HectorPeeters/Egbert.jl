using GpuOptim: @custom, @rewritetarget, Options
using Test: @testset, @test
using LinearAlgebra: diag, sum, transpose
using MetaTheory
using GemmKernels

struct MyMatrix
    data::Matrix{Float64}
end

function Base.:(==)(a::MyMatrix, b::MyMatrix)
    return a.data == b.data
end

@rewritetarget function add(A::MyMatrix, B::MyMatrix)::MyMatrix
    return MyMatrix(A.data + B.data)
end

@rewritetarget function mul(A::MyMatrix, B::MyMatrix)::MyMatrix
    return MyMatrix(A.data * B.data)
end

@rewritetarget function transp(A::MyMatrix)::MyMatrix
    return MyMatrix(transpose(A.data))
end

function gemm(A::MyMatrix, B::MyMatrix, transpa::Bool=false, transpb::Bool=false)::MyMatrix
    conf = GemmKernelGemmKernelss.get_config(
        gemm_shape=(M=1024, N=1024, K=1024),
        operator=Operator.WMMAOp{16,16,16,Float32},
        global_a_layout=transpa ? Layout.UnsafeAlignedRowMajor{Float64} : Layout.UnsafeAlignedColMajor{Float64},
        global_b_layout=transpb ? Layout.UnsafeAlignedRowMajor{Float64} : Layout.UnsafeAlignedColMajor{Float64},
        global_c_layout=Layout.UnsafeAlignedColMajor{Float64},
        global_d_layout=Layout.UnsafeAlignedColMajor{Float32},
        is_a_col_major=!transpa,
        is_b_col_major=!transpb,
    )

    C = MyMatrix(zero(1024, 1024))

    GemmKernels.matmul(A.data, B.data, C.data, C.data, conf; kernel=Kernel.matmul_pipelined)

    return C
end

@testset "Gemm Optimization" begin
    A = rand(1024, 1024)
    B = rand(1024, 1024)

    rules = @theory a b c d e begin
        mul(a, b) == mul(b, a)
        mul(a, b) --> gemm(a, b)
        mul(tansp(a), b) --> gemm(a, b, true, false)
        mul(tansp(a), transp(b)) --> gemm(a, b, true, true)
    end

    @test mul(A, B) == gemm(A, B)
    @test mul(transp(A), B) == gemm(A, B, true)
    @test mul(A, transp(B)) == gemm(A, B, false, true)
    @test mul(transp(A), transp(B)) == gemm(A, B, true, true)
end
