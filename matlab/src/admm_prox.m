function [P, px] = admm_prox(P, A, rho, pts)
%ADMM_PROX  Add the proximal term (rho/2) * sum_t (A_t x - v_t)^2 of ADMM to the LP P as a convex
%   piecewise-linear under-approximation (tangent cuts at the deviations pts, MW), so that both
%   subproblems stay LPs for glpk:  s_t >= rho d_j (A_t x - v_t) - rho/2 d_j^2  for every tangent point d_j.
%   A (H x n, sparse) maps the variables x of P to the coupling vector (MW). The targets v only enter the
%   right-hand side, which ADMM_PROX_RHS writes into P.bineq(px.rows) before every solve, so the model is
%   built once. The cut error is at most rho/8 * (gap between neighbouring tangent points)^2.
%   px: rows (rows of P.Aineq), s (indices of the epigraph variables), dj (tangent points), H, rho.
[H, n] = size(A); pts = pts(:); J = numel(pts);
P.f = [P.f(:); ones(H, 1)]; P.lb = [P.lb(:); zeros(H, 1)]; P.ub = [P.ub(:); Inf(H, 1)];
P.Aineq = [P.Aineq, sparse(size(P.Aineq, 1), H)];
P.Aeq = [P.Aeq, sparse(size(P.Aeq, 1), H)];
cut = [kron(rho * pts, A), -kron(ones(J, 1), speye(H))];          % (J H) x (n + H), row (j, t)
px.rows = size(P.Aineq, 1) + (1:J * H)';
P.Aineq = [P.Aineq; cut];
P.bineq = [P.bineq(:); zeros(J * H, 1)];
px.s = n + (1:H)'; px.dj = pts; px.H = H; px.rho = rho; px.A = [A, sparse(H, H)];
end
