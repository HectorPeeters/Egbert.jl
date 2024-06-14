using Metatheory.TermInterface
using Metatheory.EGraphs
using DataStructures: OrderedDict

"""
A helper type used to signal the module of an IRExpr is unknown.    
"""
struct Unknown end


"""
    IRExpr

This struct represents a node in the tree representation of an IRCode object. 
It is used to perform e-graph optimizations on said IR code. The IRCode is 
converted to an IRExpr object, which is then converted back to IRCode after
optimizations.

This closely matches the functionality of the builtin Julia Expr but includes
additional information such as the type and module of each node.
"""
struct IRExpr
    """
    The head of the expression node. Most of the time this is :call, depicting
    a function call. All the possible values can be found in the following function:
    
        function expr_to_ir!(exprtoir::ExprToIr, expr::IRExpr; no_cse=false)
    """
    head::Symbol

    """
    The operation of the node, this value is a duplicate of the head, except for
    call instructions. Then the operation represents the function being called. 
    """
    operation::Any

    """
    The arguments of the node. These can be actual arguments to a function call
    but also the value returned by a :return node.
    """
    args::Vector{Any}

    """
    The type of this node. This information is added during the conversion process
    and tracked as well as possible throughout the e-graph optimization process. 
    """
    type::Any

    """
    The module information used for function calls. This is a workaround for
    the limitations in Metatheory 2.0 where qualified function names aren't
    matched correctly. 
    """
    mod::Union{Symbol,Unknown,Nothing}
end

function Base.:(==)(a::IRExpr, b::IRExpr)
    a.head == b.head && a.args == b.args
end

TermInterface.istree(e::IRExpr) = e.head == :call || e.head == :alpha || e.head == :ret || e.head == :effect
TermInterface.operation(e::IRExpr) = e.operation
TermInterface.exprhead(e::IRExpr) = e.head
TermInterface.arguments(e::IRExpr) = e.args
TermInterface.metadata(e::IRExpr) = (type=e.type, mod=e.mod)

function TermInterface.similarterm(
    ::IRExpr, head, args;
    metadata=nothing, exprhead=:call
)
    metadata = metadata !== nothing ? metadata : (type=nothing, mod=Unknown())

    IRExpr(exprhead, head, args, metadata.type, metadata.mod)
end

# NOTE: this function is not required anymore in the new version of
#       Metatheory.
function EGraphs.egraph_reconstruct_expression(
    ::Type{IRExpr}, op, args;
    metadata=nothing,
    exprhead=nothing
)
    metadata = metadata !== nothing ? metadata : (type=nothing, mod=Unknown())

    IRExpr(exprhead, op, args, metadata.type, metadata.mod)
end

function EGraphs.make(::Val{:metadata_analysis}, g, n)
    return (type=Any, mod=Unknown())
end

function EGraphs.join(::Val{:metadata_analysis}, a, b)
    # We use the module of either a or b. If both have
    # a module attached, make sure they're identical.
    mod = Unknown()
    if a.mod !== nothing
        if a.mod !== nothing
            a.mod != b.mod && error("Different modules")
        else
            mod = b.mod
        end
    elseif a.mod !== nothing
        mod = a.mod
    end

    type = typejoin(a.type, b.type)
    return (type=type, mod=mod)
end

"""
Struct maintaining the context required for converting an IRCode
object to an tree of IRExpr nodes.  
"""
mutable struct IrToExpr
    """
    The list of IRCode instructions used during the conversion  
    """
    instructions::Vector{Any}

    """
    The types of the IRCode instructions.  
    """
    types::Vector{Any}

    """
    The flags of the IRCode instructions.  
    """
    flags::Vector{Any}

    """
    The range of instructions used during the conversion. This
    allows only a subset of instructions to be converted.

    This was added to support multiple basic blocks at some
    point but for now this range always matches the full
    instruction span.
    """
    range::CC.StmtRange

    """
    The SSA index of the current instruction being converted. This 
    information is used to attach to side-effect nodes to correctly
    perform the deduplication procedure when converting back to
    IRCode instructions.
    """
    ssa_index::Integer

    IrToExpr(instrs::CC.InstructionStream, range::CC.StmtRange) = new(
        instrs.stmt,
        instrs.type,
        instrs.flag,
        range,
        1
    )
end

"""
    get_root_expr!(irtoexpr::IrToExpr)

The function to call when converting a full list of instructions
into an expression tree. This function is responsible for generting
the side effect list.
"""
function get_root_expr!(irtoexpr::IrToExpr)
    sideeffect_exprs = []

    for i in irtoexpr.range
        flags = irtoexpr.flags[i]

        # Emit all instructions that contain side-effects
        if !CC.has_flag(flags, CC.IR_FLAG_EFFECT_FREE)

            # If the instruction list contains a nothing, skip it 
            irtoexpr.instructions[i] === nothing && continue

            # Convert the instruction to a tree representation
            expr = ir_to_expr!(irtoexpr, CC.SSAValue(i))

            # Add it to the list of side-effect instructions
            push!(sideeffect_exprs, expr)
        end
    end

    # The top-level alpha node, essentially the side-effect skeleton (list)
    # from the Cranelift algorithm.
    return IRExpr(:alpha, :alpha, sideeffect_exprs, nothing, nothing)
