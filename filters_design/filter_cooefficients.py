from scipy.signal import firwin

b = firwin(
    numtaps=64,
    cutoff=40,
    fs=1000
)

print(b)