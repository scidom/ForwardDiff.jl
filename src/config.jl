#######
# Tag #
#######

struct Tag{F,H} end

# Here, we could've just as easily used `hash`; however, this
# is unsafe/undefined behavior if `hash(::Type{V})` is overloaded
# in a module loaded after ForwardDiff. Thus, we instead use
# `hash(Symbol(V))`, which is somewhat safer since it's far less
# likely that somebody would overwrite the Base definition for
# `Symbol(::DataType)` or `hash(::Symbol)`.
@generated function Tag(::Type{F}, ::Type{V}) where {F,V}
    H = hash(Symbol(V))
    return quote
        $(Expr(:meta, :inline))
        Tag{F,$H}()
    end
end

#########
# Chunk #
#########

struct Chunk{N} end

function Chunk(input_length::Integer, threshold::Integer = DEFAULT_CHUNK_THRESHOLD)
    N = pickchunksize(input_length, threshold)
    return Chunk{N}()
end

function Chunk(x::AbstractArray, threshold::Integer = DEFAULT_CHUNK_THRESHOLD)
    return Chunk(length(x), threshold)
end

# Constrained to `N <= threshold`, minimize (in order of priority):
#   1. the number of chunks that need to be computed
#   2. the number of "left over" perturbations in the final chunk
function pickchunksize(input_length, threshold = DEFAULT_CHUNK_THRESHOLD)
    if input_length <= threshold
        return input_length
    else
        nchunks = round(Int, input_length / DEFAULT_CHUNK_THRESHOLD, RoundUp)
        return round(Int, input_length / nchunks, RoundUp)
    end
end

##################
# AbstractConfig #
##################

abstract type AbstractConfig{T<:Tag,N} end

struct ConfigMismatchError{F,G,H} <: Exception
    f::F
    cfg::AbstractConfig{Tag{G,H}}
end

function Base.showerror{F,G}(io::IO, e::ConfigMismatchError{F,G})
    print(io, "The provided configuration (of type $(typeof(e.cfg))) was constructed for a",
              " function other than the current target function. ForwardDiff cannot safely",
              " perform differentiation in this context; see the following issue for details:",
              " https://github.com/JuliaDiff/ForwardDiff.jl/issues/83. You can resolve this",
              " problem by constructing and using a configuration with the appropriate target",
              " function, e.g. `ForwardDiff.GradientConfig($(e.f), x)`")
end

Base.copy(cfg::AbstractConfig) = deepcopy(cfg)

@inline chunksize{T,N}(::AbstractConfig{T,N}) = N

##################
# GradientConfig #
##################

struct GradientConfig{T,V,N,D} <: AbstractConfig{T,N}
    seeds::NTuple{N,Partials{N,V}}
    duals::D
end

function GradientConfig{V,N,F,T}(::F,
                                 x::AbstractArray{V},
                                 ::Chunk{N} = Chunk(x),
                                 ::T = Tag(F, V))
    seeds = construct_seeds(Partials{N,V})
    duals = similar(x, Dual{T,V,N})
    return GradientConfig{T,V,N,typeof(duals)}(seeds, duals)
end

##################
# JacobianConfig #
##################

struct JacobianConfig{T,V,N,D} <: AbstractConfig{T,N}
    seeds::NTuple{N,Partials{N,V}}
    duals::D
end

function JacobianConfig{V,N,F,T}(::F,
                                 x::AbstractArray{V},
                                 ::Chunk{N} = Chunk(x),
                                 ::T = Tag(F, V))
    seeds = construct_seeds(Partials{N,V})
    duals = similar(x, Dual{T,V,N})
    return JacobianConfig{T,V,N,typeof(duals)}(seeds, duals)
end

function JacobianConfig{Y,X,N,F,T}(::F,
                                   y::AbstractArray{Y},
                                   x::AbstractArray{X},
                                   ::Chunk{N} = Chunk(x),
                                   ::T = Tag(F, X))
    seeds = construct_seeds(Partials{N,X})
    yduals = similar(y, Dual{T,Y,N})
    xduals = similar(x, Dual{T,X,N})
    duals = (yduals, xduals)
    return JacobianConfig{T,X,N,typeof(duals)}(seeds, duals)
end

#################
# HessianConfig #
#################

struct HessianConfig{T,V,N,D,H,DJ} <: AbstractConfig{T,N}
    jacobian_config::JacobianConfig{Tag{Void,H},V,N,DJ}
    gradient_config::GradientConfig{T,Dual{Tag{Void,H},V,N},D}
end

function HessianConfig{F,V}(f::F,
                            x::AbstractArray{V},
                            chunk::Chunk = Chunk(x),
                            tag::Tag = Tag(F, Dual{Void,V,0}))
    jacobian_config = JacobianConfig(nothing, x, chunk)
    gradient_config = GradientConfig(f, jacobian_config.duals, chunk, tag)
    return HessianConfig(jacobian_config, gradient_config)
end

function HessianConfig{F,V}(result::DiffResult,
                            f::F,
                            x::AbstractArray{V},
                            chunk::Chunk = Chunk(x),
                            tag::Tag = Tag(F, Dual{Void,V,0}))
    jacobian_config = JacobianConfig(nothing, DiffBase.gradient(result), x, chunk)
    gradient_config = GradientConfig(f, jacobian_config.duals[2], chunk, tag)
    return HessianConfig(jacobian_config, gradient_config)
end
