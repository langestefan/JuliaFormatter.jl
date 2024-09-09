import Base: show

@enum(
    FNode,

    # dummy
    NONE,

    # leaf nodes
    NEWLINE,
    SEMICOLON,
    WHITESPACE,
    PLACEHOLDER,
    NOTCODE,
    INLINECOMMENT,
    TRAILINGCOMMA,
    TRAILINGSEMICOLON,
    INVERSETRAILINGSEMICOLON,
    KEYWORD,
    LITERAL,
    OPERATOR,
    PUNCTUATION,
    IDENTIFIER,
    MACRONAME,

    # non-leaf nodes
    Accessor,
    MacroBlock,
    MacroCall,
    MacroStr,
    Macroname,
    GlobalRefDoc,
    TupleN,
    CartesianIterator,
    RefN,
    ModuleN,
    Unary,
    Binary,
    Chain,
    Comparison,
    Conditional,
    Where,
    Vect,
    Braces,
    Brackets,
    Curly,
    Call,
    Parameters,
    Kw,
    Vcat,
    Hcat,
    Ncat,
    TypedVcat,
    TypedNcat,
    TypedHcat,
    Row,
    NRow,
    BracesCat,
    TypedComprehension,
    Comprehension,
    Generator,
    Filter,
    Flatten,
    For,
    While,
    If,
    Begin,
    Try,
    Quote,
    Do,
    Let,
    Block,
    BareModule,
    TopLevel,
    StringN,
    Macro,
    FunctionN,
    Struct,
    Mutable,
    Primitive,
    Abstract,
    Return,
    Local,
    Outer,
    Global,
    Const,
    Import,
    Export,
    Using,
    File,
    Quotenode,
    Unknown,
    As,
    NonStdIdentifier, # i.e. var"##iv369"
    ImportPath,
    Juxtapose,
    Break,
    Continue,
    Inert,
)

@enum(NestBehavior, AllowNest, AlwaysNest, NeverNest, NeverNestNode, AllowNestButDontRemove)

struct Metadata
    op_kind::JuliaSyntax.Kind
    op_dotted::Bool
    is_standalone_shortcircuit::Bool
    is_short_form_function::Bool
    is_assignment::Bool
    is_long_form_function::Bool
end

function Metadata(k::JuliaSyntax.Kind, dotted::Bool)
    return Metadata(k, dotted, false, false, false, false)
end

"""
Formatted Syntax Tree
"""
mutable struct FST
    typ::FNode

    # Start and end lines of the node
    # in the original source file.
    startline::Int
    endline::Int

    indent::Int
    len::Int
    val::Union{Nothing,AbstractString}
    nodes::Union{Nothing,Vector{FST}}
    ref::Union{Nothing,Ref{<:JuliaSyntax.GreenNode}}
    nest_behavior::NestBehavior

    # Extra margin caused by parent nodes.
    # i.e. `(f(arg))`
    #
    # `f(arg)` would have `extra_margin` = 1
    # due to `)` after `f(arg)`.
    extra_margin::Int
    line_offset::Int

    metadata::Union{Nothing,Metadata}
end

function show(io::IO, fst::FST)
    show(io, MIME("text/plain"), fst)
end

function show(io::IO, ::MIME"text/plain", fst::FST, indent = "")
    if fst.nodes !== nothing
        println(io, indent, "FST: $(fst.typ) $(length(fst.nodes))")
        println(
            io,
            indent,
            "  ($(fst.startline), $(fst.endline), $(fst.indent), $(fst.len))",
        )
        println(io, indent, "  nest_behavior: ", fst.nest_behavior)
        println(io, indent, "  extra_margin: ", fst.extra_margin)

        println(io, indent, "  nodes:")
        for (i, node) in enumerate(fst.nodes)
            print(io, indent, "    [$i] ")
            show(io, MIME("text/plain"), node, indent * "    ")
        end
    else
        println(io, indent, "FST: $(fst.typ)")
        println(io, indent, "  val: \"$(fst.val)\"")
        println(io, indent, "  line_offset: ", fst.line_offset)
        println(io, indent, "  indent: ", fst.indent)
    end
end

FST(typ::FNode, cst::JuliaSyntax.GreenNode, indent::Int) =
    FST(typ, -1, -1, indent, 0, nothing, FST[], Ref(cst), AllowNest, 0, -1, nothing)

FST(typ::FNode, indent::Int) =
    FST(typ, -1, -1, indent, 0, nothing, FST[], nothing, AllowNest, 0, -1, nothing)

