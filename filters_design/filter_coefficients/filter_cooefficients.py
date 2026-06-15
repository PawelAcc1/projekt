
import scipy.signal as signal
import matplotlib.pyplot as plt
from math import pi
import os

# ==========================================
# 1. PARAMETRY SYSTEMU
# ==========================================

fs = 500.0  # Częstotliwość próbkowania w Hz
nyq = 0.5 * fs  # Częstotliwość Nyquista
f_cutoff = [40, 60] # Częstotliwość do obrazowania ekg

num_taps = 301 # liczba odprowadzeń

# ==========================================
# 2. PROJEKTOWANIE FILTRÓW
# ==========================================

bandpass_coeffs = signal.firwin(
    numtaps=num_taps,
    cutoff=f_cutoff,
    fs=fs,
    window='blackmanharris',
    pass_zero='bandstop'
)

# ==========================================
# 3. KWANTYZACJA DLA FPGA (16-bit)
# ==========================================
# Rezerwujemy 1 bit na znak, zostaje 15 bitów na precyzję ułamka.
skala_fpga = 2**15 - 1  # 32767
bandpass_coeffs_fpga = np.round(bandpass_coeffs * skala_fpga).astype(int)

# ==========================================
# 4. ZAPIS WSPÓŁCZYNNIKÓW DO PLIKU .COE
# ==========================================
#lokalizacja pliku ze wspolczynnikami
file_path = r"C:\Users\48509\Desktop\UEC2_Projekt\projekt\projekt_basys3\fir_compiler_notch" # r - raw string - python ignoruje znaki specjalne
file_name = "bandstop_coeffs.coe"
full_path = os.path.join(file_path, file_name) # concatenation of file path and file name

# format coefficient 
coeffs_joined = ",\n".join(map(str, bandpass_coeffs_fpga))

preamble = "radix=10;\ncoefdata=\n" # preamble for .coe file
coeffs_string_table = f"{preamble}{coeffs_joined};" 

with open(full_path, 'w') as file:
    file.write(coeffs_string_table)

print(f"Wygenerowano plik: {full_path}")
