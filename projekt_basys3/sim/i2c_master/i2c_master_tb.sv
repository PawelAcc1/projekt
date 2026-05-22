`timescale 1ns / 1ps

/* ==============================================================================
   Moduł testowy: i2c_master_tb
   Przeznaczenie: Weryfikacja działania I2C Mastera wraz z wirtualnym Slave (ADC).
   ============================================================================== */

module i2c_master_tb;

    // 1. Definicje sygnałów symulacyjnych
    // Obniżamy częstotliwość głównego zegara do 10 MHz, żeby symulacja
    // I2C (100 kHz) nie trwała w nieskończoność w oknie Vivado.
    localparam SYS_FREQ = 10_000_000; 
    localparam I2C_FREQ = 100_000;
    localparam ADC_ADDR = 7'h48;

    logic clk;
    logic rst_n;
    logic start_sampling;

    wire SDA;
    wire SCL;
    wire [11:0] adc_data;
    wire data_ready;

    /* ==========================================================================
       2. REZYSTOR PODCIĄGAJĄCY (PULL-UP)
       To najważniejsza linijka w testbenchu dla I2C! Symuluje sprzętowy rezystor,
       który wymusza stan '1', gdy nikt (ani Master, ani Slave) nie ściąga linii 
       SDA lub SCL do masy. Bez tego mielibyśmy stany nieokreślone (X).
       ========================================================================== */
    pullup(SDA);
    pullup(SCL); 

    /* ==========================================================================
       3. WIRTUALNY PRZETWORNIK ADC (Sterowanie linią SDA)
       Rejestry używane przez nasz symulowany ADC do odpowiadania Masterowi.
       ========================================================================== */
    logic sda_slave_out;
    logic sda_slave_en;
    
    // Jeśli wirtualny ADC chce wysłać 0 (np. ACK), podłącza się do SDA.
    assign SDA = (sda_slave_en) ? sda_slave_out : 1'bz;

    // 4. Instancjacja testowanego Mastera I2C
    i2c_master #(
        .SYS_CLK_FREQ(SYS_FREQ),
        .I2C_FREQ(I2C_FREQ),
        .ADC_ADDRESS(ADC_ADDR)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .start_sampling(start_sampling),
        .SDA(SDA),
        .SCL(SCL),
        .adc_data(adc_data),
        .data_ready(data_ready)
    );

    // 5. Generator zegara systemowego (10 MHz -> T = 100 ns)
    always #50 clk = ~clk;

    // 6. Główny scenariusz pobudzający (zachowanie Mastera)
    initial begin
        // Stan początkowy
        clk = 0;
        rst_n = 0;
        start_sampling = 0;
        sda_slave_en = 0;
        sda_slave_out = 0;

        #200;
        rst_n = 1;    // Puszczamy reset (aktywny nisko)
        #500;

        // Symulujemy impuls 'tick' z naszego sampling_timer'a
        @(posedge clk);
        start_sampling = 1;
        @(posedge clk);
        start_sampling = 0;

        // Czekamy, aż Master odczyta wszystko i wystawi nową próbkę
        @(posedge data_ready);
        $display("Pomiar EKG zakonczony! Odebrano wartosc: %h", adc_data);
        
        #2000;
        $finish; // Koniec symulacji
    end

    /* ==========================================================================
       7. WIRTUALNY PRZETWORNIK ADC (Zachowanie Slave'a)
       Ten blok kodu nasłuchuje linii I2C i reaguje dokładnie tak, 
       jak zrobiłby to układ na płytce. 
       Wysłana próbka EKG: 12'hA5C (Szesnastkowo A=10, 5, C=12)
       Która zostanie podzielona na dwa bajty: 8'h0A i 8'h5C.
       ========================================================================== */
    logic [15:0] fake_adc_data = 16'h0A5C; 
    integer i;

    initial begin
        // KROK A: Oczekujemy na warunek START (SDA spada, podczas gdy SCL = 1)
        wait (SDA === 1'b0 && SCL === 1'b1);
        $display("Wirtualny ADC: Wykryto warunek START");

        // KROK B: Przepuszczamy (ignorujemy) 8 bitów z adresem i kierunkiem odczytu
        for(i=0; i<8; i=i+1) begin
            @(negedge SCL); // Czekamy na 8 opadających zboczy zegara
        end
        
        // KROK C: Wysyłamy ACK1 (Ściągamy SDA do '0', żeby Master wiedział, że istniejemy)
        sda_slave_en = 1'b1;
        sda_slave_out = 1'b0;
        @(negedge SCL);      // Trzymamy przez jeden cykl SCL
        sda_slave_en = 1'b0; // Puszczamy SDA przed fazą odczytu
        
        // KROK D: Wysyłamy pierwszy bajt (8'h0A) z próbką EKG
        for(i=15; i>=8; i=i-1) begin
            sda_slave_en = 1'b1;
            sda_slave_out = fake_adc_data[i];
            @(negedge SCL);  // Zmieniamy bity tylko na opadającym zboczu SCL!
        end
        sda_slave_en = 1'b0; // Puszczamy linię...
        
        // KROK E: ...i czekamy na ACK (potwierdzenie) od samego Mastera (FPGA)
        @(negedge SCL);
        
        // KROK F: Wysyłamy drugi bajt (8'h5C) z resztą wyniku
        for(i=7; i>=0; i=i-1) begin
            sda_slave_en = 1'b1;
            sda_slave_out = fake_adc_data[i];
            @(negedge SCL);
        end
        sda_slave_en = 1'b0; // Puszczamy linię
        
        // Master powinien wygenerować NACK (1) i STOP. Kończymy zadanie ADC.
        $display("Wirtualny ADC: Wyslano cale dane. Czekam na NACK i STOP.");
    end

endmodule