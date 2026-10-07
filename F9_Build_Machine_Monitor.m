%% F19_Build_Machine_Monitor.m
%  Complete, self-contained machine monitor for all 16 machines.
%  Wires by PORT HANDLE, not by block name, so the 'm1/1' naming problem
%  cannot occur. Cleans up any half-built blocks from earlier attempts.
%
%  Per machine: its measurement bus (the machine block's last output port)
%    -> Bus Selector reading 5 signals with this model's dotted names
%    -> global Goto  MON_<gen>
%  Per area: From blocks -> Mux -> To Workspace  M_area<n>  at 120 Hz.
%
%  Back up first:  copyfile('IEEE_BUS_68_AGC.slx','PRE_MACHMON.slx');

mdl = 'IEEE_BUS_68_AGC';
if ~bdIsLoaded(mdl), load_system(mdl); end
MF = {'MatchFilter', @Simulink.match.allVariants};

SIG = { 'Mechanical.Rotor speed deviation dw (pu)'
        'Mechanical.Rotor angle deviation d_theta (rad)'
        'Mechanical.Electrical power Pe (pu)'
        'dq0 components.Stator voltage vd (pu)'
        'dq0 components.Stator voltage vq (pu)' };
COLS = {'dw','delta','Pe','vd','vq'};
AREAOF = containers.Map(num2cell(1:16), ...
   {3,2,2,1,1,1,1,3,3,4,4,4,4,5,5,5});

fprintf('\n===============================================================\n');
fprintf(' BUILD MACHINE MONITOR (port-handle wiring)   %s\n', datestr(now));
fprintf('===============================================================\n');

% ---- 0. remove anything from earlier attempts ----
for pat = {'mon_sel_%d','mon_goto_%d','mSel_%d','mGoto_%d','fSel_%d','fGoto_%d'}
    for g = 1:16
        b = find_system(mdl,'LookUnderMasks','all','FollowLinks','on',MF{:}, ...
                        'Name', sprintf(pat{1},g));
        for k = 1:numel(b), try, delete_block(b{k}); catch, end; end
    end
end
for nm = {'MachineMon','MachineMonitor','AreaFreq'}
    b = find_system(mdl,'SearchDepth',1,'Name',nm{1});
    for k = 1:numel(b), try, delete_block(b{k}); catch, end; end
end
fprintf('cleaned up earlier partial blocks\n');

root = [mdl '/MachineMon'];
add_block('built-in/Subsystem', root, 'Position',[40 760 200 840]);

% ---- 1. per machine: selector on the measurement port + goto ----
ok = 0; todo = {};
for g = 1:16
    gb = find_system(mdl,'LookUnderMasks','all','FollowLinks','on',MF{:}, ...
                     'Name', sprintf('gen%d',g));
    if isempty(gb), todo{end+1}=sprintf('gen%d not found',g); continue; end %#ok<SAGROW>
    gb = gb{1};
    wrapper = get_param(gb,'Parent');

    ph = get_param(gb,'PortHandles');
    if isempty(ph.Outport)
        todo{end+1}=sprintf('gen%d has no output port',g); continue; end %#ok<SAGROW>
    mport = ph.Outport(end);       % measurement bus = last output

    sel = sprintf('%s/mon_sel_%d', wrapper, g);
    add_block('built-in/BusSelector', sel, 'Position',[900 700+6*g 995 785+6*g]);
    set_param(sel,'OutputSignals',strjoin(SIG,','),'MuxedOutput','on');
    selph = get_param(sel,'PortHandles');

    try
        add_line(wrapper, mport, selph.Inport(1), 'autorouting','on');
    catch ME
        todo{end+1}=sprintf('gen%d wire: %s',g,ME.message); %#ok<SAGROW>
        fprintf('  gen%-2d selector placed, wire failed: %s\n', g, ME.message);
        continue
    end

    gt = sprintf('%s/mon_goto_%d', wrapper, g);
    add_block('built-in/Goto', gt, 'Position',[1015 715+6*g 1095 775+6*g]);
    set_param(gt,'GotoTag',sprintf('MON_%d',g),'TagVisibility','global');
    gtph = get_param(gt,'PortHandles');
    add_line(wrapper, selph.Outport(1), gtph.Inport(1), 'autorouting','on');

    ok = ok + 1;
    fprintf('  gen%-2d  wired  (in %s)\n', g, strrep(wrapper,[mdl '/'],''));
end

% ---- 2. per-area collectors ----
for a = 1:5
    gens = find(cell2mat(values(AREAOF, num2cell(1:16)))==a);
    n = numel(gens);
    ap = sprintf('%s/area%d', root, a);
    add_block('built-in/Subsystem', ap, 'Position',[60 40+80*a 220 100+80*a]);
    add_block('built-in/Mux', [ap '/Mux'], 'Inputs', num2str(n), ...
              'Position',[320 40 360 40+30*n]);
    for j = 1:n
        add_block('built-in/From', sprintf('%s/In_%d',ap,gens(j)), ...
                  'GotoTag', sprintf('MON_%d',gens(j)), ...
                  'Position',[140 40+30*(j-1) 280 60+30*(j-1)]);
        add_line(ap, sprintf('In_%d/1',gens(j)), sprintf('Mux/%d',j), 'autorouting','on');
    end
    add_block('simulink/Sinks/To Workspace', [ap '/Log'], 'Position',[420 40 500 70]);
    set_param([ap '/Log'],'VariableName',sprintf('M_area%d',a), ...
              'SampleTime','1/120','SaveFormat','StructureWithTime','MaxDataPoints','inf');
    add_line(ap, 'Mux/1', 'Log/1', 'autorouting','on');
    fprintf('  area %d: %s -> M_area%d\n', a, mat2str(gens), a);
end

save_system(mdl);
fprintf('\n---------------------------------------------------------------\n');
fprintf(' %d of 16 machines wired. %d issues.\n', ok, numel(todo));
for i=1:numel(todo), fprintf('   - %s\n', todo{i}); end
fprintf(' Columns per machine: %s\n', strjoin(COLS,', '));
fprintf(' Vt = sqrt(vd^2+vq^2) formed in extraction.\n');
fprintf(' Outputs: M_area1..M_area5 at 120 Hz.\n');
fprintf('\n Ctrl+D, run once, then:  size(M_area4.signals.values)\n');
fprintf(' should show 20 columns (4 machines x 5 signals).\n');
fprintf('---------------------------------------------------------------\n\n');