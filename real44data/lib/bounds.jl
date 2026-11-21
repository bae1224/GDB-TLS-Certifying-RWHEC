# Complete, fixed-candidate certification calls, from raw A/B CSVs.
# Reimplements the existing research prototype in Julia for common-language
# timings. No geometric pair bound, translation box, or candidate refit is used.
include(joinpath(@__DIR__, "costs.jl"))
using Statistics
pad(values...) = 1e-8 + 2e-12sum(abs, values)

function prepare(folder)
    meta=TOML.parsefile(joinpath(folder,"metadata.toml"))
    A=posecsv(joinpath(folder,"A.csv")); B=posecsv(joinpath(folder,"B.csv"))
    X=readdlm(joinpath(folder,"X_candidate.csv"),',',Float64)
    Y=readdlm(joinpath(folder,"Y_candidate.csv"),',',Float64)
    for P in (X,Y)
        R=P[1:3,1:3]
        @assert norm(R'R-I)<1e-7 && abs(det(R)-1)<1e-7
    end
    x=pack(X,Y)
    Qs=[costmat(a,b,meta["rot_weight"],meta["translation_weight"])/meta["tau2"] for (a,b) in zip(A,B)]
    q=[dot(x,Q*x) for Q in Qs]; U=sum(min.(q,1.))
    (;Qs,x,q,U,full=all(q .< 1))
end

function anchor(data)
    Q=sum(data.Qs); T=Q[1:6,1:6]; V=Q[1:6,7:25]; P=pinv(T;rtol=1e-10)
    @assert norm(V-T*P*V)<1e-7max(1.,norm(V))
    C=Matrix(Symmetric(Q[7:25,7:25]-V'P*V))
    H,b=get_double_rotation_constraints(true,true,3)
    model=Model(optimizer_with_attributes(COSMO.Optimizer,"verbose"=>false,
        "eps_abs"=>1e-10,"eps_rel"=>1e-10,"max_iter"=>100000,"time_limit"=>30.))
    @variable(model,Z[1:19,1:19],PSD)
    refs=@constraint(model,[i=1:length(b)],sum(H[i,r,c]*Z[r,c] for r=1:19,c=1:19)==b[i])
    scale=max(opnorm(C),1.)
    @objective(model,Min,sum(C[r,c]/scale*Z[r,c] for r=1:19,c=1:19))
    optimize!(model)
    has_duals(model) || return nothing
    y=dual.(refs)*scale; M=zeros(25,25)
    M[7:25,7:25]=sum(y[i]*H[i,:,:] for i=1:length(b))
    beta=dot(y,b); S=Q-M
    F=cholesky(Symmetric(S[1:24,1:24]);check=false)
    issuccess(F) || return nothing
    z0=-(F\S[1:24,25]);x0=[z0;1.]
    cross=dot(S[1:24,25],z0)
    gamma=beta+S[25,25]+cross-pad(beta,S[25,25],cross)
    @assert abs(dot(data.x,M*data.x)-beta)<1e-6
    (;S,beta,gamma,F,x0,status=string(termination_status(model)))
end

function groupcheck(data,a,mode)
    n=length(data.q);gap=data.U-a.gamma;kmax=min(n,floor(Int,data.U+1e-7))
    Linv=inv(a.F.L)
    Vs=[Matrix(Symmetric(Linv*Q[1:24,1:24]*Linv')) for Q in data.Qs]
    rho=max.(0.,[dot(a.x0,Q*a.x0) for Q in data.Qs]);rho .+= pad(maximum(rho))
    single=[eigmax(Symmetric(V))+1e-9 for V in Vs]
    scores=Float64[];pairvals=Float64[];pairrho=Float64[]
    if mode=="pair"
        for j=2:n,i=1:j-1
            push!(pairvals,eigmax(Symmetric(Vs[i]+Vs[j]))+1e-9)
            push!(pairrho,rho[i]+rho[j])
        end
    end
    for k=1:kmax
        budget=k-gap
        budget>0 || return false,scores,"anchor_gap",0
        w=single+rho/budget
        score=mode=="single" ? sum(sort(w;rev=true)[1:k]) :
            (k÷2)*maximum(pairvals+pairrho/budget)+(k%2)*maximum(w)
        push!(scores,score)
        score<1-1e-7 || return false,scores,"sufficient_condition_failed",0
    end
    true,scores,"all_deletions_excluded",0
end

# Strong direct comparator: enumerate D and minimize the SAME fixed-dual
# Lagrangian exactly over the affine lifted coordinates. This is tighter than
# the spectral deletion envelope but has combinatorial support cost.
function enumeratecheck(data,a; maxsets=1_000_000, seconds=10.)
    start=time_ns();n=length(data.q);U=data.U;kmax=min(n,floor(Int,U+1e-7))
    count=Ref(0);reason=Ref("all_deletions_excluded");worst=Ref(Inf)
    function visit(first,remaining,total,Sd)
        if remaining==0
            count[]+=1
            if count[]>maxsets || (time_ns()-start)/1e9>seconds
                reason[]="enumeration_limit";return false
            end
            S=a.S-Sd;F=cholesky(Symmetric(S[1:24,1:24]);check=false)
            if !issuccess(F);reason[]="nonpositive_deleted_hessian";return false;end
            cross=dot(S[1:24,25],F\S[1:24,25])
            lower=total+a.beta+S[25,25]-cross-pad(a.beta,S[25,25],cross)
            worst[]=min(worst[],lower)
            if lower<=U+1e-7;reason[]="fixed_dual_bound_inconclusive";return false;end
            return true
        end
        for i=first:n-remaining+1
            visit(i+1,remaining-1,total,Sd+data.Qs[i]) || return false
        end
        true
    end
    for k=1:kmax
        visit(1,k,k,zeros(25,25)) || return false,Float64[],reason[],count[]
    end
    true,Float64[],reason[],count[]
end

function trial(folder,mode)
    t=time_ns();data=prepare(folder);t1=time_ns()
    result=Dict{String,Any}("case"=>basename(folder),"mode"=>mode,"N"=>length(data.q),
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
    ok,scores,reason,sets=mode=="enumerate" ? enumeratecheck(data,a) : groupcheck(data,a,mode)
    gap=(data.U-a.gamma)/max(1.,data.U);t3=time_ns()
    merge!(result,Dict("status"=>ok && -1e-6<=gap<=1e-6 ? "numerically_certified" : "inconclusive",
        "reason"=>reason,"lower"=>a.gamma,"relative_gap"=>gap,"scores"=>scores,"sets"=>sets,
        "sdp_status"=>a.status,"anchor_seconds"=>(t2-t1)/1e9,
        "check_seconds"=>(t3-t2)/1e9,"total_seconds"=>(t3-t)/1e9))
end

