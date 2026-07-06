function scene_aware_ue_comimo_uplink()
% SCENE_AWARE_UE_COMIMO_UPLINK
% Scene-Aware UE-CoMIMO for AI-glass uplink live streaming (Scenario 1).
%
% A creator wearing AI glasses live-streams first-person video while walking
% from outdoors into a venue, then dwells indoors for a long session. The
% glasses offload over 5 GHz Wi-Fi to a smartphone and never transmit at
% 700 MHz. The phone (hub agent) predicts indoor entry and pre-switches its
% uplink from 3.5 GHz to 700 MHz before the link collapses; indoors it
% engages a shared CPE either by full delegation (M4: phone cellular off,
% CPE carries everything) or by non-coherent packet split (M3) when the CPE
% is busy. A thermal- and battery-aware governor caps the bitrate over the
% long dwell. Objective = QoE (incl. glass heat, glass battery, phone
% battery), not peak throughput.
%
% Policies: A glass-3.5-direct | B reactive-700-switch
%           C scene-aware w/o governor (ablation) | Proposed
%
% This script is the batch reference for the case study. The full system
% model, every parameter with its provenance, and the discussion of results
% are in the companion supplement (Agentic_UEcoMIMO_Supplement.tex); an
% interactive port with the identical control logic is game/ue_comimo_game.html.
%
% Outputs: a metric table in the command window; figures saved to
% ./results_matlab/ (mode timeline, rate/CPE, buffer, QoE, temperature,
% battery, KPI summary, and the combined two-panel paper figure).
%
% Usage:  scene_aware_ue_comimo_uplink
% Requires: base MATLAB only (R2018b+ recommended).

cfg = make_config();
rng(cfg.sim.seed);           % fixed seed for reproducibility

scen = make_scenario(cfg);   % user trajectory and environment per time step
ch   = make_channels(cfg, scen);  % precompute per-step channel / per-mode rates

% Four policies: A-B baselines, C ablation (scene-aware, no governor), Proposed.
% (B & D from earlier revisions were transitional variants of the reactive switch
% and the fixed-700 relay; a real handset already band-switches, so they are dropped.)
policies = {'A: glass 3.5 direct', 'B: reactive 700 switch', ...
            'C: scene-aware w/o governor', 'Proposed: scene-aware UE-CoMIMO'};

logs = cell(1, numel(policies));
mets = cell(1, numel(policies));
for p = 1:numel(policies)
    logs{p} = run_policy(p, cfg, scen, ch);     % simulate, log per-step state
    mets{p} = compute_metrics(logs{p}, scen);   % aggregate KPIs
end

print_table(policies, mets);  % comparison table to the command window
outdir = fullfile(fileparts(mfilename('fullpath')), 'results_matlab');
if ~exist(outdir, 'dir'), mkdir(outdir); end
make_plots(outdir, cfg, scen, ch, policies, logs, mets);
fprintf('\nFigures written to %s\n', outdir);
end

% ======================================================================
% Configuration. See the supplement parameter table for provenance;
% values are tagged [standards] (3GPP/IEEE/IEC/ITU-T) or [illustrative].
% ======================================================================
function cfg = make_config()
% Episode 900 s, step 0.1 s. Long dwell exposes the thermal time constant
% (tau ~ 150 s) and the divergence in battery drain across policies.
cfg.sim.total_time_s = 900;  cfg.sim.dt = 0.1;  cfg.sim.seed = 7;

% [3GPP TR 38.901] Trajectory: from x=-30 m outdoors at 1 m/s, dwelling at
% x_stop=10 m (kept inside the UMa NLOS valid range, 10 m to 5 km).
cfg.traj.v_mps = 1.0;  cfg.traj.x0 = -30;  cfg.traj.x_entrance = 0;
cfg.traj.x_indoor = 5;  cfg.traj.x_stop = 10;

% [3GPP TR 38.901 §7.3] gNB: 70-100 m away, 25 m high, NF 7 dB (typical UE Rx).
cfg.gnb.x = -100;  cfg.gnb.h = 25;  cfg.gnb.nf_db = 7;

% [3GPP NR / 802.11ax] Bandwidths: Wi-Fi 80 MHz. Cellular figures are the share
% a single user actually gets, not the full carrier (n78 100 MHz / n28 20 MHz are
% shared among many UEs), so we model half the carrier per user: 50 MHz / 10 MHz.
% Spectral-efficiency discount eta (Shannon-to-implementation gap) [illustrative].
% M3 split is at the packet layer, so no extra PHY penalty (cost is the overhead).
cfg.bw.wifi = 80e6;  cfg.bw.c35 = 50e6;  cfg.bw.c700 = 10e6;
cfg.eff.wifi = 0.50; cfg.eff.cell = 0.55;

% [3GPP TR 38.901 §7.4.3 O2I] High-loss building penetration, consistent
% across bands: 28 dB at 3.5 GHz, 18 dB at 700 MHz.
cfg.ch.pen35_db = 28;   cfg.ch.pen700_db = 18;
% [illustrative] Body loss (phone 3, glass 2 dB); indoor clutter 0.2 dB/m, cap 4 dB.
cfg.ch.body_phone_db = 3;  cfg.ch.body_glass_db = 2;
cfg.ch.clutter_db_per_m = 0.2;  cfg.ch.clutter_cap_db = 4;
% [illustrative] 700 MHz interference margin 6 dB; doorway diffraction peak 8 dB (3.5 GHz only).
cfg.ch.interf700_db = 6;  cfg.ch.door35_db = 8;
% [3GPP TR 38.901 UMa NLOS] Shadowing std sigma35=4, sigma700=3 dB; decorr. 10 m.
cfg.ch.shadow35_db = 4;   cfg.ch.shadow700_db = 3;  cfg.ch.shadow_corr_m = 10;
% [illustrative] Temporal fading (people moving): AR(1), sigma 1.5 dB, corr. time 2 s,
% so the channel keeps fluctuating after the user stops walking.
cfg.ch.tvar_sigma_db = 1.5;  cfg.ch.tvar_tau_s = 2.0;
% [illustrative] Wi-Fi SINR (short link, not the bottleneck).
cfg.ch.wifi_sinr_out_db = 25;  cfg.ch.wifi_sinr_in_db = 22;

% [3GPP TS 38.101 Power Class 3] 23 dBm cap; glasses reduced to 20 dBm [illustrative].
cfg.glass.tx_dbm = 20;  cfg.glass.ant_db = -2;
% [illustrative] Glass power: camera 0.7 W; encoder 0.1 + 1.6*(r/r_max)^1.5 W
% (superlinear in pixel rate); Wi-Fi 0.3 + 0.3*(r/r_max) W; direct cellular 2.0 W.
cfg.glass.p_cam = 0.7;
cfg.glass.p_enc0 = 0.1;  cfg.glass.p_enc1 = 1.6;  cfg.glass.enc_exp = 1.5;
cfg.glass.p_wifi0 = 0.3; cfg.glass.p_wifi1 = 0.3; cfg.glass.p_cell35 = 2.0;
% [IEC 62368-1 / EN 563] Skin-contact safe 42 C, emergency 48 C.
cfg.glass.t_amb = 28;   cfg.glass.t_safe = 42;  cfg.glass.t_max = 48;
% [illustrative] 1st-order RC thermal: a=0.99933 -> tau ~ 150 s (multi-minute
% warm-up); b=0.004 -> 6 K/W steady-state rise. Per 0.1 s step.
cfg.glass.th_a = 0.99933; cfg.glass.th_b = 0.004;
% [Rokid measurement] glass battery ~0.8 Wh (210 mAh, ~45 min continuous capture).
cfg.glass.batt_Wh = 0.8;

