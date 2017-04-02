__precompile__()
module RemoteEval

    using Reexport
    @reexport using Gadfly

    export eval_command_remotely

    # Compatitbily with 0.5
    if !isdefined(Base,:(showlimited))
        showlimited(x) = show(x)
        showlimited(io::IO,x) = show(io,x)
    else
        import Base.showlimited
    end

    #FIXME dirty hack
    function clean_error_msg(s::String)
        r  = Regex("(.*)in eval_command_remotely.*","s")
        m = match(r,s)
        m != nothing && return m.captures[1]
        s
    end
    
    function trim(s::AbstractString,L::Int)#need to be AbstracString to accept SubString
    if length(s) > L
        return string(s[1:L],"...")
    end
    s
    end

    function eval_command_remotely(cmd::String,eval_in::Module)

        ex = Base.parse_input_line(cmd)
        ex = expand(ex)

        evalout = ""
        v = :()
        try
            v = eval(eval_in,ex)
            eval(eval_in, :(ans = $(Expr(:quote, v))))

            evalout = v == nothing ? "" : sprint(showlimited,v)
        catch err
            bt = catch_backtrace()
            evalout = clean_error_msg( sprint(showerror,err,bt) )
        end

        evalout = trim(evalout,2000)
        finalOutput = evalout == "" ? "" : "$evalout\n"
        v = typeof(v) <: Gadfly.Plot ? v : nothing #FIXME refactor. This avoid sending types that
        # are not defined on worker 1
        
        return finalOutput, v
    end

end