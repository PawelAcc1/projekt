module render_signal #(
    parameter WIDTH = 12,
    parameter ADDR = 10
)(
    input logic clk,
    input logic rst_n,
    input logic [WIDTH-1:0] ecg_data_read,
    vga_if.in vga_in,
    vga_if.out vga_out,
    output logic [ADDR-1:0] read_address
);

import vga_pkg::*;

localparam logic [11:0] SIGNAL_COLOUR = 12'hf_0_0;
localparam logic [11:0] LINE_WIDTH    = 12'd1;   // dodatkowa grubość linii (px)

logic [13:0] data_x3;
logic [11:0] y_cur;        // y bieżącej kolumny (zgrane ze stopniem s1)

always_comb begin
    read_address = vga_in.hcount[ADDR-1:0];
    data_x3 = ecg_data_read * 3;
    y_cur   = (VER_PIXELS - 1) - {2'd0, data_x3[13:4]};
end

// ----- stopień 1: opóźnione o 1 takt sygnały VGA + zapamiętane y poprzedniej kolumny -----
logic        s1_hblnk, s1_vblnk, s1_hsync, s1_vsync;
logic [11:0] s1_vcount, s1_hcount, s1_rgb;
logic [11:0] y_prev;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        s1_hblnk <= '0; s1_vblnk <= '0; s1_hsync <= '0; s1_vsync <= '0;
        s1_vcount <= '0; s1_hcount <= '0; s1_rgb <= '0;
        y_prev <= VER_PIXELS/2;
    end
    else begin
        s1_hblnk <= vga_in.hblnk; s1_vblnk <= vga_in.vblnk;
        s1_hsync <= vga_in.hsync; s1_vsync <= vga_in.vsync;
        s1_vcount <= vga_in.vcount; s1_hcount <= vga_in.hcount;
        s1_rgb <= vga_in.rgb;
        y_prev <= y_cur;          // y kolumny o jeden wcześniejszej
    end
end

// ----- stopień 2: rysowanie CIĄGŁEJ linii (wypełnienie odcinka y_prev -> y_cur) -----
logic [11:0] y_prev_eff;
logic [11:0] y_lo, y_hi, band_lo, band_hi;
logic        in_active, in_band;

always_comb begin
    // Na lewej krawędzi ekranu nie łączymy z próbką z poza obszaru aktywnego.
    y_prev_eff = (s1_hcount == 12'd0) ? y_cur : y_prev;

    y_lo = (y_prev_eff < y_cur) ? y_prev_eff : y_cur;
    y_hi = (y_prev_eff < y_cur) ? y_cur      : y_prev_eff;

    band_lo = (y_lo > LINE_WIDTH) ? (y_lo - LINE_WIDTH) : 12'd0;
    band_hi = y_hi + LINE_WIDTH;

    in_active = !s1_hblnk && !s1_vblnk;
    in_band   = (s1_vcount >= band_lo) && (s1_vcount <= band_hi);
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        vga_out.hblnk <= '0; vga_out.vblnk <= '0;
        vga_out.hsync <= '0; vga_out.vsync <= '0;
        vga_out.vcount <= '0; vga_out.hcount <= '0;
        vga_out.rgb <= '0;
    end
    else begin
        vga_out.hblnk <= s1_hblnk; vga_out.vblnk <= s1_vblnk;
        vga_out.hsync <= s1_hsync; vga_out.vsync <= s1_vsync;
        vga_out.vcount <= s1_vcount; vga_out.hcount <= s1_hcount;
        vga_out.rgb <= (in_active && in_band) ? SIGNAL_COLOUR : s1_rgb;
    end
end

endmodule
