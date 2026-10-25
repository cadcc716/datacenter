function [ok, info] = region_check(ctx, C, strat, opts)
%REGION_CHECK  Is the commitment vector C (MW, one value per event of ctx.ev) deliverable on the day of
%   ctx under the recovery strategy strat?
%   "Deliverable" = for every called event k the mean grid import over the event stays at least C_k
%   below the mean DR baseline (full delivery on the Jiangsu settlement basis, no shortfall;
%   opts.basis = 'mean', the default) or in every step of the event (opts.basis = 'step', constant
%   reduction as MAX_DELIVERABLE); all task deadlines are met; the connection limit is hard; perfect
%   information; free terminal state.
%   opts.called (K x 1 logical, default all true): events that are called. A called event with C_k = 0
%   still caps the mean load at the baseline (the region of a fixed call pattern is then a convex
%   polytope); an event that is not called carries no obligation.
%   strat: 'JR'   joint recovery: any feasible operation of the joint model (one LP);
%          'IR-O' independent recovery planned sequentially as the open-loop IR-O plan: stage 1 the IT
%                 scheduler with its static share opts.alpha * C_k, stage 2 the facility EMS with the
%                 IT schedule fixed (BUILD_COMPUTE_MODEL, BUILD_MODEL with fix_y);
%          'IR-P' as IR-O, but the IT scheduler pays the recovery-channel price of the joint plan for C
%                 (duals of the electric balance minus the TOU price, as DAYAHEAD_PRICES) instead of
%                 following a share. Its LP response to the price is not unique (see Proposition 4):
%          'IR-P+' optimistic IR-P: deliverable with SOME optimal IT response to that price (one LP);
%                 opts.irp_tol = relative tolerance on the IT objective (default 1e-7: optimal responses;
%                 e.g. 1e-3: responses within 0.1 % of the IT optimum).
%   info.lam (IR-P), info.y (stage-1 or joint IT schedule, H x 3), info.sol (last LP), info.time.
if nargin < 4, opts = struct(); end
t0 = tic;
[par, st, sc, ev, opt, slv] = region_setup(ctx, C, [], opts);
info = struct('lam', [], 'y', [], 'sol', [], 'time', 0);
switch strat
    case 'JR'
        [ok, info.sol, ix] = joint_lp(par, st, sc, ev, opt, slv);
        if ok, info.y = [info.sol.x(ix.Y{1}), info.sol.x(ix.Y{2}), info.sol.x(ix.Y{3})]; end
    case {'IR-O', 'IR-P'}
        o1 = struct('visible', opt.visible, 'pgt_nom', ctx.pgt_nom, 'ynom_now', sum(ctx.inp.real.flex(1, :)));
        if strcmp(strat, 'IR-O')
            o1.alpha = opts.alpha;
        else
            [okj, sj, ixj] = joint_lp(par, st, sc, ev, opt, slv);
            if ~okj || isempty(sj.marg_eq), ok = false; info.time = toc(t0); return; end
            lam = max(sj.marg_eq(ixj.row_el) / par.dt, 0) - sc.price(:);
            o1.alpha = 0; o1.lambda = lam; o1.use_share = false; info.lam = lam;
        end
        [P1, ix1] = build_compute_model(par, st, sc, ev, o1);
        s1 = solve_milp(P1, slv);
        if ~s1.ok, ok = false; info.time = toc(t0); return; end
        y = [s1.x(ix1.Y{1}), s1.x(ix1.Y{2}), s1.x(ix1.Y{3})];
        z = []; if ~isempty(ix1.Zc), z = [s1.x(ix1.Zc{1}), s1.x(ix1.Zc{2}), s1.x(ix1.Zc{3})]; end
        o2 = opt; o2.fix_y = y; o2.fix_z = z; info.y = y;
        [ok, info.sol] = joint_lp(par, st, sc, ev, o2, slv);
    case 'IR-P+'
        % optimistic IR-P: is there an optimal response of the IT scheduler to the JR channel price
        % (IT objective within tol of its optimum) with which the facility can deliver C? One LP over
        % the joint model and the IT model, linked by the IT schedule.
        [okj, sj, ixj] = joint_lp(par, st, sc, ev, opt, slv);
        if ~okj || isempty(sj.marg_eq), ok = false; info.time = toc(t0); return; end
        lam = max(sj.marg_eq(ixj.row_el) / par.dt, 0) - sc.price(:); info.lam = lam;
        o1 = struct('visible', opt.visible, 'pgt_nom', ctx.pgt_nom, 'ynom_now', sum(ctx.inp.real.flex(1, :)), ...
                    'alpha', 0, 'lambda', lam, 'use_share', false);
        [P1, ix1] = build_compute_model(par, st, sc, ev, o1);
        s1 = solve_milp(P1, slv);
        if ~s1.ok, ok = false; info.time = toc(t0); return; end
        [P, ix] = build_model(par, st, sc, ev, opt); P.ub(ix.POV(:)) = 0;
        rt = 1e-7; if isfield(opts, 'irp_tol') && ~isempty(opts.irp_tol), rt = opts.irp_tol; end
        n = numel(P.f); n1 = numel(P1.f); tol = rt * abs(s1.fval) + 1e-4;
        Q.f = zeros(n + n1, 1); Q.lb = [P.lb; P1.lb]; Q.ub = [P.ub; P1.ub]; Q.intcon = [];
        Q.Aineq = [blkdiag(P.Aineq, P1.Aineq); sparse(1, n + (1:n1), P1.f(:)', 1, n + n1)];
        Q.bineq = [P.bineq; P1.bineq; s1.fval + tol];
        J0 = []; J1 = [];
        for q = 1:3, J0 = [J0; ix.Y{q}(:)]; J1 = [J1; ix1.Y{q}(:)]; end %#ok<AGROW>
        if ~isempty(ix.Zc) && ~isempty(ix1.Zc)
            for q = 1:3, J0 = [J0; ix.Zc{q}(:)]; J1 = [J1; ix1.Zc{q}(:)]; end %#ok<AGROW>
        end
        nl = numel(J0); L = sparse([1:nl, 1:nl], [J0; n + J1], [ones(nl, 1); -ones(nl, 1)], nl, n + n1);
        Q.Aeq = [blkdiag(P.Aeq, P1.Aeq); L]; Q.beq = [P.beq; P1.beq; zeros(nl, 1)];
        sol = solve_milp(Q, slv); ok = sol.ok; info.sol = sol;
        if ok, info.y = reshape(sol.x(n + J1(1:3 * numel(ix1.Y{1}))), [], 3); end
    otherwise
        error('region_check:strat', 'unknown strategy %s', strat);
end
info.time = toc(t0);
end

function [ok, sol, ix] = joint_lp(par, st, sc, ev, opt, solver)
[P, ix] = build_model(par, st, sc, ev, opt);
P.ub(ix.POV(:)) = 0;
sol = solve_milp(P, solver);
ok = sol.ok;
end