% [3GPP TS 38.101 Power Class 3] Phone 23 dBm, 0 dBi.
cfg.phone.tx_dbm = 23;  cfg.phone.ant_db = 0;
% [illustrative] Phone power states: idle 0.3, Wi-Fi Rx 0.4, 3.5G Tx 2.0,
% 700M Tx 1.2, Wi-Fi Tx (to CPE) 0.6 W. M4 switches the cellular radio off.
cfg.phone.p_idle = 0.3;  cfg.phone.p_wrx = 0.4;
cfg.phone.p_tx35 = 2.0;  cfg.phone.p_tx700 = 1.2;  cfg.phone.p_wtx = 0.6;
% [typical 4000 mAh phone] battery ~15 Wh.
cfg.phone.batt_Wh = 15.0;

% [illustrative] Shared CPE at x=15 m, 4 dBi. Total grant 40 Mbps; a two-state
% Markov background load (other users) sits at 5 Mbps (mean dwell 30 s) or
% 25 Mbps (mean dwell 15 s), so allocatable capacity toggles 35/15 Mbps and
% forces the agent to re-balance between M3 and M4.
cfg.cpe.avail_from_x = 0;  cfg.cpe.x = 15;
cfg.cpe.tx_dbm = 23;  cfg.cpe.ant_db = 10;  cfg.cpe.pen_db = 12;
cfg.cpe.cap_total = 40e6;
cfg.cpe.bg_low = 5e6;   cfg.cpe.bg_dwell_low_s = 30;
cfg.cpe.bg_high = 25e6; cfg.cpe.bg_dwell_high_s = 15;
% Coordination overhead 2 Mbps, setup 1 s; alpha=0.8 is the Option C split ratio.
cfg.cpe.coord_ovh = 2e6;  cfg.cpe.setup_s = 1.0;  cfg.cpe.alpha = 0.8;

% [illustrative] RF dead-zone: a shielded interior pocket (lift lobby / metal-clad
% hall) over x in [x0,x1] that blocks the OUTDOOR macro uplink -- both 3.5 GHz and
% 700 MHz get +cell_extra_db of isolation -- while the in-venue CPE (reached over the
% local Wi-Fi hop) is untouched. The cellular-only creators (A glass-direct, B
% reactive-700) lose their link and stall here; those that delegated to the CPE (C, P)
% stream straight through. This isolates a coverage-hole story (proactive
% infrastructure delegation) from the thermal/energy story.
cfg.deadzone.enable = true;  cfg.deadzone.x0 = 8;  cfg.deadzone.x1 = 14;
cfg.deadzone.cell_extra_db = 60;

% [illustrative] ABR ladder 3/8/15/25 Mbps (720p..4K-live), target 15 Mbps.
cfg.video.bitrates = [3e6 8e6 15e6 25e6];
cfg.video.target   = 15e6;  cfg.video.margin = 3e6;
cfg.video.buf0_s = 2.0;  cfg.video.buf_cap_s = 2.5;  cfg.video.buf_low_s = 1.0;

% [illustrative] Controller: p_in threshold 0.65; reactive threshold -5 dB;
% min dwell 2 s; make-before-break gap 1.5 s (NR MBB is sub-100 ms, conservative);
% hyst 5 Mbps margin before switching to a lower-power mode (anti ping-pong).
cfg.ctrl.p_in_thr = 0.65;
cfg.ctrl.react_thr_db = -5;  cfg.ctrl.react_ema_s = 3.5;
cfg.ctrl.min_dur_s = 2.0;    cfg.ctrl.gap_s = 1.5;
cfg.ctrl.hyst_bps = 5e6;

% [illustrative] Scene sensing: sigmoid triggered at x=-6 m, 1 s on-device
% inference delay, additive quantisation noise.
cfg.scene.x_trigger = -6;  cfg.scene.k = 0.8;
cfg.scene.infer_delay_s = 1.0;  cfg.scene.noise_sigma = 0.05;

% [illustrative, cf. ITU-T P.1203] QoE weights. Stall dominates (4.0); thermal
% (3.0) is next because exceeding the skin limit is a hard wearable constraint;
% then delay 1.5 > rate 1.0 > glass energy 0.8 > phone energy 0.6 > switch 0.5.
cfg.qoe.w_rate = 1.0;  cfg.qoe.w_over = 0.1;  cfg.qoe.w_stall = 4.0;  cfg.qoe.w_delay = 1.5;
cfg.qoe.w_energy = 0.8;  cfg.qoe.w_thermal = 3.0;  cfg.qoe.w_switch = 0.5;
cfg.qoe.w_phone = 0.6;
cfg.qoe.mode_delay_s = [0.02 0.03 0.03 0.05 0.05];  % M0..M4 switching delay [illustrative]

% [illustrative] Governor (Proposed only). Predictive intent trigger: stable
% indoors >=10 s + buffer >=80% + long-session intent + predicted top-rung
% steady-state temperature within 0.5 C of the safe limit; releases when the
% scene signals departure (p_in < 0.4). The reactive thermal cap and the
% battery-aware tier are applied inline in run_policy.
cfg.gov.long_session = true;  cfg.gov.dwell_s = 10;
cfg.gov.buf_frac = 0.8;       cfg.gov.t_margin = 0.5;
cfg.gov.exit_pin = 0.4;

% ---- Predictive energy-aware extensions (Proposed only) ----------------
% [illustrative] Mechanism 1 (energy-budget): the fixed ~1.1 W overhead
% (camera + ISP + radio baseline) makes the target rung the most
% quality-per-joule operating point, so cap at the target at all times and
% ride it to battery death instead of reactive battery step-downs.
cfg.ebudget.enable = true;
% [illustrative] Scene complexity C(t) in [0,1] = smoothed ego-motion +
% O2I doorway + crowd. Mechanism 2 (perceptual-rate) uses it to encode only
% what the predicted scene needs; r_floor_frac sets the static-scene bitrate.
cfg.cx.enable = true;   cfg.cx.base = 0.10;
cfg.cx.w_move = 0.60;   cfg.cx.w_door = 0.50;  cfg.cx.w_crowd = 0.40;
cfg.cx.tau_s = 1.0;     cfg.cx.r_floor_frac = 0.40;
% [illustrative] Mechanism 3 (adaptive frame rate): drop the capture frame
% rate on a predicted-static scene (min fraction = 15 fps), with a small
% conservative bias decoupled from the bitrate choice to avoid judder.
cfg.fps.enable = true;  cfg.fps.min_frac = 0.60;  cfg.fps.bias = 0.08;
% [illustrative] Non-ideal prediction: worst-case complexity over a 4 s
% horizon from the known trajectory, corrupted by Gaussian error (sigma_p).
cfg.pred.horizon_s = 4.0;  cfg.pred.cx_noise = 0.15;  cfg.pred.cx_bias = 0.0;
% A predictor's complexity estimate is temporally stable; smooth the noisy
% per-step value (EMA, 3 s) so the encoder holds a rung instead of whipsawing.
cfg.pred.ema_s = 3.0;
end

