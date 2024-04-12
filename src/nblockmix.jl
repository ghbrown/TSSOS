mutable struct mcpop_data
    n # number of all variables
    nb # number of binary variables
    m # number of all constraints
    numeq # number of equality constraints
    supp # support data
    coe # coefficient data
    basis # monomial bases
    rlorder # relaxation order
    ksupp # extended support at the k-th step
    cql # number of cliques
    cliques # cliques of variables
    cliquesize # numbers of cliques
    J # constraints associated to each clique
    ncc # constraints associated to no clique
    sb # sizes of different blocks
    numb # numbers of different blocks
    blocks # block structure
    cl # numbers of blocks
    blocksize # sizes of blocks
    GramMat # Gram matrix
    moment # Moment matrix
    solver # SDP solver
    SDP_status
    tol # tolerance to certify global optimality
    flag # 0 if global optimality is certified; 1 otherwise
end

"""
    opt,sol,data = cs_tssos_first(pop, x, d; nb=0, numeq=0, CS="MF", cliques=[], TS="block", merge=false, md=3, solver="Mosek", QUIET=false, solve=true, solution=false,
    Gram=false, MomentOne=false, Mommat=false, tol=1e-4)

Compute the first TS step of the CS-TSSOS hierarchy for constrained polynomial optimization.
If `merge=true`, perform the PSD block merging. 
If `solve=false`, then do not solve the SDP.
If `Gram=true`, then output the Gram matrix.
If `Mommat=true`, then output the moment matrix.
If `MomentOne=true`, add an extra first order moment matrix to the moment relaxation.

# Input arguments
- `pop`: vector of the objective, inequality constraints, and equality constraints
- `x`: POP variables
- `d`: relaxation order
- `nb`: number of binary variables in `x`
- `numeq`: number of equality constraints
- `CS`: method of chordal extension for correlative sparsity (`"MF"`, `"MD"`, `"NC"`, `false`)
- `cliques`: the set of cliques used in correlative sparsity
- `TS`: type of term sparsity (`"block"`, `"MD"`, `"MF"`, `false`)
- `md`: tunable parameter for merging blocks
- `normality`: impose the normality condtions (`true`, `false`)
- `QUIET`: run in the quiet mode (`true`, `false`)
- `tol`: relative tolerance to certify global optimality

# Output arguments
- `opt`: optimum
- `sol`: (near) optimal solution (if `solution=true`)
- `data`: other auxiliary data 
"""
function cs_tssos_first(pop, x, d; nb=0, numeq=0, foc=100, CS="MF", cliques=[], basis=[], minimize=false, TS="block", merge=false, md=3, solver="Mosek", 
    tune=false, dualize=false, QUIET=false, solve=true, solution=false, Gram=false, MomentOne=false, Mommat=false, tol=1e-4, cosmo_setting=cosmo_para(), normality=false, NormalSparse=false)
    n,supp,coe = polys_info(pop, x, nb=nb)
    opt,sol,data = cs_tssos_first(supp, coe, n, d, numeq=numeq, nb=nb, foc=foc, CS=CS, cliques=cliques, basis=basis, minimize=minimize, TS=TS,
    merge=merge, md=md, QUIET=QUIET, solver=solver, tune=tune, dualize=dualize, solve=solve, solution=solution, Gram=Gram, MomentOne=MomentOne,
    Mommat=Mommat, tol=tol, cosmo_setting=cosmo_setting, normality=normality, NormalSparse=NormalSparse)
    return opt,sol,data
end

function polys_info(pop, x; nb=0)
    n = length(x)
    m = length(pop)-1
    if nb > 0
        gb = x[1:nb].^2 .- 1
        for i in eachindex(pop)
            pop[i] = rem(pop[i], gb)
        end
    end
    coe = Vector{Vector{Float64}}(undef, m+1)
    supp = Vector{Vector{Vector{UInt16}}}(undef, m+1)
    for k = 1:m+1
        mon = monomials(pop[k])
        coe[k] = coefficients(pop[k])
        lm = length(mon)
        supp[k] = [UInt16[] for i=1:lm]
        for i = 1:lm
            ind = mon[i].z .> 0
            vars = mon[i].vars[ind]
            exp = mon[i].z[ind]
            for j in eachindex(vars)
                l = ncbfind(x, n, vars[j])
                append!(supp[k][i], l*ones(UInt16, exp[j]))
            end
        end
    end
    return n,supp,coe
end

