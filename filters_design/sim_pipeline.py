"""
Bit-accurate (sample-domain) model of the hardware ECG pipeline used to debug
STEMI detection. Replicates:
  differentiator.sv -> squarer.sv -> moving_window_integration.sv ->
  adaptive_threshold.sv  (R-peak)
  + delay_buffer.sv (x2) + stemi_detector.sv

The goal is to reproduce the buggy behaviour seen on the board / in the TB,
then to validate fixes.
"""

import os
import numpy as np
import scipy.signal as signal
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = r"C:\Users\pbuko\Desktop\SystemVerilog\projekt"
CSV = os.path.join(ROOT, "ecg_samples_4.csv")

# ----------------------------------------------------------------------------
# 1. Re-create the artificial STEMI signal exactly like patology_prep.py
# ----------------------------------------------------------------------------
raw = []
with open(CSV, "r") as f:
    for row in f:
        raw.append(int(row.strip(), 16))
raw = np.array(raw)

ecg_template = raw[800:1200].astype(float)
ecg_template_mean = np.mean(ecg_template)
ecg_template = ecg_template - ecg_template_mean
ecg_template = signal.windows.hann(len(ecg_template)) * ecg_template

stemi_template = np.copy(ecg_template)
st_start, st_end = 180, 230
st_width = st_end - st_start
st_elevation = int(os.environ.get("ST_ELEV", "300"))
st_bump = signal.windows.gaussian(st_width, std=st_width / 3) * st_elevation
stemi_template[st_start:st_end] += st_bump

stemi = np.zeros(len(raw))
beats_num = 31
samples_between_beats = 500
beat_starts = []
for beat in range(beats_num):
    start = beat * samples_between_beats
    end = start + len(stemi_template)
    if end < len(raw):
        beat_starts.append(start)
        if 5 <= beat <= 10:
            stemi[start:end] += stemi_template
        else:
            stemi[start:end] += ecg_template
stemi += ecg_template_mean

# ----------------------------------------------------------------------------
# 2. Bandpass FIR (fir_compiler_0_1) + notch FIR (fir_compiler_notch)
#    using the REAL integer coefficients from the project .coe files, so the
#    group delay, DC leakage and ST-bump attenuation match the hardware.
# ----------------------------------------------------------------------------
def load_coe(path):
    """Load radix=10 integer coefficients from a Vivado .coe file."""
    vals = []
    with open(path) as f:
        for line in f:
            line = line.strip().rstrip(",;")
            if not line or "=" in line:          # skip 'radix=10;' / 'coefdata='
                continue
            if line.lstrip("-").isdigit():
                vals.append(int(line))
    return np.array(vals, dtype=float)

bp_path = os.path.join(ROOT, "projekt_basys3", "fir_compiler_0_1", "bandpass_coeffs.coe")
notch_path = os.path.join(ROOT, "projekt_basys3", "fir_compiler_notch", "bandstop_coeffs.coe")
bp = load_coe(bp_path)
nf = load_coe(notch_path)
print(f"[coeffs] bandpass taps={len(bp)} sum(DC gain)={bp.sum():.1f}  "
      f"notch taps={len(nf)} sum={nf.sum():.1f}")

# Raw-integer filtering; absolute coeff scaling is irrelevant because we
# re-calibrate the output magnitude to board units right after.
filt = signal.lfilter(bp, 1.0, stemi)
if nf.sum() != 0:
    filt = signal.lfilter(nf, 1.0, filt)

# HARDWARE SCALE: calibrate so the AC R-peak magnitude matches what the board
# shows on filtered_data_1 (~120..130 LSB). Overridable via TARGET_R / SCALE.
ac_ref = filt - np.median(filt)                       # AC part for magnitude ref
TARGET_R = float(os.environ.get("TARGET_R", "125"))   # board AC R-peak
auto_scale = TARGET_R / np.max(np.abs(ac_ref))
SCALE = float(os.environ.get("SCALE", str(auto_scale)))
filtered_data_1 = np.round(filt * SCALE).astype(np.int64)  # board-scale signed
# steady-state DC offset reproduced by the real (non-zero-DC-gain) bandpass:
flat_off = int(np.round(np.median(filtered_data_1[2000:])))
print(f"[scale] SCALE={SCALE:.5f}  filtered R-peak(AC) ~ "
      f"{int(np.max(np.abs(filtered_data_1 - flat_off)))}  steady DC offset ~ {flat_off}")