% ======================================================================
% Scenario: per-step position, environment (out/door/in), CPE availability,
% and the scene-aware indoor probability p_in(t).
% ======================================================================
function s = make_scenario(cfg)
s.dt = cfg.sim.dt;
s.t  = (0:cfg.sim.dt:cfg.sim.total_time_s - cfg.sim.dt).';
% Walk linearly to x_stop, then dwell (stable indoor environment).
s.x  = min(cfg.traj.x0 + cfg.traj.v_mps * s.t, cfg.traj.x_stop);

% env: 0 outdoor, 1 doorway (x in [0,5)), 2 indoor.
s.env = zeros(size(s.t));
s.env(s.x >= cfg.traj.x_entrance & s.x < cfg.traj.x_indoor) = 1;
s.env(s.x >= cfg.traj.x_indoor) = 2;

% Penetration-loss fraction (0 outdoor .. 1 fully indoor) and indoor depth.
s.pen_frac = min(max((s.x - cfg.traj.x_entrance) ...
    / (cfg.traj.x_indoor - cfg.traj.x_entrance), 0), 1);
s.depth = max(0, s.x - cfg.traj.x_indoor);
s.cpe_avail = s.x >= cfg.cpe.avail_from_x;  % CPE discoverable from the entrance

% p_in(t): sigmoid of position, with inference lag and quantisation noise.
p_raw = 1 ./ (1 + exp(-cfg.scene.k * (s.x - cfg.scene.x_trigger)));
lag = round(cfg.scene.infer_delay_s / s.dt);
p_lag = [zeros(lag, 1); p_raw(1:end-lag)];
s.p_in = min(max(p_lag + cfg.scene.noise_sigma * randn(size(s.t)), 0), 1);

s.t_entrance = s.t(find(s.x >= cfg.traj.x_entrance, 1));  % entrance crossing time (s)
end

% ======================================================================
% Channels: path loss, shadowing, SINR, per-mode rates.
% Mode index: 1=M0 glass3.5  2=M1 phone3.5  3=M2 phone700
%             4=M3 coop split 5=M4 CPE full delegation.
% ch.R is N-by-5 (per step x per mode available rate, bps).
% ======================================================================
function ch = make_channels(cfg, s)
N = numel(s.t);
d2d  = abs(s.x - cfg.gnb.x);         % 2D distance (m)
d3d  = sqrt(d2d.^2 + cfg.gnb.h^2);   % 3D distance incl. gNB height
d3dc = sqrt((cfg.cpe.x - cfg.gnb.x)^2 + cfg.gnb.h^2);  % fixed CPE-to-gNB distance

% Spatially correlated shadowing (moving average, corr. 10 m).
sh35 = corr_shadow(s.x, cfg.ch.shadow35_db, cfg.ch.shadow_corr_m);
sh70 = corr_shadow(s.x, cfg.ch.shadow700_db, cfg.ch.shadow_corr_m);

% Temporal AR(1) fading (channel keeps fluctuating during the dwell).
tv35 = ar1_fade(N, s.dt, cfg.ch.tvar_sigma_db, cfg.ch.tvar_tau_s);
tv70 = ar1_fade(N, s.dt, cfg.ch.tvar_sigma_db, cfg.ch.tvar_tau_s);

% Indoor clutter (grows with depth, capped at 4 dB).
clut  = min(s.depth * cfg.ch.clutter_db_per_m, cfg.ch.clutter_cap_db);

% 3.5 GHz penetration: linear ramp + doorway peak (4*p*(1-p) is 1 at mid-crossing).
pen35 = s.pen_frac * cfg.ch.pen35_db ...
      + cfg.ch.door35_db * 4 .* s.pen_frac .* (1 - s.pen_frac);
pen70 = s.pen_frac * cfg.ch.pen700_db;  % 700 MHz: lower loss, no doorway peak

% Noise power (dBm) = -174 dBm/Hz + BW(dB-Hz) + NF (+ interference margin).
n35 = -174 + 10*log10(cfg.bw.c35) + cfg.gnb.nf_db;
n70 = -174 + 10*log10(cfg.bw.c700) + cfg.gnb.nf_db + cfg.ch.interf700_db;

% RF dead-zone: +dz dB of extra isolation on the OUTDOOR macro uplink (3.5 GHz
% glass/phone + 700 MHz phone) over x in [x0,x1]. The local CPE link is unaffected.
if cfg.deadzone.enable
    dz = cfg.deadzone.cell_extra_db ...
        * double(s.x >= cfg.deadzone.x0 & s.x <= cfg.deadzone.x1);
else
    dz = zeros(size(s.x));
end

% Per-step SINR (dB), incl. spatial shadowing and temporal fading.
ch.sinr_glass35 = cfg.glass.tx_dbm + cfg.glass.ant_db - pl(d3d, 3.5) ...
    - sh35 - tv35 - pen35 - clut - cfg.ch.body_glass_db - dz - n35;
ch.sinr_phone35 = cfg.phone.tx_dbm + cfg.phone.ant_db - pl(d3d, 3.5) ...
    - sh35 - tv35 - pen35 - clut - cfg.ch.body_phone_db - dz - n35;
ch.sinr_phone700 = cfg.phone.tx_dbm + cfg.phone.ant_db - pl(d3d, 0.7) ...
    - sh70 - tv70 - pen70 - clut - cfg.ch.body_phone_db - dz - n70;
sinr_cpe = cfg.cpe.tx_dbm + cfg.cpe.ant_db - pl(d3dc, 0.7) ...
    - cfg.cpe.pen_db - n70;                       % CPE is static, SINR constant

% Efficiency-discounted Shannon rates.
r_glass35 = rate(cfg.eff.cell, cfg.bw.c35, ch.sinr_glass35);
r_phone35 = rate(cfg.eff.cell, cfg.bw.c35, ch.sinr_phone35);
r_phone70 = rate(cfg.eff.cell, cfg.bw.c700, ch.sinr_phone700);
r_cpe_link = rate(cfg.eff.cell, cfg.bw.c700, sinr_cpe) * ones(N, 1);  % CPE physical link

% Shared CPE: two-state Markov background load (other users); allocatable
% capacity = min(physical link, total grant - background load).
bg = zeros(N, 1);  hi = false;
for i = 1:N
    if ~hi && rand < s.dt / cfg.cpe.bg_dwell_low_s,  hi = true;
    elseif hi && rand < s.dt / cfg.cpe.bg_dwell_high_s, hi = false;
    end
    bg(i) = cfg.cpe.bg_low + (cfg.cpe.bg_high - cfg.cpe.bg_low) * hi;
