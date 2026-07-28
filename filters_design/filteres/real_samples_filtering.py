import numpy as np
import matplotlib.pyplot as plt
import scipy.signal as signal

raw_samples = []
row_number = 0

with open ('ecg_samples_4.csv', 'r') as file:
    for row in file:
        row_number += 1
        raw_samples.append(int(row.strip(), 16)) #convert hex to int

raw_samples = np.array(raw_samples)

fs = 500.0  # Częstotliwość próbkowania w Hz
nyq = 0.5 * fs  # Częstotliwość Nyquista
f_cutoff = [0.5, 40] # Częstotliwość do obrazowania ekg
num_taps = 601 # liczba odprowadzeń


#fir 1
bandpass_coeffs_1 = signal.firwin(
    numtaps=num_taps,
    cutoff=f_cutoff,
    fs=fs,
    window='hamming',
    pass_zero='bandpass'
)

num_taps = 301

#fir 2
bandpass_coeffs_2 = signal.firwin(
    numtaps=num_taps,
    cutoff=f_cutoff,
    fs=fs,
    window='blackmanharris',
    pass_zero='bandpass'
)

#combination of both filters == convolution of their impulse response
combined_coeffs = np.convolve(bandpass_coeffs_1, bandpass_coeffs_2)

filtered_samples = signal.lfilter(combined_coeffs, 1.0, raw_samples)

#frequency response
w, h = signal.freqz(combined_coeffs, worN=8192)
f = (w * fs) / (2 * np.pi)

#time domain
t = np.arange(1200)


# Zwiększamy wysokość płótna, żeby oba wykresy miały czym oddychać
plt.figure(figsize=(12, 8)) 

# --- WYKRES GÓRNY (Surowe dane) ---
# 2 wiersze, 1 kolumna, 1-szy wykres (góra)
plt.subplot(2, 1, 1) 
plt.title("Surowy sygnał EKG (Zaszumiony)")
plt.plot(t[:1200], raw_samples[3000:4200], color='gray')
plt.ylabel("Amplituda [j.m.]")
plt.grid(True)

# --- WYKRES DOLNY (Po filtracji) ---
# 2 wiersze, 1 kolumna, 2-gi wykres (dół)
plt.subplot(2, 1, 2) 
plt.title("EKG po kaskadzie filtrów (Czyste, ale opóźnione)")
plt.plot(t[:1200], filtered_samples[3000:4200], color='red')
plt.xlabel("Czas [s]")
plt.ylabel("Amplituda [j.m.]")
plt.grid(True)

# --- MAGIA FORMATOWANIA ---
# Ta funkcja upewnia się, że tytuł dolnego wykresu nie wejdzie 
# na liczby z osi X górnego wykresu. Zawsze wywołuj ją przed show()!
plt.tight_layout() 

plt.show()