# ----------------------------------------------------------------------------
# helpers: fixed-width signed wrap
# ----------------------------------------------------------------------------
def s_wrap(val, bits):
    mask = (1 << bits) - 1
    v = val & mask
    if v & (1 << (bits - 1)):
        v -= (1 << bits)
    return v

# ----------------------------------------------------------------------------
# 3. differentiator.sv : y[n] = (2x[n]+x[n-1]-x[n-3]-2x[n-4]) >>> 3
# ----------------------------------------------------------------------------
x = filtered_data_1
N = len(x)
diff = np.zeros(N, dtype=np.int64)
for n in range(N):
    xn  = x[n]
    xn1 = x[n - 1] if n - 1 >= 0 else 0
    xn3 = x[n - 3] if n - 3 >= 0 else 0
    xn4 = x[n - 4] if n - 4 >= 0 else 0
    s = (xn << 1) + xn1 - xn3 - (xn4 << 1)
    diff[n] = s >> 3   # arithmetic shift (sum[WIDTH+2:3])

# ----------------------------------------------------------------------------
# 4. squarer.sv
# ----------------------------------------------------------------------------
sq = (diff * diff).astype(np.int64)

# ----------------------------------------------------------------------------
# 5. moving_window_integration.sv  (window 75)
# ----------------------------------------------------------------------------
WIN = 75
mwi = np.zeros(N, dtype=np.int64)
acc = 0
from collections import deque
dl = deque([0] * WIN, maxlen=WIN)
for n in range(N):
    oldest = dl[0]
    acc = acc + sq[n] - oldest
    dl.append(sq[n])
    mwi[n] = acc

# ----------------------------------------------------------------------------
# 6. adaptive_threshold.sv
# ----------------------------------------------------------------------------
def adaptive_threshold(mwi, blanking_period=100, warmup=0):
    rpk = np.zeros(len(mwi), dtype=np.int64)
    mwi_d1 = mwi_d2 = 0
    spki = npki = thr = 0
    blank = 0
    thr_log = np.zeros(len(mwi), dtype=np.int64)
    for n in range(len(mwi)):
        data_in = int(mwi[n])
        # defaults / next
        n_mwi_d1 = data_in
        n_mwi_d2 = mwi_d1
        n_spki, n_npki, n_blank = spki, npki, blank
        if blank > 0:
            n_blank = blank - 1
        if (mwi_d1 > data_in) and (mwi_d1 >= mwi_d2):
            if (mwi_d1 > thr) and (blank == 0):
                if n >= warmup:          # suppress output during warm-up
                    rpk[n] = 1
                n_blank = blanking_period
                n_spki = spki - (spki >> 3) + (mwi_d1 >> 3)
            elif (mwi_d1 <= thr) and (blank == 0):
                n_npki = npki - (npki >> 3) + (mwi_d1 >> 3)
        # threshold uses OLD spki/npki (non-blocking)
        if spki > npki:
            n_thr = npki + ((spki - npki) >> 2)
        else:
            n_thr = npki
        thr_log[n] = thr
        mwi_d1, mwi_d2 = n_mwi_d1, n_mwi_d2
        spki, npki, thr, blank = n_spki, n_npki, n_thr, n_blank
    return rpk, thr_log

WARMUP_RPEAK = 700      # ~1.4 s : let FIR filters settle + threshold adapt
BLANKING = int(os.environ.get("BLANKING", "100"))
r_peak, thr_log = adaptive_threshold(mwi, blanking_period=BLANKING, warmup=WARMUP_RPEAK)

