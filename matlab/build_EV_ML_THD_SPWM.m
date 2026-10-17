% build_EV_ML_THD_SPWM.m
% Builds the full single-phase bipolar SPWM model (ideal switches), runs it,
% and computes the steady-state THD of the output voltage.
% Run from the MATLAB command window.
clear; clc;

% ---------- Parameters ----------
Vdc   = 200;          % DC bus voltage (V)
m     = 0.8;          % modulation index
f0    = 50;           % fundamental frequency (Hz)
mf    = 199;          % carrier ratio (odd)
fsw   = mf * f0;      % switching frequency (9950 Hz)
R     = 10;           % load resistance (ohm)
L     = 0.01;         % load inductance (H)
Ts    = 1e-6;         % fixed simulation step (s)
Tstop = 0.2;          % 10 fundamental cycles

% ---------- Create a fresh model ----------
mdl = 'EV_ML_THD_SPWM';
if bdIsLoaded(mdl), close_system(mdl, 0); end
if exist([mdl '.slx'], 'file'), delete([mdl '.slx']); end
new_system(mdl);
open_system(mdl);

set_param(mdl, 'SolverType', 'Fixed-step', 'Solver', 'ode4', 'FixedStep', num2str(Ts), 'StopTime', num2str(Tstop));

% ---------- Reference and carrier ----------
add_block('simulink/Sources/Sine Wave', [mdl '/Reference'], 'Amplitude', num2str(m), 'Bias', '0', 'Frequency', num2str(2*pi*f0), 'Phase', '0', 'Position', [40 80 70 110]);
add_block('simulink/Math Operations/Gain', [mdl '/NegReference'], 'Gain', '-1', 'Position', [110 150 140 180]);
add_block('simulink/Sources/Repeating Sequence', [mdl '/Carrier'], 'rep_seq_t', sprintf('[0 0.5 1]/%g', fsw), 'rep_seq_y', '[-1 1 -1]', 'Position', [40 260 70 290]);

% ---------- Comparators (gate signals for leg A and leg B) ----------
add_block('simulink/Logic and Bit Operations/Relational Operator', [mdl '/CmpA'], 'Operator', '>', 'Position', [200 80 230 110]);
add_block('simulink/Logic and Bit Operations/Relational Operator', [mdl '/CmpB'], 'Operator', '>', 'Position', [200 230 230 260]);
add_block('simulink/Signal Attributes/Data Type Conversion', [mdl '/CastA'], 'OutDataTypeStr', 'double', 'Position', [270 80 300 110]);
add_block('simulink/Signal Attributes/Data Type Conversion', [mdl '/CastB'], 'OutDataTypeStr', 'double', 'Position', [270 230 300 260]);

% ---------- Bridge output: vAB = Vdc*(sA - sB) ----------
add_block('simulink/Math Operations/Sum', [mdl '/Diff'], 'Inputs', '+-', 'Position', [340 150 370 190]);
add_block('simulink/Math Operations/Gain', [mdl '/Vdc_Gain'], 'Gain', num2str(Vdc), 'Position', [410 150 450 190]);

% ---------- RL load (i = v / (L s + R)) ----------
add_block('simulink/Continuous/Transfer Fcn', [mdl '/Load_RL'], 'Numerator', '1', 'Denominator', sprintf('[%g %g]', L, R), 'Position', [490 150 560 190]);

% ---------- Logging and scope ----------
add_block('simulink/Sinks/To Workspace', [mdl '/vout_Log'], 'VariableName', 'vout', 'SaveFormat', 'Structure With Time', 'Position', [490 260 550 290]);
add_block('simulink/Sinks/To Workspace', [mdl '/iout_Log'], 'VariableName', 'iout', 'SaveFormat', 'Structure With Time', 'Position', [600 150 660 180]);
add_block('simulink/Sinks/Scope', [mdl '/Scope'], 'Position', [600 260 630 290]);

% ---------- Connections ----------
add_line(mdl, 'Reference/1', 'CmpA/1');
add_line(mdl, 'Reference/1', 'NegReference/1');
add_line(mdl, 'NegReference/1', 'CmpB/1');
add_line(mdl, 'Carrier/1', 'CmpA/2');
add_line(mdl, 'Carrier/1', 'CmpB/2');
add_line(mdl, 'CmpA/1', 'CastA/1');
add_line(mdl, 'CmpB/1', 'CastB/1');
add_line(mdl, 'CastA/1', 'Diff/1');
add_line(mdl, 'CastB/1', 'Diff/2');
add_line(mdl, 'Diff/1', 'Vdc_Gain/1');
add_line(mdl, 'Vdc_Gain/1', 'Load_RL/1');
add_line(mdl, 'Vdc_Gain/1', 'vout_Log/1');
add_line(mdl, 'Vdc_Gain/1', 'Scope/1');
add_line(mdl, 'Load_RL/1', 'iout_Log/1');

save_system(mdl, fullfile(pwd, [mdl '.slx']));

% ---------- Run and capture the logged signals ----------
simOut = sim(mdl, 'ReturnWorkspaceOutputs', 'on');
vout = simOut.vout;
iout = simOut.iout;

% ---------- THD over 5 steady-state cycles ----------
t   = vout.time;
v   = vout.signals.values;
i0  = find(t >= 0.1, 1);
N   = round(0.1 / Ts);
v   = v(i0:i0 + N - 1);

Vf  = abs(fft(v)) / N * 2;
k1  = 6;
hsq = 0;
for h = 2:50
    hsq = hsq + Vf(5*h + 1)^2;
end
THD = 100 * sqrt(hsq) / Vf(k1);

fprintf('Fundamental amplitude: %.1f V (expected about %.0f V)\n', Vf(k1), m*Vdc);
fprintf('THD (harmonics 2 to 50): %.3f %%\n', THD);

% ---------- Waveform check ----------
figure;
plot(vout.time, vout.signals.values);
xlim([0.1 0.12]); grid on;
xlabel('Time (s)'); ylabel('Output voltage (V)');
title('SPWM output voltage (steady state)');

open_system(mdl);