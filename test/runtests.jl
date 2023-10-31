using GpuOptim: @custom
using Test

add(a, b) = a + b

@testset "GpuOptim.jl" begin
    @test (@custom add(12, 13)) == 25
end
