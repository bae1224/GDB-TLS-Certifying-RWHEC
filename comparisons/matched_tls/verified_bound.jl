# Certificate validation, independent of the DRS convergence heuristic.
# The mathematical model uses the imported Float64 A/B matrices as exact data.
# Scalar intervals use adjacent floating-point numbers. Matrix products use
# explicit IEEE-754 dot-product error enclosures, including underflow terms.
# See LOWER_BOUND.md for the theorem, assumptions, and failure behavior.

struct IV
    lo::Float64
    hi::Float64
end
IV(x::Real)=IV(Float64(x),Float64(x))
down(x)=prevfloat(x)
up(x)=nextfloat(x)
Base.:+(a::IV,b::IV)=IV(down(a.lo+b.lo),up(a.hi+b.hi))
Base.:-(a::IV,b::IV)=IV(down(a.lo-b.hi),up(a.hi-b.lo))
Base.:-(a::IV)=IV(-a.hi,-a.lo)
function Base.:*(a::IV,b::IV)
    v=(a.lo*b.lo,a.lo*b.hi,a.hi*b.lo,a.hi*b.hi)
    IV(down(minimum(v)),up(maximum(v)))
end
function Base.:/(a::IV,b::IV)
    b.lo>0 || error("Interval denominator must be positive")
    a*IV(down(1/b.hi),up(1/b.lo))
end
function square(a::IV)
    if a.lo<=0<=a.hi
        return IV(0.,up(max(a.lo*a.lo,a.hi*a.hi)))
    end
    IV(max(0.,down(min(a.lo*a.lo,a.hi*a.hi))),up(max(a.lo*a.lo,a.hi*a.hi)))
end
isqrt(a::IV)=IV(max(0.,down(sqrt(max(0.,a.lo)))),up(sqrt(a.hi)))
absupper(a::IV)=max(abs(a.lo),abs(a.hi))
mid(a::IV)=a.lo/2+a.hi/2
finite(a::IV)=isfinite(a.lo)&&isfinite(a.hi)&&a.lo<=a.hi

# Exact operands A and B are binary floating-point numbers. For a length-k
# dot product, gamma_(2k) bounds multiplication and accumulation errors.
# g=2k*eps is larger than gamma_(2k), for the asserted range. The absolute
# product is itself enclosed before it is used to bound the signed product.
function product_box(A::AbstractMatrix{Float64},B::AbstractMatrix{Float64})
    k=size(A,2); @assert size(B,1)==k && 2k*eps(Float64)<0.01
    C=A*B; V=abs.(A)*abs.(B)
    g=up(2k*eps(Float64)); tail=up(4k*nextfloat(0.))
    out=Matrix{IV}(undef,size(C))
    for j in axes(C,2),i in axes(C,1)
        vmax=up(up(V[i,j]+tail)/down(1-g))
        rad=up(up(g*vmax)+tail)
        out[i,j]=IV(down(C[i,j]-rad),up(C[i,j]+rad))
    end
    out
end
function inf_upper(A::AbstractMatrix{IV})
    result=0.
    for i in axes(A,1)
        s=0.
        for j in axes(A,2); s=up(s+absupper(A[i,j]));end
        result=max(result,s)
    end
    result
end
norm_upper(A::AbstractMatrix{IV})=max(inf_upper(A),inf_upper(permutedims(A)))

