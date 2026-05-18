import numpy as np
import scipy.signal as signal
import matplotlib.pyplot as plt

# ==========================================
# 1. PARAMETRY SYSTEMU I FILTRU
# ==========================================
fs = 500.0  
numtaps = 501 
f_cutoff = [1, 48.0, 52.0, 150.0] 

# Generujemy współczynniki naszego filtru
b_fir = signal.firwin(numtaps, f_cutoff, fs=fs, window='hamming', pass_zero=False)
a_fir = [1.0] # Dla filtru FIR mianownik to zawsze po prostu 1

# ==========================================
# 2. GENEROWANIE SYNTETYCZNEGO, ZASZUMIONEGO EKG
# ==========================================
t = np.arange(0, 4.0, 1.0/fs) # 4 sekundy nagrania

# A. Syntetyczne, czyste bicie serca (Piki QRS co ~0.8 sekundy)
czyste_ekg = signal.windows.gaussian(20, 2)
czyste_ekg = np.tile(np.pad(czyste_ekg, (0, int(fs*0.8) - 20)), 10)[:len(t)]

# B. Dodajemy zakłócenia, z którymi spotkasz się w rzeczywistości!
plywanie_izolinii = 1.5 * np.sin(2 * np.pi * 0.2 * t) # Powolne oddychanie (0.2 Hz)
szum_sieci = 0.5 * np.sin(2 * np.pi * 50.0 * t)       # Przydźwięk z gniazdka (50 Hz)
szum_miesniowy = 0.2 * np.random.randn(len(t))        # Losowy szum wysokoczęstotliwościowy

# Gotowy, okropny sygnał prosto z elektrod
surowe_ekg = czyste_ekg + plywanie_izolinii + szum_sieci + szum_miesniowy

# ==========================================
# 3. FILTRACJA (SYMULACJA UKŁADU FPGA)
# ==========================================
# lfilter działa dokładnie jak Twój docelowy układ sprzętowy próbka po próbce
przefiltrowane_ekg = signal.lfilter(b_fir, a_fir, surowe_ekg)

# ==========================================
# 4. WIZUALIZACJA WYNIKÓW
# ==========================================
plt.figure(figsize=(14, 7))

# Wykres 1: Sygnał Wejściowy
plt.subplot(2, 1, 1)
plt.plot(t, surowe_ekg, color='red', alpha=0.7)
plt.title('Surowy sygnał z elektrod (Pływająca izolinia + 50 Hz + Szum)')
plt.ylabel('Amplituda')
plt.grid(True, linestyle='--')

# Wykres 2: Sygnał Wyjściowy (Zwróć uwagę na opóźnienie!)
plt.subplot(2, 1, 2)
plt.plot(t, przefiltrowane_ekg, color='blue', linewidth=1.5)
plt.title('Sygnał za filtrem FIR (Zwróć uwagę na płaską izolinię i opóźnienie QRS o 0.5s)')
plt.xlabel('Czas [sekundy]')
plt.ylabel('Amplituda')
plt.grid(True, linestyle='--')

# Dodajemy linie pomocnicze, żeby pokazać opóźnienie grupowe (Group Delay)
opoznienie_s = ((numtaps - 1) / 2) / fs
plt.axvline(0.8, color='green', linestyle='--', label='Oryginalny pik QRS (0.8s)')
plt.axvline(0.8 + opoznienie_s, color='orange', linestyle='--', label=f'Przefiltrowany pik QRS ({0.8 + opoznienie_s}s)')
plt.legend()

plt.tight_layout()
plt.show()