"""
    opt,sol,data = cs_tssos_first(supp::Vector{Vector{Vector{UInt16}}}, coe, n, d; nb=0, numeq=0, CS="MF", cliques=[], TS="block", 
    merge=false, md=3, QUIET=false, solver="Mosek", solve=true, solution=false, Gram=false, MomentOne=false, Mommat=false, tol=1e-4)

Compute the first TS step of the CS-TSSOS hierarchy for constrained polynomial optimization. 
Here the polynomial optimization problem is defined by `supp` and `coe`, corresponding to the supports and coeffients of `pop` respectively.
"""
function cs_tssos_first(supp::Vector{Vector{Vector{UInt16}}}, coe, n, d; numeq=0, nb=0, foc=100, CS="MF", cliques=[], basis=[], minimize=false, 
    TS="block", merge=false, md=3, QUIET=false, solver="Mosek", tune=false, dualize=false, solve=true, solution=false, MomentOne=false, Gram=false, 
    Mommat=false, tol=1e-4, cosmo_setting=cosmo_para(), normality=false, NormalSparse=false)
    println("*********************************** TSSOS ***********************************")
    println("Version 1.0.0, developed by Jie Wang, 2020--2024")
    println("TSSOS is launching...")
    m = length(supp)-1
    supp[1],coe[1] = resort(supp[1], coe[1])
    dg = [maximum(length.(supp[i])) for i=2:m+1]
    if cliques != []
        cql = length(cliques)
        cliquesize = length.(cliques)
    else
        time = @elapsed begin
        cliques,cql,cliquesize = clique_decomp(n, m, dg, supp, order=d, alg=CS, minimize=minimize)
        end
        if CS != false && QUIET == false
            mc = maximum(cliquesize)
            println("Obtained the variable cliques in $time seconds. The maximal size of cliques is $mc.")
        end
    end
    J,ncc = assign_constraint(m, supp, cliques, cql, cliquesize)
    rlorder = init_order(dg, J, cliquesize, cql, foc=foc, order=d)
    if TS != false && QUIET == false
        println("Starting to compute the block structure...")
    end
    time = @elapsed begin
    blocks,cl,blocksize,sb,numb,basis,status = get_cblocks_mix(dg, J, rlorder, m, supp, cliques, cql, cliquesize, nb=nb, TS=TS, merge=merge, md=md, basis=basis)
    end
    if TS != false && QUIET == false
        mb = maximum(maximum.(sb))
        println("Obtained the block structure in $time seconds.\nThe maximal size of blocks is $mb.")
    end
    opt,ksupp,moment,GramMat,SDP_status = blockcpop_mix(n, m, supp, coe, basis, cliques, cql, cliquesize, J, ncc, blocks, cl, blocksize, numeq=numeq, nb=nb, QUIET=QUIET,
    TS=TS, solver=solver, tune=tune, dualize=dualize, solve=solve, solution=solution, MomentOne=MomentOne, Gram=Gram, Mommat=Mommat, cosmo_setting=cosmo_setting, normality=normality, NormalSparse=NormalSparse)
    data = mcpop_data(n, nb, m, numeq, supp, coe, basis, rlorder, ksupp, cql, cliques, cliquesize, J, ncc, sb, numb, blocks, cl, blocksize, GramMat, moment, solver, SDP_status, tol, 1)
    sol = nothing
    if solution == true
        sol,gap,data.flag = approx_sol(opt, moment, n, cliques, cql, cliquesize, supp, coe, numeq=numeq, tol=tol)
        if data.flag == 1
            sol = gap > 0.5 ? randn(n) : sol
            sol,data.flag = refine_sol(opt, sol, data, QUIET=true, tol=tol)
        end
    end
    return opt,sol,data
end

"""
    opt,sol,data = cs_tssos_higher!(data; TS="block", merge=false, md=3, QUIET=false, solve=true,
    solution=false, Gram=false, Mommat=false, MomentOne=false)

Compute higher TS steps of the CS-TSSOS hierarchy.
"""
function cs_tssos_higher!(data::mcpop_data; TS="block", merge=false, md=3, QUIET=false, solve=true, tune=false, solution=false, Gram=false, dualize=false, 
    MomentOne=false, Mommat=false, cosmo_setting=cosmo_para(), normality=false, NormalSparse=false)
    n = data.n
    nb = data.nb
    m = data.m
    numeq = data.numeq
    supp = data.supp
    coe = data.coe
    basis = data.basis
    rlorder = data.rlorder
    ksupp = data.ksupp
    cql = data.cql
    cliques = data.cliques
    cliquesize = data.cliquesize
    J = data.J
    ncc = data.ncc
    blocks = data.blocks
    cl = data.cl
    blocksize = data.blocksize
    sb = data.sb
    numb = data.numb
    solver = data.solver
    tol = data.tol
    if TS != false && QUIET == false
        println("Starting to compute the block structure...")
    end
    time = @elapsed begin
    blocks,cl,blocksize,sb,numb,basis,status = get_cblocks_mix([], J, rlorder, m, supp, cliques, cql,
    cliquesize, tsupp=ksupp, basis=basis, blocks=blocks, cl=cl, blocksize=blocksize, sb=sb, numb=numb,
    nb=nb, TS=TS, merge=merge, md=md)
    end
    opt = sol = nothing
    if status == 1
        if TS != false && QUIET == false
            mb = maximum(maximum.(sb))
            println("Obtained the block structure in $time seconds.\nThe maximal size of blocks is $mb.")
        end
        opt,ksupp,moment,GramMat,SDP_status = blockcpop_mix(n, m, supp, coe, basis, cliques, cql, cliquesize, J, ncc, blocks, cl,
        blocksize, numeq=numeq, nb=nb, QUIET=QUIET, solver=solver, solve=solve, tune=tune, solution=solution, dualize=dualize,
        MomentOne=MomentOne, Gram=Gram, Mommat=Mommat, cosmo_setting=cosmo_setting, normality=normality, NormalSparse=NormalSparse)
        if solution == true
            sol,gap,data.flag = approx_sol(opt, moment, n, cliques, cql, cliquesize, supp, coe, numeq=numeq, tol=tol)
            if data.flag == 1
                sol = gap > 0.5 ? randn(n) : sol
                sol,data.flag = refine_sol(opt, sol, data, QUIET=true, tol=tol)
            end
        end
        data.ksupp = ksupp
        data.blocks = blocks
        data.cl = cl
        data.blocksize = blocksize
        data.GramMat = GramMat
        data.moment = moment
        data.sb = sb
        data.numb = numb
        data.SDP_status = SDP_status
    else
        println("No higher TS step of the CS-TSSOS hierarchy!")
    end
    return opt,sol,data
