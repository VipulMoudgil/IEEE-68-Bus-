%% F10_Build_PMU_Monitor.m
%  PMU-based voltage and frequency measurement, grouped by area.
%
%  Creates one subsystem per area, each holding a PMU on every bus in that
%  area, and logs two variables per area:
%       V_pmu_area1 .. V_pmu_area5   magnitude (pu)
%       F_pmu_area1 .. F_pmu_area5   frequency (Hz)
%  matching the existing V_area1..V_area5 naming.
%
%  PMU OUTPUTS
%    port 1  magnitude (pu)   port 2  phase (deg)   port 3  frequency (Hz)
%
%  A CAUTION WORTH READING
%  Each PMU contains a phase-locked loop, and a PLL needs a fixed sample
%  time. This model runs a variable-step solver. An earlier attempt at all
%  68 buses produced non-finite values that propagated into the network and
%  stalled the solver.
%
%  Start with ONE_AREA_ONLY = 4. If that area runs clean, set it to 0 and
%  build all five. Building all 68 PMUs first risks repeating the failure
%  with no way to tell which part caused it.

mdl         = 'IEEE_BUS_68_AGC';
TLOG        = 1/120;
PMU_TS      = 'Ts';          % PMU sample time
ONE_AREA_ONLY = 4;           % 4 = build area 4 only; 0 = build all five
REPORT_ONLY = false;

areas = struct( ...
 'n',     {1,2,3,4,5}, ...
 'buses', {[4 5 6 7 19 20 21 22 23 24 68], ...
           [2 3 37 52 55 56 57 58 59 60 62 63 64 65 66 67], ...
           [1 8 9 25 26 27 28 29 47 53 54], ...
           [10 11 12 13 17 30 31 32 33 34 35 36 38 39 43 44 45 46 49 50 51 61], ...
           [14 15 16 18 40 41 42 48]});

if ~bdIsLoaded(mdl), load_system(mdl); end

fprintf('\n===============================================================\n');
fprintf(' PMU MONITORING BY AREA   %s\n', mdl);
fprintf(' %s\n', datestr(now));
fprintf('===============================================================\n');

%% ---------- locate the PMU library block ----------------------------
try, load_system('sps_lib'); catch, end
PMUREF = '';
try
    b = find_system('sps_lib','LookUnderMasks','all','FollowLinks','on','Type','Block');
    n = get_param(b,'Name'); if ischar(n), n = {n}; end
    hit = b(contains(n,'PMU'));
    fprintf('\nPMU blocks in sps_lib:\n');
    for i = 1:numel(hit)
        fprintf('   %s\n', hit{i});
        if isempty(PMUREF)
            try
                r = get_param(hit{i},'ReferenceBlock');
                if ~isempty(r), PMUREF = r; else, PMUREF = hit{i}; end
            catch
                PMUREF = hit{i};
            end
        end
    end
catch
end
if isempty(PMUREF)
    fprintf(['\nNo PMU block located. Paste this output back and we will\n' ...
             'switch to Discrete Frequency blocks instead.\n\n']);
    return
end
fprintf('\nUsing: %s\n', PMUREF);

%% ---------- map buses to Vabc tags ----------------------------------
g = find_system(mdl,'LookUnderMasks','all','FollowLinks','on','BlockType','Goto');
t = get_param(g,'GotoTag'); if ischar(t), t = {t}; end
tagOf = containers.Map('KeyType','double','ValueType','char');
for i = 1:numel(t)
    k = regexp(t{i},'^Vabc_?(\d+)$','tokens','once');
    if ~isempty(k)
        bb = str2double(k{1});
        if ~isKey(tagOf,bb), tagOf(bb) = t{i}; end
    end
end
fprintf('%d Vabc tags found\n', tagOf.Count);

%% ---------- which areas to build ------------------------------------
if ONE_AREA_ONLY > 0
    todo = find([areas.n] == ONE_AREA_ONLY);
    fprintf('\nBuilding AREA %d ONLY (%d buses)\n', ONE_AREA_ONLY, numel(areas(todo).buses));
    fprintf('Set ONE_AREA_ONLY = 0 to build all five once this runs clean.\n');
else
    todo = 1:numel(areas);
    tot = sum(arrayfun(@(a) numel(a.buses), areas));
    fprintf('\nBuilding ALL FIVE AREAS -- %d PMUs total\n', tot);
end

if REPORT_ONLY
    fprintf('\nREPORT_ONLY = true, nothing changed.\n\n');  return
end

