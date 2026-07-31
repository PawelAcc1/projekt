"""
SPECIFICITY TEST: przepuszcza WSZYSTKIE patologie (tachykardia, bradykardia,
arytmia PVC, STEMI, oraz czysty zdrowy) przez ten sam bit-dokladny model
pipeline'u co sim_pipeline.py, z FINALNYMI parametrami RTL:
    baseline_restore (DC_SHIFT=9) na sciezce ECG,
    differentiator/squarer/MWI(75)/adaptive_threshold(warmup=700, blank=100),
    delay_ecg=5, delay_deriv=4,
    stemi_detector: STJ=76, STEMI_THRESHOLD=20, DERIV_MARGIN=20, CONSECUTIVE_BEATS=2.

Cel: sprawdzic, czy detektor STEMI NIE zapala sie falszywie dla nie-STEMI.
"""
import os
import numpy as np
import scipy.signal as signal
from collections import deque

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CSV = os.path.join(ROOT, "ecg_samples_4.csv")
BP = os.path.join(ROOT, "projekt_basys3", "fir_compiler_0_1", "bandpass_coeffs.coe")
NF = os.path.join(ROOT, "projekt_basys3", "fir_compiler_notch", "bandstop_coeffs.coe")

# --- RTL parameters (final) ---
DELAY_ECG, DELAY_DERIV = 5, 4
STJ, STEMI_THRESHOLD, DERIV_MARGIN = 76, 20, 20
CONSECUTIVE_BEATS = 2
WARMUP, BLANKING, MWI_WIN = 700, 100, 75
DC_SHIFT = 9

# --- prog ratiometryczny: prog = (amplituda_R * RATIO_NUM) >> RATIO_SHIFT ---
# 5/32 = 0.156. Przy R~128 daje ~20 (tyle co stary staly prog).
# RATIO_FLOOR: dolny limit progu (ochrona przed degeneracja przy malym/ujemnym R).
USE_RATIO = os.environ.get("USE_RATIO", "1") == "1"
RATIO_NUM, RATIO_SHIFT, RATIO_FLOOR = 5, 5, 12


def load_coe(path):
    vals = []
    with open(path) as f:
        for line in f:
            line = line.strip().rstrip(",;")
            if not line or "=" in line:
                continue
            if line.lstrip("-").isdigit():
                vals.append(int(line))
    return np.array(vals, dtype=float)


raw = []
with open(CSV) as f:
    for row in f:
        raw.append(int(row.strip(), 16))
raw = np.array(raw)
N = len(raw)

ecg_template = raw[800:1200].astype(float)
ecg_mean = np.mean(ecg_template)
ecg_template = ecg_template - ecg_mean
ecg_template = signal.windows.hann(len(ecg_template)) * ecg_template
TPL = len(ecg_template)


def smooth_plateau(width, amplitude, edge=10):
    shape = np.ones(width) * amplitude
    edge = min(edge, width // 2)
    ramp = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, edge))
    shape[:edge] *= ramp
    shape[-edge:] *= ramp[::-1]
    return shape


def attenuate_segment(template, start, end, keep=0.2, edge=16):
    out = np.copy(template)
    width = end - start
    multiplier = np.ones(width) * keep
    edge = min(edge, width // 2)
    ramp = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, edge))
    multiplier[:edge] = 1 - (1 - keep) * ramp
    multiplier[-edge:] = keep + (1 - keep) * ramp
    out[start:end] *= multiplier
    return out


def flatten_segment(template, start, end, keep=0.05):
    out = np.copy(template)
    width = end - start
    baseline = np.linspace(out[start], out[end - 1], width)
    out[start:end] = baseline + keep * (out[start:end] - baseline)
    return out


def add_template(dst, template, start_index, wrap=False):
    start_index %= len(dst)
    end_index = start_index + len(template)
    if end_index <= len(dst):
        dst[start_index:end_index] += template
    elif wrap:
        first_len = len(dst) - start_index
        dst[start_index:] += template[:first_len]
        dst[:end_index - len(dst)] += template[first_len:]

bp = load_coe(BP)
nf = load_coe(NF)