end

function blockcpop_mix(n, m, supp::Vector{Vector{Vector{UInt16}}}, coe, basis, cliques, cql, cliquesize, J, ncc, blocks, cl, blocksize; 
    numeq=0, nb=0, QUIET=false, TS="block", solver="Mosek", tune=false, solve=true, solution=false, Gram=false, MomentOne=false, 
    Mommat=false, cosmo_setting=cosmo_para(), dualize=false, normality=false, NormalSparse=false)
    tsupp = Vector{UInt16}[]
    for i = 1:cql, j = 1:cl[i][1], k = 1:blocksize[i][1][j], r = k:blocksize[i][1][j]
        @inbounds bi = sadd(basis[i][1][blocks[i][1][j][k]], basis[i][1][blocks[i][1][j][r]], nb=nb)
        push!(tsupp, bi)
    end
    if (MomentOne == true || solution == true) && TS != false
        ksupp = copy(tsupp)
    end
    if normality == true
        if NormalSparse == true
            st = Vector{UInt16}[]
            for i = 1:m+1
                append!(st, sign_type.(supp[i]))
            end
            unique!(st)
            hyblocks = Vector{Vector{Vector{Vector{UInt16}}}}(undef, cql)
        end
        # wbasis = Vector{Vector{Vector{UInt16}}}(undef, cql)
        wbasis = get_sbasis(Vector(1:n), 1, nb=nb)
        bs = length(wbasis)
        # for s = 1:cql
            # wbasis[s] = basis[s][1]
            # bs = length(wbasis[s])
            if NormalSparse == true
                hyblocks[s] = Vector{Vector{Vector{UInt16}}}(undef, cliquesize[s])
                for i = 1:cliquesize[s]
                    G = SimpleGraph(2bs)
                    for j = 1:bs, k = j:bs
                        bi = sadd(wbasis[s][j], wbasis[s][k], nb=nb)
                        if isempty(sign_type(bi)) || any(l->isodd(length(intersect(sign_type(bi), st[l]))), 1:length(st))
                            add_edge!(G, j, k)
                        end
                        bi = sadd(sadd(wbasis[s][j], wbasis[s][k], nb=nb), [cliques[s][i];cliques[s][i]], nb=nb)
                        if isempty(sign_type(bi)) || any(l->isodd(length(intersect(sign_type(bi), st[l]))), 1:length(st))
                            add_edge!(G, j+bs, k+bs)
                        end
                        bi = sadd(sadd(wbasis[s][j], wbasis[s][k], nb=nb), [cliques[s][i]], nb=nb)
                        if isempty(sign_type(bi)) || any(l->isodd(length(intersect(sign_type(bi), st[l]))), 1:length(st))
                            add_edge!(G, j, k+bs)
                        end
                    end
                    hyblocks[s][i] = connected_components(G)
                    for l = 1:length(hyblocks[s][i])
                        for j = 1:length(hyblocks[s][i][l]), k = j:length(hyblocks[s][i][l])
                            if hyblocks[s][i][l][j] <= bs && hyblocks[s][i][l][k] > bs
                                bi = sadd(sadd(wbasis[s][hyblocks[s][i][l][j]], wbasis[s][hyblocks[s][i][l][k]-bs], nb=nb), [cliques[s][i]], nb=nb)
                                push!(tsupp, bi)
                            elseif hyblocks[s][i][l][j] > bs
                                bi = sadd(sadd(wbasis[s][hyblocks[s][i][l][j]-bs], wbasis[s][hyblocks[s][i][l][k]-bs], nb=nb), [cliques[s][i];cliques[s][i]], nb=nb)
                                push!(tsupp, bi)
                            end
                        end
                    end
                end
            else
                # for i = 1:cliquesize[s], j = 1:bs, k = j:bs
                for i = 1:n, j = 1:bs, k = j:bs
                    # bi = sadd(sadd(wbasis[s][j], wbasis[s][k], nb=nb), [cliques[s][i];cliques[s][i]], nb=nb)
                    bi = sadd(sadd(wbasis[j], wbasis[k], nb=nb), [i;i], nb=nb)
                    push!(tsupp, bi)
                    # bi = sadd(sadd(wbasis[s][j], wbasis[s][k], nb=nb), [cliques[s][i]], nb=nb)
                    bi = sadd(sadd(wbasis[j], wbasis[k], nb=nb), [i], nb=nb)
                    push!(tsupp, bi)
                end
            end
        # end
    end
    for i = 1:cql, (j, w) in enumerate(J[i])
        for l = 1:cl[i][j+1], t = 1:blocksize[i][j+1][l], r = t:blocksize[i][j+1][l], s = 1:length(supp[w+1])
            ind1 = blocks[i][j+1][l][t]
            ind2 = blocks[i][j+1][l][r]
            @inbounds bi = sadd(sadd(basis[i][j+1][ind1], supp[w+1][s], nb=nb), basis[i][j+1][ind2], nb=nb)
            push!(tsupp, bi)
        end
    end
    for i ∈ ncc, j = 1:length(supp[i+1])
        push!(tsupp, supp[i+1][j])
    end
    if (MomentOne == true || solution == true) && TS != false
        for i = 1:cql, j = 1:cliquesize[i]
            push!(tsupp, [cliques[i][j]])
            for k = j+1:cliquesize[i]
                push!(tsupp, [cliques[i][j];cliques[i][k]])
            end
        end
    end
    sort!(tsupp)
    unique!(tsupp)
    if (MomentOne == true || solution == true) && TS != false
        sort!(ksupp)
        unique!(ksupp)
    else
        ksupp = tsupp
    end
    objv = moment = GramMat = SDP_status = nothing
    if solve == true
        ltsupp = length(tsupp)
        if QUIET == false
            println("Assembling the SDP...")
            println("There are $ltsupp affine constraints.")
        end
        if solver == "Mosek"
            if dualize == false
                model = Model(optimizer_with_attributes(Mosek.Optimizer))
            else
                model = Model(dual_optimizer(Mosek.Optimizer))
            end
            if tune == true
                set_optimizer_attributes(model,
                "MSK_DPAR_INTPNT_CO_TOL_MU_RED" => 1e-7,
                "MSK_DPAR_INTPNT_CO_TOL_INFEAS" => 1e-7,
                "MSK_DPAR_INTPNT_CO_TOL_REL_GAP" => 1e-7,
                "MSK_DPAR_INTPNT_CO_TOL_DFEAS" => 1e-7,
                "MSK_DPAR_INTPNT_CO_TOL_PFEAS" => 1e-7,
                "MSK_DPAR_INTPNT_CO_TOL_NEAR_REL" => 1e6,
                "MSK_IPAR_BI_IGNORE_NUM_ERROR" => 1,
                "MSK_DPAR_BASIS_TOL_X" => 1e-3,
                "MSK_DPAR_BASIS_TOL_S" => 1e-3,
                "MSK_DPAR_BASIS_REL_TOL_S" => 1e-5)
            end
        elseif solver == "COSMO"
            model = Model(optimizer_with_attributes(COSMO.Optimizer, "eps_abs" => cosmo_setting.eps_abs, "eps_rel" => cosmo_setting.eps_rel, "max_iter" => cosmo_setting.max_iter))
        elseif solver == "SDPT3"
            model = Model(optimizer_with_attributes(SDPT3.Optimizer))
        elseif solver == "SDPNAL"
            model = Model(optimizer_with_attributes(SDPNAL.Optimizer))
        else
            @error "The solver is currently not supported!"
            return nothing,nothing,nothing,nothing
        end
        set_optimizer_attribute(model, MOI.Silent(), QUIET)
        time = @elapsed begin
        cons = [AffExpr(0) for i=1:ltsupp]
        if normality == true
            # for s = 1:cql
                # bs = length(wbasis[s])
                bs = length(wbasis)
                # for i = 1:cliquesize[s]
                for i = 1:n
                    if NormalSparse == false
                       hnom = @variable(model, [1:2bs, 1:2bs], PSD)
                       for j = 1:bs, k = j:bs
                        #    bi = sadd(wbasis[s][j], wbasis[s][k], nb=nb)
                           bi = sadd(wbasis[j], wbasis[k], nb=nb)
                           Locb = bfind(tsupp, ltsupp, bi)
                           if j == k
                               @inbounds add_to_expression!(cons[Locb], hnom[j,k])
                           else
                               @inbounds add_to_expression!(cons[Locb], 2, hnom[j,k])
                           end
                        #    bi = sadd(sadd(wbasis[s][j], wbasis[s][k], nb=nb), [cliques[s][i];cliques[s][i]], nb=nb)
                           bi = sadd(sadd(wbasis[j], wbasis[k], nb=nb), [i;i], nb=nb)
                           Locb = bfind(tsupp, ltsupp, bi)
                           if j == k
                               @inbounds add_to_expression!(cons[Locb], hnom[j+bs,k+bs])
                           else
                               @inbounds add_to_expression!(cons[Locb], 2, hnom[j+bs,k+bs])
                           end
                        #    bi = sadd(sadd(wbasis[s][j], wbasis[s][k], nb=nb), [cliques[s][i]], nb=nb)
                           bi = sadd(sadd(wbasis[j], wbasis[k], nb=nb), [i], nb=nb)        
                           Locb = bfind(tsupp, ltsupp, bi)
                           if j == k
                               @inbounds add_to_expression!(cons[Locb], 2, hnom[j,k+bs])
                           else
                               @inbounds add_to_expression!(cons[Locb], 2, hnom[j,k+bs]+hnom[k,j+bs])
                           end
                        end
                    else
                        for l = 1:length(hyblocks[s][i])
                            hbs = length(hyblocks[s][i][l])
                            hnom = @variable(model, [1:hbs, 1:hbs], PSD)
                            for j = 1:hbs, k = j:hbs
                                if hyblocks[s][i][l][k] <= bs
                                    bi = sadd(wbasis[s][hyblocks[s][i][l][j]], wbasis[s][hyblocks[s][i][l][k]], nb=nb)
                                elseif hyblocks[s][i][l][j] <= bs && hyblocks[s][i][l][k] > bs
                                    bi = sadd(sadd(wbasis[s][hyblocks[s][i][l][j]], wbasis[s][hyblocks[s][i][l][k]-bs], nb=nb), [cliques[s][i]], nb=nb)
                                else
                                    bi = sadd(sadd(wbasis[s][hyblocks[s][i][l][j]-bs], wbasis[s][hyblocks[s][i][l][k]-bs], nb=nb), [cliques[s][i];cliques[s][i]], nb=nb)
                                end
                                Locb = bfind(tsupp, ltsupp, bi)
                                if j == k
                                    @inbounds add_to_expression!(cons[Locb], hnom[j,k])
                                else
                                    @inbounds add_to_expression!(cons[Locb], 2, hnom[j,k])
                                end
                            end
                        end
                    end
                end
            # end
        end
        pos = Vector{Vector{Vector{Union{VariableRef,Symmetric{VariableRef}}}}}(undef, cql)
        for i = 1:cql
            if (MomentOne == true || solution == true) && TS != false
                bs = cliquesize[i]+1
                pos0 = @variable(model, [1:bs, 1:bs], PSD)
                for t = 1:bs, r = t:bs
                    if t == 1 && r == 1
                        bi = UInt16[]
                    elseif t == 1 && r > 1
                        bi = [cliques[i][r-1]]
                    else
                        bi = sadd(cliques[i][t-1], cliques[i][r-1], nb=nb)
                    end
                    Locb = bfind(tsupp, ltsupp, bi)
                    if t == r
                        @inbounds add_to_expression!(cons[Locb], pos0[t,r])
                    else
                        @inbounds add_to_expression!(cons[Locb], 2, pos0[t,r])
                    end
                end
            end
            pos[i] = Vector{Vector{Union{VariableRef,Symmetric{VariableRef}}}}(undef, 1+length(J[i]))
            pos[i][1] = Vector{Union{VariableRef,Symmetric{VariableRef}}}(undef, cl[i][1])
            for l = 1:cl[i][1]
                @inbounds bs = blocksize[i][1][l]
                if bs == 1
                    pos[i][1][l] = @variable(model, lower_bound=0)
                    @inbounds bi = sadd(basis[i][1][blocks[i][1][l][1]], basis[i][1][blocks[i][1][l][1]], nb=nb)
                    Locb = bfind(tsupp, ltsupp, bi)
                    @inbounds add_to_expression!(cons[Locb], pos[i][1][l])
                else
                    pos[i][1][l] = @variable(model, [1:bs, 1:bs], PSD)
                    for t = 1:bs, r = t:bs
                        @inbounds ind1 = blocks[i][1][l][t]
                        @inbounds ind2 = blocks[i][1][l][r]
                        @inbounds bi = sadd(basis[i][1][ind1], basis[i][1][ind2], nb=nb)
                        Locb = bfind(tsupp, ltsupp, bi)
                        if t == r
                            @inbounds add_to_expression!(cons[Locb], pos[i][1][l][t,r])
                        else
                            @inbounds add_to_expression!(cons[Locb], 2, pos[i][1][l][t,r])
                        end
                    end
                end
            end
        end
        for i in ncc
            if i <= m-numeq
                pos0 = @variable(model, lower_bound=0)
            else
                pos0 = @variable(model)
            end
            for j = 1:length(supp[i+1])
                Locb = bfind(tsupp, ltsupp, supp[i+1][j])
                @inbounds add_to_expression!(cons[Locb], coe[i+1][j], pos0)
            end
        end
        for i = 1:cql, (j, w) in enumerate(J[i])
            pos[i][j+1] = Vector{Union{VariableRef,Symmetric{VariableRef}}}(undef, cl[i][j+1])
            for l = 1:cl[i][j+1]
                bs = blocksize[i][j+1][l]
                if bs == 1
                    if w <= m-numeq
                        pos[i][j+1][l] = @variable(model, lower_bound=0)
                    else
                        pos[i][j+1][l] = @variable(model)
                    end
                    ind = blocks[i][j+1][l][1]
                    for s = 1:length(supp[w+1])
                        @inbounds bi = sadd(sadd(basis[i][j+1][ind], supp[w+1][s], nb=nb), basis[i][j+1][ind], nb=nb)
                        Locb = bfind(tsupp, ltsupp, bi)
                        @inbounds add_to_expression!(cons[Locb], coe[w+1][s], pos[i][j+1][l])
                    end
                else
                    if w <= m-numeq
                        pos[i][j+1][l] = @variable(model, [1:bs, 1:bs], PSD)
                    else
                        pos[i][j+1][l] = @variable(model, [1:bs, 1:bs], Symmetric)
                    end
                    for t = 1:bs, r = t:bs
                        ind1 = blocks[i][j+1][l][t]
                        ind2 = blocks[i][j+1][l][r]
                        for s = 1:length(supp[w+1])
                            @inbounds bi = sadd(sadd(basis[i][j+1][ind1], supp[w+1][s], nb=nb), basis[i][j+1][ind2], nb=nb)
                            Locb = bfind(tsupp, ltsupp, bi)
                            if t == r
                                @inbounds add_to_expression!(cons[Locb], coe[w+1][s], pos[i][j+1][l][t,r])
                            else
                                @inbounds add_to_expression!(cons[Locb], 2*coe[w+1][s], pos[i][j+1][l][t,r])
                            end
                        end
                    end
                end
            end
        end
        bc = zeros(ltsupp)
        for i = 1:length(supp[1])
            Locb = bfind(tsupp, ltsupp, supp[1][i])
            if Locb === nothing
               @error "The monomial basis is not enough!"
               return nothing,nothing,nothing,nothing
            else
               bc[Locb] = coe[1][i]
            end
        end
        @variable(model, lower)
        if solution == true || Mommat == true
            cons[1] += lower
            @constraint(model, con[i=1:ltsupp], cons[i]==bc[i])
        else
            @constraint(model, cons[2:end].==bc[2:end])
            @constraint(model, cons[1]+lower==bc[1])
        end
        @objective(model, Max, lower)
        end
        if QUIET == false
            println("SDP assembling time: $time seconds.")
            println("Solving the SDP...")
        end
        time = @elapsed begin
        optimize!(model)
        end
        if QUIET == false
            println("SDP solving time: $time seconds.")
        end
        SDP_status = termination_status(model)
        objv = objective_value(model)
        if SDP_status != MOI.OPTIMAL
           println("termination status: $SDP_status")
           status = primal_status(model)
           println("solution status: $status")
        end
        println("optimum = $objv")
        if Gram == true
            GramMat = Vector{Vector{Vector{Union{Float64,Matrix{Float64}}}}}(undef, cql)
            for i = 1:cql
                GramMat[i] = Vector{Vector{Union{Float64,Matrix{Float64}}}}(undef, 1+length(J[i]))
                for j = 1:1+length(J[i])
                    GramMat[i][j] = [value.(pos[i][j][l]) for l = 1:cl[i][j]]
                end
            end
        end
        if solution == true
            measure = -dual.(con)
            moment = get_moment(measure, tsupp, cliques, cql, cliquesize, nb=nb)
        end
        if Mommat == true
            measure = -dual.(con)
            moment = get_moment(measure, tsupp, cliques, cql, cliquesize, basis=basis, nb=nb)
        end
    end
    return objv,ksupp,moment,GramMat,SDP_status
