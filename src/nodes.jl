using Metatheory.TermInterface
const TI = TermInterface

struct Unknown end

"""
    IRExpr

This struct represents the tree structure of an IRCode object. It is used to
perform e-graph optimizations on the IR code. The IRCode is converted to an
IRExpr object, which is then converted back to IRCode after optimizations.
"""
struct IRExpr
    head::Symbol
    args::Vector{Any}
    type::Any
    mod::Union{Symbol,Unknown,Nothing}
end

function Base.:(==)(a::IRExpr, b::IRExpr)
    a.head == b.head && a.args == b.args
end

TI.isexpr(e::IRExpr) = true
TI.iscall(e::IRExpr) = e.head == :call

TI.head(e::IRExpr) = e.head
TI.children(e::IRExpr) = e.args

TI.operation(e::IRExpr) = iscall(e) ? first(children(e)) : error("Operation called on non-call node")
TI.arguments(e::IRExpr) = iscall(e) ? @view(e.args[2:end]) : error("Arguments called on non-call node")

TI.metadata(e::IRExpr) = (type=e.type, mod=e.mod)

function TI.maketerm(
    ::Type{IRExpr}, head, args, metadata
)
    if head == :__alpha__
        return AlphaExpr(args)
    end

    if head == :__return__
        return ReturnExpr(only(args))
    end

    if head == :__effect__
        @assert length(args) == 2
        return EffectExpr(first(args), args[2])
    end

    if head == :__new__
        return NewNode(args)
    end

    println(parentmodule(eval(head)), "\t", args)

    if metadata !== nothing
        IRExpr(:call, [head, args...], metadata.type, metadata.mod)
    else
        IRExpr(:call, [head, args...], nothing, Unknown())
    end
end


struct AlphaExpr
    children::Vector{Any}
end

TI.isexpr(e::AlphaExpr) = true
TI.iscall(e::AlphaExpr) = false

TI.head(::AlphaExpr) = :__alpha__
TI.children(e::AlphaExpr) = e.children

function TI.maketerm(
    ::Type{AlphaExpr}, ::Symbol, args, metadata
)
    AlphaExpr(args)
end


struct ReturnExpr
    value::Union{Any, Nothing}
end

TI.isexpr(e::ReturnExpr) = true
TI.iscall(e::ReturnExpr) = false

TI.head(::ReturnExpr) = :__return__
TI.children(e::ReturnExpr) = e.value === nothing ? [] : [e.value]

function TI.maketerm(
    ::Type{ReturnExpr}, ::Symbol, args, metadata
)
    ReturnExpr(only(args))
end


struct EffectExpr
    value::IRExpr
    index::Int
end

TI.isexpr(e::EffectExpr) = true
TI.iscall(e::EffectExpr) = false

TI.head(::EffectExpr) = :__effect__
TI.children(e::EffectExpr) = [e.value, e.index]

function TI.maketerm(
    ::Type{EffectExpr}, ::Symbol, args, metadata
)
    @assert length(args) == 2
    EffectExpr(args...)
end

struct NewExpr
    args::Vector{Any}
end

TI.isexpr(e::NewExpr) = true
TI.iscall(e::NewExpr) = true

TI.head(e::NewExpr) = e.head
TI.children(e::NewExpr) = e.args

TI.operation(e::NewExpr) = iscall(e) ? first(children(e)) : error("Operation called on non-call node")
TI.arguments(e::NewExpr) = iscall(e) ? @view(e.args[2:end]) : error("Arguments called on non-call node")