end
ch.cpe_cap = max(0, min(r_cpe_link, cfg.cpe.cap_total - bg));
r_cpe70 = ch.cpe_cap;

% Wi-Fi (glass->phone): different in/out SINR, usually not the bottleneck.
wifi_sinr = cfg.ch.wifi_sinr_in_db * ones(N, 1);
wifi_sinr(s.env == 0) = cfg.ch.wifi_sinr_out_db;
r_wifi = rate(cfg.eff.wifi, cfg.bw.wifi, wifi_sinr);

% M3: non-coherent packet-split (Option C). alpha fraction split + (1-alpha)
% on the stronger link, minus the coordination overhead (no PHY penalty).
a = cfg.cpe.alpha;
coop = a*(r_phone70 + r_cpe70) + (1-a)*max(r_phone70, r_cpe70) - cfg.cpe.coord_ovh;
coop = max(coop, 0);

% M4: full delegation (glass->phone->CPE->gNB, phone cellular off). Bounded
% by Wi-Fi and CPE capacity (two Wi-Fi hops on separate channels, no contention).
r_deleg = r_cpe70;

% ch.R: per step x per mode (M0..M4). min(r_wifi, .) keeps Wi-Fi off the
% critical path for relayed modes.
ch.R = [r_glass35, min(r_wifi, r_phone35), min(r_wifi, r_phone70), ...
        min(r_wifi, coop), min(r_wifi, r_deleg)];
% Availability: M0/M1/M2 always; M3/M4 require the CPE in range.
ch.avail = [true(N, 3), s.cpe_avail, s.cpe_avail];

% Scene complexity C(t) in [0,1]: a smoothed sum of ego-motion (still walking
% toward the stop), the O2I doorway, and a crowd term active during a busy
% indoor CPE spell. Shared by all policies (it is a property of the scene);
% the Proposed policy predicts it ahead in run_policy.
ch.moving = s.x < cfg.traj.x_stop - 1e-9;                 % walking vs dwelling
ch.busy   = (bg > cfg.cpe.bg_low) & s.cpe_avail & (s.env == 2);
cx_raw = min(max(cfg.cx.base + cfg.cx.w_move*double(ch.moving) ...
    + cfg.cx.w_door*double(s.env == 1) + cfg.cx.w_crowd*double(ch.busy), 0), 1);
ac = exp(-s.dt / cfg.cx.tau_s);                           % AR(1) smoothing
cx = zeros(N, 1);  cx(1) = cfg.cx.base;
for i = 2:N, cx(i) = ac*cx(i-1) + (1 - ac)*cx_raw(i); end
ch.cx = cx;
end

% UMa-style path loss (d in m, fc in GHz).
function v = pl(d, fc_ghz)
v = 13.54 + 39.08*log10(max(d, 1)) + 20*log10(fc_ghz);
end

% Efficiency-discounted Shannon rate (eta discount, bw Hz, SINR dB).
function r = rate(eta, bw, sinr_db)
r = eta * bw .* log2(1 + 10.^(sinr_db / 10));
end

% AR(1) temporal fading (dB): std sigma, correlation time tau (s).
function v = ar1_fade(n, dt, sigma, tau)
r = exp(-dt / tau);
v = zeros(n, 1);
for i = 2:n
    v(i) = r * v(i-1) + sqrt(1 - r^2) * sigma * randn;
end
end

% Spatially correlated shadowing: white noise, moving-averaged, interpolated to x.
function sh = corr_shadow(x, sigma_db, corr_m)
grid = (min(x) - corr_m : 1 : max(x) + 2*corr_m).';
raw = randn(size(grid));
w = max(3, round(corr_m));
sm = conv(raw, ones(w, 1)/w, 'same');      % moving average = spatial correlation
sm = sm / (std(sm) + 1e-9) * sigma_db;     % normalise to target std
sh = interp1(grid, sm, x, 'linear', 'extrap');
end

% ======================================================================
% Policy engine: one policy over the episode. pid index
% (1=A glass-3.5-direct  2=B reactive-700-switch
%  3=C scene-aware w/o governor  4=Proposed scene-aware with governor).
% ======================================================================
function log = run_policy(pid, cfg, s, ch)
N = numel(s.t);  dt = s.dt;
br = sort(cfg.video.bitrates);  ultra = br(end);  % top rung (QoE normaliser)
tgt_lvl = find(br == cfg.video.target, 1);        % rung the governor caps to

% ---- controller state -------------------------------------------------
mode = 0;        % current mode (0 = uninitialised)
prev = 0;        % old mode during a make-before-break gap
last_sw = -1e9;  % last switch time
gap_until = -1;  % make-before-break gap end time
cpe_init = false; % charge the CPE setup delay only once (first M3/M4)
tripped = false;  % baseline B: latched once SINR drops below threshold
use_gov = (pid == 4);  % only the full proposal runs the governor
gov_on = false;        % governor state
t_indoor = inf;        % time of entering the indoor region (env==2)

% reactive EMA (baseline B): y[n] = alpha*x[n] + (1-alpha)*y[n-1] via filter().
alpha = dt / cfg.ctrl.react_ema_s;
ema = filter(alpha, [1, alpha-1], ch.sinr_phone35, ch.sinr_phone35(1)*(1-alpha));

% ---- video / device state --------------------------------------------
buf = cfg.video.buf0_s;  % live buffer (s)
level = numel(br);       % current ABR rung (start at top)
downgrades = 0;
temp = cfg.glass.t_amb + 6;  % glass temperature (ambient + 6 C self-heat)
energy = 0;              % glass cumulative energy (J)
ph_energy = 0;           % phone cumulative energy (J)
glass_batt = cfg.glass.batt_Wh;  phone_batt = cfg.phone.batt_Wh;  % batteries (Wh)
dead = false;  death_t = NaN;  alive_time = 0;  % glass battery empty -> stream ends
useful_q = 0;                    % useful quality-seconds (longevity-aware metric)

% Predictive complexity (Proposed only): worst-case scene complexity over a
% horizon from the KNOWN trajectory (deterministic ego-motion + doorway part),
% used by Mechanisms 2 and 3. The crowd term and noise are added per step.
egomax = [];  cx_ema = cfg.cx.base;   % cx_ema: smoothed predicted complexity
if use_gov && cfg.cx.enable
    H = round(cfg.pred.horizon_s / dt);
    ego_raw = cfg.cx.base + cfg.cx.w_move*double(ch.moving) ...
            + cfg.cx.w_door*double(s.env == 1);
    egomax = zeros(N, 1);
    for i = 1:N, egomax(i) = max(ego_raw(i:min(N, i+H))); end
end

% per-step logs
log.mode = zeros(N,1); log.rate = zeros(N,1); log.vrate = zeros(N,1);
log.buf = zeros(N,1);  log.stall = false(N,1); log.qoe = zeros(N,1);
log.temp = zeros(N,1); log.power = zeros(N,1);
log.phone_w = zeros(N,1); log.gov = false(N,1);  log.fps = ones(N,1);
log.glass_batt = zeros(N,1); log.phone_batt = zeros(N,1); log.alive = true(N,1);

