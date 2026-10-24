function dist = load_job_dist(source, datadir)
%LOAD_JOB_DIST  Empirical gang-size / run-time distribution of each runtime class (data/job_dist.csv).
%   source : 'pai' (Alibaba PAI 2020) | 'seren' | 'kalos' (Acme 2023, LLM development)
%   dist(c).g (gang size, GPUs), dist(c).d (run time, min), dist(c).w (number of jobs), c = 1..3.
if nargin < 2, datadir = fullfile(fileparts(mfilename('fullpath')), '..', '..', 'data'); end
fid = fopen(fullfile(datadir, 'job_dist.csv'), 'r');
if fid < 0, error('load_job_dist:file', 'data/job_dist.csv not found (run data_prep/prepare_acme.py)'); end
fgetl(fid);
C = textscan(fid, '%s %f %f %f %f', 'Delimiter', ',');
fclose(fid);
sel = strcmp(C{1}, source);
if ~any(sel), error('load_job_dist:source', 'unknown job source %s', source); end
dist = struct('g', {}, 'd', {}, 'w', {});
for c = 1:3
    k = sel & C{2} == c;
    dist(c).g = C{3}(k); dist(c).d = C{4}(k); dist(c).w = C{5}(k);
end
end
