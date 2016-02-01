#################
# API Utilities #
#################

const KWARG_DEFAULTS = (:all => false, :chunk => nothing, :multithread => false,
                        :input_length => nothing, :input_mutates => false,
                        :output_length => nothing, :output_mutates => false)

iskwarg(ex) = isa(ex, Expr) && (ex.head == :kw || ex.head == :(=))

function separate_kwargs(args)
    # if called as `f(args...; kwargs...)`, i.e. with a semicolon
    if isa(first(args), Expr) && first(args).head == :parameters
        kwargs = first(args).args
        args = args[2:end]
    else # if called as `f(args..., kwargs...)`, i.e. with a comma
        i = findfirst(iskwarg, args)
        if i == 0
            kwargs = tuple()
        else
            kwargs = args[i:end]
            args = args[1:i-1]
        end
    end
    return args, kwargs
end

function arrange_kwargs(kwargs, defaults, order)
    badargs = setdiff(map(kw -> kw.args[1], kwargs), order)
    @assert isempty(badargs) "unrecognized keyword arguments: $(badargs)"
    return [:(Val{$(getkw(kwargs, kwsym, defaults))}) for kwsym in order]
end

function getkw(kwargs, kwsym, defaults)
    for kwexpr in kwargs
        if kwexpr.args[1] == kwsym
            return kwexpr.args[2]
        end
    end
    return default_value(defaults, kwsym)
end

function default_value(defaults, kwsym)
    for kwpair in defaults
        if kwpair.first == kwsym
            return kwpair.second
        end
    end
    throw(KeyError(kwsym))
end

const AUTO_CHUNK_THRESHOLD = 11

function pick_chunk(input_length)
    if input_length <= AUTO_CHUNK_THRESHOLD
        return input_length
    else
        # Constrained to chunk <= AUTO_CHUNK_THRESHOLD, minimize (in order of priority):
        #   1. the number of chunks that need to be computed
        #   2. the number of "left over" perturbations in the final chunk
        nchunks = round(Int, input_length / AUTO_CHUNK_THRESHOLD, RoundUp)
        return round(Int, input_length / nchunks, RoundUp)
    end
end
