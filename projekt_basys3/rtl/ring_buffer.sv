`timescale 1ns / 1ps

/* ==============================================================================
   Moduł: ring_buffer (Pamięć przebiegu EKG)
   Przeznaczenie: Dwuportowa pamięć pełniąca rolę bufora kołowego między 
   wolnym źródłem danych (I2C) a szybkim odbiornikiem (VGA).
   ============================================================================== */

module ring_buffer #(
    // Jeśli używamy standardowej rozdzielczości VGA 640x480, 
    // potrzebujemy przechować co najmniej 640 punktów wykresu.
    // Najbliższa potęga dwójki to 1024, więc adres musi mieć 10 bitów (2^10 = 1024).
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 16   // 16 bitów, bo taki wynik zwraca nasz ADC
)(
    // PORT A (Zapis - połączony z I2C Masterem)
    input  wire clk_write,           // Zegar systemowy (np. 100 MHz)
    input  wire write_enable,        // Sygnał 'data_ready' z modułu I2C
    input  wire [DATA_WIDTH-1:0] write_data, // Wynik 'adc_data' z modułu I2C
    
    // PORT B (Odczyt - połączony z kontrolerem grafiki VGA)
    input  wire clk_read,            // Zegar odczytu (może to być zegar VGA np. 25 MHz)
    input  wire [ADDR_WIDTH-1:0] read_addr,  // Aktualna współrzędna X na ekranie
    output logic  [DATA_WIDTH-1:0] read_data   // Wartość EKG wyciągnięta z pamięci
);

    // Główna tablica pamięci. 
    // Deklarujemy 1024 'szufladek', każda po 16 bitów.
    // Syntezator Vivado automatycznie rozpozna ten wzorzec i użyje wbudowanych
    // w układ FPGA zasobów BRAM (Block RAM) zamiast zwykłych rejestrów.
    logic [DATA_WIDTH-1:0] memory [0:(1<<ADDR_WIDTH)-1];

    // Wewnętrzny licznik adresu zapisu (wskaźnik bufora kołowego)
    logic [ADDR_WIDTH-1:0] write_ptr = 0;

    /* ==========================================================================
       PORT A: Proces zapisu (Write)
       ========================================================================== */
    always @(posedge clk_write) begin
        if (write_enable) begin
            // Jeśli przyszła nowa próbka z I2C, zapisz ją pod aktualnym adresem
            memory[write_ptr] <= write_data;
            
            // Przesuń wskaźnik na następną pozycję.
            // Gdy licznik osiągnie maksimum, sam "przekręci się" na 0 
            // (np. po 1023 wróci na 0), co tworzy zjawisko bufora kołowego!
            // Uwaga: Jeśli szerokość ekranu wynosi np. 640, możemy go zawrócić wcześniej:
            if (write_ptr == 639)
                write_ptr <= 0;
            else
                write_ptr <= write_ptr + 1;
        end
    end

    /* ==========================================================================
       PORT B: Proces odczytu (Read)
       ========================================================================== */
    always @(posedge clk_read) begin
        // Port odczytu zawsze (niezależnie od wszystkiego) podaje wartość 
        // z komórki pamięci wskazanej przez 'read_addr'. W przypadku VGA
        // będzie to po prostu wartość piksela X na ekranie (od 0 do 639).
        read_data <= memory[read_addr];
    end

endmodule