end


"""
    ir_to_expr!(irtoexpr::IrToExpr, s::CC.SSAValue)

Convert an SSA value into an expression tree. This performs a
lookup in the instruction list to find the actual instruction
and convert it into a tree.
"""
function ir_to_expr!(irtoexpr::IrToExpr, s::CC.SSAValue)
    # Keep track of the previous SSA index to reset afterwards
    old_ssa_index = irtoexpr.ssa_index
    # Update the ssa_index
    irtoexpr.ssa_index = s.id

    # If we're outside of the range, just return the SSAValue
    if s.id < irtoexpr.range.start || s.id > irtoexpr.range.stop
        return s
    end

    # Generate the tree expression from the ssa value
    result = ir_to_expr!(
        irtoexpr,
        irtoexpr.instructions[s.id],
        irtoexpr.types[s.id]
    )

    # Reset the old ssa index
    irtoexpr.ssa_index = old_ssa_index

    return result
end

ir_to_expr!(::IrToExpr, r::GlobalRef, _) = r
ir_to_expr!(::IrToExpr, x) = x

"""    
    ir_to_expr!(irtoexpr::IrToExpr, r::CC.ReturnNode, t)

Generate a return expression tree from a ReturNode. This
handles the two cases where there is or isn't a return value.
"""
function ir_to_expr!(irtoexpr::IrToExpr, r::CC.ReturnNode, t)
    if isdefined(r, :val)
        return IRExpr(
            :ret,
            :ret,
            [ir_to_expr!(irtoexpr, r.val)],
            t,
            nothing
        )
    end

    return IRExpr(
        :ret,
        :ret,
        [],
        t,
        nothing
    )
end

"""
   has_effects(irtoexpr::IrToExpr, i)

A helper function to check if the instruction at index i
has side-effects.
"""
function has_effects(irtoexpr::IrToExpr, i)
    flags = irtoexpr.flags[i]
    !CC.has_flag(flags, CC.IR_FLAG_EFFECT_FREE)
end

"""
    ir_to_expr!(irtoexpr::IrToExpr, e::Expr, t)

Convert an Expr instruction into a expression tree node. This
handles the following cases:

- :invoke
- :call
- :new
- :foreigncall
- :boundscheck
"""
function ir_to_expr!(irtoexpr::IrToExpr, e::Expr, t)
    if e.head == :invoke

        # All invokes are converted into call nodes. However, they get converted
        # back into invoke nodes after the rewrite optimization where possible.
        result = IRExpr(
            :call,
            Symbol(e.args[1].def.name),
            map(enumerate(e.args[3:end])) do (i, x)
                ir_to_expr!(irtoexpr, x)
            end,
            t,
            Symbol(e.args[1].def.module)
        )

        # Wrap the node in an effect node if the call produces side effects. 
        if has_effects(irtoexpr, irtoexpr.ssa_index)
            result = IRExpr(
                :effect,
                :effect,
                [result, irtoexpr.ssa_index],
                nothing,
                nothing
            )
        end

        return result
    end

    if e.head == :call
        method = ir_to_expr!(irtoexpr, e.args[1])

        result = if method isa GlobalRef
            # If we encounter a GlobalRef as a function object, attach the module
            # information to the node
            IRExpr(
                :call,
                method.name,
                map(enumerate(e.args[2:end])) do (i, x)
                    ir_to_expr!(irtoexpr, x)
                end,
                t,
                Symbol(method.mod)
            )
        else
            IRExpr(
                :call,
                e.args[1],
                map(enumerate(e.args[2:end])) do (i, x)
                    ir_to_expr!(irtoexpr, x)
                end,
                t,
                nothing
            )
        end

        # Wrap the call in an effect node when the call produces side effects
        if has_effects(irtoexpr, irtoexpr.ssa_index)
            result = IRExpr(
                :effect,
                :effect,
                [result, irtoexpr.ssa_index],
                nothing,
                nothing
            )
        end

        return result
    end

    if e.head == :new
        return IRExpr(
            :new,
            :new,
            map(enumerate(e.args[1:end])) do (i, x)
                ir_to_expr!(irtoexpr, x)
            end,
            t,
            nothing
        )
    end

    if e.head == :foreigncall
        return IRExpr(
            :foreigncall,
            :foreigncall,
            [e, irtoexpr.ssa_index],
            nothing,
            nothing
        )
    end

    if e.head == :boundscheck
        return IRExpr(
            :boundscheck,
            :boundscheck,
            [e, irtoexpr.ssa_index],
            nothing,
            nothing
        )
    end

    error("Expression not supported: ", e.head)
end