# ----------------------------------------------------------------------------
# 7. delay_buffer.sv  -> simple sample-domain delays
# ----------------------------------------------------------------------------
def delay(sig, d):
    if d <= 0:
        return sig.copy()
    out = np.zeros_like(sig)
    out[d:] = sig[:-d]
    return out

# baseline_restore.sv : leaky-integrator DC remover (high-pass ~0.15 Hz)
#   dc_est = dc_acc >>> DC_SHIFT ; ac = data_in - dc_est ; dc_acc += ac
# The STEMI detector now runs on this DC-removed signal (matches top_ecg.sv).
def baseline_restore(sig, dc_shift=9):
    out = np.zeros_like(sig)
    dc_acc = 0
    for n in range(len(sig)):
        dc_est = dc_acc >> dc_shift            # Python >> on int == arithmetic shift
        ac = int(sig[n]) - dc_est
        out[n] = s_wrap(ac, 16)                # data_out <= ac[15:0]
        dc_acc += ac
    return out

# DC-removed level signal fed to the STEMI detector (derivative path stays on x)
ecg_dc_removed = baseline_restore(filtered_data_1)
print(f"[baseline_restore] level offset after DC removal ~ "
      f"{int(np.round(np.median(ecg_dc_removed[2000:])))} (was {flat_off})")

# Locate ST bump relative to QRS in the FILTERED domain (template alone)
tpl = np.zeros(2000)
tpl[500:500 + len(stemi_template)] += stemi_template
tplf = signal.lfilter(bp, 1.0, tpl)
tpl_diff = np.zeros(len(tplf))
for n in range(4, len(tplf)):
    tpl_diff[n] = ((tplf[n] * 2 + tplf[n-1] - tplf[n-3] - 2 * tplf[n-4])) / 8
qrs_tpl = int(np.argmax(np.abs(tpl_diff)))
st_center_tpl = 500 + (st_start + st_end) // 2  # ST bump center offset in tpl input
# filter group delay ~ shifts both equally; measure ST peak in filtered template
st_peak_tpl = 500 + st_start + int(np.argmax(tplf[500 + st_start:500 + st_end]))
print(f"[template] QRS(argmax|diff|)={qrs_tpl}  ST-peak(filtered)={st_peak_tpl}  "
      f"-> ST is at QRS{st_peak_tpl - qrs_tpl:+d} samples")