function FST(
    typ::FNode,
    cst::JuliaSyntax.GreenNode,
    line_offset::Int,
    startline::Int,
    endline::Int,
    val::AbstractString,
)
    FST(
        typ,
        startline,
        endline,
        0,
        length(val),
        val,
        nothing,
        Ref(cst),
        AllowNest,
        0,
        line_offset,
        nothing,
    )
end

function FST(
    typ::FNode,
    line_offset::Int,
    startline::Int,
    endline::Int,
    val::AbstractString,
)
    FST(
        typ,
        startline,
        endline,
        0,
        length(val),
        val,
        nothing,
        nothing,
        AllowNest,
        0,
        line_offset,
        nothing,
    )
end

function Base.setindex!(fst::FST, node::FST, ind::Int)
    nodes = fst.nodes::Vector{FST}
    fst.len -= nodes[ind].len
    nodes[ind] = node
    fst.len += node.len
end
Base.getindex(fst::FST, inds...) = (fst.nodes::Vector{FST})[inds...]
Base.lastindex(fst::FST) = length(fst.nodes::Vector{FST})
Base.firstindex(fst::FST) = 1
Base.length(fst::FST) = fst.len
function Base.iterate(fst::FST, state = 1)
    nodes = fst.nodes::Vector{FST}
    if state > length(nodes::Vector{FST})
        return nothing
    end
    return nodes[state], state + 1
end

function Base.insert!(fst::FST, ind::Int, node::FST)
    insert!(fst.nodes::Vector{FST}, ind, node)
    fst.len += node.len
    return
end

# nesting behaviors
must_nest(fst::FST) = fst.nest_behavior === AlwaysNest
cant_nest(fst::FST) = fst.nest_behavior === NeverNest
can_nest(fst::FST) = fst.nest_behavior in (AllowNest, AllowNestButDontRemove)
can_remove(fst::FST) = fst.nest_behavior !== AllowNestButDontRemove

Newline(; length = 0, nest_behavior = AllowNest) =
    FST(NEWLINE, -1, -1, 0, length, "\n", nothing, nothing, nest_behavior, 0, -1, nothing)
Semicolon() = FST(SEMICOLON, -1, -1, 0, 1, ";", nothing, nothing, AllowNest, 0, -1, nothing)
TrailingComma() =
    FST(TRAILINGCOMMA, -1, -1, 0, 0, "", nothing, nothing, AllowNest, 0, -1, nothing)
Whitespace(n) =
    FST(WHITESPACE, -1, -1, 0, n, " "^n, nothing, nothing, AllowNest, 0, -1, nothing)
Placeholder(n) =
    FST(PLACEHOLDER, -1, -1, 0, n, " "^n, nothing, nothing, AllowNest, 0, -1, nothing)
Notcode(startline, endline) =
    FST(NOTCODE, startline, endline, 0, 0, "", nothing, nothing, AllowNest, 0, -1, nothing)
InlineComment(line) =
    FST(INLINECOMMENT, line, line, 0, 0, "", nothing, nothing, AllowNest, 0, -1, nothing)

is_leaf(cst::JuliaSyntax.GreenNode) = !haschildren(cst)
is_leaf(fst::FST) = fst.nodes === nothing

is_punc(cst::JuliaSyntax.GreenNode) =
    kind(cst) in KSet", ( ) [ ] { } @" || kind(cst) === K"." && !haschildren(cst)
is_punc(fst::FST) = fst.typ === PUNCTUATION

is_end(x::JuliaSyntax.GreenNode) = kind(x) === K"end"
is_end(x::FST) = x.typ === KEYWORD && x.val == "end"

is_colon(x::FST) = x.typ === OPERATOR && x.val == ":"

is_comma(fst::FST) = fst.typ === TRAILINGCOMMA || (is_punc(fst) && fst.val == ",")
is_comment(fst::FST) = fst.typ === INLINECOMMENT || fst.typ === NOTCODE

is_identifier(x) = kind(x) === K"Identifier" && !haschildren(x)

function traverse(text, ex, pos = 1)
    if !haschildren(ex)
        println(
            repr(JuliaSyntax.kind(ex)),
            " => ",
            repr(text[pos:prevind(text, pos+JuliaSyntax.span(ex))]),
        )
        return
    end
    for e in children(ex)
        traverse(text, e, pos)
        pos += JuliaSyntax.span(e)
    end
