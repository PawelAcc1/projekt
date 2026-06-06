`timescale 1ns / 1ps

/* ==============================================================================
   Moduł: signal_conditioner
   Przeznaczenie: Przygotowanie próbki z filtra FIR do wyświetlenia na VGA.

   Tor: próbka z FIR jest ZE ZNAKIEM i może mieć resztkowy offset DC (dryf
   linii bazowej), a bufor/render oczekują wartości BEZ ZNAKU, wyśrodkowanej
   na połowie zakresu (mid-scale).

   Działanie:
     1. Usunięcie składowej stałej (DC) - filtr górnoprzepustowy I rzędu
        (leaky integrator). Dzięki temu linia bazowa zawsze wraca na środek
        ekranu, niezależnie od offsetu/dryfu z przetwornika i filtra.
            dc_est = dc_acc >> DC_SHIFT
            ac     = sample - dc_est
            dc_acc = dc_acc + ac           (aktualizacja co nową próbkę)
        Stała czasowa ~ 2^DC_SHIFT / Fs (przy 500 Hz i DC_SHIFT=9 ~ 1 s,
        czyli odcięcie ok. 0.3 Hz - usuwa dryf, zachowuje załamki EKG).
     2. Wzmocnienie składowej zmiennej (przesunięcie w lewo o GAIN_LSHIFT).
     3. Dodanie offsetu mid-scale (baseline na środek ekranu).
     4. Nasycenie (saturacja) do 0 .. (2^OUT_WIDTH - 1) - brak zawijania.

   Pokrętła kalibracji na sprzęcie:
     - GAIN_LSHIFT : amplituda przebiegu (mała -> zwiększ, klipowanie -> zmniejsz),
     - DC_SHIFT    : szybkość powrotu linii bazowej do środka (większe = wolniej).
   ============================================================================== */

module signal_conditioner #(
    parameter int IN_WIDTH    = 16, // szerokość słowa z FIR (signed)
    parameter int OUT_WIDTH   = 12, // szerokość danych bufora/wyświetlania (unsigned)
    parameter int GAIN_LSHIFT = 3,  // wzmocnienie składowej zmiennej (x 2^GAIN_LSHIFT)
    parameter int DC_SHIFT    = 9   // stała czasowa usuwania DC (większa = wolniejsza)
)(
    input  logic clk,
    input  logic rst_n,
    input  logic sample_valid,          // impuls: nowa próbka z FIR (tvalid)
    input  logic [IN_WIDTH-1:0]  data_in,
    output logic [OUT_WIDTH-1:0] data_out
);

    localparam int MID  = (1 << (OUT_WIDTH-1)); // środek zakresu (2048 dla 12 bitów)
    localparam int MAXV = (1 << OUT_WIDTH) - 1; // maksimum zakresu (4095 dla 12 bitów)

    logic signed [IN_WIDTH-1:0] sample;
    logic signed [31:0]         dc_acc;   // akumulator estymaty DC
    logic signed [31:0]         dc_est;
    logic signed [31:0]         ac;       // próbka po usunięciu DC
    logic signed [31:0]         centered;

    assign sample = data_in;                  // reinterpretacja jako signed
    assign dc_est = dc_acc >>> DC_SHIFT;      // estymata składowej stałej
    assign ac     = 32'(sample) - dc_est;     // składowa zmienna (AC)

    // Wzmocnienie + wyśrodkowanie + saturacja (kombinacyjnie, wyrównane z tvalid)
    always_comb begin
        centered = (ac <<< GAIN_LSHIFT) + MID;
        if (centered < 0)
            data_out = '0;
        else if (centered > MAXV)
            data_out = OUT_WIDTH'(MAXV);
        else
            data_out = centered[OUT_WIDTH-1:0];
    end

    // Aktualizacja estymaty DC tylko przy nowej próbce
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dc_acc <= '0;
        else if (sample_valid)
            dc_acc <= dc_acc + ac;
    end

endmodule