end

function init_order(dg, J, cliquesize, cql; foc=100, order="min")
    rlorder = ones(Int, cql)
    if order == "min"
        for i = 1:cql
            if !isempty(J[i])
                rlorder[i] = ceil(Int, maximum(dg[J[i]])/2)
            end
        end
    else
        for i = 1:cql
            if cliquesize[i] <= foc
                rlorder[i] = order
            end
        end
    end
    return rlorder
end

function get_cblocks_mix(dg, J, rlorder, m, supp::Vector{Vector{Vector{UInt16}}}, cliques, cql,
    cliquesize; tsupp=[], basis=[], blocks=[], cl=[], blocksize=[], sb=[], numb=[], TS="block",
    nb=0, merge=false, md=3)
    if isempty(tsupp)
        blocks = Vector{Vector{Vector{Vector{UInt16}}}}(undef, cql)
        cl = Vector{Vector{UInt16}}(undef, cql)
        blocksize = Vector{Vector{Vector{UInt16}}}(undef, cql)
        sb = Vector{Vector{UInt16}}(undef, cql)
        numb = Vector{Vector{UInt16}}(undef, cql)
        label = 0
        if isempty(basis)
            label = 1
            basis = Vector{Vector{Vector{Vector{UInt16}}}}(undef, cql)
        end
        tsupp = reduce(vcat, supp) 
        sort!(tsupp)
        unique!(tsupp)
        flag = 1
    else
        flag = 0
    end
    status = ones(Int, cql)
    for i = 1:cql
        lc = length(J[i])
        ind = [issubset(tsupp[j], cliques[i]) for j in eachindex(tsupp)]
        fsupp = copy(tsupp[ind])
        if flag == 1
            if label == 1
               basis[i] = Vector{Vector{Vector{UInt16}}}(undef, lc+1)
               basis[i][1] = get_sbasis(cliques[i], rlorder[i], nb=nb)
            end
            for j = 1:length(basis[i][1])
                push!(fsupp, sadd(basis[i][1][j], basis[i][1][j], nb=nb))
            end
            sort!(fsupp)
            unique!(fsupp)
            if label == 1
                for s = 1:lc
                    basis[i][s+1] = get_sbasis(cliques[i], rlorder[i]-ceil(Int, dg[J[i][s]]/2), nb=nb)
                end
            end
            blocks[i] = Vector{Vector{Vector{UInt16}}}(undef, lc+1)
            cl[i] = Vector{UInt16}(undef, lc+1)
            blocksize[i] = Vector{Vector{UInt16}}(undef, lc+1)
            sb[i] = Vector{UInt16}(undef, lc+1)
            numb[i] = Vector{UInt16}(undef, lc+1)
            blocks[i],cl[i],blocksize[i],sb[i],numb[i],status[i] = get_cblocks(lc, fsupp, supp[J[i].+1], basis[i],
            TS=TS, nb=nb, QUIET=true, merge=merge, md=md)
        else
            blocks[i],cl[i],blocksize[i],sb[i],numb[i],status[i] = get_cblocks(lc, fsupp, supp[J[i].+1], basis[i],
            blocks=blocks[i], cl=cl[i], blocksize=blocksize[i], sb=sb[i], numb=numb[i], TS=TS, nb=nb, QUIET=true,
            merge=merge, md=md)
        end
    end
    return blocks,cl,blocksize,sb,numb,basis,maximum(status)
