import numpy as np
import scipy.signal as signal
import matplotlib.pyplot as plt

# ==========================================
# 1. PARAMETRY SYSTEMU
# ==========================================
fs = 250.0  # Częstotliwość próbkowania w Hz
nyq = 0.5 * fs  # Częstotliwość Nyquista

# Format sprzętowy: 16-bitowy ze znakiem (Q15)
# Mnożymy ułamki przez 2^15, aby uzyskać liczby całkowite
skala_fpga = 32768 

# ==========================================
# 2. PROJEKTOWANIE FILTRÓW
# ==========================================

# A. Filtr Górnoprzepustowy (HPF) - 0.5 Hz, Rząd 1
# Usuwa pływanie izolinii (oddychanie)
fc_hp = 0.5
b_hp, a_hp = signal.butter(1, fc_hp/nyq, btype='high')

# B. Filtr Środkowozaporowy (Notch) - 50 Hz
# Usuwa przydźwięk z sieci energetycznej
f_notch = 50.0
Q_notch = 30.0  # Dobroć filtru (im wyższa, tym węższe wycięcie)
b_notch, a_notch = signal.iirnotch(f_notch, Q_notch, fs=fs)

# C. Filtr Dolnoprzepustowy (LPF) - 40 Hz, Rząd 2
# Usuwa szum mięśniowy (EMG)
fc_lp = 40.0
b_lp, a_lp = signal.butter(2, fc_lp/nyq, btype='low')

# ==========================================
# 3. FUNKCJA DO KONWERSJI NA FPGA (FIXED-POINT)
# ==========================================
def kwantyzuj_do_fpga(wspolczynniki, nazwa):
    wsp_int = np.round(wspolczynniki * skala_fpga).astype(int)
    print(f"{nazwa}:")
    # Formatuje wyjście tak, aby łatwo było skopiować do SystemVeriloga
    print("{" + ", ".join(map(str, wsp_int)) + "}")
    return wsp_int

print("--- WSPÓŁCZYNNIKI CAŁKOWITE DLA FPGA (Mnożnik x32768) ---")
print("// Skopiuj te tablice do pamięci ROM / localparam w module SystemVerilog\n")

print("// 1. Filtr Górnoprzepustowy (0.5 Hz)")
kwantyzuj_do_fpga(b_hp, "b_hp")
kwantyzuj_do_fpga(a_hp, "a_hp")

print("\n// 2. Filtr Notch (50 Hz)")
kwantyzuj_do_fpga(b_notch, "b_notch")
kwantyzuj_do_fpga(a_notch, "a_notch")

print("\n// 3. Filtr Dolnoprzepustowy (40 Hz)")
kwantyzuj_do_fpga(b_lp, "b_lp")
kwantyzuj_do_fpga(a_lp, "a_lp")
print("---------------------------------------------------------")

# ==========================================
# 4. WIZUALIZACJA (WYKRES BODE) KASKADY
# ==========================================
# Łączymy filtry mnożąc ich transmitancje (splot w dziedzinie czasu)
b_kaskada = np.convolve(np.convolve(b_hp, b_notch), b_lp)
a_kaskada = np.convolve(np.convolve(a_hp, a_notch), a_lp)

w, h = signal.freqz(b_kaskada, a_kaskada, worN=8000)
f = (w * fs) / (2 * np.pi)

plt.figure(figsize=(10, 6))
plt.plot(f, 20 * np.log10(abs(h)), linewidth=2)
plt.title('Charakterystyka Amplitudowa Kaskady (HPF + Notch + LPF)')
plt.xlabel('Częstotliwość [Hz]')
plt.ylabel('Amplituda [dB]')
plt.xlim(0, 100)
plt.ylim(-60, 5)
plt.grid(True, which="both", ls="--")
plt.axvline(50, color='red', linestyle='--', label='Zakłócenia sieci (50 Hz)')
plt.axvline(40, color='green', linestyle='--', label='Odcięcie LPF (40 Hz)')
plt.legend()
plt.tight_layout()
plt.show()