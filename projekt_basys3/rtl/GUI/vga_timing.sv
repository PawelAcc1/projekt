module vga_timing (
        input  logic clk,
        input  logic rst_n,
        vga_if.out   vga_out
    );

    timeunit 1ns;
    timeprecision 1ps;

    import vga_pkg::*;
    
    logic [11:0] vcount, hcount;
    logic vsync, vblnk, hsync, hblnk;

    logic [11:0] vcount_nxt, hcount_nxt;
    logic vsync_nxt, vblnk_nxt, hsync_nxt, hblnk_nxt;

    assign vga_out.vcount = vcount;
    assign vga_out.hcount = hcount;
    assign vga_out.vsync  = vsync;
    assign vga_out.vblnk  = vblnk;
    assign vga_out.hsync  = hsync;
    assign vga_out.hblnk  = hblnk;
    assign vga_out.rgb    = '0; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vcount <= '0;
            vsync  <= '0;
            vblnk  <= '0;
            hcount <= '0;
            hsync  <= '0;
            hblnk  <= '0;
        end else begin
            vcount <= vcount_nxt;
            vsync  <= vsync_nxt;
            vblnk  <= vblnk_nxt;
            hcount <= hcount_nxt;
            hsync  <= hsync_nxt;
            hblnk  <= hblnk_nxt; 
        end
    end

    always_comb begin
        hcount_nxt = hcount;
        vcount_nxt = vcount;
        vsync_nxt  = vsync;
        vblnk_nxt  = vblnk;

        if (hcount < HOR_TOTAL_TIME - 1) begin
            hcount_nxt = hcount + 1;
        end else begin
            hcount_nxt = '0;
            vblnk_nxt  = ((vcount >= (VER_BLANK_START - 1)) && (vcount < VER_TOTAL_TIME - 1));
            vsync_nxt  = ((vcount >= (VER_SYNC_START - 1)) && (vcount < VER_SYNC_START + VER_SYNC_TIME - 1));
            if (vcount < VER_TOTAL_TIME - 1) begin
                vcount_nxt = vcount + 1;
            end else begin
                vcount_nxt = '0;
            end
        end
        hblnk_nxt = ((hcount >= HOR_BLANK_START - 1) && (hcount < HOR_TOTAL_TIME - 1));
        hsync_nxt = (hcount >= (HOR_SYNC_START - 1)  && (hcount < HOR_SYNC_START + HOR_SYNC_TIME - 1));
    end

endmodule