end

function assign_constraint(m, supp::Vector{Vector{Vector{UInt16}}}, cliques, cql, cliquesize)
    J = [UInt32[] for i=1:cql]
    ncc = UInt32[]
    for i = 2:m+1
        ind = findall(k->issubset(unique(reduce(vcat, supp[i])), cliques[k]), 1:cql)
        isempty(ind) ? push!(ncc, i-1) : push!.(J[ind], i-1)
    end
    return J,ncc
end

# generate the standard monomial basis in the sparse form
function get_sbasis(var, d; nb=0)
    n = length(var)
    lb = binomial(n+d, d)
    basis = Vector{Vector{UInt16}}(undef, lb)
    basis[1] = UInt16[]
    i = 0
    t = 1
    while i < d+1
        t += 1
        if sum(basis[t-1]) == var[n]*i
           if i < d
               basis[t] = var[1]*ones(UInt16, i+1)
           end
           i += 1
        else
            j = bfind(var, n, basis[t-1][1])
            basis[t] = copy(basis[t-1])
            ind = findfirst(x->basis[t][x]!=var[j], 1:length(basis[t]))
            if ind === nothing
                ind = length(basis[t])+1
            end
            if j != 1
                basis[t][1:ind-2] = var[1]*ones(UInt16, ind-2)
            end
            basis[t][ind-1] = var[j+1]
        end
    end
    if nb > 0
        ind = [!any([basis[i][j]==basis[i][j+1]&&basis[i][j]<=nb for j=1:length(basis[i])-1]) for i=1:lb]
        basis = basis[ind]
    end
    return basis