end

function is_multiline(fst::FST)
    fst.endline > fst.startline &&
        fst.typ in (StringN, Vcat, TypedVcat, Ncat, TypedNcat, MacroStr)
end

is_macrocall(fst::FST) = fst.typ === MacroCall || fst.typ === MacroBlock

function is_macrodoc(fst::FST)
    fst.typ === GlobalRefDoc && return true
    fst.typ === MacroBlock &&
        fst[1].typ === Macroname &&
        fst[1][1].val == "@doc" &&
        return true
    return false
end

function is_macrostr(t)
    if kind(t) == K"macrocall" && haschildren(t)
        return contains_macrostr(t[1])
    end
    return false
end

function contains_macrostr(t)
    if kind(t) in KSet"StringMacroName CmdMacroName core_@cmd"
        return true
    elseif kind(t) === "quote"
        return contains_macrostr(t[1])
    elseif kind(t) === K"." && haschildren(t)
        for c in reverse(children(t))
            if contains_macrostr(c)
                return true
            end
        end
    end
    return false
end

function is_func_call(t::JuliaSyntax.GreenNode)
    kind(t) in KSet"call dotcall" && JuliaSyntax.is_prefix_call(t) && return true
    if kind(t) in KSet":: where"
        idx = findfirst(n -> !JuliaSyntax.is_whitespace(n), children(t))
        idx === nothing && return false
        return is_func_call(t[idx])
    elseif kind(t) == K"parens"
        idx = findfirst(
            n -> !JuliaSyntax.is_whitespace(n) && !(kind(n) in KSet"( )"),
            children(t),
        )
        idx === nothing && return false
        return is_func_call(t[idx])
    end
    return false
end

function defines_function(x::JuliaSyntax.GreenNode)
    kind(x) in KSet"function macro" && haschildren(x) && return true
    if is_assignment(x)
        idx = findfirst(n -> !JuliaSyntax.is_whitespace(kind(n)), children(x))
        return is_func_call(x[idx])
    end
    return false
end

function is_if(cst::JuliaSyntax.GreenNode)
    kind(cst) in KSet"if elseif else" && haschildren(cst)
end

function is_try(cst::JuliaSyntax.GreenNode)
    kind(cst) in KSet"try catch finally" && haschildren(cst)
end

function is_custom_leaf(fst::FST)
    fst.typ === NEWLINE ||
        fst.typ === WHITESPACE ||
        fst.typ === PLACEHOLDER ||
        fst.typ === NOTCODE ||
        fst.typ === INLINECOMMENT ||
        fst.typ === TRAILINGCOMMA
end

contains_comment(nodes::Vector{FST}) = findfirst(is_comment, nodes) !== nothing
function contains_comment(fst::FST)
    is_leaf(fst) && return false
    contains_comment(fst.nodes::Vector)
end

function get_args(t::JuliaSyntax.GreenNode)
    nodes = JuliaSyntax.GreenNode[]
    k = kind(t)

    ret = if k == K"where"
        if is_leaf(t[end])
            JuliaSyntax.GreenNode[t[end]]
        else
            get_args(children(t)[end])
        end
    elseif k in KSet"typed_vcat typed_ncat ref curly typed_comprehension call"
        get_args(children(t)[2:end])
    elseif k in KSet"dotcall macrocall"
        get_args(children(t)[3:end])
    else
        get_args(children(t))
    end
    append!(nodes, ret)

    nodes
end

function get_args(args::Vector{JuliaSyntax.GreenNode{T}}) where {T}
    nodes = JuliaSyntax.GreenNode[]
    for c in args
        if is_punc(c) ||
           kind(c) == K";" ||
           JuliaSyntax.is_whitespace(c) ||
           kind(c) in KSet"` ``` \" \"\"\""
            continue
        end
        if kind(c) === K"parameters"
            append!(nodes, get_args(c))
        else
            push!(nodes, c)
        end
    end
    nodes
end

function get_args(::Nothing)
    return JuliaSyntax.GreenNode[]
end

n_args(x) = length(get_args(x))

function is_prev_newline(fst::FST)
    if fst.typ === NEWLINE
        return true
    elseif is_leaf(fst) || length(fst.nodes::Vector) == 0
        return false
    end
    is_prev_newline(fst[end])
end

