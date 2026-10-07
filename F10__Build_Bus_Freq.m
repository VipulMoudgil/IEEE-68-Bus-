%% F23_Build_PMU.m
%  One PMU per bus, all 68 buses, grouped by area, logging frequency and
%  voltage magnitude to the workspace. Updated for the current model.
%
%  Each area:  From_nn -> PMU_nn -> MuxV -> Scope + To Workspace  V_areaN
%                                -> MuxF -> Scope + To Workspace  F_areaN
%
%  Reads the existing Vabc_* tags. Touches no electrical block.
%  Safe to re-run: deletes and rebuilds its own subsystem.
%
%  WARNING: 68 PLLs is heavy. This is for a short diagnostic run, after
%  which you keep the buses you want and delete the rest.
%
%  Back up first:  copyfile('IEEE_BUS_68_AGC.slx','PRE_PMU.slx');

mdl   = 'IEEE_BUS_68_AGC';          % <-- updated model name
BLK   = 'PMU Monitoring';

BUILD         = true;
ONE_AREA_ONLY = false;              % false = all five areas
TLOG          = 1/120;              % logging interval [s]

IDX_MAG  = 1;   % PMU out 1 = magnitude (pu)
IDX_FREQ = 3;   % PMU out 3 = frequency (Hz)

PMULIB = 'spsPMUPLLBasedPositiveSequenceLib';
pmuLib = [PMULIB '/PMU' newline '(PLL-Based,' newline 'Positive-Sequence)'];

if ~bdIsLoaded(mdl), load_system(mdl); end
load_system(PMULIB);
MF = {'MatchFilter', @Simulink.match.allVariants};

fprintf('\n===============================================================\n');
fprintf(' PMU BUILDER (all 68 buses)   %s\n', datestr(now));
fprintf('===============================================================\n');

% ---- sample-time note (informational; the PMU runs at model Ts) ----
try, Tsv = evalin('base','Ts'); catch, Tsv = str2double(get_param(mdl,'FixedStep')); end
fprintf('\nModel Ts = %g. PMU sampling rate is a DFT window length in pts/cycle,\n', Tsv);
fprintf('run at model Ts -- it need not divide Ts. Default 24 is fine.\n');

if ~BUILD, fprintf('\n BUILD=false, nothing changed.\n\n'); return; end

% ---- discover Vabc tags ----
g = find_system(mdl,'LookUnderMasks','all','FollowLinks','on',MF{:},'BlockType','Goto');
tags = get_param(g,'GotoTag'); if ischar(tags), tags={tags}; end
vt = unique(tags(startsWith(tags,'Vabc')));
tagOfBus = containers.Map('KeyType','double','ValueType','char');
for i = 1:numel(vt)
    t = regexp(vt{i},'Vabc_?0*(\d+)','tokens','once');
    if ~isempty(t)
        b = str2double(t{1});
        if ~isKey(tagOfBus,b), tagOfBus(b) = vt{i}; end
    end
end
fprintf('\nFound %d Vabc tags covering %d buses\n', numel(vt), tagOfBus.Count);

% ---- area map ----
areas = struct( ...
 'name', {'area1','area2','area3','area4','area5'}, ...
 'buses',{[4 5 6 7 19 20 21 22 23 24 68], ...
          [2 3 37 52 55 56 57 58 59 60 62 63 64 65 66 67], ...
          [1 8 9 25 26 27 28 29 47 53 54], ...
          [10 11 12 13 17 30 31 32 33 34 35 36 38 39 43 44 45 46 49 50 51 61], ...
          [14 15 16 18 40 41 42 48]});
if ONE_AREA_ONLY, areas = areas(1); end

% ---- clear previous build ----
top = find_system(mdl,'SearchDepth',1,'BlockType','SubSystem');
for i = 1:numel(top)
    if strcmp(strtrim(get_param(top{i},'Name')), BLK)
        delete_block(top{i}); fprintf('Removed previous %s\n', BLK);
    end