end

function get_graph(tsupp::Vector{Vector{UInt16}}, basis::Vector{Vector{UInt16}}; nb=0)
    lb = length(basis)
    G = SimpleGraph(lb)
    ltsupp = length(tsupp)
    for i = 1:lb, j = i+1:lb
        bi = sadd(basis[i], basis[j], nb=nb)
        if bfind(tsupp, ltsupp, bi) !== nothing
            add_edge!(G, i, j)
        end
    end
    return G
end

function get_cgraph(tsupp::Vector{Vector{UInt16}}, supp::Vector{Vector{UInt16}}, basis::Vector{Vector{UInt16}}; nb=0)
    lb = length(basis)
    ltsupp = length(tsupp)
    G = SimpleGraph(lb)
    for i = 1:lb, j = i+1:lb
        ind = findfirst(x -> bfind(tsupp, ltsupp, sadd(sadd(basis[i], x, nb=nb), basis[j], nb=nb)) !== nothing, supp)
        if ind !== nothing
            add_edge!(G, i, j)
        end
    end
    return G
end

function clique_decomp(n, m, dg, supp::Vector{Vector{Vector{UInt16}}}; order="min", alg="MF", minimize=false)
    if alg == false
        cliques,cql,cliquesize = [UInt16[i for i=1:n]],1,[n]
    else
        G = SimpleGraph(n)
        for i = 1:m+1
            if order == "min" || i == 1 || order == ceil(Int, dg[i-1]/2)
                foreach(x -> add_clique!(G, unique(x)), supp[i])
            else
                add_clique!(G, unique(reduce(vcat, supp[i])))
            end
        end
        if alg == "NC"
            cliques,cql,cliquesize = max_cliques(G)
        else
            cliques,cql,cliquesize = chordal_cliques!(G, method=alg, minimize=minimize)
        end
    end
    uc = unique(cliquesize)
    sizes=[sum(cliquesize.== i) for i in uc]
    println("-----------------------------------------------------------------------------")
    println("The clique sizes of varibles:\n$uc\n$sizes")
    println("-----------------------------------------------------------------------------")
    return cliques,cql,cliquesize