"""
    `length_to(x::FST, ntyps; start::Int = 1)`

Returns the length to any node type in `ntyps` based off the `start` index.
"""
function length_to(fst::FST, ntyps; start::Int = 1)
    fst.typ in ntyps && return 0, true
    is_leaf(fst) && return length(fst), false
    len = 0
    nodes = fst.nodes::Vector
    for i in start:length(nodes)
        l, found = length_to(nodes[i], ntyps)
        len += l
        found && return len, found
    end
    return len, false
end

is_closer(fst::FST) =
    fst.typ === PUNCTUATION && (fst.val == "}" || fst.val == ")" || fst.val == "]")
is_closer(t::JuliaSyntax.GreenNode) = kind(t) in KSet"} ) ]"

is_opener(fst::FST) =
    fst.typ === PUNCTUATION && (fst.val == "{" || fst.val == "(" || fst.val == "[")
is_opener(t::JuliaSyntax.GreenNode) = kind(t) in KSet"{ ( ["

function is_iterable(t::JuliaSyntax.GreenNode)
    kind(t) in
    KSet"parens tuple vect vcat braces curly comprehension typed_comprehension macrocall ref typed_vcat import using export" ||
        is_func_call(t)
end

function is_iterable(x::FST)
    is_named_iterable(x) && return true
    is_unnamed_iterable(x) && return true
    is_import_expr(x) && return true
    return false
end
is_iterable(::Nothing) = false

function is_unnamed_iterable(x::FST)
    x.typ === TupleN && return true
    x.typ === Vect && return true
    x.typ === Vcat && return true
    x.typ === Ncat && return true
    x.typ === Braces && return true
    x.typ === Comprehension && return true
    x.typ === Brackets && return true
    return false
end

function is_named_iterable(x::FST)
    x.typ === Call && return true
    x.typ === Curly && return true
    x.typ === TypedComprehension && return true
    x.typ === MacroCall && return true
    x.typ === RefN && return true
    x.typ === TypedVcat && return true
    x.typ === TypedNcat && return true
    return false
end

function is_import_expr(x::FST)
    x.typ === Import && return true
    x.typ === Using && return true
    x.typ === Export && return true
    return false
end

"""
Returns whether `fst` can be an iterable argument. For example in
the case of a function call, which is of type `Call`:

```julia
(a, b, c; k1=v1)
```

This would return `true` for `a`, `b`, `c` and `k1=v1` and `false` for all other nodes.
"""
function is_iterable_arg(fst::FST)
    if fst.typ in (PUNCTUATION, KEYWORD, OPERATOR, SEMICOLON) || is_custom_leaf(fst)
        return false
    end
    return true
end

function is_comprehension(x::JuliaSyntax.GreenNode)
    kind(x) in KSet"comprehension typed_comprehension"
end

function is_comprehension(x::FST)
    x.typ === Comprehension && return true
    x.typ === TypedComprehension && return true
    return false
end

function is_block(x::JuliaSyntax.GreenNode)
    is_if(x) && return true
    kind(x) in KSet"do try for while let" && return true
    (kind(x) == K"block" && haschildren(x)) && return true
    (kind(x) == K"quote" && is_block(x[1])) && return true
    return false
end

function is_block(x::FST)
    x.typ in (Block, If, Do, Try, Begin, For, While, Let) ||
        x.typ === Quote && x[1].val == "quote"
end

function is_typedef(fst::FST)
    fst.typ === Struct && return true
    fst.typ === Mutable && return true
    fst.typ === Primitive && return true
    fst.typ === Abstract && return true
    return false
end

function is_opcall(x)
    is_binary(x) && return true
    kind(x) == K"comparison" && return true
    is_chain(x) && return true
    is_unary(x) && return true
    if kind(x) === K"parens"
        idx = findfirst(
            n -> !JuliaSyntax.is_whitespace(kind(n)) && !(kind(n) in KSet"( )"),
            children(x),
        )
        return is_opcall(x[idx])
    end
    return false
end

function is_prefix_op_call(x)
    is_opcall(x) || return false
    idx = findfirst(n -> !JuliaSyntax.is_whitespace(n), children(x))
    isnothing(idx) && return false
    return JuliaSyntax.is_operator(x[idx])
end

function is_gen(x)
    kind(x) in KSet"generator filter"
end

function is_gen(x::FST)
    x.typ === Generator && return true
    x.typ === Filter && return true
    x.typ === Flatten && return true
    return false
end