# ----------------------------------------------------------------------------
# 8. stemi_detector.sv  (baseline tracker + FSM)
# ----------------------------------------------------------------------------
def stemi_detector(ecg_in, deriv_in, rpk,
                   STEMI_THRESHOLD=10, DERIV_MARGIN=20,
                   SAMPLES_TO_J=30, SAMPLES_AVG=8, verbose=True,
                   WARMUP=0, CONSECUTIVE_BEATS=1,
                   USE_RATIO=0, RATIO_NUM=5, RATIO_SHIFT=5, RATIO_FLOOR=12):
    Nn = len(ecg_in)
    # baseline tracker regs
    baseline_candidate = 0
    flat_counter = 0
    # fsm regs
    state = "IDLE"
    baseline_locked = 0
    delay_counter = 0
    st_counter = 0
    st_acc = 0
    alarm = 0
    elevated_streak = 0
    # peak-hold amplitudy R (do progu ratiometrycznego)
    running_max = 0
    r_amp = 0
    alarm_log = np.zeros(Nn, dtype=np.int64)
    events = []
    meas_idx = []
    rpk_fire_n = None
    base_capture_n = -1
    last_base_capture_n = -1
    for n in range(Nn):
        # ----- baseline tracker (always_ff #1) -----
        d = deriv_in[n]
        abs_d = -d if d < 0 else d
        n_baseline_candidate = baseline_candidate
        n_flat = flat_counter
        if abs_d <= DERIV_MARGIN:
            if flat_counter >= 20:
                n_baseline_candidate = ecg_in[n]
                base_capture_n = n
            else:
                n_flat = flat_counter + 1
        else:
            n_flat = 0

        # ----- peak-hold R (always_ff): max ECG, na R-peaku zatrzask+reset -----
        n_running_max = running_max
        n_r_amp = r_amp
        if rpk[n]:
            n_r_amp = running_max - baseline_candidate
            n_running_max = ecg_in[n]
        elif ecg_in[n] > running_max:
            n_running_max = ecg_in[n]

        # ----- FSM (comb + ff #2) -----
        n_state = state
        n_delay = delay_counter
        n_stc = st_counter
        n_acc = st_acc
        n_lock = baseline_locked
        n_alarm = alarm
        n_streak = elevated_streak
        if state == "IDLE":
            if rpk[n] and n >= WARMUP:
                n_state = "R_DETECTED"
                n_lock = baseline_candidate
                n_delay = 0
                rpk_fire_n = n
                last_base_capture_n = base_capture_n
        elif state == "R_DETECTED":
            # data_sample_valid_in is 1 every step
            if delay_counter == SAMPLES_TO_J - 1:
                n_state = "J_POINT"
                n_stc = 0
                n_acc = 0
            else:
                n_delay = delay_counter + 1
        elif state == "J_POINT":
            n_acc = st_acc + ecg_in[n]
            meas_idx.append(n)
            if st_counter == SAMPLES_AVG - 1:
                n_state = "EVALUATE"
            else:
                n_stc = st_counter + 1
        elif state == "EVALUATE":
            st_avg = st_acc >> 3   # >>> clog2(8)=3
            # prog dynamiczny: ratiometryczny (R_amp) albo staly
            if not USE_RATIO:
                thr = STEMI_THRESHOLD
            else:
                rt = (r_amp * RATIO_NUM) >> RATIO_SHIFT if r_amp > 0 else 0
                thr = rt if rt > RATIO_FLOOR else RATIO_FLOOR
            if st_avg - baseline_locked >= thr:
                if elevated_streak >= (CONSECUTIVE_BEATS - 1):
                    n_alarm = 1
                else:
                    n_streak = elevated_streak + 1
            else:
                n_streak = 0
                n_alarm = 0
            events.append((n, st_avg, baseline_locked, n_alarm, list(meas_idx), rpk_fire_n, last_base_capture_n))
            meas_idx = []
            n_state = "IDLE"

        # commit
        baseline_candidate, flat_counter = n_baseline_candidate, n_flat
        running_max, r_amp = n_running_max, n_r_amp
        state, delay_counter, st_counter, st_acc, baseline_locked, alarm = \
            n_state, n_delay, n_stc, n_acc, n_lock, n_alarm
        elevated_streak = n_streak
        alarm_log[n] = alarm
    return alarm_log, events

def run_for_delay(de, dd, stj=30, warmup=0, thr=10, consec=1):
    eb = delay(ecg_dc_removed, de)   # level path = DC-removed (data_baseline)
    db = delay(diff, dd)             # derivative path = raw filtered_data_1
    return stemi_detector(eb, db, r_peak, SAMPLES_TO_J=stj, WARMUP=warmup,
                          STEMI_THRESHOLD=thr, CONSECUTIVE_BEATS=consec)

def per_beat_diffs(de, stj, warmup=0):
    """Return {beat_index: (st_avg-baseline)} using nearest-QRS mapping."""
    _, ev = run_for_delay(de, max(de - 1, 0), stj, warmup)
    out = {}
    for e in ev:
        n_eval, st_avg, base, alarm, midx, rfire, bcap = e
        if rfire is None:
            continue
        nq = min(qrs_pos, key=lambda q: abs(q - rfire))
        if abs(nq - rfire) > 120:   # spurious (startup) detection, not a real beat
            continue
        bi = qrs_pos.index(nq)
        out[bi] = st_avg - base
    return out

# FIXED RTL configuration (matches the patched .sv files):
DELAY_ECG = 5
DELAY_DERIV = 4
RTL_STJ = 76
RTL_THR = 20
RTL_CONSEC = 2
ecg_buff = delay(ecg_dc_removed, DELAY_ECG)
deriv_buff = delay(diff, DELAY_DERIV)
alarm_log, events = run_for_delay(DELAY_ECG, DELAY_DERIV, stj=RTL_STJ,
                                  thr=RTL_THR, consec=RTL_CONSEC)

