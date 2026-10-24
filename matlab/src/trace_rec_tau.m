function tau = trace_rec_tau(source, datadir)
%TRACE_REC_TAU  Rigid-job recovery time constants of the runtime classes (h) for par.it.rec_tau:
%   gang-weighted mean run time of each class of a job trace (data/job_class_stats.csv).
%   source: 'pai' | 'seren' | 'kalos'.
if nargin < 2, datadir = fullfile(fileparts(mfilename('fullpath')), '..', '..', 'data'); end
fid = fopen(fullfile(datadir, 'job_class_stats.csv'), 'r');
if fid < 0, error('trace_rec_tau:file', 'data/job_class_stats.csv not found (run data_prep/prepare_acme.py)'); end
hdr = strsplit(fgetl(fid), ',');
C = textscan(fid, ['%s' repmat(' %f', 1, numel(hdr) - 1)], 'Delimiter', ',');
fclose(fid);
col = find(strcmp(hdr, 'gang_weighted_runtime_h'));
sel = strcmp(C{1}, source);
if ~any(sel), error('trace_rec_tau:source', 'unknown job source %s', source); end
cls = C{2}(sel); v = C{col}(sel);
tau = zeros(1, 3);
for c = 1:3, tau(c) = v(cls == c); end
end
