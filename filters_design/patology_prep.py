import numpy as np
import matplotlib.pyplot as plt
import scipy.signal as signal
import os

raw_samples = []

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
samples_path = os.path.join(ROOT_DIR, "ecg_samples_4.csv")

with open(samples_path, 'r') as file:
    for row in file:
        raw_samples.append(int(row.strip(), 16)) #convert hex to int
        
raw_samples = np.array(raw_samples)
N_SAMPLES = len(raw_samples) # Długość ROM, standardowo 7560

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

t_template = np.arange(400)
t_signal = np.arange(N_SAMPLES)

# 1 heartbeat cycle for patology preparation
ecg_template = raw_samples[800:1200] 
ecg_template_mean = np.mean(ecg_template)
ecg_template = ecg_template - np.mean(ecg_template) # baseline cancelation
ecg_template = signal.windows.hann(len(ecg_template)) * ecg_template # windowing

# ---------------------------------------------------------
# TACHYCARDIA (~107 BPM)
# ---------------------------------------------------------
tachycardia = np.zeros(N_SAMPLES)
spacing_tachy = 280 
for start_index in range(0, N_SAMPLES, spacing_tachy):
    add_template(tachycardia, ecg_template, start_index, wrap=True)
tachycardia += ecg_template_mean

# ---------------------------------------------------------
# BRADYCARDIA (~40 BPM)
# ---------------------------------------------------------
bradycardia = np.zeros(N_SAMPLES)
spacing_brady = 756
for start_index in range(0, N_SAMPLES, spacing_brady):
    add_template(bradycardia, ecg_template, start_index, wrap=True)
bradycardia += ecg_template_mean

# ---------------------------------------------------------
# STEMI (~60 BPM, patologia tylko na uderzeniach 5-10)
# ---------------------------------------------------------
stemi_base_template = flatten_segment(ecg_template, 245, 360, keep=0.05)
stemi_template = np.copy(stemi_base_template)

st_start = 180 
st_end = 280 
st_width = st_end - st_start 

# Zwiększona elewacja (200) z zachowaniem idealnie gładkich zboczy
st_elevation = 200 
st_bump = st_elevation * signal.windows.hann(st_width)
stemi_template[st_start:st_end] += st_bump

stemi = np.zeros(N_SAMPLES)
spacing_normal = 504 

for beat, start_index in enumerate(range(0, N_SAMPLES, spacing_normal)):
    # Jeśli to uderzenie od 5 do 10 - generuj zawał (STEMI)
    if 5 <= beat <= 10:
        add_template(stemi, stemi_template, start_index, wrap=True)
    # W przeciwnym razie - generuj zdrowy, normalny rytm (bez elewacji ST)
    else:
        add_template(stemi, stemi_base_template, start_index, wrap=True)
        
stemi += ecg_template_mean

# ---------------------------------------------------------
# ARRHYTHMIA (~60 BPM bazowo, z PVC)
# ---------------------------------------------------------
arrhythmia = np.zeros(N_SAMPLES)

pvc_template = np.copy(ecg_template)
pvc_width = 180
pvc_amplitude = 250 
pvc_shape = -pvc_amplitude * signal.windows.hann(pvc_width)

pvc_start = 130
pvc_end = pvc_start + pvc_width
pvc_template[pvc_start:pvc_end] += pvc_shape

for beat, start_index in enumerate(range(0, N_SAMPLES, spacing_normal)):
    if beat == 5 or beat == 10: 
        start_index -= 180 
        add_template(arrhythmia, pvc_template, start_index, wrap=True)
    else:
        add_template(arrhythmia, ecg_template, start_index, wrap=True)

arrhythmia += ecg_template_mean

# =========================================================
# GENEROWANIE PLIKÓW .COE DLA VIVADO
# =========================================================
file_path = os.path.join(ROOT_DIR, "projekt_basys3", "memory_init")
os.makedirs(file_path, exist_ok=True) 

preamble = "memory_initialization_radix=16;\nmemory_initialization_vector=\n" 

coeffs_joined_tachycardia = ",\n".join([format(int(x) & 0xFFFF, '04X') for x in tachycardia])
coeffs_joined_bradycardia = ",\n".join([format(int(x) & 0xFFFF, '04X') for x in bradycardia])
coeffs_joined_stemi = ",\n".join([format(int(x) & 0xFFFF, '04X') for x in stemi])
coeffs_joined_arrhythmia = ",\n".join([format(int(x) & 0xFFFF, '04X') for x in arrhythmia])

files_to_save = {
    "tachycardia.coe": coeffs_joined_tachycardia,
    "bradycardia.coe": coeffs_joined_bradycardia,
    "stemi.coe": coeffs_joined_stemi,
    "arrhythmia.coe": coeffs_joined_arrhythmia
}

for filename, coeffs in files_to_save.items():
    full_path = os.path.join(file_path, filename)
    with open(full_path, 'w') as file:
        file.write(f"{preamble}{coeffs};")
    print(f"Wygenerowano plik: {full_path}")

# =========================================================
# WIZUALIZACJA (WYKRESY)
# =========================================================
if os.environ.get("SHOW_PLOTS", "0") == "1":
    plt.figure(figsize=(12, 10))

    plt.subplot(4, 1, 1)
    plt.plot(t_signal, tachycardia, color='green')
    plt.title(f"Tachycardia (~107 BPM) - Długość: {len(tachycardia)}")
    plt.grid(True)

    plt.subplot(4, 1, 2)
    plt.plot(t_signal, bradycardia, color='red')
    plt.title(f"Bradycardia (~40 BPM) - Długość: {len(bradycardia)}")
    plt.grid(True)

    plt.subplot(4, 1, 3)
    plt.plot(t_signal, stemi, color='blue')
    plt.title(f"STEMI (Uderzenia 5-10) - Długość: {len(stemi)}")
    plt.grid(True)

    plt.subplot(4, 1, 4)
    plt.plot(t_signal, arrhythmia, color='black')
    plt.title(f"Arrhythmia (PVC) - Długość: {len(arrhythmia)}")
    plt.grid(True)

    plt.tight_layout()
    plt.show()
