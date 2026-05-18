import numpy as np
import scipy.signal as signal
import matplotlib.pyplot as plt

# ==========================================
# 1. PARAMETRY SYSTEMU
# ==========================================

fs = 500.0  # Częstotliwość próbkowania w Hz
nyq = 0.5 * fs  # Częstotliwość Nyquista
numtaps = 501 # liczba odprowadzeń 
f_cutoff = [0.5, 48.0, 52.0, 150] # pasmo

# ==========================================
# 2. PROJEKTOWANIE FILTRÓW
# ==========================================

bandpass_coeffs = signal.firwin(
    numtaps=numtaps,
    cutoff=f_cutoff,
    fs=fs,
    window='hamming',
    pass_zero=False
)

# ==========================================
# 3. KWANTYZACJA DLA FPGA (16-bit)
# ==========================================
# Rezerwujemy 1 bit na znak, zostaje 15 bitów na precyzję ułamka.
fpga_scale = 2**15 - 1  # 32767
bandpass_coeffs_fpga = np.round(bandpass_coeffs * fpga_scale).astype(int)

# ==========================================
# 4. WIZUALIZACJA WYNIKU
# ==========================================
w, h = signal.freqz(bandpass_coeffs, worN=8000)
f = (w * fs) / (2 * np.pi)

plt.figure(figsize=(12, 6))
plt.plot(f, 20 * np.log10(abs(h)), color='blue')
plt.title(f'Odpowiedź Amplitudowa (Taps={numtaps})')
plt.ylabel('Tłumienie [dB]')
plt.xlabel('Częstotliwość [Hz]')
plt.xlim(0, 250)
plt.ylim(-80, 5)
plt.grid(True, linestyle='--')
plt.show()