# ----------------------------------------------------------------------------
# Diagnostics
# ----------------------------------------------------------------------------
rpk_idx = np.where(r_peak == 1)[0]
print("=" * 70)
print(f"Signal length            : {N}")
print(f"Detected R-peaks (count) : {len(rpk_idx)}")
print(f"R-peak indices           : {rpk_idx.tolist()}")
print(f"Beat starts (template)   : {beat_starts}")
print("-" * 70)
print("STEMI beats are #5..#10 -> starts:",
      [beat_starts[b] for b in range(len(beat_starts)) if 5 <= b <= 10])
print("-" * 70)
# True QRS position in the FILTERED domain = argmax|diff| inside each beat window.
# (filter group delay cancels because diff & ecg_buff share the same x.)
abs_diff = np.abs(diff)
qrs_pos = []
for bs in beat_starts:
    lo = bs
    hi = min(bs + samples_between_beats, N)
    qrs_pos.append(lo + int(np.argmax(abs_diff[lo:hi])))
print("QRS positions in x (argmax|diff| per beat):", qrs_pos)
print("-" * 70)
print("EVALUATE events:")
print("  n_eval | rpk_fire | (rpk-QRS) | baseline_capt | meas_window      | st_avg | baseline | alarm")
for e in events:
    n_eval, st_avg, base, alarm, midx, rfire, bcap = e
    # nearest QRS to the rpk fire
    if rfire is not None:
        nearest_qrs = min(qrs_pos, key=lambda q: abs(q - rfire))
        rel = rfire - nearest_qrs
        mwin = f"{midx[0]}..{midx[-1]}" if midx else "-"
        meas_rel = f"QRS+{midx[0]-nearest_qrs}..+{midx[-1]-nearest_qrs}" if midx else "-"
        print(f"  {n_eval:5d} | {rfire:5d}    | {rel:+5d}    | {bcap:7d}      | {mwin:14s} | {st_avg:6d} | {base:7d} | {alarm}   meas={meas_rel}")
print("-" * 70)
alarm_on = np.where(alarm_log == 1)[0]
if len(alarm_on):
    print(f"ALARM high from n={alarm_on[0]} to n={alarm_on[-1]} ({len(alarm_on)} samples)")
else:
    print("ALARM never asserted")
print("=" * 70)

# ----------------------------------------------------------------------------
# DELAY SWEEP: find delay that lands the 8-sample window on the ST segment
# ----------------------------------------------------------------------------
print("=" * 70)
print("2D SWEEP: separation margin = min(STEMI diff) - max(healthy diff)")
print("(want LARGE positive; threshold sits between). delay x SAMPLES_TO_J")
best = None
for de in range(0, 51, 5):
    for stj in range(10, 56, 5):
        d = per_beat_diffs(de, stj, warmup=0)
        stemi_d = [v for b, v in d.items() if 5 <= b <= 10]
        healthy_d = [v for b, v in d.items() if b not in range(5, 11)]
        if not stemi_d or not healthy_d:
            continue
        margin = min(stemi_d) - max(healthy_d)
        if best is None or margin > best[0]:
            best = (margin, de, stj, min(stemi_d), max(healthy_d))
print(f"BEST: margin={best[0]}  delay={best[1]}  SAMPLES_TO_J={best[2]}  "
      f"min_STEMI_diff={best[3]}  max_healthy_diff={best[4]}")
# show full row for the best delay
print(f"\nDetail at delay={best[1]} (diff = st_avg - baseline per beat):")
print("  stj | healthy diffs                         | STEMI diffs")
for stj in range(10, 56, 5):
    d = per_beat_diffs(best[1], stj)
    hd = [d.get(b) for b in range(len(qrs_pos)) if b not in range(5, 11) and b in d]
    sd = [d.get(b) for b in range(5, 11) if b in d]
    print(f"  {stj:3d} | {str(hd):38s} | {sd}")
