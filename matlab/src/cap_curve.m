function cv = cap_curve(par)
%CAP_CURVE  GPU power-capping model used by the MILPs and the plant (M6: several capping levels).
%   A group of y busy GPUs of a class may reduce its dynamic power by w GPU-equivalents (w <= rmax*y)
%   during DR events. Its throughput loss is the convex piecewise-linear function
%       loss(w, y) = max(0, max_k s_k*w + i_k*y)        (GPU-equivalents of lost work)
%   through the points (0,0), (rho_1, l_1), ..., (rho_K, l_K) of the per-GPU curve: capping at power
%   reduction rho_k costs throughput l_k. GPUs of a class can sit at different levels, so the group
%   loss is the perspective y*l(w/y) of the per-GPU curve, i.e. the maximum above.
%   par.it.cap_rho (levels) and par.it.cap_loss (losses); with cap_loss empty a single level with
%   loss cap_beta*cap_rho is used (the earlier model). Fields: on, rmax, s, i, K, linear.
cv.on = isfield(par.it, 'cap_on') && par.it.cap_on;
rho = par.it.cap_rho(:);
if isfield(par.it, 'cap_loss') && ~isempty(par.it.cap_loss)
    l = par.it.cap_loss(:);
    if numel(l) ~= numel(rho), error('cap_curve:size', 'cap_rho and cap_loss must have the same length'); end
else
    rho = rho(end); l = par.it.cap_beta(end) * rho;
end
r0 = [0; rho]; l0 = [0; l];
cv.s = diff(l0) ./ diff(r0);
cv.i = l0(2:end) - cv.s .* r0(2:end);
cv.rmax = rho(end); cv.K = numel(rho); cv.linear = cv.K == 1;
if any(diff(r0) <= 0) || any(diff(cv.s) < -1e-12)
    error('cap_curve:convex', 'capping levels must increase and the loss curve must be convex');
end
end
