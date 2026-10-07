%% dump_everything.m
%  Complete snapshot of a Specialized Power Systems model:
%  structure, parameters, comment state, workspace data, load flow results.
%
%  USAGE:  paste this whole file into the MATLAB Command Window,
%          or save it as dump_everything.m and type  dump_everything
%
%  OUTPUT: model_full_dump.txt   (text, shareable)
%          model_full_dump.mat   (binary, all workspace vars)

mdl = 'IEEE_BUS_68_AGC';          % <-- change if your model name differs

%% ------------------------------------------------------------------
if ~bdIsLoaded(mdl), load_system(mdl); end
outfile = 'model_full_dump.txt';
fid = fopen(outfile,'w');
if fid < 0, error('Cannot write %s',outfile); end

W = @(varargin) fprintf(fid, varargin{:});
HDR = @(t) W('\n\n%s\n= %s\n%s\n', repmat('=',1,72), t, repmat('=',1,72));

W('MODEL SNAPSHOT: %s\n', mdl);
W('Generated: %s\n', datestr(now));
W('MATLAB:    %s\n', version);

%% ================= 1. SOLVER / MODEL CONFIG =======================
HDR('1. MODEL CONFIGURATION');
cfg = {'Solver','SolverType','StartTime','StopTime','FixedStep','MaxStep', ...
       'RelTol','AbsTol','SimulationMode'};
for k = 1:numel(cfg)
    try, W('  %-18s = %s\n', cfg{k}, get_param(mdl,cfg{k})); catch, end
end

pg = find_system(mdl,'LookUnderMasks','all','FollowLinks','on','MaskType','powergui');
for i = 1:numel(pg)
    W('\n  powergui: %s\n', pg{i});
    try
        p = fieldnames(get_param(pg{i},'DialogParameters'));
        for k = 1:numel(p)
            v = get_param(pg{i},p{k});
            if ischar(v) && ~isempty(v), W('     %-22s = %s\n', p{k}, v); end
        end
    catch, end
end

%% ================= 2. WORKSPACE VARIABLES =========================
HDR('2. WORKSPACE VARIABLES (full precision)');

% -- collect from base workspace and model workspace ----------------
S = struct();
bv = evalin('base','who');
for i = 1:numel(bv)
    try, S.(bv{i}) = evalin('base',bv{i}); catch, end
end
try
    hws = get_param(mdl,'ModelWorkspace');
    mw  = hws.whos;
    W('\n  Model Workspace contains %d variables\n', numel(mw));
    for i = 1:numel(mw)
        try, S.(mw(i).name) = hws.getVariable(mw(i).name); catch, end
    end
catch
    W('\n  (no accessible model workspace)\n');
end

lbl = struct();
lbl.mac_con = {'mach','bus','baseMVA','x_l','r_a','x_d','x_dp','x_dpp', ...
               'T_dop','T_dopp','x_q','x_qp','x_qpp','T_qop','T_qopp', ...
               'H','d_o','d_1','d_2','bus2','S1_0','S1_2'};
lbl.line    = {'from','to','R','L','C','tap','baseMVA','baseKV','col9','col10'};
lbl.AVR_Data= {'tr','Ka','Ta','Tb','Tc','Vset','Vmin','Vmax'};
lbl.Bus     = {'bus','baseKV'};

fn = sort(fieldnames(S));
for i = 1:numel(fn)
    n = fn{i}; v = S.(n);
    if isnumeric(v) || islogical(v)
        if isscalar(v)
            W('\n  %-14s = %.12g\n', n, v);
        elseif ndims(v)==2 && numel(v) <= 5000
            W('\n\n---- %s  [%d x %d] ----\n', n, size(v,1), size(v,2));
            nc = size(v,2);
            if isfield(lbl,n)
                c = lbl.(n);
                if numel(c) < nc, c(end+1:nc) = repmat({'?'},1,nc-numel(c));
                else, c = c(1:nc); end
                W('%5s',''); W('%15s', c{:}); W('\n');
            end
            for r = 1:size(v,1)
                W('%5d', r); W('%15.8g', v(r,:)); W('\n');
            end
        else
            W('\n  %-14s : numeric [%s] (too large to print)\n', n, ...
              strjoin(string(size(v)),'x'));
        end
    elseif ischar(v)
        W('\n  %-14s = ''%s''\n', n, v);
    else
        W('\n  %-14s : %s [%s]\n', n, class(v), strjoin(string(size(v)),'x'));
    end
end

%% ================= 3. BLOCK INVENTORY =============================
HDR('3. BLOCK INVENTORY');
blks = find_system(mdl,'LookUnderMasks','all','FollowLinks','on','Type','Block');
W('  Total blocks: %d\n\n', numel(blks));

types = cell(numel(blks),1);
for i = 1:numel(blks)
    try, types{i} = get_param(blks{i},'BlockType'); catch, types{i}='?'; end
end
[u,~,ix] = unique(types); cnt = accumarray(ix,1);
[~,ord] = sort(cnt,'descend');
for i = ord'
    W('  %-32s %d\n', u{i}, cnt(i));
end

%% ================= 4. COMMENTED / DISABLED BLOCKS =================
HDR('4. COMMENTED-OUT OR DISABLED BLOCKS');
n = 0;
for i = 1:numel(blks)
    try
        c = get_param(blks{i},'Commented');
        if ~strcmp(c,'off')
            W('  [%-7s] %s\n', c, blks{i}); n = n+1;
        end
    catch, end
end
if n==0, W('  (none)\n'); else, W('\n  total: %d\n', n); end