for i = 1:N
    t = s.t(i);

    % ---- battery death: stream stops, QoE frozen (excluded from average),
    %      temperature relaxes to ambient -----------------------------------
    if dead
        temp = cfg.glass.t_amb + cfg.glass.th_a*(temp - cfg.glass.t_amb);
        log.mode(i)=mode; log.rate(i)=0; log.vrate(i)=0; log.buf(i)=0;
        log.stall(i)=true; log.qoe(i)=0; log.alive(i)=false;
        log.temp(i)=temp; log.power(i)=0; log.phone_w(i)=cfg.phone.p_idle;
        log.gov(i)=gov_on; log.glass_batt(i)=0; log.phone_batt(i)=phone_batt;
        continue;
    end

    % ---- Step 0: governor (Proposed only) -------------------------------
    % (i) predictive intent trigger: a long stable indoor dwell whose predicted
    % top-rung steady-state temperature would breach the safe limit.
    if s.env(i) == 2, t_indoor = min(t_indoor, t); end
    if use_gov && ~gov_on
        p_top = glass_power(cfg, ultra, ultra, false);  % top rung, Wi-Fi offload
        t_ss  = cfg.glass.t_amb + cfg.glass.th_b/(1 - cfg.glass.th_a)*p_top;
        if cfg.gov.long_session && (t - t_indoor) >= cfg.gov.dwell_s ...
                && buf >= cfg.gov.buf_frac * cfg.video.buf_cap_s ...
                && t_ss > cfg.glass.t_safe - cfg.gov.t_margin
            gov_on = true;
        end
    elseif gov_on && s.p_in(i) < cfg.gov.exit_pin
        gov_on = false;  % scene signals departure -> release the cap
    end
    % base cap: Mechanism 1 (energy-budget) caps at the target at all times;
    % otherwise the governor caps the ladder only while it is engaged.
    if (use_gov && cfg.ebudget.enable) || gov_on
        kmax = tgt_lvl;
    else
        kmax = numel(br);
    end
    % (ii) reactive thermal cap (location-agnostic, protects outdoor dwell too).
    if use_gov && temp > cfg.glass.t_safe
        kmax = min(kmax, 2);              % >42 C -> 8 Mbps
    elseif use_gov && temp > cfg.glass.t_safe - 1
        kmax = min(kmax, tgt_lvl);        % >41 C -> 15 Mbps
    end
    % Mechanisms 2 and 3: predict the scene complexity from the known trajectory,
    % cap the bitrate to what the picture needs, and match the capture frame rate.
    fps_frac = 1;
    if use_gov && cfg.cx.enable
        Cpred = min(max(egomax(i) + cfg.cx.w_crowd*double(ch.busy(i)), 0), 1);
        Cpred = min(max(Cpred + cfg.pred.cx_bias + cfg.pred.cx_noise*randn, 0), 1);
        ac_p = exp(-dt / cfg.pred.ema_s);             % smooth the noisy estimate
        cx_ema = ac_p*cx_ema + (1 - ac_p)*Cpred;
        rn = r_need(cfg, cx_ema);         % Mechanism 2: perceptual-rate cap
        for k = 1:numel(br)
            if br(k) >= rn, kmax = min(kmax, k); break; end
        end
        if cfg.fps.enable                 % Mechanism 3: adaptive frame rate
            fps_frac = fps_need(cfg, min(max(cx_ema + cfg.fps.bias, 0), 1));
        end
    end
    % legacy reactive battery tier (only when the energy budget is disabled).
    if use_gov && ~cfg.ebudget.enable
        bf = glass_batt / cfg.glass.batt_Wh;
        if bf < 0.10, kmax = 1; elseif bf < 0.25, kmax = min(kmax, 2); end
    end
    need = br(kmax) + cfg.video.margin;  % rate requirement tracks the quality demand

    % ---- Step 1: desired mode -------------------------------------------
    switch pid
        case 1, want = 1;                          % A: fixed M0 (glass 3.5G)
        case 2                                     % B: reactive M1 -> M2 on threshold
            if ema(i) < cfg.ctrl.react_thr_db, tripped = true; end
            want = 2 + tripped;                    % M1 -> M2 (never reverts)
        otherwise                                  % C / Proposed: scene-aware
            want = scene_aware(i, mode, need, cfg, s, ch);
    end

    % ---- Step 2: hysteresis + make-before-break gap ---------------------
    just_sw = false;
    if mode == 0
        mode = want;  last_sw = t;  % first init, no delay
    elseif want ~= mode && (t - last_sw) >= cfg.ctrl.min_dur_s
        g = cfg.ctrl.gap_s;
        % first CPE engagement (M3 or M4) adds the one-time setup gap
        if (want == 4 || want == 5) && ~cpe_init
            g = g + cfg.cpe.setup_s;  cpe_init = true;
        end
        gap_until = t + g;  prev = mode;  mode = want;  last_sw = t;
        just_sw = true;
    end

    % ---- Step 3: the old link keeps serving during the gap --------------
    in_gap = t < gap_until;
    if in_gap && prev > 0
        mused = prev;
    else
        mused = mode;
    end
    delivered = ch.R(i, mused) * ch.avail(i, mused);

    % ---- Step 4: ABR selection (ladder capped at kmax) ------------------
    new = 1;  % drop to the floor, then climb to the highest sustainable rung
    for k = 1:kmax
        if delivered >= br(k) + cfg.video.margin, new = k; end
    end
    if buf < cfg.video.buf_low_s, new = max(1, new - 1); end  % buffer low -> drop one
    if new < level, downgrades = downgrades + 1; end
    level = new;  vrate = br(level);
    if temp > cfg.glass.t_max, vrate = br(1); end  % hard overheat protection (all policies)

    % ---- Step 5: buffer update ------------------------------------------
    buf = min(cfg.video.buf_cap_s, max(0, buf + dt*(delivered/vrate - 1)));
    stall = buf <= 1e-9;

    % ---- Step 6: glass/phone power, batteries, glass temperature --------
    pw  = glass_power(cfg, vrate, ultra, mode == 1, fps_frac);  % glasses (M0 uses cellular)
    ppw = phone_power(cfg, mused);                    % phone (by serving mode)
    energy = energy + pw*dt;
    ph_energy = ph_energy + ppw*dt;
    glass_batt = glass_batt - pw*dt/3600;             % Wh
    phone_batt = max(0, phone_batt - ppw*dt/3600);
    if glass_batt <= 0, glass_batt = 0; dead = true; death_t = t; end
    alive_time = alive_time + dt;
    temp = cfg.glass.t_amb + cfg.glass.th_a*(temp - cfg.glass.t_amb) ...
         + cfg.glass.th_b*pw;

    % ---- Step 7: per-step QoE -------------------------------------------
    % energy term counts only the glass radio power (computed directly so it is
    % independent of the frame-rate scaling applied to camera/encoder above).
    rr = vrate / ultra;
    if mode == 1, p_rad = cfg.glass.p_cell35;
    else,         p_rad = cfg.glass.p_wifi0 + cfg.glass.p_wifi1 * rr; end
    q = qoe_score(cfg, ultra, ternary(stall, 0, vrate), stall, mode, ...
                  p_rad, ppw, temp, just_sw, fps_frac, ch.cx(i));
    % useful quality-seconds: SATURATING perceived quality (no over-target bonus)
    % per non-stalled, alive second, so the integral never exceeds alive time.
    useful_q = useful_q + ternary(stall, 0, ...
        sat_q(cfg, vrate, fps_frac, ch.cx(i))) * dt;

    % ---- log ------------------------------------------------------------
    log.mode(i) = mode;  log.rate(i) = delivered;  log.vrate(i) = vrate;
    log.buf(i) = buf;    log.stall(i) = stall;     log.qoe(i) = q;
    log.temp(i) = temp;  log.power(i) = pw;
    log.phone_w(i) = ppw;  log.gov(i) = gov_on;  log.fps(i) = fps_frac;
    log.glass_batt(i) = glass_batt;  log.phone_batt(i) = phone_batt;  log.alive(i) = true;