print("=" * 70)
print("DELAY SWEEP (meas x-region relative to its beat's QRS):")
print(" delay | healthy: st_avg base meas(xQRS+)   | STEMI: st_avg base meas(xQRS+)  | #alarmbeats")
for de in [0, 5, 10, 15, 20, 25, 30, 45]:
    dd = max(de - 1, 0)
    al, ev = run_for_delay(de, dd)
    # classify each evaluate event by nearest QRS, compute meas x-region rel QRS
    h = None; s = None; nalarm = 0
    for e in ev:
        n_eval, st_avg, base, alarm, midx, rfire, bcap = e
        if rfire is None or not midx:
            continue
        nearest_qrs = min(qrs_pos, key=lambda q: abs(q - rfire))
        beat_i = qrs_pos.index(nearest_qrs)
        xlo = midx[0] - de - nearest_qrs
        xhi = midx[-1] - de - nearest_qrs
        is_stemi = 5 <= beat_i <= 10
        if alarm:
            nalarm += 1
        rec = (st_avg, base, xlo, xhi, alarm)
        if is_stemi and s is None and beat_i >= 6:
            s = rec
        if (not is_stemi) and h is None and beat_i in (11, 12, 13):
            h = rec
    hs = f"{h[0]:6d} {h[1]:5d}  +{h[2]}..+{h[3]} a={h[4]}" if h else "n/a"
    ss = f"{s[0]:6d} {s[1]:5d}  +{s[2]}..+{s[3]} a={s[4]}" if s else "n/a"
    print(f"  {de:3d}  | {hs:30s} | {ss:30s} | {nalarm}")
print("=" * 70)

# ----------------------------------------------------------------------------
# ROBUST STJ SWEEP at the fixed RTL delays (de=5, dd=4).
# Use MEDIAN of healthy / STEMI per-beat diffs so the 2 filter-smearing
# boundary beats (601-tap FIR > 500-sample beat) don't dominate.
# ----------------------------------------------------------------------------
print("=" * 70)
print("ROBUST STJ SWEEP (de=5, dd=4)  -- median ignores boundary beats")
print("  stj | med_healthy | med_STEMI | separation | (bulk min/max)")
best_stj = None
for stj in range(8, 56, 1):
    d = per_beat_diffs(5, stj, warmup=0)
    healthy_d = sorted(v for b, v in d.items() if b not in range(5, 11))
    stemi_d = sorted(v for b, v in d.items() if 5 <= b <= 10)
    if not healthy_d or not stemi_d:
        continue
    mh = int(np.median(healthy_d))
    ms = int(np.median(stemi_d))
    sep = ms - mh
    if best_stj is None or sep > best_stj[0]:
        best_stj = (sep, stj, mh, ms)
    if stj % 2 == 1 or stj in (8, 10, 12, 14):
        print(f"  {stj:3d} | {mh:11d} | {ms:9d} | {sep:10d} | "
              f"H[{healthy_d[0]}..{healthy_d[-1]}] S[{stemi_d[0]}..{stemi_d[-1]}]")
print(f"--> BEST separation: stj={best_stj[1]}  med_healthy={best_stj[2]}  "
      f"med_STEMI={best_stj[3]}  sep={best_stj[0]}  "
      f"-> recommend THRESHOLD ~ {(best_stj[2]+best_stj[3])//2}")
print("=" * 70)

# ----------------------------------------------------------------------------
# FINAL VERIFICATION of the proposed fix
#   warm-up on r-peak  +  delay_ecg=5 / delay_deriv=4  +  SAMPLES_TO_J=15
#   +  STEMI_THRESHOLD=150
# ----------------------------------------------------------------------------
print("=" * 70)
print("PROPOSED FIX VERIFICATION  (board-scale)")
FIX_DELAY_ECG = 5
FIX_DELAY_DERIV = 4
FIX_STJ = 17
eb = delay(ecg_dc_removed, FIX_DELAY_ECG)
db = delay(diff, FIX_DELAY_DERIV)
print(f"  warm-up={WARMUP_RPEAK}, delay_ecg={FIX_DELAY_ECG}, "
      f"delay_deriv={FIX_DELAY_DERIV}, SAMPLES_TO_J={FIX_STJ}")