%% ================= 5. COMPONENT TABLES ============================
HDR('5. COMPONENT TABLES');

getp = @(b,f) localGet(b,f);

% ---- synchronous machines ----
W('\n\n---- SYNCHRONOUS MACHINES ----\n');
for i = 1:numel(blks)
    if hasFields(blks{i},{'NominalParameters','Reactances1'})
        W('\n  %s\n', blks{i});
        for f = {'NominalParameters','Reactances1','TimeConstants2', ...
                 'StatorResistance','Mechanical','Saturation','SetSaturation', ...
                 'BusType','Pref','Qref','Vref','LoadFlowParameters'}
            v = getp(blks{i},f{1});
            if ~isempty(v), W('     %-22s = %s\n', f{1}, v); end
        end
    end
end

% ---- transformers ----
W('\n\n---- TRANSFORMERS ----\n');
W('  %-14s %-20s %-28s %-28s\n','NAME','NominalPower','Winding1','Winding2');
for i = 1:numel(blks)
    if hasFields(blks{i},{'NominalPower','Winding1'})
        W('  %-14s %-20s %-28s %-28s  Rm=%s Lm=%s\n', ...
          get_param(blks{i},'Name'), getp(blks{i},'NominalPower'), ...
          getp(blks{i},'Winding1'), getp(blks{i},'Winding2'), ...
          getp(blks{i},'Rm'), getp(blks{i},'Lm'));
    end
end

% ---- PI section lines ----
W('\n\n---- PI SECTION LINES ----\n');
for i = 1:numel(blks)
    if hasFields(blks{i},{'Resistances','Capacitances'})
        W('  %-16s R=%-26s L=%-26s C=%-26s len=%s\n', ...
          get_param(blks{i},'Name'), getp(blks{i},'Resistances'), ...
          getp(blks{i},'Inductances'), getp(blks{i},'Capacitances'), ...
          getp(blks{i},'Length'));
    end
end

% ---- loads ----
W('\n\n---- LOADS ----\n');
for i = 1:numel(blks)
    if hasFields(blks{i},{'ActivePower'})
        W('  %-14s Vn=%-14s P=%-14s QL=%-14s QC=%-14s conf=%s\n', ...
          get_param(blks{i},'Name'), getp(blks{i},'NominalVoltage'), ...
          getp(blks{i},'ActivePower'), getp(blks{i},'InductivePower'), ...
          getp(blks{i},'CapacitivePower'), getp(blks{i},'Configuration'));
    end
end

% ---- load flow buses ----
W('\n\n---- LOAD FLOW BUS BLOCKS ----\n');
W('  %-10s %-12s %-10s %-10s %-10s %s\n','ID','Vbase','Vref','Vangle','VLF','angleLF');
for i = 1:numel(blks)
    if hasFields(blks{i},{'ID','Vbase'})
        W('  %-10s %-12s %-10s %-10s %-10s %-10s   %s\n', ...
          getp(blks{i},'ID'), getp(blks{i},'Vbase'), getp(blks{i},'Vref'), ...
          getp(blks{i},'Vangle'), getp(blks{i},'VLF'), getp(blks{i},'angleLF'), ...
          blks{i});
    end
end

% ---- goto / from tags ----
W('\n\n---- GOTO TAGS ----\n');
g = find_system(mdl,'LookUnderMasks','all','FollowLinks','on','BlockType','Goto');
for i = 1:numel(g)
    W('  %-18s [%-6s] %s\n', getp(g{i},'GotoTag'), getp(g{i},'TagVisibility'), g{i});
end
W('\n---- FROM TAGS ----\n');
f = find_system(mdl,'LookUnderMasks','all','FollowLinks','on','BlockType','From');
ft = cell(numel(f),1);
for i = 1:numel(f), ft{i} = getp(f{i},'GotoTag'); end
[uf,~,ifx] = unique(ft); cf = accumarray(ifx,1);
for i = 1:numel(uf), W('  %-18s x%d\n', uf{i}, cf(i)); end

%% ================= 6. FULL PARAMETER DUMP =========================
HDR('6. FULL BLOCK PARAMETER DUMP');
for i = 1:numel(blks)
    b = blks{i};
    W('\n=== %s\n', b);
    try, W('    BlockType : %s\n', get_param(b,'BlockType')); catch, end
    try
        c = get_param(b,'Commented');
        if ~strcmp(c,'off'), W('    COMMENTED : %s\n', c); end
    catch, end
    try
        dp = get_param(b,'DialogParameters');
        if isempty(dp), continue; end
        p = fieldnames(dp);
        for k = 1:numel(p)
            try
                v = get_param(b,p{k});
                if ischar(v) && ~isempty(v) && numel(v) < 400
                    W('    %-24s = %s\n', p{k}, v);
                end
            catch, end
        end
    catch, end
end

fclose(fid);

%% ================= 7. SAVE WORKSPACE AS .MAT ======================
save('model_full_dump.mat','-struct','S');

fprintf('\nWrote %s\n', fullfile(pwd,outfile));
d = dir(outfile);
fprintf('Size: %.1f MB\n', d.bytes/1e6);
fprintf('Wrote %s\n', fullfile(pwd,'model_full_dump.mat'));


%% ---------------- helper functions --------------------------------
function out = localGet(b,f)
out = '';
try
    v = get_param(b,f);
    if ischar(v), out = v; end
catch
end
end

function tf = hasFields(b,flds)
tf = false;
try
    dp = get_param(b,'DialogParameters');
    if isempty(dp), return; end
    tf = all(cellfun(@(f) isfield(dp,f), flds));
catch
end
end