end
log.downgrades = downgrades;  log.energy_j = energy;  log.useful_q_s = useful_q;
log.phone_energy_j = ph_energy;
log.glass_batt_pct = 100*max(0,glass_batt)/cfg.glass.batt_Wh;
log.phone_batt_pct = 100*phone_batt/cfg.phone.batt_Wh;
log.death_t = death_t;  log.uptime_s = alive_time;
end

% Glass power: camera + superlinear encoder + radio. is_m0 -> direct cellular
% (2.0 W); otherwise Wi-Fi offload (base + airtime term).
function pw = glass_power(cfg, vrate, ultra, is_m0, fps_frac)
if nargin < 5, fps_frac = 1; end   % frame-rate fraction (Mechanism 3); baselines = 1
r = vrate / ultra;
% Frame rate scales the camera + per-frame encoder base (sensor/ISP capture);
% the bitrate-driven encoder term and the radio are data/link costs, untouched.
pw = fps_frac*(cfg.glass.p_cam + cfg.glass.p_enc0) + cfg.glass.p_enc1 * r^cfg.glass.enc_exp;
if is_m0
    pw = pw + cfg.glass.p_cell35;
else
    pw = pw + cfg.glass.p_wifi0 + cfg.glass.p_wifi1 * r;
end
end

% Phone power: idle + Wi-Fi Rx + uplink radio (by mode). M4 turns the cellular
% radio off (only Wi-Fi relaying), which is the phone-battery saver.
function pw = phone_power(cfg, mode)
c = cfg.phone;
switch mode
    case 1, pw = c.p_idle;                                   % M0: phone idle
    case 2, pw = c.p_idle + c.p_wrx + c.p_tx35;              % M1: 3.5G uplink
    case 3, pw = c.p_idle + c.p_wrx + c.p_tx700;             % M2: 700M uplink
    case 4, pw = c.p_idle + c.p_wrx + c.p_tx700 + c.p_wtx;   % M3: 700M + Wi-Fi to CPE
    case 5, pw = c.p_idle + c.p_wrx + c.p_wtx;               % M4: cellular off
    otherwise, pw = c.p_idle;
end
end

% ======================================================================
% Scene-aware controller (shared by E and Proposed; the governor only
% changes the rate requirement `need` that is passed in).
% Outdoor: M1 workhorse; high p_in (or dead 3.5G) -> pre-switch to M2.
% Indoor: among {M4, M2, M3} pick the lowest-phone-power mode that meets
% `need` (resource-rational: let the phone cellular radio sleep if it can).
% ======================================================================
function want = scene_aware(i, mode, need, cfg, s, ch)
indoor  = s.env(i) == 2;  outdoor = s.env(i) == 0;
sinr_ok = ch.sinr_phone35(i) > 0;  % 3.5 GHz worth keeping only if SINR > 0 dB

if indoor && s.cpe_avail(i)
    % candidates ordered by phone power: M4 (1.3 W) < M2 (1.9 W) < M3 (2.5 W)
    cands = [5 3 4];
    cur_pw = inf;
    if mode > 0, cur_pw = phone_power(cfg, mode); end
    for k = 1:3
        m = cands(k);
        thr = need;
        % switching to a lower-power mode needs an extra rate margin (anti ping-pong)
        if phone_power(cfg, m) < cur_pw, thr = thr + cfg.ctrl.hyst_bps; end
        if ch.avail(i, m) && ch.R(i, m) >= thr
            want = m;  return
        end
    end
    % nothing meets `need`: best effort, take the highest available rate
    r = ch.R(i, 3:5) .* ch.avail(i, 3:5);
    [~, j] = max(r);  want = j + 2;  return
end
% scene predicts indoor entry (or 3.5G is dead) -> pre-switch to 700 MHz
if s.p_in(i) >= cfg.ctrl.p_in_thr || ~sinr_ok
    want = 3;  return
end
% outdoor with usable 3.5G -> phone 3.5G workhorse
if outdoor && sinr_ok
    want = 2;  return
end
want = 2;  % doorway transition, otherwise keep phone 3.5G
end

% ======================================================================
% QoE score: rate utility (log2-normalised) minus stall, switching delay,
% glass radio energy, phone energy, thermal stress, and the switch cost.
% ======================================================================
function q = qoe_score(cfg, ultra, vrate, stall, mode, p_rad, ppw, temp, switched, fps_frac, C)
ph_max = cfg.phone.p_idle + cfg.phone.p_wrx + cfg.phone.p_tx35;  % max phone power (M1)
% Perceptual utility: the weaker of bitrate and frame-rate adequacy for the
% scene complexity, saturating at the target need; for baselines (fps=1, C
% unused) it reduces to the saturating bitrate ratio at the 15 Mbps target.
rate_util = perceptual_q(cfg, ultra, vrate, fps_frac, C);
q = cfg.qoe.w_rate   * rate_util ...
  - cfg.qoe.w_stall  * stall ...
  - cfg.qoe.w_delay  * cfg.qoe.mode_delay_s(mode) / 0.2 ...
  - cfg.qoe.w_energy * max(0, p_rad) / cfg.glass.p_cell35 ...
  - cfg.qoe.w_phone  * ppw / ph_max ...
  - cfg.qoe.w_thermal * max(0, temp - cfg.glass.t_safe) ...
                      / (cfg.glass.t_max - cfg.glass.t_safe) ...
  - cfg.qoe.w_switch * switched;
end

% Bitrate needed for the target perceived quality at scene complexity C:
% static (C->0) needs r_floor_frac*target, full motion (C->1) needs target.
function rn = r_need(cfg, C)
if cfg.cx.enable, x = min(max(C, 0), 1); else, x = 1; end
rn = cfg.video.target * (cfg.cx.r_floor_frac + (1 - cfg.cx.r_floor_frac)*x);
end

