__precompile__()
module RemoteEval

    using Reexport
    @reexport using Gadfly
    
    export eval_command_remotely, isdone, interrupt_task, run_task, eval_symbol

    function __init__()
        global _run_task = @schedule begin end
    end

    run_task() = _run_task
    isdone() = _run_task.state == :done
    interrupt_task() = @schedule Base.throwto(_run_task, InterruptException())
    
    #FIXME dirty hack
    function clean_error_msg(s::String)
    
        if VERSION < v"0.6.0"
    
            r  = Regex("(.*)in eval_command_remotely.*","s")
            m = match(r,s)
            m != nothing && return m.captures[1]
        else
            r  = Regex("(.*)\\[\\d\\] eval_command_remotely.*""","s")
            m = match(r,s)
            m != nothing && return m.captures[1]
        end
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
        global _run_task = @schedule _eval_command_remotely(cmd,eval_in)
        nothing
    end
    
    function _eval_command_remotely(cmd::String,eval_in::Module)
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

    # Some utilities to modify nested QuoteNode's
    
    "takes :A,:B,:C and return :(A.B.C)"
    qn(a,b) = Expr(:(.),a,QuoteNode(b))
    qn(a,b,rest...) = qn(qn(a,b), rest...)


    "parse :(A.B.C) and returns an array of symbols with :A,:B,:C"
    qs(ex::Expr) = qs(ex,Symbol[])
    qs(s::Symbol) = [s]
    function qs(ex::Expr,out::Vector{Symbol}) 

        if ex.head == :(.)
            qs(ex.args[1],out)
            qs(ex.args[2],out)
        end    
        out
    end   
    qs(s::Symbol,out::Vector{Symbol}) = push!(out,s)
    qs(s::QuoteNode,out::Vector{Symbol}) = qs(s.value,out)

    #qn(:A, qs(:(B.C))...) == :(A.B.C)
    #qn(:A,:B,:C) == :(A.B.C)


    """
        eval_symbol(s,eval_in::Module)
        
    eval s in module eval_in, used for data hint.
        
    """
    function eval_symbol(ex::Union{Expr,Symbol},eval_in::Module)
    
        #this prepends eval_in so we can evaluate in Main directly :(eval_in.ex)
        ex = qn(eval_in, qs(ex)...)
        
        evalout = try eval(Main,ex) catch err "" end
    end

    function get_doc(s::Symbol,eval_in::Module)
        Base.Docs.doc(
            Base.Docs.Binding(eval_in,s)
        )
    end
    function get_doc(ex::Expr,eval_in::Module)
        try eval(eval_in,:( @doc $ex )) catch "" end 
    end

   
end
