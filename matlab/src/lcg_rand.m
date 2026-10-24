function [u, x] = lcg_rand(x, n)
%LCG_RAND  n uniform numbers in (0,1) from the Park-Miller minimal-standard generator with state x.
%   Platform independent (exact in double precision), so MATLAB and Octave draw the same job
%   populations in JOB_GEN and the same checkpoint losses in JOB_REPLAY.
u = zeros(n, 1);
for i = 1:n
    x = mod(16807 * x, 2147483647);
    u(i) = x / 2147483647;
end
end