% Frame-rate fraction the scene needs (min fraction at C=0, full at C=1).
function f = fps_need(cfg, C)
if ~cfg.fps.enable, f = 1; return; end
f = cfg.fps.min_frac + (1 - cfg.fps.min_frac) * min(max(C, 0), 1);
end

% Perceptual quality: the weaker of bitrate and frame-rate adequacy for the
% complexity, plus a small over-target bonus. A static scene reaches u=1 at a
% low bitrate AND low frame rate; under-provisioning either lowers u.
function u = perceptual_q(cfg, ultra, vrate, fps_frac, C)
rn = r_need(cfg, C);
pq_rate = min(1, vrate / rn);
if cfg.fps.enable, pq_fps = min(1, fps_frac / fps_need(cfg, C)); else, pq_fps = 1; end
u = min(pq_rate, pq_fps) + cfg.qoe.w_over * max(0, (vrate - rn) / max(ultra - rn, 1));
end

% Saturating adequacy in [0,1]: the min-of-adequacies WITHOUT the over-target
% bonus, used for useful quality-seconds so quality credit caps at 1 per second.
function u = sat_q(cfg, vrate, fps_frac, C)
rn = r_need(cfg, C);
pq_rate = min(1, vrate / rn);
if cfg.fps.enable, pq_fps = min(1, fps_frac / fps_need(cfg, C)); else, pq_fps = 1; end
u = min(pq_rate, pq_fps);
end

% Ternary helper (MATLAB has no native ?: operator).
function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

% ======================================================================
% Metrics: bitrate, stalls, QoE (alive-only average), temperature,
% batteries, energy, mode times, switch timing.
% ======================================================================
function m = compute_metrics(log, s)
dt = s.dt;
m.avg_rate_mbps = mean(log.rate)/1e6;
m.p5_rate_mbps  = prctile_(log.rate, 5)/1e6;
m.avg_bitrate_mbps = mean(log.vrate)/1e6;
m.downgrades = log.downgrades;
st = log.stall;
m.stall_count = sum(diff([false; st]) == 1);   % number of stall events
m.stall_total_s = sum(st)*dt;                  % total stall time (s)
m.avg_qoe = mean(log.qoe(log.alive));          % average over alive steps (frozen at death)
m.p5_qoe  = prctile_(log.qoe(log.alive), 5);
% worst QoE in the +/-10 s window around entrance (the critical transition)
win = s.t >= s.t_entrance-10 & s.t <= s.t_entrance+10;
m.min_qoe_transition = min(log.qoe(win));
m.glass_energy_j = log.energy_j;
m.glass_temp_max_c = max(log.temp);
m.mode_switches = sum(diff(log.mode) ~= 0);
% switch_lead_s > 0 means the cellular band changed before entrance (proactive)
lead_idx = find(log.mode >= 3, 1);  % first time off 3.5 GHz (M2/M3/M4)
if isempty(lead_idx), m.switch_lead_s = NaN;
else, m.switch_lead_s = s.t_entrance - s.t(lead_idx); end
m.time_in_modes = accumarray(log.mode, dt, [5 1]).';  % seconds in each mode
m.phone_energy_j = log.phone_energy_j;
m.glass_batt_pct = log.glass_batt_pct;                 % glass charge remaining (%)
m.phone_batt_pct = log.phone_batt_pct;                 % phone charge remaining (%)
m.uptime_s = log.uptime_s;                             % streaming uptime (s)
m.useful_q_s = log.useful_q_s;                         % useful quality-seconds (longevity-aware)
end

% Percentile without the Statistics Toolbox.
function v = prctile_(x, p)
xs = sort(x(:));  n = numel(xs);
idx = min(max(1, round(p/100*(n-1)) + 1), n);
v = xs(idx);
end

function print_table(names, mets)
cols = {'avg_bitrate_mbps','stall_total_s','avg_qoe','min_qoe_transition', ...
        'useful_q_s','uptime_s','glass_temp_max_c','glass_batt_pct','phone_batt_pct', ...
        'phone_energy_j','mode_switches','switch_lead_s'};
fprintf('\n%-34s', 'policy');
for c = 1:numel(cols), fprintf('| %18s ', cols{c}); end
fprintf('\n%s\n', repmat('-', 1, 34 + 21*numel(cols)));
for p = 1:numel(names)
    fprintf('%-34s', names{p});
    for c = 1:numel(cols)
        fprintf('| %18.2f ', mets{p}.(cols{c}));
    end
    fprintf('\n');
end
fprintf('\nTime in modes (s)  [M0 M1 M2 M3 M4]:\n');
for p = 1:numel(names)
    fprintf('  %-34s: %s\n', names{p}, mat2str(round(mets{p}.time_in_modes)));
end
end

% ======================================================================
% Figures. See the supplement for the discussion each one supports.
% ======================================================================
function make_plots(outdir, cfg, s, ch, names, logs, mets)
% Per-policy colour (C is the purple ablation, Proposed the blue solid lead).
col = containers.Map( ...
    {'A: glass 3.5 direct','B: reactive 700 switch', ...
     'C: scene-aware w/o governor','Proposed: scene-aware UE-CoMIMO'}, ...
    {[0.69 0.69 0.69],[0.82 0.44 0.12], ...
     [0.58 0.40 0.74],[0.12 0.37 0.82]});
% Line style: distinct dashes per policy, solid for Proposed.
sty = containers.Map( ...
    {'A: glass 3.5 direct','B: reactive 700 switch', ...
     'C: scene-aware w/o governor','Proposed: scene-aware UE-CoMIMO'}, ...
    {'--', '-.', ':', '-'});
% Line width: Proposed thickest (visual lead).
lwd = containers.Map( ...
    {'A: glass 3.5 direct','B: reactive 700 switch', ...
     'C: scene-aware w/o governor','Proposed: scene-aware UE-CoMIMO'}, ...
    {1.2, 1.2, 1.4, 2.2});
t = s.t;  te = s.t_entrance;
ip = find(strcmp(names, 'Proposed: scene-aware UE-CoMIMO'));
ic = find(strcmp(names, 'B: reactive 700 switch'));
ie = find(strcmp(names, 'C: scene-aware w/o governor'));
modeNames = {'M0','M1','M2','M3','M4'};

% ---- Fig 1: mode timeline (Proposed pre-switches and alternates M3/M4;
%             reactive C switches only after entry) ---------------------
f = figure('Visible','off','Position',[100 100 760 280]);
stairs(t, logs{ip}.mode, 'LineWidth', lwd(names{ip}), 'LineStyle', sty(names{ip}), 'Color', col(names{ip})); hold on
stairs(t, logs{ic}.mode, 'LineWidth', lwd(names{ic}), 'LineStyle', sty(names{ic}), 'Color', col(names{ic}));
xline(te, 'k--'); yticks(1:5); yticklabels(modeNames); ylim([0.5 5.5])
xlabel('Time (s)'); title('Mode timeline')
legend({names{ip}, names{ic}}, 'Location','southeast', 'FontSize',7)
save_fig(f, outdir, 'fig1_mode_timeline');

