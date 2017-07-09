__precompile__()
module RemoteEval

    using Reexport
    @reexport using Gadfly

    export eval_command_remotely

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

    function format_output(x)
        io = IOBuffer()
        io = IOContext(io,:display_size=>(20,20))
        io = IOContext(io,:limit=>true)
        show(io,MIME"text/plain"(),x)
        String(take!(io.io))
    end

    function eval_command_remotely(cmd::String,eval_in::Module)

        ex = Base.parse_input_line(cmd)
        ex = expand(ex)

        evalout = ""
        v = :()
        try
            v = eval(eval_in,ex)
            eval(eval_in, :(ans = $(Expr(:quote, v))))

            evalout = v == nothing ? "" : format_output(v)

        catch err
            bt = catch_backtrace()
            evalout = clean_error_msg( sprint(showerror,err,bt) )
        end

        evalout = trim(evalout,4000)
        finalOutput = evalout == "" ? "" : "$evalout\n"
        v = typeof(v) <: Gadfly.Plot ? v : nothing #FIXME refactor. This avoid sending types that
        # are not defined on worker 1

        return finalOutput, v
    end

end
