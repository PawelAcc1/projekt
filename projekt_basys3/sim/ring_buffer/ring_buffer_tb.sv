`timescale 1ns / 1ps

/* ==============================================================================
   Moduł testowy: ring_buffer_tb
   Przeznaczenie: Weryfikacja działania dwuportowej pamięci bufora kołowego.
   Sprawdza asynchroniczny odczyt/zapis oraz prawidłowe "zawijanie" adresu zapisu.
   ============================================================================== */

module ring_buffer_tb;

    // Parametry zgodne z testowanym modułem
    localparam ADDR_WIDTH = 10;
    localparam DATA_WIDTH = 12;

    // Sygnały dla Portu A (Zapis - strona I2C)
    logic clk_write;
    logic write_enable;
    logic [DATA_WIDTH-1:0] write_data;
    
    // Sygnały dla Portu B (Odczyt - strona VGA)
    logic clk_read;
    logic [ADDR_WIDTH-1:0] read_addr;
    wire [DATA_WIDTH-1:0] read_data;

    // Instancjacja testowanego modułu (UUT)
    ring_buffer #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk_write(clk_write),
        .write_enable(write_enable),
        .write_data(write_data),
        .clk_read(clk_read),
        .read_addr(read_addr),
        .read_data(read_data)
    );

    /* ==========================================================================
       GENERATORY ZEGARÓW (Clock Domains)
       Symulujemy dwa różne zegary działające niezależnie od siebie.
       ========================================================================== */
    // Zegar systemowy zapisu: 100 MHz (Okres 10 ns)
    always #5 clk_write = ~clk_write; 
    
    // Zegar kontrolera VGA: 25 MHz (Okres 40 ns)
    always #20 clk_read = ~clk_read;  

    // Zmienna pomocnicza do pętli 'for'
    integer i;

    /* ==========================================================================
       GŁÓWNA SEKWENCJA TESTOWA
       ========================================================================== */
    initial begin
        // 1. Inicjalizacja stanów początkowych
        clk_write = 0;
        clk_read = 0;
        write_enable = 0;
        write_data = 0;
        read_addr = 0;

        #100; // Czekamy chwilę na ustabilizowanie układu
        
        $display("Rozpoczynam zapisywanie 642 probek...");

        // 2. Symulacja napływania danych z I2C
        // Pętla wykona się 642 razy (iteracje od 0 do 641).
        // Jako wartość danych celowo podajemy numer iteracji 'i', żeby łatwo 
        // zidentyfikować w pamięci, co dokładnie odczytujemy.
        for (i = 0; i < 642; i = i + 1) begin
            @(posedge clk_write);
            write_enable = 1;         // Dajemy impuls zapisu
            write_data = i[11:0];     // Wrzucamy dane
            
            @(posedge clk_write);
            write_enable = 0;         // Kończymy zapis
            
            // Czekamy losową chwilę. Z punktu widzenia I2C próbki przychodzą wolno.
            #30; 
        end
        
        $display("Zapis zakonczony. Rozpoczynam weryfikacje odczytu (wrap-around)...");
        #100;

        // 3. Sprawdzanie poprawności zawijania (Port B)
        // Zmieniamy adres odczytu i czekamy jeden pełny cykl zegara odczytu, 
        // aby pamięć BRAM zdążyła wystawić wartość na wyjście 'read_data'.

        // Test 1: Adres 0. Ponieważ zapisaliśmy 642 próbki, a limit to 639, 
        // adres 0 powinien zostać nadpisany przez 640-tą próbkę.
        read_addr = 0;
        @(posedge clk_read); @(posedge clk_read); 
        $display("Adres 0   -> Odczytano: %d (Oczekiwane: 640)", read_data);
        
        // Test 2: Adres 1. Został nadpisany przez ostatnią, 641-szą próbkę.
        read_addr = 1;
        @(posedge clk_read); @(posedge clk_read); 
        $display("Adres 1   -> Odczytano: %d (Oczekiwane: 641)", read_data);

        // Test 3: Adres 2. Tutaj zawijanie nie dotarło. Powinna tu być stara wartość (2).
        read_addr = 2;
        @(posedge clk_read); @(posedge clk_read); 
        $display("Adres 2   -> Odczytano: %d (Oczekiwane: 2)", read_data);

        // Test 4: Ostatni piksel ekranu (639). 
        read_addr = 639;
        @(posedge clk_read); @(posedge clk_read); 
        $display("Adres 639 -> Odczytano: %d (Oczekiwane: 639)", read_data);

        #100;
        $finish;
    end

endmodule