function residual_matrices(A,B)
    I3=Matrix{Float64}(I,3,3)
    Mr=hcat(zeros(9,6),kron(I3,A[1:3,1:3]),-kron(B[1:3,1:3]',I3),zeros(9,1))
    Mt=hcat(A[1:3,1:3],-I3,zeros(3,9),-kron(B[1:3,4]',I3),A[1:3,4])
    Mr,Mt
end

# A binary quaternion defines an exactly feasible rotation by its homogeneous
# rational formula. It represents the supplied rotation to rounding accuracy;
# no optimizer, candidate refit, or new observation selection is involved.
function rotation_box(R)
    if tr(R)>0
        s=2sqrt(1+tr(R));q=[s/4,(R[3,2]-R[2,3])/s,(R[1,3]-R[3,1])/s,(R[2,1]-R[1,2])/s]
    else
        i=argmax(diag(R));j=mod1(i+1,3);k=mod1(i+2,3)
        s=2sqrt(1+R[i,i]-R[j,j]-R[k,k]);q=zeros(4)
        q[1]=(R[k,j]-R[j,k])/s;q[i+1]=s/4
        q[j+1]=(R[j,i]+R[i,j])/s;q[k+1]=(R[k,i]+R[i,k])/s
    end
    w,x,y,z=IV.(q); d=square(w)+square(x)+square(y)+square(z); two=IV(2.)
    out=[square(w)+square(x)-square(y)-square(z) two*(x*y-w*z) two*(x*z+w*y);
         two*(x*y+w*z) square(w)-square(x)+square(y)-square(z) two*(y*z-w*x);
         two*(x*z-w*y) two*(y*z+w*x) square(w)-square(x)-square(y)+square(z)]
    out=[a/d for a in out]
    err=maximum(absupper(out[i,j]-IV(R[i,j])) for i=1:3,j=1:3)
    @assert err<1e-7 "Candidate rotation is not a rounding-level SO(3) representation"
    out,err
end
function interval_matvec(A,x)
    [foldl(+, (IV(A[i,j])*x[j] for j in axes(A,2));init=IV(0.)) for i in axes(A,1)]
end

function certificate_context(folder,data)
    meta=TOML.parsefile(joinpath(folder,"metadata.toml"))
    A=posecsv(joinpath(folder,"A.csv"));B=posecsv(joinpath(folder,"B.csv"))
    X=readdlm(joinpath(folder,"X_candidate.csv"),',',Float64)
    Y=readdlm(joinpath(folder,"Y_candidate.csv"),',',Float64)
    RX,ex=rotation_box(X[1:3,1:3]);RY,ey=rotation_box(Y[1:3,1:3])
    x=[IV.(X[1:3,4]);IV.(Y[1:3,4]);vec(RX);vec(RY);IV(1.)]
    wr=IV(meta["rot_weight"])/IV(meta["tau2"])
    wt=IV(meta["translation_weight"])/IV(meta["tau2"])
    @assert wr.lo>0 && wt.lo>0
    Qbox=Matrix{IV}[];upper=IV(0.)
    for (a,b) in zip(A,B)
        Mr,Mt=residual_matrices(a,b)
        qr=product_box(Mr',Mr);qt=product_box(Mt',Mt)
        push!(Qbox,[wr*qr[i,j]+wt*qt[i,j] for i=1:25,j=1:25])
        er=interval_matvec(Mr,x);et=interval_matvec(Mt,x)
        q=wr*foldl(+,square.(er);init=IV(0.))+wt*foldl(+,square.(et);init=IV(0.))
        upper+=IV(max(0.,min(1.,q.lo)),min(1.,q.hi))
    end
    U=max(0.,upper.hi);n=length(A);ng=floor(Int,U)+1
    bound=Inf;etas=Float64[];group_bounds=Float64[]
    if ng<=n
        radius=isqrt(IV(1.)/wt).hi
        for g=1:ng
            inds=collect(g:ng:n)
            M=vcat([hcat(A[i][1:3,1:3],-Matrix{Float64}(I,3,3)) for i in inds]...)
            c=Float64[]
            for i in inds
                tb=isqrt(foldl(+,square.(IV.(B[i][1:3,4]));init=IV(0.))).hi
                append!(c,[up(up(abs(A[i][r,4])+tb)+radius) for r=1:3])
            end
            # pinv only proposes a left inverse; the following enclosure proves
            # its validity. No singular-value tolerance is a certificate.
            Kleft=pinv(M)
            KM=product_box(Kleft,M)
            E=[IV(i==j ? 1. : 0.)-KM[i,j] for i=1:6,j=1:6]
            eta=inf_upper(E);push!(etas,eta)
            if !(eta<1);push!(group_bounds,Inf);continue;end
            num=maximum(foldl((s,v)->up(s+v),
                (up(abs(Kleft[r,j])*c[j]) for j in eachindex(c));init=0.) for r=1:6)
            push!(group_bounds,up(num/down(1-eta)))
        end
        bound=maximum(group_bounds)
    end
    Cnorm=isfinite(bound) ? up((n+1)*up(up(6*up(bound*bound))+7)) : Inf
    G=hcat(vec.(manifold())...)
    (;U,Qbox,n,translation_bound=bound,norm_squared_bound=Cnorm,groups=ng,
       left_inverse_errors=etas,group_bounds,candidate_rotation_change=max(ex,ey),
       nominal_upper=data.U,G,Gpinv=pinv(G))
end

# Canonicalization is an exact polynomial identity for theta_i in {-1,1}:
# within-block skew parts vanish, and all diagonal theta_i^2 terms can be
# replaced by their common average. Interval operations enclose that identity.
function affine_residual_box(B,ctx,target)
    K=ctx.n+1;d=25K
    D=[-IV(a) for a in B]
    E=zeros(25,25);E[25,25]=1.
    for i=1:ctx.n
        Q=ctx.Qbox[i];idx=25i .+ (1:25)
        for c=1:25,r=1:25
            D[r,c]+=(Q[r,c]+IV(E[r,c]))/IV(2.)
            v=(Q[r,c]-IV(E[r,c]))/IV(4.)
            D[r,idx[c]]+=v;D[idx[r],c]+=v
        end
    end
    D[25,25]-=IV(target)
    blocks=reshape(permutedims(reshape(D,25,K,25,K),(1,3,2,4)),625,K*K)
    for j=1:K,i=1:K
        block=reshape(view(blocks,:,i+(j-1)*K),25,25)
        for c=1:25,r=1:c
            v=(block[r,c]+block[c,r])/IV(2.)
            block[r,c]=v;block[c,r]=v
        end
    end
    diagonal=fill(IV(0.),625)
    for i=1:K;diagonal .+= view(blocks,:,i+(i-1)*K);end
    diagonal=[a/IV(K) for a in diagonal]
    for i=1:K;blocks[:,i+(i-1)*K]=diagonal;end
    # Any finite multipliers are allowed: all columns of G are exact SO(3)
    # equalities. The least-squares solve itself need not be verified.
    multipliers=ctx.Gpinv*mid.(blocks)
    correction=product_box(ctx.G,multipliers)
    blocks=blocks-correction
    reshape(permutedims(reshape(blocks,25,25,K,K),(1,3,2,4)),d,d)
end

function psd_residual_upper(B,delta,K)
    M=IV.(B)
    for k=0:K-1,j=7:25;idx=25k+j;M[idx,idx]+=IV(delta);end
    F=eigen(Symmetric(mid.(M)))
    # The rounded factor is an exact binary matrix for this check. Its exact
    # Gram product is PSD, regardless of eigensolver error or missing null rays.
    factor=F.vectors .* sqrt.(max.(0.,F.values))'
    gram=product_box(factor,factor')
    norm_upper(M-gram)
end

function verified_positive_bound(B,ctx,target,delta)
    if !isfinite(ctx.norm_squared_bound) || !isfinite(delta) || delta<0
        return (;lower=0.,affine_correction=Inf,psd_correction=Inf,checked=false)
    end
    ea=norm_upper(affine_residual_box(B,ctx,target))
    es=psd_residual_upper(B,delta,ctx.n+1)
    v=IV(target)-IV(7*(ctx.n+1))*IV(delta)-IV(ctx.norm_squared_bound)*(IV(ea)+IV(es))
    lower=finite(v) ? max(0.,min(ctx.U,v.lo)) : 0.
    (;lower,affine_correction=ea,psd_correction=es,checked=true)
end

function checked_lower_bound(S,W,target,ctx;translation_basis,translation_null)
    proposal=schur_proposal(S,W,target;translation_basis,translation_null)
    # A failed screen returns the known exact TLS lower bound zero. No value
    # computed after dropping nullspace directions is ever reported as a bound.
    check=(;lower=0.,affine_correction=0.,psd_correction=0.,checked=false)
    if proposal.lower >= ctx.U-1e-6*max(1.,ctx.U)
        B=physical_slack(S,W)
        check=verified_positive_bound(B,ctx,target,proposal.delta)
    end
    (;check...,delta=proposal.delta,schur_min=proposal.schur_min,
      translation_pd=proposal.translation_pd,null_error=proposal.null_error,
      screening_value=proposal.lower)
end
