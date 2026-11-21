# Same frozen inputs and original methods; new lazy singleton-to-pair cascade.
include(joinpath(@__DIR__, "bounds.jl"))

function cascadecheck(data,a)
    n=length(data.q);gap=data.U-a.gamma;kmax=min(n,floor(Int,data.U+1e-7))
    Linv=inv(a.F.L)
    Vs=[Matrix(Symmetric(Linv*Q[1:24,1:24]*Linv')) for Q in data.Qs]
    rho=max.(0.,[dot(a.x0,Q*a.x0) for Q in data.Qs]);rho .+= pad(maximum(rho))
    single=[eigmax(Symmetric(V))+1e-9 for V in Vs]
    singlescores=Float64[]
    for k=1:kmax
        budget=k-gap
        budget>0 || return false,singlescores,"anchor_gap",0
        push!(singlescores,sum(sort(single+rho/budget;rev=true)[1:k]))
    end
    all(singlescores .< 1-1e-7) && return true,singlescores,"singleton_stage",0
    pairvals=Float64[];pairrho=Float64[]
    for j=2:n,i=1:j-1
        push!(pairvals,eigmax(Symmetric(Vs[i]+Vs[j]))+1e-9)
        push!(pairrho,rho[i]+rho[j])
    end
    scores=copy(singlescores)
    for k=1:kmax
        scores[k]<1-1e-7 && continue
        budget=k-gap
        score=(k÷2)*maximum(pairvals+pairrho/budget)+(k%2)*maximum(single+rho/budget)
        scores[k]=min(scores[k],score)
        scores[k]<1-1e-7 || return false,scores,"pair_stage_inconclusive",length(pairvals)
    end
    true,scores,"pair_stage",length(pairvals)
end

function cascade_trial(folder)
    t=time_ns();data=prepare(folder);t1=time_ns()
    result=Dict{String,Any}("case"=>basename(folder),"mode"=>"cascade","N"=>length(data.q),
        "upper"=>data.U,"full_support"=>data.full,"input_seconds"=>(t1-t)/1e9)
    if !data.full
        merge!(result,Dict("status"=>"inapplicable","reason"=>"candidate_rejects_observations",
            "anchor_seconds"=>0.,"check_seconds"=>0.,"total_seconds"=>(time_ns()-t)/1e9));return result
    end
    a=anchor(data);t2=time_ns()
    if isnothing(a)
        merge!(result,Dict("status"=>"inconclusive","reason"=>"anchor_not_available",
            "anchor_seconds"=>(t2-t1)/1e9,"check_seconds"=>0.,"total_seconds"=>(time_ns()-t)/1e9));return result
    end
    ok,scores,reason,npairs=cascadecheck(data,a)
    gap=(data.U-a.gamma)/max(1.,data.U);t3=time_ns()
    merge!(result,Dict("status"=>ok && -1e-6<=gap<=1e-6 ? "numerically_certified" : "inconclusive",
        "reason"=>reason,"lower"=>a.gamma,"relative_gap"=>gap,"scores"=>scores,"pair_eigenvalues"=>npairs,
        "sdp_status"=>a.status,"anchor_seconds"=>(t2-t1)/1e9,
        "check_seconds"=>(t3-t2)/1e9,"total_seconds"=>(t3-t)/1e9))
end

