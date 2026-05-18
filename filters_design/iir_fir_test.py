import numpy as np
import scipy.signal as signal
import matplotlib.pyplot as plt

fs = 500.0  
t = np.arange(0, 4.0, 1.0/fs) 

# ==========================================
# 1. ZASZUMIONE EKG (Ten sam brudny sygnał)
# ==========================================
czyste_ekg = signal.windows.gaussian(20, 2)
czyste_ekg = np.tile(np.pad(czyste_ekg, (0, int(fs*0.8) - 20)), 10)[:len(t)]
plywanie_izolinii = 1.5 * np.sin(2 * np.pi * 0.2 * t) 
szum_sieci = 0.5 * np.sin(2 * np.pi * 50.0 * t)       
szum_miesniowy = 0.2 * np.random.randn(len(t))        
surowe_ekg = czyste_ekg + plywanie_izolinii + szum_sieci + szum_miesniowy

# ==========================================
# 2. OSTATECZNY ŁAŃCUCH DSP (Architektura FPGA)
# ==========================================

# KROK A: IIR Górnoprzepustowy (0.5 Hz) - Usuwa izolinię
b_hp, a_hp = signal.butter(2, 0.5/(fs/2), btype='high')
ekg_hp = signal.lfilter(b_hp, a_hp, surowe_ekg)

# KROK B: IIR Notch (50 Hz) - Chirurgiczne cięcie szumu z sieci!
# Parametr Q=30 określa jak "wąskie" jest to wycięcie.
b_notch, a_notch = signal.iirnotch(50.0, 30.0, fs)
ekg_notch = signal.lfilter(b_notch, a_notch, ekg_hp)

# KROK C: Krótki FIR Dolnoprzepustowy (40 Hz) - Wygładza resztę szumu (np. mięśniowego)
numtaps = 101
b_fir = signal.firwin(numtaps, 40.0, fs=fs, window='hamming')
ekg_idealne = signal.lfilter(b_fir, [1.0], ekg_notch)

# ==========================================
# 3. WIZUALIZACJA WYNIKÓW
# ==========================================
plt.figure(figsize=(14, 7))

plt.subplot(2, 1, 1)
plt.plot(t, surowe_ekg, color='red', alpha=0.7)
plt.title('Surowy sygnał z elektrod (Chaos)')
plt.grid(True, linestyle='--')

plt.subplot(2, 1, 2)
plt.plot(t, ekg_idealne, color='blue', linewidth=1.5)
plt.title('Sygnał Idealny (IIR HPF + IIR Notch 50Hz + FIR LPF 101-taps)')
plt.xlabel('Czas [sekundy]')

opoznienie_s = ((numtaps - 1) / 2) / fs
plt.axvline(0.8, color='green', linestyle='--', label='Oryginalny QRS')
plt.axvline(0.8 + opoznienie_s, color='orange', linestyle='--', label=f'Przefiltrowany QRS (+{opoznienie_s}s)')
plt.legend()
plt.grid(True, linestyle='--')

plt.tight_layout()
plt.show()