function _callinfo(x)
    k = kind(x)
    n_operators = 0
    n_args = 0
    for c in children(x)
        if JuliaSyntax.is_whitespace(c) || is_punc(c)
            continue
        elseif haschildren(c) || (!haschildren(c) && !JuliaSyntax.is_operator(c))
            n_args += 1
        elseif k == K"dotcall" && JuliaSyntax.is_operator(c) && kind(c) == K"."
            continue
        elseif JuliaSyntax.is_operator(c)
            n_operators += 1
        end
    end
    return n_operators, n_args
end

function is_unary(x::JuliaSyntax.GreenNode)
    JuliaSyntax.is_unary_op(x) && return true
    if kind(x) === K"call" || (JuliaSyntax.is_operator(x) && haschildren(x))
        nops, nargs = _callinfo(x)
        return nops == 1 && nargs == 1
    end
    return false
end

function is_binary(x)
    if !JuliaSyntax.is_infix_op_call(x) && !(JuliaSyntax.is_operator(x) && haschildren(x))
        return false
    end
    nops, nargs = _callinfo(x)
    return nops == 1 && nargs == 2
end

function is_chain(x::JuliaSyntax.GreenNode)
    kind(x) === K"call" || return false
    nops, nargs = _callinfo(x)
    return nops > 1 && nargs > 2
end

function is_assignment(x::FST)
    if x.typ === Binary
        return !isnothing(x.metadata) && x.metadata.is_assignment
    end

    if (
        x.typ === Const ||
        x.typ === Local ||
        x.typ === Global ||
        x.typ === Outer ||
        x.typ === MacroBlock
    ) && is_assignment(x[end])
        return true
    end

    return false
end

function is_assignment(t::JuliaSyntax.GreenNode)
    if JuliaSyntax.is_prec_assignment(t)
        return !any(c -> kind(c) in KSet"in ∈", children(t))
    end
    return false
end
is_assignment(::Nothing) = false

function is_pairarrow(cst::JuliaSyntax.GreenNode)
    op = get_op(cst)
    isnothing(op) ? false : kind(op) === K"=>"
end

function is_function_or_macro_def(cst::JuliaSyntax.GreenNode)
    !haschildren(cst) && return false
    k = kind(cst)
    (k == K"function" || k == K"macro") && return true

    if JuliaSyntax.is_operator(cst) && k === K"="
        idx = findfirst(n -> !JuliaSyntax.is_whitespace(n), children(cst))
        return is_function_like_lhs(cst[idx])
    end

    return false
end

function is_function_like_lhs(node::JuliaSyntax.GreenNode)
    k = kind(node)
    if k == K"call"
        return true
    elseif k == K"where" || k == K"::"
        return haschildren(node) && is_function_like_lhs(node[1])
    end
    return false
end

function has_leading_whitespace(n::JuliaSyntax.GreenNode)
    kind(n) === K"Whitespace" && return true
    if haschildren(n) && length(children(n)) > 0
        return has_leading_whitespace(n[1])
    end
    return false
end

function remove_empty_notcode(fst::FST)
    is_iterable(fst) && return true
    fst.typ === Binary && return true
    fst.typ === Conditional && return true
    fst.typ === Comparison && return true
    fst.typ === Chain && return true
    return false
end

"""
`cst` is assumed to be a single child node. Returnss true if the node is of the syntactic form `{...}, [...], or (...)`.
"""
function unnestable_node(cst::JuliaSyntax.GreenNode)
    kind(cst) in KSet"tuple vect braces bracescat comprehension parens"
end

function is_binaryop_nestable(::S, cst::JuliaSyntax.GreenNode) where {S<:AbstractStyle}
    if is_assignment(cst) || is_pairarrow(cst)
        idx = findlast(n -> !JuliaSyntax.is_whitespace(n), children(cst))
        return !is_str_or_cmd(cst[idx])
    end
    true
end

function nest_rhs(cst::JuliaSyntax.GreenNode)::Bool
    if defines_function(cst)
        for c in children(cst)
            if is_if(c) || kind(c) in KSet"do try for while let" && haschildren(c)
                return true
            end
        end
    end
    false
end

function get_op(cst::JuliaSyntax.GreenNode)::Union{JuliaSyntax.GreenNode,Nothing}
    JuliaSyntax.is_operator(cst) && return cst
    if is_binary(cst) ||
       kind(cst) in KSet"comparison dotcall call" ||
       is_chain(cst) ||
       is_unary(cst)
        for c in children(cst)
            if kind(cst) === K"dotcall" && kind(c) === K"."
                continue
            elseif JuliaSyntax.is_operator(c)
                return c
            end
        end
    end
    return nothing
