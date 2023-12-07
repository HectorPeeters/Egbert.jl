using GpuOptim: @custom
using Test

function times_two(a)
    a + a
end

@testset "GpuOptim.jl" begin
    @test (@custom times_two(13)) == 26
end