end

function sadd(a, b; nb=0)
    c = [a; b]
    sort!(c)
    if nb > 0
        i = 1
        while i < length(c)
            if c[i] <= nb
                if c[i] == c[i+1]
                    deleteat!(c, i:i+1)
                else
                    i += 1
                end
            else
                break
            end
        end
    end
    return c
end

# extract an approximate solution from the moment matrix
function approx_sol(opt, moment, n, cliques, cql, cliquesize, supp, coe; numeq=0, tol=1e-4)
    qsol = Float64[]
    lcq = sum(cliquesize)
    A = zeros(lcq,n)
    q = 1
    for k = 1:cql
        cqs = cliquesize[k]
        F = eigen(moment[k], cqs+1:cqs+1)
        temp = sqrt(F.values[1])*F.vectors[:,1]
        if temp[1] == 0
            temp = zeros(cqs)
        else
            temp = temp[2:cqs+1]./temp[1]
        end
        append!(qsol, temp)
        for j = 1:cqs
            A[q,cliques[k][j]] = 1
            q += 1
        end
    end
    sol = (A'*A)\(A'*qsol)
    ub = seval(supp[1], coe[1], sol)
    gap = abs(opt-ub)/max(1, abs(ub))
    flag = gap >= tol ? 1 : 0
    m = length(supp)-1
    for i = 1:m-numeq
        if seval(supp[i+1], coe[i+1], sol) <= -tol
            flag = 1
        end
    end
    for i = m-numeq+1:m
        if abs(seval(supp[i+1], coe[i+1], sol)) >= tol
            flag = 1
        end
    end
    if flag == 0
        @printf "Global optimality certified with relative optimality gap %.6f%%!\n" 100*gap
    end
    return sol,gap,flag