end

function op_kind(cst::JuliaSyntax.GreenNode)::Union{JuliaSyntax.Kind,Nothing}
    op = get_op(cst)
    if op !== nothing
        return kind(op)
    end
    return nothing
end

function op_kind(fst::FST)::Union{JuliaSyntax.Kind,Nothing}
    return isnothing(fst.metadata) ? nothing : fst.metadata.op_kind
end

function extract_operator_indices(childs)
    args = findall(n -> !JuliaSyntax.is_whitespace(n), childs)
    op_indices = Int[]
    i = 2
    while i <= length(args)
        push!(op_indices, args[i])
        if i < length(args) &&
           kind(childs[args[i]]) === K"." &&
           !haschildren(childs[args[i]])
            push!(op_indices, args[i+1])
            i += 1
        end
        i += 2
    end
    return op_indices
end

# """
#     is_standalone_shortcircuit(cst::JuliaSyntax.GreenNode)
#
# Returns `true` if the `cst` is a short-circuit expression (uses `&&`, `||`)
# and is *standalone*, meaning it's not directly associated with another statement or
# expression.
#
# ### Examples
#
# ```julia
# # this IS a standalone short-circuit
# a && b
#
# # this IS NOT a standalone short-circuit
# if a && b
# end
#
# # this IS NOT a standalone short-circuit
# var = a && b
#
# # this IS NOT a standalone short-circuit
# @macro a && b
#
# # operation inside parenthesis IS NOT a standalone short-circuit
# # operation outside parenthesis IS a standalone short-circuit
# (a && b) && c
# ```
# """

"""
    eq_to_in_normalization!(fst::FST, always_for_in::Bool, for_in_replacement::String)
    eq_to_in_normalization!(fst::FST, always_for_in::Nothing, for_in_replacement::String)

Transforms

```julia
for i = iter body end

=>

for i in iter body end
```

AND

```julia
for i in 1:10 body end

=>

for i = 1:10 body end
```

`always_for_in=nothing` disables this normalization behavior.

- https://github.com/domluna/JuliaFormatter.jl/issues/34
"""
function eq_to_in_normalization!(fst::FST, always_for_in::Bool, for_in_replacement::String)
    if fst.typ === Binary
        idx = findfirst(n -> n.typ === OPERATOR, fst.nodes::Vector)
        isnothing(idx) && return
        op = fst[idx]
        valid_for_in_op(op.val) || return

        # surround op with ws
        if for_in_replacement != "=" && fst[idx-1].typ !== WHITESPACE
            insert!(fst, idx, Whitespace(1))
            insert!(fst, idx + 2, Whitespace(1))
        end

        if always_for_in
            op.val = for_in_replacement
            op.len = length(op.val)
        elseif op.val == "=" && op_kind(fst[end]) !== K":"
            op.val = "in"
            op.len = length(op.val)
        elseif op.val == "in" && op_kind(fst[end]) === K":"
            op.val = "="
            op.len = length(op.val)
        end
    elseif fst.typ === Block || fst.typ === Brackets || fst.typ === Filter
        past_if = false
        for n in fst.nodes::Vector
            if n.typ === KEYWORD && n.val == "if"
                # [x for x in xs if x in 1:length(ys)]
                # we do not want to convert the binary operations after an "if" keyword.
                past_if = true
            end
            past_if && break
            eq_to_in_normalization!(n, always_for_in, for_in_replacement)
        end
    end
end

eq_to_in_normalization!(::FST, ::Nothing, ::String) = nothing

# Check if the caller of a call is in `list`
# Note that this also works for JuliaSyntax.GreenNode
function caller_in_list(fst::FST, list::Vector{String})
    if is_leaf(fst[1]) && (fst[1].val) in list
        return true
    elseif !is_leaf(fst[1]) && is_leaf(fst[1][1]) && (fst[1][1].val) in list
        return true
    end

    return false
end

function caller_in_list(caller::AbstractString, list::Vector{String})
    return caller in list
end

function is_str_or_cmd(t)
    kind(t) in KSet"doc string cmdstring String CmdString"
end

function is_lazy_op(t)
    kind(t) in KSet"|| &&"
end

function needs_placeholder(
    childs::Vector{JuliaSyntax.GreenNode{T}},
    start_index::Int,
    stop_kind::JuliaSyntax.Kind,
) where {T}
    j = start_index
    while j <= length(childs)
        if !JuliaSyntax.is_whitespace(childs[j])
            return kind(childs[j]) !== stop_kind
        end
        j += 1
    end
    return false