%% ---------- build ---------------------------------------------------
order = struct();
for a = todo
    an  = sprintf('area%d', areas(a).n);
    BLK = sprintf('PMU %s', an);

    top = find_system(mdl,'SearchDepth',1,'BlockType','SubSystem');
    for i = 1:numel(top)
        if strcmp(strtrim(get_param(top{i},'Name')), BLK)
            delete_block(top{i});
            fprintf('\nRemoved previous %s\n', BLK);
        end
    end
    root = [mdl '/' BLK];
    add_block('built-in/SubSystem', root, ...
              'Position',[400+areas(a).n*40 1900 700+areas(a).n*40 2120]);
    inner = find_system(root,'SearchDepth',1,'Type','Block');
    for i = 1:numel(inner)
        if ~strcmp(getfullname(inner{i}), root), delete_block(inner{i}); end
    end

    use = areas(a).buses(arrayfun(@(x) isKey(tagOf,x), areas(a).buses));
    miss = setdiff(areas(a).buses, use);
    if ~isempty(miss)
        fprintf('  %s: no tag for buses %s\n', an, mat2str(miss));
    end
    if isempty(use)
        fprintf('  %s: nothing to build\n', an);  continue
    end

    nb   = numel(use);
    muxV = [root '/MuxV'];  muxF = [root '/MuxF'];
    add_block('simulink/Signal Routing/Mux', muxV, 'Inputs', num2str(nb), ...
              'Position',[560 40 568 40+nb*60]);
    add_block('simulink/Signal Routing/Mux', muxF, 'Inputs', num2str(nb), ...
              'Position',[560 60+nb*80 568 60+nb*140]);
    pV = get_param(muxV,'PortHandles');
    pF = get_param(muxF,'PortHandles');

    ok = 0;
    for i = 1:nb
        bb = use(i);  y = 40 + (i-1)*80;
        fb = sprintf('%s/From_%02d', root, bb);
        pb = sprintf('%s/PMU_%02d',  root, bb);
        try
            add_block('simulink/Signal Routing/From', fb, ...
                      'GotoTag', tagOf(bb), 'Position',[60 y 200 y+20]);
            add_block(PMUREF, pb, 'Position',[300 y 430 y+62]);
            dp = get_param(pb,'DialogParameters');
            for f = fieldnames(dp)'
                if any(strcmpi(f{1},{'Ts','SampleTime','ts'}))
                    try, set_param(pb, f{1}, PMU_TS); catch, end
                end
            end
            add_line(root, get_param(fb,'PortHandles').Outport(1), ...
                           get_param(pb,'PortHandles').Inport(1),'autorouting','on');
            ph = get_param(pb,'PortHandles');
            add_line(root, ph.Outport(1), pV.Inport(i),'autorouting','on');
            if numel(ph.Outport) >= 3
                add_line(root, ph.Outport(3), pF.Inport(i),'autorouting','on');
            end
            ok = ok + 1;
        catch ME
            fprintf('  %s bus %-3d FAILED: %s\n', an, bb, ME.message);
        end
    end

    addSink(root, pV.Outport(1), ['V_pmu_' an], 700,  40, TLOG);
    addSink(root, pF.Outport(1), ['F_pmu_' an], 700, 300, TLOG);

    try, Simulink.BlockDiagram.arrangeSystem(root); catch, end
    order.(an) = use;
    fprintf('  %s: %d of %d PMUs built  ->  V_pmu_%s, F_pmu_%s\n', ...
            an, ok, nb, an, an);
end

save_system(mdl);

fprintf('\n---------------------------------------------------------------\n');
fprintf(' COLUMN ORDER PER AREA\n');
for f = fieldnames(order)'
    fprintf('   %-7s %s\n', f{1}, mat2str(order.(f{1})));
end
fprintf('\n AFTER A RUN, CHECK THESE FIRST:\n');
for f = fieldnames(order)'
    fprintf('   any(isnan(F_pmu_%s.signals.values(:)))   should be 0\n', f{1});
end
fprintf('   mean of the final row should be near 60 Hz\n');
fprintf('   confirm the run reached its StopTime\n');
fprintf('\n IF NaN APPEARS OR THE SOLVER STALLS, remove the subsystems:\n');
for f = fieldnames(order)'
    fprintf('   delete_block(''%s/PMU %s'')\n', mdl, f{1});
end
fprintf(' and we will use Discrete Frequency blocks instead.\n');
fprintf('---------------------------------------------------------------\n\n');


%% ================= helper ==============================================
function addSink(sys, srcPort, varname, x, y, tlog)
sc = sprintf('%s/Scope_%s', sys, varname);
tw = sprintf('%s/Log_%s',   sys, varname);
add_block('simulink/Sinks/Scope', sc, 'Position',[x y x+40 y+40]);
add_block('simulink/Sinks/To Workspace', tw, 'VariableName',varname, ...
          'SaveFormat','Structure With Time','SampleTime',mat2str(tlog), ...
          'Position',[x y+80 x+80 y+120]);
add_line(sys, srcPort, get_param(sc,'PortHandles').Inport(1),'autorouting','on');
add_line(sys, srcPort, get_param(tw,'PortHandles').Inport(1),'autorouting','on');
end