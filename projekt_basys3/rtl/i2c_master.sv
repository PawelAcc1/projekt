`timescale 1ns / 1ps

/* ==============================================================================
   Moduł: i2c_master
   Przeznaczenie: Komunikacja z przetwornikiem ADC (SAR) po magistrali I2C (Pmod AD2 / AD7991).
   
   Zasada działania: 
   1. Po włączeniu zasilania (lub resecie) układ wykonuje jednorazową konfigurację 
      własną, wysyłając bajt konfiguracyjny wybierający kanał CH0 (V0 na złączu).
   2. Następnie przechodzi w stan spoczynku.
   3. Po otrzymaniu impulsowego sygnału 'start_sampling' (z timera) moduł generuje 
      warunek START, wysyła adres urządzenia (z bitem Read), odbiera dwa bajty
      (16 bitów) pomiaru, składa z nich pełny 16-bitowy wynik dla filtra cyfrowego, 
      a następnie kończy transmisję warunkiem STOP.
   ============================================================================== */

module i2c_master #(
    parameter SYS_CLK_FREQ = 100_000_000, // Zegar systemowy 100 MHz z Basys 3
    parameter I2C_FREQ = 100_000,         // Docelowa częstotliwość magistrali I2C (100 kHz)
    parameter ADC_ADDRESS = 7'b0101000    // 7-bitowy adres sprzętowy przetwornika Pmod AD2
)(
    input  wire clk,                      // Główny sygnał zegarowy
    input  wire rst_n,                    // Asynchroniczny reset (aktywny stanem niskim)
    input  wire start_sampling,           // Sygnał z timera (impuls rozpoczynający pomiar)
    
    // Zewnętrzne linie I2C (podłączone bezpośrednio do fizycznych pinów Pmod)
    inout  wire SDA,                      // Dwukierunkowa linia danych (Serial Data)
    output wire SCL,                      // Linia zegarowa generowana przez nasze FPGA (Serial Clock)
    
    // Dane wyjściowe do bufora kołowego / filtra cyfrowego
    output logic [15:0] adc_data,         // Pełny, 16-bitowy wynik pomiaru bez obcinania MSB
    output logic data_ready               // Flaga: '1' przez jeden cykl, informująca że wynik jest gotowy
);

    /* ==========================================================================
       1. STEROWANIE LINIĄ SDA (Open-Drain Tristate Buffer)
       Magistrala I2C to typowy "otwarty dren" (open-drain). Układ FPGA nigdy 
       nie powinien aktywnie wymuszać na niej jedynki logicznej. Jedynkę 
       zapewnia zewnętrzny rezystor podciągający (pull-up) na płytce Pmod AD2.
       
       Jeśli chcemy wysłać '0', ściągamy linię do masy (1'b0). 
       Jeśli chcemy wysłać '1' (lub słuchać odpowiedzi od ADC), 
       ustawiamy wysoką impedancję (1'bz).
       ========================================================================== */
    logic sda_out_enable; 
    logic sda_out_value;

    assign SDA = (sda_out_enable && sda_out_value == 1'b0) ? 1'b0 : 1'bz;

    /* ==========================================================================
       2. GENERATOR ZEGARA I2C (2x szybszy tick)
       Aby bezpiecznie zmieniać stan linii SDA (gdy SCL jest niski) i próbkować 
       dane (gdy SCL jest wysoki), potrzebujemy wewnętrznego sygnału tykającego
       z częstotliwością dwukrotnie wyższą niż docelowy zegar I2C (czyli 200 kHz).
       ========================================================================== */
    localparam TICK_DIVIDER = SYS_CLK_FREQ / (I2C_FREQ * 2);
    logic [$clog2(TICK_DIVIDER)-1:0] tick_counter = 0;
    logic i2c_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_counter <= 0;
            i2c_tick <= 0;
        end else begin
            if (tick_counter == TICK_DIVIDER - 1) begin
                tick_counter <= 0;
                i2c_tick <= 1'b1; // Wystawienie impulsu
            end else begin
                tick_counter <= tick_counter + 1;
                i2c_tick <= 1'b0; // Oczekiwanie
            end
        end
    end

    /* ==========================================================================
       3. DEFINICJE STANÓW DLA MASZYNY STANÓW (FSM)
       ========================================================================== */
    localparam STATE_IDLE    = 4'd0; // Stan spoczynku (oczekiwanie)
    localparam STATE_START   = 4'd1; // Generowanie warunku START
    localparam STATE_ADDR    = 4'd2; // Wysyłanie 7 bitów adresu + bitu kierunku
    localparam STATE_ACK1    = 4'd3; // Oczekiwanie na pierwsze potwierdzenie od ADC
    localparam STATE_RX_MSB  = 4'd4; // Odbiór starszych 8 bitów danych
    localparam STATE_ACK2    = 4'd5; // FPGA potwierdza odbiór pierwszego bajtu
    localparam STATE_RX_LSB  = 4'd6; // Odbiór młodszych 8 bitów danych
    localparam STATE_NACK    = 4'd7; // FPGA nie daje potwierdzenia (NACK) - koniec odczytu
    localparam STATE_STOP    = 4'd8; // Generowanie warunku STOP
    localparam STATE_DONE    = 4'd9; // Zgłoszenie gotowości danych (data_ready)
    
    // Specjalne stany do jednorazowej inicjalizacji układu AD7991 po restarcie
    localparam STATE_INIT_START = 4'd10;
    localparam STATE_INIT_ADDR  = 4'd11;
    localparam STATE_INIT_ACK1  = 4'd12;
    localparam STATE_INIT_DATA  = 4'd13;
    localparam STATE_INIT_ACK2  = 4'd14;
    localparam STATE_INIT_STOP  = 4'd15;

    logic [3:0] state = STATE_IDLE;
    
    // Wewnętrzne rejestry pomocnicze
    logic [7:0] tx_shift_reg;     // Rejestr do wysyłania adresu i danych konfiguracyjnych
    logic [7:0] rx_shift_reg;     // Rejestr (Shift Register) do wciągania odebranych bitów
    logic [3:0] bit_counter;      // Licznik bitów (zlicza od 7 w dół do 0 dla każdego bajtu)
    logic scl_reg;                // Fizyczny stan, który zostanie przypisany do pinu SCL
    logic phase;                  // Faza: 0 = SCL niski (zmiana na SDA), 1 = SCL wysoki (odczyt z SDA)
    logic [7:0] msb_byte;         // Pamięć podręczna na pierwszy odebrany bajt pomiaru
    logic init_done;              // Flaga: 0 = po resecie trzeba skonfigurować ADC, 1 = ADC skonfigurowany
    
    assign SCL = scl_reg;         // Podłączenie wewnętrznego rejestru pod pin zewnętrzny

    /* ==========================================================================
       4. GŁÓWNA MASZYNA STANÓW (FSM)
       Wykonuje skoki wyłącznie wtedy, gdy wystąpi impuls 'i2c_tick' z dzielnika 
       zegara (czyli z prędkością 200 kHz).
       ========================================================================== */
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Twardy reset wszystkich parametrów do bezpiecznych stanów początkowych
            state <= STATE_IDLE;
            scl_reg <= 1'b1;
            sda_out_enable <= 1'b0;
            data_ready <= 1'b0;
            phase <= 1'b0;
            init_done <= 1'b0; 
        end else begin
            
            // Domyślnie flaga data_ready trwa tylko 1 cykl zegara systemowego
            data_ready <= 1'b0; 

            if (i2c_tick) begin
                case (state)
                    
                    STATE_IDLE: begin
                        scl_reg <= 1'b1;        // Obie linie zwolnione (ciągnięte do VCC przez pull-upy)
                        sda_out_enable <= 1'b0;
                        
                        if (!init_done) begin
                            // ŚCIEŻKA 1: Układ po resecie, wymaga jednorazowej inicjalizacji
                            state <= STATE_INIT_START;
                            // Przygotowanie do zapisu: Adres ADC + bit Write (0)
                            tx_shift_reg <= {ADC_ADDRESS, 1'b0}; 
                        end 
                        else if (start_sampling) begin
                            // ŚCIEŻKA 2: Normalna praca, timer dał impuls do nowego pomiaru
                            state <= STATE_START;
                            // Przygotowanie do odczytu: Adres ADC + bit Read (1)
                            tx_shift_reg <= {ADC_ADDRESS, 1'b1}; 
                        end
                    end

                    /* =========================================================
                       SEKWENCJA INICJALIZACJI (JEDNORAZOWY ZAPIS DO AD7991)
                       Cel: Ustawienie Rejestru Konfiguracyjnego na czytanie z CH0.
                       ========================================================= */
                    STATE_INIT_START: begin
                        sda_out_enable <= 1'b1;
                        sda_out_value <= 1'b0;  // Ściągamy SDA w dół przy wysokim SCL (START)
                        scl_reg <= 1'b1;        
                        state <= STATE_INIT_ADDR;
                        bit_counter <= 3'd7;    
                        phase <= 1'b0;
                    end

                    STATE_INIT_ADDR: begin
                        if (phase == 1'b0) begin
                            scl_reg <= 1'b0;
                            sda_out_enable <= 1'b1;
                            sda_out_value <= tx_shift_reg[bit_counter]; // Wystawiamy kolejny bit
                            phase <= 1'b1;
                        end else begin
                            scl_reg <= 1'b1;    // ADC próbkuję naszą linię
                            phase <= 1'b0;
                            if (bit_counter == 0)
                                state <= STATE_INIT_ACK1;
                            else
                                bit_counter <= bit_counter - 1;
                        end
                    end

                    STATE_INIT_ACK1: begin
                        if (phase == 1'b0) begin
                            scl_reg <= 1'b0;
                            sda_out_enable <= 1'b0; // Ustawiamy 'Z', oddajemy sterowanie SDA ADC (czekamy na ACK)
                            phase <= 1'b1;
                        end else begin
                            scl_reg <= 1'b1;
                            phase <= 1'b0;
                            state <= STATE_INIT_DATA;
                            bit_counter <= 3'd7;
                            // Ładujemy dane: 8'b0001_0000 oznacza włączenie kanału CH0 (V0 na złączu Pmod)
                            tx_shift_reg <= 8'b0001_0000; 
                        end
                    end

                    STATE_INIT_DATA: begin
                        if (phase == 1'b0) begin
                            scl_reg <= 1'b0;
                            sda_out_enable <= 1'b1;
                            sda_out_value <= tx_shift_reg[bit_counter]; // Wysyłanie bajtu konfiguracyjnego
                            phase <= 1'b1;
                        end else begin
                            scl_reg <= 1'b1;
                            phase <= 1'b0;
                            if (bit_counter == 0)
                                state <= STATE_INIT_ACK2;
                            else
                                bit_counter <= bit_counter - 1;
                        end
                    end

                    STATE_INIT_ACK2: begin
                        if (phase == 1'b0) begin
                            scl_reg <= 1'b0;
                            sda_out_enable <= 1'b0; // Oczekujemy drugiego ACK potwierdzającego zapis
                            phase <= 1'b1;
                        end else begin
                            scl_reg <= 1'b1;
                            phase <= 1'b0;
                            state <= STATE_INIT_STOP;
                        end
                    end

                    STATE_INIT_STOP: begin
                        if (phase == 1'b0) begin
                            scl_reg <= 1'b0;
                            sda_out_enable <= 1'b1;
                            sda_out_value <= 1'b0;  // Przygotowanie do wygenerowania STOPu
                            phase <= 1'b1;
                        end else begin
                            scl_reg <= 1'b1;        
                            phase <= 1'b0;
                            init_done <= 1'b1;   // ZAPIS SUKCES: Oznaczamy układ jako skonfigurowany    
                            state <= STATE_IDLE; // Wracamy na początek i czekamy na sygnały timera
                        end
                    end

                    /* =========================================================
                       GŁÓWNA PĘTLA ODCZYTU (URUCHAMIANA CO X MS PRZEZ TIMER)
                       Cel: Pobranie 16 bitów sygnału EKG i przekazanie go dalej.
                       ========================================================= */
                    STATE_START: begin
                        sda_out_enable <= 1'b1;
                        sda_out_value <= 1'b0;  // Zmiana SDA z '1' na '0' gdy SCL = '1'
                        scl_reg <= 1'b1;        
                        state <= STATE_ADDR;
                        bit_counter <= 3'd7;    
                        phase <= 1'b0;
                    end

                    STATE_ADDR: begin
                        if (phase == 1'b0) begin
                            scl_reg <= 1'b0;        // Faza zmiany: Zegar niski
                            sda_out_enable <= 1'b1;
                            sda_out_value <= tx_shift_reg[bit_counter];
                            phase <= 1'b1;
                        end else begin
                            scl_reg <= 1'b1;        // Faza odczytu: Zegar wysoki (ADC czyta adres)
                            phase <= 1'b0;
                            if (bit_counter == 0)
                                state <= STATE_ACK1;
                            else
                                bit_counter <= bit_counter - 1;
                        end
                    end

                    STATE_ACK1: begin
                        if (phase == 1'b0) begin
                            scl_reg <= 1'b0;
                            sda_out_enable <= 1'b0; // "Puszczamy" linię, czekamy aż ADC potwierdzi obecność
                            phase <= 1'b1;
                        end else begin
                            scl_reg <= 1'b1;
                            phase <= 1'b0;
                            state <= STATE_RX_MSB;  // Przejście do pobierania użytecznych danych
                            bit_counter <= 3'd7;
                        end
                    end

                    STATE_RX_MSB: begin
                        if (phase == 1'b0) begin
                            scl_reg <= 1'b0;        // Zegar niski, ADC ładuje kolejny bit na przewód SDA
                            phase <= 1'b1;
                        end else begin
                            scl_reg <= 1'b1;        // Zegar wysoki, my odczytujemy stabilny bit!
                            rx_shift_reg[bit_counter] <= SDA; 
                            phase <= 1'b0;
                            if (bit_counter == 0) begin
                                msb_byte <= {rx_shift_reg[7:1], SDA}; // Składamy cały MSB do bufora
                                state <= STATE_ACK2;
                            end else begin
                                bit_counter <= bit_counter - 1;
                            end
                        end
                    end

                    STATE_ACK2: begin 
                        if (phase == 1'b0) begin
                            scl_reg <= 1'b0;
                            sda_out_enable <= 1'b1;
                            sda_out_value <= 1'b0;  // Ściągamy SDA w dół - To NASZE potwierdzenie (ACK) dla ADC
                            phase <= 1'b1;
                        end else begin
                            scl_reg <= 1'b1;
                            phase <= 1'b0;
                            state <= STATE_RX_LSB;  // Odbieramy resztę (młodsze bity)
                            bit_counter <= 3'd7;
                        end
                    end

                    STATE_RX_LSB: begin
                        if (phase == 1'b0) begin
                            scl_reg <= 1'b0;
                            sda_out_enable <= 1'b0; // Ponownie zwalniamy szynę dla ADC
                            phase <= 1'b1;
                        end else begin
                            scl_reg <= 1'b1;
                            rx_shift_reg[bit_counter] <= SDA;
                            phase <= 1'b0;
                            if (bit_counter == 0) begin
                                // SKLEJANIE WYNIKU:
                                // Przekazujemy PEŁNE 16 bitów, aby cyfrowy filtr sprzętowy miał pełny dostęp 
                                // do surowego słowa z przetwornika (z wiodącymi zerami).
                                adc_data <= {msb_byte, rx_shift_reg[7:1], SDA}; 
                                state <= STATE_NACK;
                            end else begin
                                bit_counter <= bit_counter - 1;
                            end
                        end
                    end

                    STATE_NACK: begin 
                        if (phase == 1'b0) begin
                            scl_reg <= 1'b0;
                            sda_out_enable <= 1'b0; // Nie ściągamy w dół! Linia zostaje w '1' - to sygnał NACK
                            phase <= 1'b1;
                        end else begin
                            scl_reg <= 1'b1;
                            phase <= 1'b0;
                            state <= STATE_STOP;
                        end
                    end

                    STATE_STOP: begin
                        if (phase == 1'b0) begin
                            scl_reg <= 1'b0;
                            sda_out_enable <= 1'b1;
                            sda_out_value <= 1'b0;  // Najpierw bezpiecznie obniżamy SDA
                            phase <= 1'b1;
                        end else begin
                            scl_reg <= 1'b1;        // SCL idzie w '1'
                            phase <= 1'b0;
                            state <= STATE_DONE;
                        end
                    end

                    STATE_DONE: begin
                        // Ostatni krok: SCL jest w '1', więc uwolnienie SDA z '0' do '1' generuje fizyczny STOP.
                        sda_out_enable <= 1'b0;     
                        data_ready <= 1'b1;         // Dajemy znać światu zewnętrznemu (Filtrowi/VGA), że jest nowa paczka!
                        state <= STATE_IDLE;        // Wracamy na początek i czekamy na sygnał od timera
                    end

                endcase
            end
        end
    end

endmodule
//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

// zmienna data_ready - wymuszenie do obliczeń filtra 
// adc_data - 16 bitowa ramka wyniku pomiaru 