end

next_node_is(nn, k::JuliaSyntax.Kind) =
    kind(nn) === k || (haschildren(nn) && next_node_is(nn[1], k))

next_node_is(nn, f::Function) = f(nn) || (haschildren(nn) && next_node_is(nn[1], f))

"""
    add_node!(
        t::FST,
        n::FST,
        s::State;
        join_lines::Bool = false,
        max_padding::Int = -1,
        override_join_lines_based_on_source::Bool = false,
    )

Appends `n` to `t`.

- `join_lines` if `false` a NEWLINE node will be added and `n` will appear
on the next line, otherwise it will appear on the same line as the previous
node (when printing).
- `max_padding` >= 0 indicates margin of `t` should be based on whether the margin
of `n` + `max_padding` is greater than the current margin of `t`. Otherwise the margin
`n` will be added to `t`.
- `override_join_lines_based_on_source` is only used when `join_lines_based_on_source` option is `true`. In which
`n` is added to `t` as if `join_lines_based_on_source` was false.
"""
function add_node!(
    t::FST,
    n::FST,
    s::State;
    join_lines::Bool = false,
    max_padding::Int = -1,
    override_join_lines_based_on_source::Bool = false,
)
    tnodes = t.nodes::Vector{FST}

    if n.typ === NONE
        if length(tnodes::Vector{FST}) == 0
            t.startline = n.startline
            t.endline = n.endline
        end
        return
    end

    if n.typ === TRAILINGCOMMA
        en = (tnodes::Vector{FST})[end]
        if en.typ === Generator ||
           en.typ === Filter ||
           en.typ === Flatten ||
           en.typ === MacroCall ||
           en.typ === MacroBlock ||
           en.typ === SEMICOLON ||
           # arg = @macro foo
           en.typ === Kw && (en[end].typ === MacroCall || en[end].typ === MacroBlock) ||
           # arg => @macro foo
           en.typ === Binary && (en[end].typ === MacroCall || en[end].typ === MacroBlock)

            # don't add trailing comma in these cases
        elseif is_comma(en) && t.typ === TupleN && n_args(t.ref[]) == 1
            # preserve comma
        elseif s.opts.trailing_comma === nothing
        elseif !s.opts.trailing_comma::Bool
            if is_comma(en)
                t[end] = Whitespace(0)
            end
        elseif is_comma(en)
            t[end] = n
        elseif en.typ === Parameters && length(en.nodes) > 0 && is_comma(en[end])
            en[end] = n
        elseif en.typ === Parameters && length(en.nodes) > 0 && en[end].typ === SEMICOLON
            # do nothing
        else
            t.len += length(n)
            n.startline = t.endline
            n.endline = t.endline
            push!(tnodes::Vector{FST}, n)
        end
        return
    elseif n.typ === NOTCODE
        n.indent = s.indent
        push!(tnodes::Vector{FST}, n)
        return
    elseif n.typ === INLINECOMMENT
        push!(tnodes::Vector{FST}, n)
        return
    elseif is_custom_leaf(n)
        t.len += length(n)
        n.startline = t.endline
        n.endline = t.endline
        push!(tnodes::Vector{FST}, n)
        return
    end

    if n.typ === Block && length(n) == 0
        push!(tnodes::Vector{FST}, n)
        return
    elseif s.opts.import_to_using && n.typ === Import && t.typ !== MacroBlock
        usings = import_to_usings(n, s)
        if length(usings) > 0
            for nn in usings
                add_node!(t, nn, s; join_lines = false, max_padding = 0)
            end
            return
        end
    elseif n.typ === Binary && n[1].typ === Binary && n[1][end].typ === Where
        # normalize FST representation for Where
        binaryop_to_whereop!(n, s)
    end

    if length(tnodes::Vector{FST}) == 0
        t.startline = n.startline
        t.endline = n.endline
        t.len += length(n)
        t.line_offset = n.line_offset
        push!(tnodes, n)
        return
    end

    # if `max_padding` >= 0 `n` should appear on the next line
    # even if it's contrary to the original source.
    if s.opts.join_lines_based_on_source &&
       !override_join_lines_based_on_source &&
       max_padding == -1 &&
       !(
           n.typ === SEMICOLON ||
           is_comma(n) ||
           is_block(t) ||
           t.typ === FunctionN ||
           t.typ === Macro ||
           is_typedef(t) ||
           t.typ === ModuleN ||
           t.typ === BareModule ||
           is_end(n)
       )
        # join based on position in original file
        join_lines = t.endline == n.startline
    end

    if !is_prev_newline(tnodes[end]::FST)
        current_line = t.endline
        notcode_startline = current_line + 1
        notcode_endline = n.startline - 1
        nt = (tnodes[end]::FST).typ

        if notcode_startline <= notcode_endline
            # If there are comments in between node elements
            # nesting is forced in an effort to preserve them.

            rm_block_nl =
                s.opts.remove_extra_newlines &&
                t.typ !== ModuleN &&
                (n.typ === Block || is_end(n))

            nest = true
            if remove_empty_notcode(t) || rm_block_nl
                nest = false
                for l in notcode_startline:notcode_endline
                    if hascomment(s.doc, l)
                        nest = true
                        break
                    end
                end
            end

            t.nest_behavior = AlwaysNest

            # If the previous node type is WHITESPACE - reset it.
            # This fixes cases similar to the one shown in issue #51.
            nt === WHITESPACE && (tnodes[end]::FST = Whitespace(0))

            if hascomment(s.doc, current_line)
                add_node!(t, InlineComment(current_line), s)
            end

            if nt !== PLACEHOLDER
                add_node!(t, Newline(nest_behavior = AlwaysNest), s)
            elseif hascomment(s.doc, current_line) && nt === PLACEHOLDER
                # swap PLACEHOLDER (will be NEWLINE) with INLINECOMMENT node
                idx = length(tnodes::Vector{FST})
                tnodes[idx-1], tnodes[idx] = tnodes[idx], tnodes[idx-1]
            end

            if nest
                add_node!(t, Notcode(notcode_startline, notcode_endline), s)
                add_node!(t, Newline(nest_behavior = AlwaysNest), s)
            end
        elseif !join_lines
            if hascomment(s.doc, current_line) && current_line != n.startline
                add_node!(t, InlineComment(current_line), s)
            end
            add_node!(t, Newline(nest_behavior = AlwaysNest), s)
        elseif nt === PLACEHOLDER &&
               current_line != n.startline &&
               hascomment(s.doc, current_line)
            t.nest_behavior = AlwaysNest
            add_node!(t, InlineComment(current_line), s)
            # swap PLACEHOLDER (will be NEWLINE) with INLINECOMMENT node
            idx = length(tnodes)
            tnodes[idx-1], tnodes[idx] = tnodes[idx], tnodes[idx-1]
        elseif nt === WHITESPACE &&
               hascomment(s.doc, current_line) &&
               current_line != n.startline
            # rely on the whitespace tracked for the inline comment
            tnodes[end] = Whitespace(0)
            add_node!(t, InlineComment(current_line), s)
            add_node!(t, Newline(nest_behavior = AlwaysNest), s)
        end
    end

    if n.startline < t.startline || t.startline == -1
        t.startline = n.startline
    end
    if n.endline > t.endline || t.endline == -1
        t.endline = n.endline
    end

    if !join_lines && is_end(n)
        # end keyword isn't useful w.r.t margin lengths
    elseif t.typ === StringN
        # The length of this node is the length of
        # the longest string. The length of the string is
        # only considered "in the positive" when it's past
        # the hits the initial """ offset, i.e. `t.indent`.
        t.len = max(t.len, n.indent + length(n) - t.indent)
    elseif is_multiline(n)
        if is_iterable(t) && n_args(t.ref[]) > 1
            t.nest_behavior = AlwaysNest
        end
        t.len += length(n)
    elseif max_padding >= 0
        t.len = max(t.len, length(n) + max_padding)
    else
        t.len += length(n)
    end

    if n.typ === Parameters
        if n.nest_behavior === AlwaysNest
            t.nest_behavior = n.nest_behavior
        end
        # no args before kwargs
        placeholder_ind = findfirst(n -> n.typ === PLACEHOLDER, tnodes)
        if placeholder_ind == length(tnodes)
            t[placeholder_ind] = Whitespace(0)
        end
        for nn in n.nodes
            push!(tnodes, nn)
            if n.startline < t.startline || t.startline == -1
                t.startline = n.startline
            end
            if n.endline > t.endline || t.endline == -1
                t.endline = n.endline
            end
        end
        return
    end

    push!(tnodes, n)
    return
end
