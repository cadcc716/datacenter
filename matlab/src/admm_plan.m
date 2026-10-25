function out = admm_plan(par, st, sc, ev, opt, a)
%ADMM_PLAN  Distributed joint recovery (review, innovation direction 3): the IT scheduler and the
%   facility EMS keep their own models and exchange only the deferrable IT power plan (MW per step)
%   and its price, by ADMM on the coupling  p = pdyn * (sum_c y_c - sum_c z_c):
%       IT        p   = argmin f_IT(p)  + lam'p  + rho/2 ||p - pF||^2     (BUILD_COMPUTE_MODEL, no energy
%                                                                       price, no private budget)
%       facility  pF  = argmin f_F(pF)  - lam'pF + rho/2 ||pF - p||^2     (BUILD_MODEL with opt.q_ext)
%       price     lam <- lam + rho (p - pF)      (CNY per MW of deferrable IT power and step)
%   f_IT + f_F is the joint model of BUILD_MODEL (deterministic, S = 1), so at convergence the plan is
%   the joint-recovery plan and lam_t / (phi_t dt) is the channel price of Proposition 2. The price
%   term is linear and exact; only the proximal term, centred at the other side's latest plan, is a
%   tangent-cut LP (ADMM_PROX), fine near zero deviation where the iterations end. Binaries of the
%   joint model are fixed (a.fixZ: every called event valid), so the facility subproblem is an LP.
%   a: rho (CNY/MW^2 per step, default 200), K (iterations, default 50), pts (tangent points, MW),
%      lam0 (H x 1, default: phi * TOU price * dt), pF0 (H x 1, default: nominal deferrable power),
%      tol (primal residual and change of pF in MW, default 0.01), fixZ (default true; relaxed when an
%      event can no longer be valid), keep_y (store the IT schedule of every iteration in out.Yh), solver.
%   out: y, z (IT schedule of the last IT update, H x 3), pIT, pF, lam, xF / ixF (facility solution),
%        hist = [k, primal residual, dual residual, IT cost, facility cost] (MW, MW, CNY), it, ok.
if nargin < 6, a = struct(); end
rho = getf(a, 'rho', 200); K = getf(a, 'K', 50); tol = getf(a, 'tol', 0.01);
pts = getf(a, 'pts', [-20 -10 -5 -2 -1 -0.5 -0.2 -0.1 -0.05 -0.02 -0.01 -0.005 0 ...
                      0.005 0.01 0.02 0.05 0.1 0.2 0.5 1 2 5 10 20]);
slv = getf(a, 'solver', struct());
d = sys_derived(par); H = sc.H; dt = par.dt;
phi = 1 + par.fac.a_aux + par.fac.theta ./ sc.cop(:, 1);
%% IT subproblem
o1 = struct('alpha', 0, 'lambda', -sc.price(:), 'use_share', false, 'no_budget', true, ...
            'visible', opt.visible, 'pgt_nom', zeros(H, 1), 'ynom_now', getf(a, 'ynom_now', sum(sc.flex(1, :, 1))));
[P1, ix1] = build_compute_model(par, st, sc, ev, o1);
n1 = numel(P1.f); I = []; J = []; V = [];
for c = 1:3
    I = [I; (1:H)']; J = [J; ix1.Y{c}(:)]; V = [V; d.pdyn * ones(H, 1)]; %#ok<AGROW>
    if ~isempty(ix1.Zc), I = [I; (1:H)']; J = [J; ix1.Zc{c}(:)]; V = [V; -d.pdyn * ones(H, 1)]; end %#ok<AGROW>
end
A1 = sparse(I, J, V, H, n1);
c1 = P1.f;                                           % IT costs without the proximal term
[P1, px1] = admm_prox(P1, A1, rho, pts);
%% facility subproblem
o2 = opt; o2.q_ext = true; o2.milp = false;
[P2, ix2] = build_model(par, st, sc, ev, o2);
P2.ub(ix2.POV(:)) = getf(a, 'pov_ub', Inf);
Zv = [];
if isfield(ix2.ev, 'Z')                              % (no such field when no event is in the horizon)
    for k = 1:numel(ix2.ev), if ~isempty(ix2.ev(k).Z), Zv = [Zv; ix2.ev(k).Z(:)]; end, end %#ok<AGROW>
end
if getf(a, 'fixZ', true), P2.lb(Zv) = 1; end
P2.intcon = [];
n2 = numel(P2.f);
A2 = sparse(1:H, ix2.Q(:), d.pdyn * ones(H, 1), H, n2);
c2 = P2.f;
[P2, px2] = admm_prox(P2, A2, rho, pts);
%% iterations
pF = getf(a, 'pF0', d.pdyn * sum(sc.flex(:, :, 1), 2));
lam = getf(a, 'lam0', phi .* sc.price(:) * dt);
hist = zeros(K, 5); x1 = []; x2 = []; ok = true; pIT = pF; out.relaxed = false;
keep = getf(a, 'keep_y', false); out.Yh = {};
for k = 1:K
    P1.f(1:n1) = c1 + A1' * lam;   P1.bineq(px1.rows) = prox_rhs(px1, pF);
    s1 = solve_milp(P1, slv);
    if ~s1.ok, ok = false; break; end
    x1 = s1.x; pIT = A1 * x1(1:n1);
    if keep, out.Yh{k} = [x1(ix1.Y{1}), x1(ix1.Y{2}), x1(ix1.Y{3})]; end
    P2.f(1:n2) = c2 - A2' * lam;   P2.bineq(px2.rows) = prox_rhs(px2, pIT);
    s2 = solve_milp(P2, slv);
    if ~s2.ok && any(P2.lb(Zv) > 0)                 % validity of an event no longer attainable: relax
        P2.lb(Zv) = 0; out.relaxed = true; s2 = solve_milp(P2, slv);
    end
    if ~s2.ok, ok = false; break; end
    x2 = s2.x; pFo = pF; pF = A2 * x2(1:n2);
    lam = lam + rho * (pIT - pF);
    rp = norm(pIT - pF); rd = norm(pF - pFo);
    hist(k, :) = [k, rp, rd, c1' * x1(1:n1), c2' * x2(1:n2)];
    if rp < tol && rd < tol, break; end
end
hist = hist(1:max(k - ~ok, 0), :);
out.ok = ok; out.it = size(hist, 1); out.hist = hist; out.rho = rho;
out.lam = lam; out.pF = pF;
out.pIT = []; out.y = []; out.z = [];
if ~isempty(x1)
    out.pIT = A1 * x1(1:n1);
    out.y = [x1(ix1.Y{1}), x1(ix1.Y{2}), x1(ix1.Y{3})];
    if ~isempty(ix1.Zc), out.z = [x1(ix1.Zc{1}), x1(ix1.Zc{2}), x1(ix1.Zc{3})]; end
end
out.xF = []; if ~isempty(x2), out.xF = x2(1:n2); end
out.ixF = ix2;
end

function b = prox_rhs(px, v)
% right-hand sides rho d_j v_t + rho/2 d_j^2 of the tangent cuts (centre v), ordered (j, t)
b = kron(px.rho * px.dj, v(:)) + kron(px.rho / 2 * px.dj .^ 2, ones(px.H, 1));
end

function v = getf(s, f, dflt)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = dflt; end
end
