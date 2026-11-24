# Reimplementation of the published TLS sparse moment/SOS certificate.
# SSR basis: [x; theta_1*x; ...; theta_N*x], x=[tX;tY;vecRX;vecRY;1].
# Yang & Carlone, TPAMI 2022, (15)--(22); DRS: NeurIPS 2020, Sec. 5.
# This is a new RWHE adapter, NOT the authors' MATLAB DRS or STRIDE software.
# No translation bound, no support restriction, no candidate refit.
include(joinpath(@__DIR__, "common.jl"))
include(joinpath(@__DIR__, "verified_bound.jl"))
using Random

struct SSRProjection
    K::Int
    basis::Matrix{Float64}
end

function make_projection(K, W)
    mats=[vec(W'*g*W) for g in manifold()]
    F=svd(hcat(mats...))
    rank=count(>(1e-10*maximum(F.S)), F.S)
    SSRProjection(K, F.U[:,1:rank])
end

# Frobenius orthogonal projection onto the homogeneous primal equality
# subspace: common diagonal block, symmetric off-diagonal blocks, and all
# representable SO(3) identities g(x)*theta_i*theta_j=0.
function project_L(P::SSRProjection, X)
    K=P.K
    blocks=reshape(permutedims(reshape(X,25,K,25,K),(1,3,2,4)),625,K*K)
    for j=1:K,i=1:K
        idx=i+(j-1)*K
        B=reshape(view(blocks,:,idx),25,25)
        B[:,:]=(B+B')/2
    end
    blocks -= P.basis*(P.basis'*blocks)
    diagonal=zeros(625)
    for i=1:K; diagonal .+= view(blocks,:,i+(i-1)*K);end
    diagonal ./= K
    for i=1:K;blocks[:,i+(i-1)*K]=diagonal;end
    out=reshape(permutedims(reshape(blocks,25,25,K,K),(1,3,2,4)),25K,25K)
    Matrix(Symmetric((out+out')/2))
end

function physical_slack(S,W)
    K=size(S,1)÷25
    V=inv(W)
    out=similar(S)
    for j=1:K,i=1:K
        a=(25(i-1)+1):25i;b=(25(j-1)+1):25j
        out[a,b]=V'*view(S,a,b)*V
    end
    Matrix(Symmetric((out+out')/2))
end

# Schur-complement proposal only. The returned screening value is NOT a lower
# bound: finite nullspace and affine residuals are checked in verified_bound.jl.
function schur_proposal(S,W,target;translation_basis=nothing,translation_null=nothing)
    K=size(S,1)÷25
    B=physical_slack(S,W)
    tidx=[25i+j for i=0:K-1 for j=1:6]
    ridx=[25i+j for i=0:K-1 for j=7:25]
    T=Matrix(Symmetric(B[tidx,tidx]))
    cross=B[tidx,ridx]
    null_error=0.0
    if !isnothing(translation_basis)
        # All-outlier and one-inlier support rays force a larger nullspace:
        # t_i=-t_0+h_i with h_i in ker([R_Ai,-I]). These are directions of
        # constant polynomial cost, so every valid PSD slack annihilates them.
        Ut=translation_null
        null_error=max(norm(T*Ut,Inf),norm(cross'*Ut,Inf))
        Vt=translation_basis
        T=Matrix(Symmetric(Vt'*T*Vt));cross=Vt'*cross
    end
    F=cholesky(Symmetric(T);check=false)
    if !issuccess(F)
        return (;lower=-Inf, delta=Inf, translation_pd=false, schur_min=-Inf,null_error)
    end
    R=Matrix(Symmetric(B[ridx,ridx]-cross'*(F\cross)))
    emin=eigmin(Symmetric(R))
    padding=1e-10+5e-14*opnorm(R,Inf)
    delta=max(0.,-emin+padding)
    lower=target-7K*delta
    (;lower,delta,translation_pd=true,schur_min=emin,null_error)
end

function ssr_setup(data;precondition=true)
    n=length(data.q);K=n+1
    W=Matrix{Float64}(I,25,25)
    if precondition
        a=anchor(data)
        if !isnothing(a)
            W[1:24,1:24]=inv(a.F.L')
            W[1:24,25]=a.x0[1:24]
        end
    end
    Qs=[Matrix(Symmetric(W'*Q*W)) for Q in data.Qs]
    E=zeros(25,25);E[25,25]=1.
    C=zeros(25K,25K);initial=zeros(25K,25K)
    for i=1:n
        j=(25i+1):25(i+1)
        C[1:25,1:25] .+= (Qs[i]+E)/2
        C[1:25,j]=(Qs[i]-E)/4
        C[j,1:25]=(Qs[i]-E)/4
        # The identity theta_i^2=1 expresses each nonnegative TLS term as
        # 1/4 ||L_i(x+theta_i*x)||^2 + 1/4 (1-theta_i)^2.
        initial[1:25,1:25] .+= (Qs[i]+E)/4
        initial[j,j]=(Qs[i]+E)/4
        initial[1:25,j]=(Qs[i]-E)/4
        initial[j,1:25]=(Qs[i]-E)/4
    end
    target=data.U-0.5e-6*max(1.,data.U)
    Ebig=zeros(25K,25K);Ebig[25,25]=1.
    P=make_projection(K,W)
    fixed=project_L(P,C-target*Ebig)
    y=W\data.x
    theta=ifelse.(data.q .<= 1,1.,-1.)
    v=kron([1.;theta],y)
    cost_error=abs(dot(v,C*v)-data.U)
    moment=v*v'
    embedding_error=norm(project_L(P,moment)-moment,Inf)/max(1.,norm(moment,Inf))
    @assert cost_error<1e-7*max(1.,data.U)
    @assert embedding_error<1e-7
    R=zeros(3n,6K)
    for i=1:n
        F=eigen(Symmetric(data.Qs[i][1:6,1:6]))
        idx=findall(>(1e-8*maximum(F.values)),F.values)
        @assert length(idx)==3
        Mi=Diagonal(sqrt.(F.values[idx]))*F.vectors[:,idx]'
        R[(3i-2):3i,1:6]=Mi
        R[(3i-2):3i,(6i+1):6(i+1)]=Mi
    end
    F=svd(R;full=true)
    translation_basis=F.V[:,1:3n]
    translation_null=F.V[:,3n+1:end]
    null_vectors=zeros(25K,size(translation_null,2))
    for i=0:n
        phys=zeros(25,size(translation_null,2));phys[1:6,:]=translation_null[(6i+1):6(i+1),:]
        null_vectors[(25i+1):25(i+1),:]=W\phys
    end
    null_basis=Matrix(qr(null_vectors).Q)[:,1:size(null_vectors,2)]
    @assert norm(project_L(P,initial-C),Inf)<1e-8
    (;P,W,C,fixed,target,cost_error,embedding_error,null_basis,translation_basis,translation_null,initial)
end

function ssr_trial(folder;seconds=30.,maxiter=10000,gamma=1.8,saveprefix="")
    t=time_ns();data=prepare(folder)
    ctx=certificate_context(folder,data)
    setup=ssr_setup(data)
    (;P,W,C,fixed,target,null_basis,translation_basis,translation_null)=setup
    Z=copy(setup.initial);t_setup=time_ns()
    best=0.;bestS=copy(setup.initial);best_info=nothing
    history=Dict{String,Any}[];iteration=0;status="time_limit"
    affine_error=Inf
    while (time_ns()-t)/1e9 < seconds && iteration<maxiter
        iteration+=1
        # Orthogonal projection onto the PSD face forced by unbounded TLS.
        V=null_basis
        face=Z-V*(V'*Z)-(Z*V)*V'+V*(V'*Z*V)*V'
        F=eigen(Symmetric(face))
        cone=(F.vectors .* max.(0.,F.values)')*F.vectors'
        reflection=2cone-Z
        affine=reflection-project_L(P,reflection)+fixed
        Z .+= gamma*(affine-cone)
        if iteration==1 || iteration%10==0
            check=checked_lower_bound(affine,W,target,ctx;translation_basis,translation_null)
            if check.lower>best || isnothing(best_info)
                best=check.lower;bestS=affine;best_info=check
            end
            gap=(IV(ctx.U)-IV(best))/IV(max(1.,ctx.U))
            gap=gap.hi
            push!(history,Dict("iteration"=>iteration,"seconds"=>(time_ns()-t)/1e9,
                "lower"=>best,"gap"=>gap,"translation_pd"=>check.translation_pd))
            if 0<=gap<=1e-6
                status="numerically_certified";break
            end
        end
        if iteration>=maxiter;status="iteration_limit";end
    end
    finalS=Z-project_L(P,Z)+fixed
    check=checked_lower_bound(finalS,W,target,ctx;translation_basis,translation_null)
    if check.lower>best || isnothing(best_info)
        bestS=finalS;best=check.lower;best_info=check
    end
    finalgap=((IV(ctx.U)-IV(best))/IV(max(1.,ctx.U))).hi
    if 0<=finalgap<=1e-6;status="numerically_certified";end
    affine_error=norm(project_L(P,bestS)-fixed,Inf)/max(1.,norm(fixed,Inf))
    @assert affine_error<1e-7
    total=(time_ns()-t)/1e9
    if !isempty(saveprefix)
        mkpath(dirname(saveprefix))
        open(saveprefix*"_slack.f64","w") do io;write(io,bestS);end
        writedlm(saveprefix*"_W.csv",W,',')
    end
    Dict{String,Any}("case"=>basename(folder),"mode"=>"ssr_drs_rwhe",
      "status"=>status,"upper"=>ctx.U,"nominal_upper"=>data.U,"lower"=>best,
      "relative_gap"=>finalgap,"N"=>length(data.q),
      "moment_size"=>size(C,1),"constraint_block_rank"=>size(P.basis,2),
      "precondition"=>"invertible LS Hessian whitening and centering",
      "iterations"=>iteration,"relaxation_parameter"=>gamma,
      "setup_seconds"=>(t_setup-t)/1e9,"total_seconds"=>total,
      "time_budget_seconds"=>seconds,"budget_checked_between_iterations"=>true,
      "relative_affine_error"=>affine_error,"embedding_error"=>setup.embedding_error,
      "cost_error"=>setup.cost_error,"target"=>target,"history"=>history,
      "schur_min_eigenvalue"=>best_info.schur_min,"bounded_shift"=>best_info.delta,
      "translation_block_positive"=>best_info.translation_pd,
      "mandatory_nullspace_error"=>best_info.null_error,
      "schur_screening_value_not_a_bound"=>best_info.screening_value,
      "positive_bound_validation_performed"=>best_info.checked,
      "affine_residual_correction"=>best_info.affine_correction,
      "psd_residual_correction"=>best_info.psd_correction,
      "sublevel_translation_bound"=>ctx.translation_bound,
      "sublevel_norm_squared_bound"=>ctx.norm_squared_bound,
      "sublevel_partition_groups"=>ctx.groups,
      "sublevel_left_inverse_errors"=>ctx.left_inverse_errors,
      "candidate_rotation_representation_change"=>ctx.candidate_rotation_change,
      "lower_bound_method"=>"zero fallback; enclosed affine and full-slack PSD residuals on a derived TLS sublevel set",
      "translation_domain"=>"unbounded","official_implementation"=>false)
end

