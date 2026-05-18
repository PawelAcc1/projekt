import numpy as np
import scipy.signal as signal
import matplotlib.pyplot as plt
from math import pi

# ==========================================
# 1. PARAMETRY SYSTEMU
# ==========================================

fs = 500.0  # Częstotliwość próbkowania w Hz
nyq = 0.5 * fs  # Częstotliwość Nyquista
f_cutoff = 40 # Częstotliwość do obrazowania ekg

num_taps = 101 # liczba odprowadzeń

# ==========================================
# 2. PROJEKTOWANIE FILTRÓW
# ==========================================

lowpass_coeffs = signal.firwin(
    numtaps=num_taps,
    cutoff=f_cutoff,
    fs=fs,
    window='hamming',
)

# ==========================================
# 3. KWANTYZACJA DLA FPGA (16-bit)
# ==========================================
# Rezerwujemy 1 bit na znak, zostaje 15 bitów na precyzję ułamka.
skala_fpga = 2**15 - 1  # 32767
lowpass_coeffs_fpga = np.round(lowpass_coeffs * skala_fpga).astype(int)

# ==========================================
# 4. WIZUALIZACJA WYNIKU
# ==========================================
w, h = signal.freqz(lowpass_coeffs, worN=8000)
f = (w * fs) / (2 * np.pi)

# Obliczanie opóźnienia grupowego (Group Delay)
w_gd, gd = signal.group_delay((lowpass_coeffs, 1), w=8000)
f_gd = (w_gd * fs) / (2 * np.pi)

plt.figure(figsize=(12, 6))

# Wykres Amplitudowy
plt.subplot(1, 2, 1)
plt.plot(f, 20 * np.log10(abs(h)), color='blue')
plt.title(f'Odpowiedź Amplitudowa (Taps={num_taps})')
plt.xlabel('Częstotliwość [Hz]')
plt.ylabel('Tłumienie [dB]')
plt.xlim(0, 500)
plt.ylim(-80, 5)
plt.grid(True, linestyle='--')

# Wykres Opóźnienia Grupowego (Zwróć uwagę na płaską linię!)
plt.subplot(1, 2, 2)
plt.plot(f_gd, gd / fs, color='red') # Przeliczenie na sekundy
plt.title('Opóźnienie Grupowe (Liniowa faza)')
plt.xlabel('Częstotliwość [Hz]')
plt.ylabel('Opóźnienie [sekundy]')
plt.xlim(0, 500)
plt.ylim(0, 0.5)
plt.grid(True, linestyle='--')

plt.tight_layout()
plt.show()