% ---- Fig 2: available rate vs selected bitrate (Proposed), with CPE
%             allocatable capacity (shows M3/M4 re-balancing) -----------
f = figure('Visible','off','Position',[100 100 760 300]);
plot(t, logs{ip}.rate/1e6, 'LineWidth', lwd(names{ip}), 'LineStyle', sty(names{ip}), 'Color', col(names{ip})); hold on
plot(t, logs{ip}.vrate/1e6, '--k', 'LineWidth',1.4);
plot(t, ch.cpe_cap/1e6, ':', 'LineWidth',1.2, 'Color',[0.45 0.45 0.45]);
xline(te, 'k--'); ylim([0 80])
xlabel('Time (s)'); ylabel('Rate (Mbps)')
title('Uplink rate and video bitrate (proposed)')
legend({'available (selected mode)','selected video bitrate', ...
        'CPE allocatable capacity'}, 'FontSize',8)
save_fig(f, outdir, 'fig2_rate_bitrate');

% ---- Fig 3: buffer level (A/B drain to stalls indoors) ----------------
f = figure('Visible','off','Position',[100 100 760 300]); hold on
for p = 1:numel(names)
    plot(t, logs{p}.buf, 'LineWidth', lwd(names{p}), 'LineStyle', sty(names{p}), 'Color', col(names{p}));
end
xline(te, 'k--');
xlabel('Time (s)'); ylabel('Live buffer (s)')
title('Buffer level (buffer = 0 means stall)')
legend(names, 'FontSize',7, 'Location','southwest')
save_fig(f, outdir, 'fig3_buffer');

% ---- Fig 4: QoE over time (2 s moving average, full range) -------------
f = figure('Visible','off','Position',[100 100 760 300]); hold on
for p = 1:numel(names)
    plot(t, movmean(logs{p}.qoe, 20), 'LineWidth', lwd(names{p}), 'LineStyle', sty(names{p}), 'Color', col(names{p}));
end
xline(te, 'k--');
xlabel('Time (s)'); ylabel('QoE (2 s moving avg)')
title('QoE over time (key region: O2I transition)')
legend(names, 'FontSize',7, 'Location','southwest')
save_fig(f, outdir, 'fig4_qoe');

% ---- Fig 5: glass temperature (A / C / Proposed; T_safe = 42 C) -------
% A is hottest; C (no governor) crosses the limit; Proposed stays below it
% after the governor activates (vertical dotted line).
f = figure('Visible','off','Position',[100 100 760 300]); hold on
idxs = [1 ie ip];
hl = gobjects(1, numel(idxs));
for k = 1:numel(idxs)
    p = idxs(k);
    hl(k) = plot(t, logs{p}.temp, 'LineWidth', lwd(names{p}), ...
                 'LineStyle', sty(names{p}), 'Color', col(names{p}));
end
hsafe = yline(cfg.glass.t_safe, 'r:');  xline(te, 'k--');
g_on = find(logs{ip}.gov, 1);
hgov = gobjects(0);
if ~isempty(g_on), hgov = xline(t(g_on), 'b:'); end
xlabel('Time (s)'); ylabel('AI-glass temperature (degC)')
title('AI-glass thermal trajectory')
legend([hl hsafe hgov], [names(idxs) {'T_{safe}'} {'governor on'}], ...
       'FontSize',8, 'Location','southeast')
save_fig(f, outdir, 'fig5_temperature');

% ---- Fig 7: glass battery drain (higher bitrate drains faster:
%             A/E first; the governor lets Proposed last longer) --------
f = figure('Visible','off','Position',[100 100 760 300]); hold on
for p = 1:numel(names)
    plot(t, 100*logs{p}.glass_batt/cfg.glass.batt_Wh, ...
        'LineWidth', lwd(names{p}), 'LineStyle', sty(names{p}), 'Color', col(names{p}));
end
xline(te, 'k--');
xlabel('Time (s)'); ylabel('AI-glass battery (%)'); ylim([0 100])
title('AI-glass battery drain')
legend(names, 'FontSize',7, 'Location','northeast')
save_fig(f, outdir, 'fig7_battery');

% ---- Fig 6: aggregate KPI bars ----------------------------------------
keys = {'avg_qoe','stall_total_s','glass_temp_max_c', ...
        'glass_batt_pct','phone_batt_pct','phone_energy_j'};
ttl  = {'Average QoE','Stall (s)','Max temp (degC)', ...
        'Glass batt (%)','Phone batt (%)','Phone energy (J)'};
shrt = {'A','B','C','Prop.'};
f = figure('Visible','off','Position',[60 60 1300 320]);
for k = 1:numel(keys)
    subplot(1, numel(keys), k); hold on
    for p = 1:numel(names)
        bar(p, mets{p}.(keys{k}), 'FaceColor', col(names{p}));
    end
    xticks(1:numel(names)); xticklabels(shrt); title(ttl{k}, 'FontSize',9)
end
sgtitle('Baseline comparison (A-B baselines, C ablation, proposed)')
save_fig(f, outdir, 'fig6_summary');

% ---- Combined paper figure (top: bitrate, bottom: QoE clipped) ---------
% QoE clipped to [-1.5, 0.5] so B/C/P detail is visible; A stalls far below
% and is labelled with an off-scale annotation rather than a broken axis.
f = figure('Visible','off','Position',[100 100 760 540]);
zorder = [ip, setdiff(1:numel(names), ip, 'stable')];
pw = @(p) min(lwd(names{p}), 1.8);
subplot(2,1,1); hold on
h = gobjects(numel(names),1);
for p = zorder
    h(p) = plot(t, logs{p}.vrate/1e6, 'LineWidth', pw(p), 'LineStyle', sty(names{p}), 'Color', col(names{p}));
end
xline(te, 'k--'); text(te+1, 2, 'indoor entry', 'FontSize',8)
ylim([0 34])
ylabel('Delivered video bitrate (Mbps)')
title('AI-glass uplink live streaming across an O2I transition')
legend(h, names, 'FontSize',7, 'Location','north', 'NumColumns',3)
subplot(2,1,2); hold on
for p = zorder
    plot(t, movmean(logs{p}.qoe, 20), 'LineWidth', pw(p), 'LineStyle', sty(names{p}), 'Color', col(names{p}));
end
xline(te, 'k--');
ylim([-1.5 0.5])
% Baselines A and B stall (B in the RF dead-zone) and descend below the visible range.
text(210, -1.38, 'A, B stall \approx -5 to -6 (\downarrow off scale)', 'FontSize',8, ...
     'HorizontalAlignment','right', 'Color', col(names{1}), 'Interpreter','tex')
ylabel('QoE (2 s moving avg)'); xlabel('Time (s)')
save_fig(f, outdir, 'fig_paper_combined');
% Tightly-cropped vector PDF (no -bestfit page margins) for the paper figure.
exportgraphics(f, fullfile(outdir, 'fig_paper_combined.pdf'), 'ContentType', 'vector');
close(f);
end

% Save one figure (PNG, 180 dpi).
function save_fig(f, outdir, name)
print(f, fullfile(outdir, name), '-dpng', '-r180');
end