def build(kind):
    """Odtwarza sygnal dokladnie jak patology_prep.py. Zwraca (sig, patho_beats)."""
    sig = np.zeros(N)
    patho = []          # indeksy uderzen patologicznych (dla STEMI/arytmii)
    if kind == "healthy":
        spacing, nbeats = 500, 31
        for b in range(nbeats):
            s, e = b * spacing, b * spacing + TPL
            if e < N:
                sig[s:e] += ecg_template
    elif kind == "stemi":
        spacing, nbeats = 504, 15
        base = flatten_segment(ecg_template, 245, 360, keep=0.05)
        st = np.copy(base)
        st[180:280] += 200 * signal.windows.hann(100)
        for b in range(nbeats):
            s, e = b * spacing, b * spacing + TPL
            if e < N:
                if 5 <= b <= 10:
                    sig[s:e] += st
                    patho.append(b)
                else:
                    sig[s:e] += base
    elif kind == "tachycardia":
        spacing = 280
        for s in range(0, N, spacing):
            add_template(sig, ecg_template, s, wrap=True)
    elif kind == "bradycardia":
        spacing, nbeats = 750, 20
        for b in range(nbeats):
            s, e = b * spacing, b * spacing + TPL
            if e < N:
                sig[s:e] += ecg_template
    elif kind == "arrhythmia":
        spacing, nbeats = 500, 31
        pvc = np.copy(ecg_template)
        pvc[130:310] += -500 * signal.windows.hann(180)
        for b in range(nbeats):
            s = b * spacing
            if b == 5 or b == 10:
                s2, e = s - 180, s - 180 + TPL
                if e < N and s2 >= 0:
                    sig[s2:e] += pvc
                    patho.append(b)
            else:
                e = s + TPL
                if e < N:
                    sig[s:e] += ecg_template
    sig += ecg_mean
    return sig, patho


# calibrate SCALE once from healthy (fixed hardware gain -> same for all)
# GAIN: sztuczna zmiana wzmocnienia sprzetu (test odpornosci progu na skale)
GAIN = float(os.environ.get("GAIN", "1.0"))
_h, _ = build("healthy")
_fh = signal.lfilter(nf, 1.0, signal.lfilter(bp, 1.0, _h))
SCALE = GAIN * 125.0 / np.max(np.abs(_fh - np.median(_fh)))


def s_wrap(v, bits):
    m = (1 << bits) - 1
    v &= m
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def filt_scale(sig):
    f = signal.lfilter(nf, 1.0, signal.lfilter(bp, 1.0, sig))
    return np.round(f * SCALE).astype(np.int64)


def baseline_restore(sig):
    out = np.zeros_like(sig)
    dc_acc = 0
    for n in range(len(sig)):
        ac = int(sig[n]) - (dc_acc >> DC_SHIFT)
        out[n] = s_wrap(ac, 16)
        dc_acc += ac
    return out


def differentiator(x):
    d = np.zeros(len(x), dtype=np.int64)
    for n in range(len(x)):
        xn = x[n]
        x1 = x[n - 1] if n >= 1 else 0
        x3 = x[n - 3] if n >= 3 else 0
        x4 = x[n - 4] if n >= 4 else 0
        d[n] = ((xn << 1) + x1 - x3 - (x4 << 1)) >> 3
    return d


def mwi(sq):
    out = np.zeros(len(sq), dtype=np.int64)
    acc, dl = 0, deque([0] * MWI_WIN, maxlen=MWI_WIN)
    for n in range(len(sq)):
        acc += sq[n] - dl[0]
        dl.append(sq[n])
        out[n] = acc
    return out


def adaptive_threshold(m):
    rpk = np.zeros(len(m), dtype=np.int64)
    d1 = d2 = spki = npki = thr = blank = 0
    for n in range(len(m)):
        di = int(m[n])
        n_spki, n_npki, n_blank = spki, npki, blank
        if blank > 0:
            n_blank = blank - 1
        if (d1 > di) and (d1 >= d2):
            if (d1 > thr) and (blank == 0):
                if n >= WARMUP:
                    rpk[n] = 1
                n_blank = BLANKING
                n_spki = spki - (spki >> 3) + (d1 >> 3)
            elif (d1 <= thr) and (blank == 0):
                n_npki = npki - (npki >> 3) + (d1 >> 3)
        n_thr = npki + ((spki - npki) >> 2) if spki > npki else npki
        d1, d2 = di, d1
        spki, npki, thr, blank = n_spki, n_npki, n_thr, n_blank
    return rpk


def delay(sig, d):
    if d <= 0:
        return sig.copy()
    out = np.zeros_like(sig)
    out[d:] = sig[:-d]
    return out


def dyn_thr(r_amp):
    """Prog dla danego uderzenia: ratiometryczny (wzgl. amplitudy R) albo staly."""
    if not USE_RATIO:
        return STEMI_THRESHOLD
    t = (r_amp * RATIO_NUM) >> RATIO_SHIFT if r_amp > 0 else 0
    return t if t > RATIO_FLOOR else RATIO_FLOOR


