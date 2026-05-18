import numpy as np
import scipy.signal as signal
import matplotlib.pyplot as plt
import wfdb  # Biblioteka do obsługi bazy PhysioNet

# ==========================================
# 1. POBRANIE PRAWDZIWYCH DANYCH Z BAZY MIT-BIH
# ==========================================
print("Pobieranie rekordu z bazy PhysioNet...")
# Pobieramy pierwsze 1500 próbek (kilka sekund) z rekordu '103'
record = wfdb.rdrecord('103', pn_dir='mitdb', sampfrom=0, sampto=1500)

# Wyciągamy surowy sygnał z pierwszego odprowadzenia (MLII)
sygnal_mitbih = record.p_signal[:, 0]
fs_bazy = record.fs  # Częstotliwość bazy (zazwyczaj 360 Hz)

# ==========================================
# 2. RESAMPLING (Symulacja Twojego wejścia ADC na 500 Hz)
# ==========================================
fs_fpga = 500.0
liczba_probek_fpga = int(len(sygnal_mitbih) * (fs_fpga / fs_bazy))

# Przeliczamy sygnał na Twoją docelową częstotliwość
surowe_ekg = signal.resample(sygnal_mitbih, liczba_probek_fpga)
t = np.arange(len(surowe_ekg)) / fs_fpga

# ==========================================
# 3. TWÓJ ŁAŃCUCH DSP (Dokładnie to, co trafi na FPGA)
# ==========================================

# KROK A: IIR Górnoprzepustowy (0.5 Hz) - Stabilizacja izolinii
b_hp, a_hp = signal.butter(2, 0.5/(fs_fpga/2), btype='high')
ekg_hp = signal.lfilter(b_hp, a_hp, surowe_ekg)

# KROK B: IIR Notch (50 Hz) - Wycięcie sieci
b_notch, a_notch = signal.iirnotch(50.0, 30.0, fs_fpga)
ekg_notch = signal.lfilter(b_notch, a_notch, ekg_hp)

# KROK C: FIR Dolnoprzepustowy (40 Hz, 101 odczepów) - Odcięcie szumów wysokich
numtaps = 101
b_fir = signal.firwin(numtaps, 40.0, fs=fs_fpga, window='hamming')
ekg_idealne = signal.lfilter(b_fir, [1.0], ekg_notch)

# ==========================================
# 4. WIZUALIZACJA WYNIKÓW
# ==========================================
plt.figure(figsize=(14, 7))

plt.subplot(2, 1, 1)
plt.plot(t, surowe_ekg, color='red', alpha=0.7)
plt.title(f'Prawdziwy sygnał pacjenta (MIT-BIH Rekord 103) zresamplowany do {fs_fpga} Hz')
plt.ylabel('Amplituda [mV]')
plt.grid(True, linestyle='--')

plt.subplot(2, 1, 2)
plt.plot(t, ekg_idealne, color='blue', linewidth=1.5)
plt.title('Sygnał po przejściu przez architekturę FPGA (IIR HPF + Notch + FIR LPF)')
plt.xlabel('Czas [sekundy]')
plt.ylabel('Amplituda [mV]')
plt.grid(True, linestyle='--')

plt.tight_layout()
plt.show()