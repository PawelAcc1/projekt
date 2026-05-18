import numpy as np
import scipy.signal as signal
import matplotlib.pyplot as plt

# ==========================================
# 1. DEFINICJA FILTRÓW (Twój docelowy łańcuch)
# ==========================================
fs = 500.0  

# A. IIR Górnoprzepustowy (0.5 Hz)
b_hp, a_hp = signal.butter(2, 0.5/(fs/2), btype='high')

# B. IIR Notch (50 Hz)
b_notch, a_notch = signal.iirnotch(50.0, 30.0, fs)

# C. FIR Dolnoprzepustowy (40 Hz, 101 odczepów)
b_fir = signal.firwin(101, 40.0, fs=fs, window='hamming')
a_fir = [1.0]

# ==========================================
# 2. WYLICZANIE ODPOWIEDZI CZĘSTOTLIWOŚCIOWEJ
# ==========================================
# Funkcja freqz zwraca wektor częstotliwości (f) oraz zespoloną odpowiedź (h)
# worN=8000 to "rozdzielczość" wykresu (ilość punktów)
f, h_hp = signal.freqz(b_hp, a_hp, worN=8000, fs=fs)
_, h_notch = signal.freqz(b_notch, a_notch, worN=8000, fs=fs)
_, h_fir = signal.freqz(b_fir, a_fir, worN=8000, fs=fs)

# Mnożenie zespolone wszystkich bloków kaskady
h_total = h_hp * h_notch * h_fir

# Zamiana na decybele (dodajemy 1e-10 żeby uniknąć logarytmowania zera)
amp_dB = 20 * np.log10(np.maximum(np.abs(h_total), 1e-10))

# ==========================================
# 3. WIZUALIZACJA (Wykres Bode)
# ==========================================
plt.figure(figsize=(12, 6))

plt.plot(f, amp_dB, color='blue', linewidth=2, label='Pełny tor EKG')

# Zaznaczamy kluczowe częstotliwości (dla czytelności)
plt.axvline(0.5, color='green', linestyle=':', label='High-Pass (0.5 Hz)')
plt.axvline(40.0, color='orange', linestyle=':', label='Low-Pass (40 Hz)')
plt.axvline(50.0, color='red', linestyle='--', alpha=0.5, label='Notch (50 Hz)')

plt.title('Odpowiedź Amplitudowa całego łańcucha DSP (IIR + Notch + FIR)')
plt.xlabel('Częstotliwość [Hz]')
plt.ylabel('Tłumienie [dB]')

# Ustawiamy zakres osi X od 0 do Nyquista (250 Hz)
plt.xlim(0, fs/2)
# Oś Y zazwyczaj ogląda się do -80 dB, poniżej to już tylko matematyczne "śmieci"
plt.ylim(-80, 5)

plt.grid(True, which='both', linestyle='--', alpha=0.7)
plt.legend()
plt.tight_layout()

plt.show()