def stemi_detector(ecg_in, deriv_in, rpk):
    baseline_candidate = flat = 0
    state = "IDLE"
    baseline_locked = dcnt = stc = acc = alarm = streak = 0
    running_max = r_amp = 0            # peak-hold amplitudy R (resetowany na R-peaku)
    events = []
    for n in range(len(ecg_in)):
        d = deriv_in[n]
        ad = -d if d < 0 else d
        nb, nf_ = baseline_candidate, flat
        if ad <= DERIV_MARGIN:
            if flat >= 20:
                nb = ecg_in[n]
            else:
                nf_ = flat + 1
        else:
            nf_ = 0
        # peak-hold: sledz max ECG; na R-peaku zatrzasnij amplitude i zresetuj
        nrm, nra = running_max, r_amp
        if rpk[n]:
            nra = running_max - baseline_candidate   # amplituda R nad linia bazowa PQ
            nrm = ecg_in[n]                           # start nowego uderzenia
        elif ecg_in[n] > running_max:
            nrm = ecg_in[n]
        ns, ndc, nstc, nacc, nl, na, nstk = state, dcnt, stc, acc, baseline_locked, alarm, streak
        if state == "IDLE":
            if rpk[n]:
                ns, nl, ndc = "R", baseline_candidate, 0
        elif state == "R":
            if dcnt == STJ - 1:
                ns, nstc, nacc = "J", 0, 0
            else:
                ndc = dcnt + 1
        elif state == "J":
            nacc = acc + ecg_in[n]
            if stc == 8 - 1:
                ns = "E"
            else:
                nstc = stc + 1
        elif state == "E":
            st_avg = acc >> 3
            thr = dyn_thr(r_amp)
            if st_avg - baseline_locked >= thr:
                if streak >= CONSECUTIVE_BEATS - 1:
                    na = 1
                else:
                    nstk = streak + 1
            else:
                nstk, na = 0, 0
            events.append((n, st_avg, baseline_locked, na, r_amp, thr))
            ns = "IDLE"
        baseline_candidate, flat = nb, nf_
        running_max, r_amp = nrm, nra
        state, dcnt, stc, acc, baseline_locked, alarm, streak = ns, ndc, nstc, nacc, nl, na, nstk
    return events


def run(kind):
    sig, patho = build(kind)
    x = filt_scale(sig)                       # filtered_data_1 (surowy, dla pochodnej)
    ecg_dc = baseline_restore(x)              # data_baseline (poziom -> detektor)
    diff = differentiator(x)
    m = mwi((diff * diff).astype(np.int64))
    rpk = adaptive_threshold(m)
    ev = stemi_detector(delay(ecg_dc, DELAY_ECG), delay(diff, DELAY_DERIV), rpk)
    n_rpk = int(rpk.sum())
    alarms = [e for e in ev if e[3] == 1]
    diffs = [e[1] - e[2] for e in ev]
    ramps = [e[4] for e in ev]
    thrs = [e[5] for e in ev]
    return n_rpk, len(ev), alarms, diffs, ramps, thrs


mode = "RATIOMETRYCZNY" if USE_RATIO else "STALY"
print(f"[scale] SCALE={SCALE:.4f}  (R-peak kalibrowany na ~125 LSB)")
if USE_RATIO:
    print(f"[prog ] RATIOMETRYCZNY: prog = (R_amp * {RATIO_NUM}) >> {RATIO_SHIFT} "
          f"(~{RATIO_NUM/(1<<RATIO_SHIFT):.3f}*R), floor={RATIO_FLOOR}")
else:
    print(f"[prog ] STALY: prog = {STEMI_THRESHOLD}")
print("=" * 92)
print(f"{'patologia':14s} | R-pk | ocen | ST-diff min..max | R_amp min..max | prog | ALARM STEMI?")
print("-" * 92)
for kind in ["healthy", "tachycardia", "bradycardia", "arrhythmia", "stemi"]:
    n_rpk, n_ev, alarms, diffs, ramps, thrs = run(kind)
    dmin, dmax = (min(diffs), max(diffs)) if diffs else (0, 0)
    rmin, rmax = (min(ramps), max(ramps)) if ramps else (0, 0)
    tmin, tmax = (min(thrs), max(thrs)) if thrs else (0, 0)
    tstr = f"{tmin}-{tmax}" if tmin != tmax else f"{tmin}"
    if alarms:
        verdict = f"TAK - {len(alarms)} uderzen"
    else:
        verdict = "nie (dobrze)" if kind != "stemi" else "NIE - ZLE! (powinien)"
    flag = "  <-- FALSZYWY!" if (alarms and kind != "stemi") else ""
    print(f"{kind:14s} | {n_rpk:4d} | {n_ev:4d} | {dmin:5d} .. {dmax:5d}   | "
          f"{rmin:5d} .. {rmax:5d}  | {tstr:>5s} | {verdict}{flag}")
print("=" * 92)
print(f"Tryb progu: {mode}, debounce = {CONSECUTIVE_BEATS} uderzen z rzedu")
