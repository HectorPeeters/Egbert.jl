using GpuOptim: @custom, @rewritetarget, is_invoke, markdead!
using Test: @testset, @test

struct CustomList
    data::Vector{Int}
end

function perform_add(a::CustomList, b::CustomList)::CustomList
    return CustomList(a.data .+ b.data)
end

@rewritetarget function add(a::CustomList, b::CustomList)::CustomList
    return perform_add(a, b)
end

function perform_mul(a::CustomList, b::CustomList)::CustomList
    # return CustomList(a.data .* b.data)
    return error("This is broken to make sure the test rewrites this.")
end

@rewritetarget function mul(a::CustomList, b::CustomList)::CustomList
    return perform_mul(a, b)
end

function perform_add_mul(a::CustomList, b::CustomList, c::CustomList)
    return CustomList(a.data .+ b.data .* c.data)
end

function add_mul(a::CustomList, b::CustomList, c::CustomList)
    return perform_add_mul(a, b, c)
end

@rewritetarget function add_mul_intermediate(a::CustomList, b::CustomList, c::CustomList)::CustomList
    return error("This is broken to make sure the test rewrites this.")
end

function optimizetarget(a, b, c)
    return add(a, mul(b, c))
end

function nooptimizetarget(a, b)
    return add(a, b)
end

function rewrite_add_mul(ir, instructions, instr, i)
    if !is_invoke(instr, Symbol(:add))
        return false
    end

    arg1 = instr.args[3]
    arg2 = instr.args[4]

    if !(arg2 isa Core.Compiler.SSAValue)
        return false
    end

    instruction2 = instructions[arg2.id]
    if !is_invoke(instruction2, Symbol(:mul))
        return false
    end

    @info "Found add and mul invocation"

    ltype = ir.stmts.type[arg2.id]

    m = methods(Main.add_mul_intermediate, Tuple{ltype,ltype,ltype}) |> first
    mi = Core.Compiler.specialize_method(m, Tuple{ltype,ltype,ltype,ltype}, Core.svec())

    instructions[i] = Expr(
        :invoke,
        mi,
        Main.add_mul,
        arg1,
        instruction2.args[3],
        instruction2.args[4])

    markdead!(ir, arg2.id)

    @info "Rewrote to add_mul_intermediate"

    return true
end

function rewrite_add_mul_intermediate(ir, instructions, instr, i)
    if !is_invoke(instr, Symbol(:add_mul_intermediate))
        return false
    end

    @info "Found add_mul_intermediate invocation"

    ltype = ir.stmts.type[1]

    m = methods(Main.add_mul, Tuple{ltype,ltype,ltype}) |> first
    mi = Core.Compiler.specialize_method(m, Tuple{ltype,ltype,ltype,ltype}, Core.svec())

    instructions[i].args[1] = mi
    instructions[i].args[2] = Main.add_mul

    @info "Rewrote to add_mul"

    return true
end

@testset "GpuOptim.jl" begin
    A = CustomList([1, 2, 3])
    B = CustomList([4, 5, 6])
    C = CustomList([7, 8, 9])

    rules = [
        rewrite_add_mul,
        rewrite_add_mul_intermediate
    ]

    @test (@custom rules optimizetarget(A, B, C)).data == [29, 42, 57]
    @test (@custom rules nooptimizetarget(A, B)).data == [5, 7, 9]
end