end

function get_moment(measure, tsupp, cliques, cql, cliquesize; basis=[], nb=0)
    moment = Vector{Union{Float64, Symmetric{Float64}, Array{Float64,2}}}(undef, cql)
    ltsupp = length(tsupp)
    for i = 1:cql
        lb = isempty(basis) ? cliquesize[i] + 1 : length(basis[i][1])
        moment[i] = zeros(Float64, lb, lb)
        if basis == []
            for j = 1:lb, k = j:lb
                if j == 1
                    bi = k == 1 ? UInt16[] : [cliques[i][k-1]]
                else
                    bi = sadd(cliques[i][j-1], cliques[i][k-1], nb=nb)
                end
                Locb = bfind(tsupp, ltsupp, bi)
                moment[i][j,k] = measure[Locb]
            end
        else
            for j = 1:lb, k = j:lb
                bi = sadd(basis[i][1][j], basis[i][1][k], nb=nb)
                Locb = bfind(tsupp, ltsupp, bi)
                if Locb !== nothing
                    moment[i][j,k] = measure[Locb]
                end
            end
        end
        moment[i] = Symmetric(moment[i],:U)
    end
    return moment
end

function ncbfind(A, l, a)
    low = 1
    high = l
    while low <= high
        mid = Int(ceil(1/2*(low+high)))
        if A[mid] == a
           return mid
        elseif A[mid] < a
            high = mid - 1
        else
            low = mid + 1
        end
    end
    return nothing
end

function seval(supp, coe, x)
    val = 0
    for i in eachindex(supp)
        temp = isempty(supp[i]) ? 1 : prod(x[supp[i][j]] for j=1:length(supp[i]))
        val += coe[i]*temp
    end
    return val
end