end
root = [mdl '/' BLK];
add_block('built-in/SubSystem', root, 'Position',[40 1400 340 1600]);
clearInside(root);

% ---- build per area ----
Y = 40;
for a = 1:numel(areas)
    an = areas(a).name; bl = areas(a).buses;
    sub = [root '/' an];
    add_block('built-in/SubSystem', sub, 'Position',[60 Y 320 Y+160]);
    clearInside(sub); Y = Y + 220;

    used = [];
    for k = 1:numel(bl)
        b = bl(k);
        if ~isKey(tagOfBus,b)
            fprintf('  %-6s bus %-3d : no Vabc tag -- skipped\n', an, b); continue
        end
        y = 40 + numel(used)*90;
        fb = sprintf('%s/From_%02d', sub, b);
        pb = sprintf('%s/PMU_%02d',  sub, b);
        add_block('simulink/Signal Routing/From', fb, ...
                  'GotoTag', tagOfBus(b), 'Position',[40 y 140 y+20]);
        add_block(pmuLib, pb, 'Position',[220 y 340 y+70]);
        try, set_param(pb,'samplingRate','24'); catch, end
        add_line(sub, get_param(fb,'PortHandles').Outport(1), ...
                      get_param(pb,'PortHandles').Inport(1), 'autorouting','on');
        used(end+1) = b; %#ok<SAGROW>
    end
    if isempty(used), continue; end

    n = numel(used);
    muxV = [sub '/MuxV']; muxF = [sub '/MuxF'];
    add_block('simulink/Signal Routing/Mux', muxV, 'Inputs',num2str(n), ...
              'Position',[440 40 448 40+n*90]);
    add_block('simulink/Signal Routing/Mux', muxF, 'Inputs',num2str(n), ...
              'Position',[440 90+n*90 448 90+2*n*90]);
    pV = get_param(muxV,'PortHandles'); pF = get_param(muxF,'PortHandles');
    for k = 1:n
        p = get_param(sprintf('%s/PMU_%02d',sub,used(k)),'PortHandles');
        add_line(sub, p.Outport(IDX_MAG),  pV.Inport(k), 'autorouting','on');
        add_line(sub, p.Outport(IDX_FREQ), pF.Inport(k), 'autorouting','on');
    end
    addSinks(sub, pV.Outport(1), ['V_' an], 560,  40, TLOG);
    addSinks(sub, pF.Outport(1), ['F_' an], 560, 240, TLOG);
    fprintf('  %-6s : %2d buses  ->  V_%s , F_%s\n', an, n, an, an);
end

try, Simulink.BlockDiagram.arrangeSystem(root); catch, end
save_system(mdl);

fprintf('\n---------------------------------------------------------------\n');
fprintf(' Built "%s"\n', BLK);
fprintf(' After a sim:  V_areaN = magnitude [pu],  F_areaN = frequency [Hz]\n');
fprintf(' Set StopTime 20, Ctrl+D, run (SLOW). Check F_area5(:,end) ~ 60.\n');
fprintf(' Then tell me which buses to keep and I trim to those.\n');
fprintf('---------------------------------------------------------------\n\n');


%% ================= helpers ============================================
function clearInside(sys)
b = find_system(sys,'SearchDepth',1,'Type','Block');
for i = 1:numel(b)
    if ~strcmp(getfullname(b{i}), sys), delete_block(b{i}); end
end
end

function addSinks(sys, srcPort, varname, x, y, tlog)
sc = sprintf('%s/Scope_%s', sys, varname);
tw = sprintf('%s/Log_%s',   sys, varname);
add_block('simulink/Sinks/Scope', sc, 'Position',[x y x+40 y+40]);
add_block('simulink/Sinks/To Workspace', tw, 'VariableName',varname, ...
          'SaveFormat','Structure With Time','SampleTime',mat2str(tlog), ...
          'Position',[x y+80 x+80 y+120]);
add_line(sys, srcPort, get_param(sc,'PortHandles').Inport(1),'autorouting','on');
add_line(sys, srcPort, get_param(tw,'PortHandles').Inport(1),'autorouting','on');
end