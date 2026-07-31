# Skrypt generujący tablicę LUT dla kalkulatora BPM
with open("bpm_rom.hex", "w") as f:
    for i in range(2048): # 11-bitowy licznik próbek
        if i < 150 or i > 2000:
            # Poniżej 150 (szum) lub powyżej 2000 (timeout) - tętno 0
            f.write("00\n")
        else:
            bpm = int(30000 / i)
            # Zabezpieczenie przed przepełnieniem 8 bitów
            if bpm > 255: 
                bpm = 255
            f.write(f"{bpm:02X}\n")
print("Plik bpm_rom.hex został wygenerowany pomyślnie!")