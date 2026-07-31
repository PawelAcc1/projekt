import os
import numpy as np
import scipy.signal as signal

ROOT = r"C:\Users\pbuko\Desktop\SystemVerilog\projekt"
CSV = os.path.join(ROOT, "ecg_samples_4.csv")
raw = []
with open(CSV) as f:
    for row in f:
        raw.append(int(row.strip(), 16))
raw = np.array(raw)

# raw template window
raw_tpl = raw[800:1200].astype(float)
m = raw_tpl.mean()
ecg_template = raw_tpl - m
hann = signal.windows.hann(len(ecg_template))
ecg_template_w = hann * ecg_template

print("RAW template raw[800:1200]:")
print(f"  argmax (R peak?) at offset {int(np.argmax(raw_tpl))}, val {raw_tpl.max():.0f}")
print(f"  argmin           at offset {int(np.argmin(raw_tpl))}, val {raw_tpl.min():.0f}")
print(f"  mean = {m:.1f}")

print("\nWINDOWED template (what is actually used):")
print(f"  argmax at offset {int(np.argmax(ecg_template_w))}, val {ecg_template_w.max():.1f}")
print(f"  argmin at offset {int(np.argmin(ecg_template_w))}, val {ecg_template_w.min():.1f}")

# QRS = steepest slope
d = np.diff(ecg_template_w)
print(f"  steepest |slope| (QRS) at offset {int(np.argmax(np.abs(d)))}")

# ST segment region used in python
st_start, st_end = 180, 230
print(f"\nST bump placed at template offset {st_start}..{st_end}")
print(f"  amplitude of windowed template there: "
      f"min={ecg_template_w[st_start:st_end].min():.1f}, max={ecg_template_w[st_start:st_end].max():.1f}")

# Show the template values at key offsets
print("\nTemplate (windowed) sampled every 20:")
for o in range(0, 400, 20):
    marker = ""
    if o == int(np.argmax(ecg_template_w)): marker += " <-Rpeak"
    if st_start <= o < st_end: marker += " <-ST"
    print(f"  offset {o:3d}: {ecg_template_w[o]:8.1f}{marker}")

# Where is R relative to ST?
rpk = int(np.argmax(ecg_template_w))
print(f"\n==> R peak at offset {rpk}; ST window at {st_start}-{st_end}.")
if st_start > rpk:
    print(f"    ST is {st_start-rpk}..{st_end-rpk} samples AFTER R peak (physiologically correct).")
else:
    print(f"    *** ST window is BEFORE/ON the R peak (offset {rpk})! Wrong placement. ***")