"""
    ExprToIr

A struct containing the required context for converting an expression tree
to a list of IRCode instructions.
"""
struct ExprToIr
    """
    List of already-emitted instructions. This list gets returned at the end
    of the full conversion procedure. 
    """
    instructions::Vector{Any}

    """
    The original SSA index for side-effect instructions. This is used to
    correctly deduplicate side-effect instructions. 
    """
    source_ssa_ids::Vector{Any}

    """
    The recovered type information for every instruction. This, combined with
    the list of instructions, is the final result of the conversion.
    """
    types::Vector{Any}

    """
    The start SSA index of the block of instructions. This was added to support
    multiple basic blocks but is in practice just the start of the function body.
    """
    ssa_start::Integer

    """
    The fallback module in case the correct module information could not be
    recovered. This is a workaround for the limitations in the current version
    of Metatheory.
    """
    mod::Module

    ExprToIr(mod::Module, range::CC.StmtRange) = new(
        [], [], [], range.start, mod)
end

"""
    push_instr!(exprtoir::ExprToIr, instr, type, source_ssa_id=nothing)

Add an instruction with optional type and SSA index to the current list of
emitted instructions.
"""
function push_instr!(exprtoir::ExprToIr, instr, type, source_ssa_id=nothing)
    push!(exprtoir.instructions, instr)

    if type === nothing
        push!(exprtoir.types, Any)
    else
        push!(exprtoir.types, type)
    end

    push!(exprtoir.source_ssa_ids, source_ssa_id)

    return SSAValue(length(exprtoir.instructions) + exprtoir.ssa_start - 1)
end

expr_to_ir!(::ExprToIr, x) = x

"""
    expr_to_ir!(exprtoir::ExprToIr, expr::IRExpr; no_cse=false)

Convert an IRExpr node into a list of instructions. This recursive
function acts as a big switch statement based on the head of the
expression.
"""
function expr_to_ir!(exprtoir::ExprToIr, expr::IRExpr; no_cse=false)
    # Top-level alpha nodes, emit all the nodes in the correct order
    if expr.head == :alpha
        for arg in expr.args
            expr_to_ir!(exprtoir, arg)
        end
        return (exprtoir.instructions, exprtoir.types)
    end

    # Side effect node, correctly perform deduplication
    if expr.head == :effect
        source_ssa_id = expr.args[2]

        # Only use an already-emitted instruction if the source_ssa_id's
        # match (i.e. they represent the same function call).
        index = findlast(x -> x == source_ssa_id, exprtoir.source_ssa_ids)
        if index !== nothing
            return SSAValue(exprtoir.ssa_start + index - 1)
        end

        # Otherwise emit a new instruction
        result = expr_to_ir!(exprtoir, expr.args[1], no_cse=true)
        exprtoir.source_ssa_ids[end] = source_ssa_id

        return result
    end

    if expr.head == :foreigncall
        ssa_id = expr.args[2]
        return push_instr!(exprtoir, expr.args[1], expr.type; source_ssa_id=ssa_id)
    end

    if expr.head == :boundscheck
        ssa_id = expr.args[2]
        return push_instr!(exprtoir, expr.args[1], expr.type; source_ssa_id=ssa_id)
    end

    if expr.head == :ret
        if length(expr.args) == 0
            return push_instr!(exprtoir, CC.ReturnNode(), expr.type)
        end

        val = expr_to_ir!(exprtoir, expr.args[1])
        return push_instr!(exprtoir, CC.ReturnNode(val), expr.type)
    end

    if expr.head == :call
        # Convert all the arguments to instructions
        args = map(a -> expr_to_ir!(exprtoir, a), expr.args)

        # If we have module information, add it to the operation
        method = if expr.mod === nothing
            expr.operation
        elseif expr.mod isa Unknown
            GlobalRef(exprtoir.mod, Symbol(expr.operation))
        else
            GlobalRef(eval(expr.mod), Symbol(expr.operation))
        end

        instruction = Expr(expr.head, method, args...)

        # If we have emitted this instruction before, use that instance. This
        # is disabled when we are emitting the call within a side-effect node.
        index = findlast(x -> x == instruction, exprtoir.instructions)
        if index !== nothing && !no_cse
            return SSAValue(exprtoir.ssa_start + index - 1)
        end

        return push_instr!(exprtoir, instruction, expr.type)
    end

    if expr.head == :new
        # Convert all the arguments to instructions
        args = map(a -> expr_to_ir!(exprtoir, a), expr.args)

        instruction = Expr(expr.head, args[1], args[2:end]...)

        # If we have emitted this instruction before, use that instance. This
        # is disabled when we are emitting the call within a side-effect node.
        index = findlast(x -> x == instruction, exprtoir.instructions)
        if index !== nothing && !no_cse
            return SSAValue(exprtoir.ssa_start + index - 1)
        end

        return push_instr!(exprtoir, instruction, expr.type)
    end

    error("Expression type not supported: ", expr.head)
end