print(f"  False R-peaks at startup now: "
      f"{np.where(r_peak[:WARMUP_RPEAK] == 1)[0].tolist()}  (expect [])")

# per-beat ST-vs-baseline difference (board units), independent of threshold
d = per_beat_diffs(FIX_DELAY_ECG, FIX_STJ, warmup=0)  # warmup already in r_peak
healthy = sorted(v for b, v in d.items() if b not in range(5, 11))
stemi = sorted(v for b, v in d.items() if 5 <= b <= 10)
print(f"  healthy ST-baseline diffs: {healthy}")
print(f"  STEMI   ST-baseline diffs: {stemi}")
if healthy and stemi:
    print(f"  --> usable STEMI_THRESHOLD range: ({max(healthy)} .. {min(stemi)}]  "
          f"recommend ~{(max(healthy)+min(stemi))//2}")

for thr in [12, 15, 16, 18, 20]:
    al_fix, ev_fix = stemi_detector(eb, db, r_peak, STEMI_THRESHOLD=thr,
                                    SAMPLES_TO_J=FIX_STJ)
    ab = []
    for e in ev_fix:
        n_eval, st_avg, base, alarm, midx, rfire, bcap = e
        if rfire is None:
            continue
        nq = min(qrs_pos, key=lambda q: abs(q - rfire))
        if abs(nq - rfire) > 120:
            continue
        if alarm:
            ab.append(qrs_pos.index(nq))
    print(f"  THRESHOLD={thr:3d} -> alarm beats {sorted(set(ab))}  (want 5..10)")
print("=" * 70)

# where is the true R peak inside one beat template? (max of filtered around a healthy beat)
# Use beat 2 (healthy) to locate QRS peak offset
b2 = beat_starts[2]
seg = x[b2:b2 + samples_between_beats]
print(f"Healthy beat #2 start={b2}, local |max| at offset "
      f"{int(np.argmax(np.abs(seg)))} value {seg[np.argmax(np.abs(seg))]}")

# ----------------------------------------------------------------------------
# Plot
# ----------------------------------------------------------------------------
# alarm of the OLD (buggy) RTL config for comparison
alarm_old, _ = run_for_delay(45, 44, stj=30, thr=10)

# true STEMI sample window (board beats 5..10)
stemi_lo = beat_starts[5]
stemi_hi = beat_starts[10] + len(stemi_template)

fig, ax = plt.subplots(4, 1, figsize=(16, 11), sharex=True)
for a in ax:
    a.axvspan(stemi_lo, stemi_hi, color="red", alpha=0.08, label="prawdziwy STEMI")
ax[0].plot(x, color="black", lw=0.7)
ax[0].set_title("filtered_data_1 (EKG do pipeline) - czerwone tlo = uderzenia STEMI")
ax[1].plot(mwi, color="purple", lw=0.7); ax[1].plot(thr_log, color="orange", lw=0.9)
ax[1].set_title("MWI (fiolet) + prog adaptacyjny (pomarancz)")
ax[2].plot(x, color="black", lw=0.5)
ax[2].vlines(rpk_idx, x.min(), x.max(), color="green", lw=0.8)
ax[2].axvline(WARMUP_RPEAK, color="blue", ls="--", lw=1)
ax[2].set_title(f"Detekcje R (zielone) + koniec warm-up={WARMUP_RPEAK} (niebieski) - brak falszywych na starcie")
ax[3].plot(alarm_old, color="gray", lw=1.5, label="STARY (delay=45, raw filtered_data_1)")
ax[3].plot(alarm_log, color="red", lw=1.2, label="NOWY (data_baseline, STJ=17, thr=20, debounce=2)")
ax[3].set_title("stemi_alarm: STARY vs NOWY")
ax[3].legend(loc="upper right")
ax[3].set_ylim(-0.1, 1.2)
plt.tight_layout()
out = os.path.join(os.path.dirname(__file__), "sim_pipeline_out.png")
plt.savefig(out, dpi=90)
print("Saved plot to", out)
