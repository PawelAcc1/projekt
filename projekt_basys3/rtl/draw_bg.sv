// vga_bg.sv
module draw_bg (
        input  logic clk,
        input  logic rst_n,
        vga_if.in    vga_in,
        vga_if.out   vga_out
    );

    timeunit 1ns;
    timeprecision 1ps;

    import vga_pkg::*;

    logic [11:0] rgb_nxt;
    logic [11:0] pixel_c1;
    logic [11:0] pixel_c2;  

    always_ff @(posedge clk or negedge rst_n) begin : bg_ff_blk
        if (!rst_n) begin
            vga_out.vcount <= '0;
            vga_out.vsync  <= '0;
            vga_out.vblnk  <= '0;
            vga_out.hcount <= '0;
            vga_out.hsync  <= '0;
            vga_out.hblnk  <= '0;
            vga_out.rgb    <= '0;
        end else begin
            vga_out.vcount <= vga_in.vcount;
            vga_out.vsync  <= vga_in.vsync;
            vga_out.vblnk  <= vga_in.vblnk;
            vga_out.hcount <= vga_in.hcount;
            vga_out.hsync  <= vga_in.hsync;
            vga_out.hblnk  <= vga_in.hblnk;
            vga_out.rgb    <= rgb_nxt;
        end
    end

function automatic logic [11:0] c_letter(
    input logic [10:0] hcount_c,
    input logic [10:0] vcount_c,
    input logic [10:0] h_offset,
    input logic [10:0] v_offset,
    input logic [11:0] c_colour
);
    localparam bg_colour = 12'h8_8_8;
    localparam width = 5;

    logic [10:0] local_h;
    logic [10:0] local_v;

    local_h = hcount_c - h_offset;
    local_v = vcount_c - v_offset;
    
    if((local_v >= (175 - width) && local_v <= (175 + width)) || 
       (local_v >= (275 - width) && local_v <= (275 + width))) begin
        if(local_h >= 475 && local_h <= 525) begin
            return c_colour;
        end
    end
    else if(local_v >= 175 && local_v <= 275) begin
        if(local_h >= (475 - width) && local_h <= (475 + width)) begin
            return c_colour;
        end
    end
    else if((local_v >= 175 && local_v <= 195) || 
            (local_v >= 255 && local_v <= 275)) begin
        if(local_h >= (525 - width) && local_h <= (525 + width)) begin
            return c_colour;
        end
    end
    
    return bg_colour;
endfunction

function automatic logic [11:0] j_letter(
    input logic [10:0] hcount_j,
    input logic [10:0] vcount_j
);
    localparam j_colour = 12'h6_f_0;
    localparam bg_colour = 12'h8_8_8;
    localparam width = 5;

    if(vcount_j >= 175 - width && vcount_j <= 175 + width) begin
        if(hcount_j >= 275 && hcount_j <= 325) return j_colour;
    end
    else if(hcount_j >= 325 - width && hcount_j <= 325 + width) begin
        if(vcount_j >= 175 && vcount_j <= 275) return j_colour;
    end
    else if(vcount_j >= 275 - width && vcount_j <= 275 + width) begin
        if(hcount_j >= 275 && hcount_j <= 325) return j_colour;
    end
    else if(hcount_j >= 275 - width && hcount_j <= 275 + width) begin
        if(vcount_j >= 250 && vcount_j <= 275) return j_colour;
    end

    return bg_colour;
endfunction

function automatic logic [11:0] p_letter(
    input logic [10:0] hcount_p,
    input logic [10:0] vcount_p
);
    localparam p_colour = 12'h0_f_f; 
    localparam bg_colour = 12'h8_8_8;
    localparam width = 5;

    if(hcount_p >= 275 - width && hcount_p <= 275 + width) begin
        if(vcount_p >= 325 && vcount_p <= 425) begin
            return p_colour;
        end
    end
    else if((vcount_p >= 325 - width && vcount_p <= 325 + width) || (vcount_p >= 375 - width && vcount_p <= 375 + width)) begin
        if(hcount_p >= 275 && hcount_p <= 325) begin
            return p_colour;
        end
    end
    else if(hcount_p >= 325 - width && hcount_p <= 325 + width) begin
        if(vcount_p >= 325 && vcount_p <= 375) begin
            return p_colour;
        end
    end
    
    return bg_colour;
endfunction 

function automatic logic [11:0] b_letter(
    input logic [10:0] hcount_b,
    input logic [10:0] vcount_b
);
    localparam b_colour = 12'hf_8_0;
    localparam bg_colour = 12'h8_8_8;
    localparam width = 5;

    if(hcount_b >= 475 - width && hcount_b <= 475 + width) begin
        if(vcount_b >= 325 && vcount_b <= 425) return b_colour;
    end
    else if((vcount_b >= 325 - width && vcount_b <= 325 + width) || 
            (vcount_b >= 375 - width && vcount_b <= 375 + width) || 
            (vcount_b >= 425 - width && vcount_b <= 425 + width)) begin
        if(hcount_b >= 475 && hcount_b <= 525) return b_colour;
    end
    else if(hcount_b >= 525 - width && hcount_b <= 525 + width) begin
        if(vcount_b >= 325 && vcount_b <= 425) return b_colour;
    end

    return bg_colour;
endfunction

    always_comb begin : bg_comb_blk
        pixel_c1 = c_letter(vga_in.hcount, vga_in.vcount, 0, 0, 12'hf_8_1);

        pixel_c2 = c_letter(vga_in.hcount, vga_in.vcount, 50, 0, 12'hf_8_a);

        if (vga_in.vblnk || vga_in.hblnk) begin            
            rgb_nxt = 12'h0_0_0;                    
        end else begin                              
            if (vga_in.vcount == 0)                    
                rgb_nxt = 12'hf_f_0;                
            else if (vga_in.vcount == VER_PIXELS - 1)   
                rgb_nxt = 12'hf_0_0;                
            else if (vga_in.hcount == 0)                
                rgb_nxt = 12'h0_f_0;                
            else if (vga_in.hcount == HOR_PIXELS - 1)   
                rgb_nxt = 12'h0_0_f;                
                else if ((vga_in.hcount >= 200 && vga_in.hcount <= 400) && (vga_in.vcount >= 150 && vga_in.vcount <= 300)) begin
                    rgb_nxt = j_letter(vga_in.hcount, vga_in.vcount);
                end
                else if ((vga_in.hcount >= 400 && vga_in.hcount <= 800) && (vga_in.vcount >= 0 && vga_in.vcount <= 300)) begin
            
                    if (pixel_c1 != 12'h8_8_8) begin
                        rgb_nxt = pixel_c1;         
                    end 
                    else if (pixel_c2 != 12'h8_8_8) begin
                        rgb_nxt = pixel_c2;        
                    end 
                    else begin
                        rgb_nxt = 12'h8_8_8;        
                    end

                end
                else if ((vga_in.hcount >= 200 && vga_in.hcount <= 400) && (vga_in.vcount >= 300 && vga_in.vcount <= 450)) begin
                    rgb_nxt = p_letter(vga_in.hcount, vga_in.vcount);
                end
                else if ((vga_in.hcount >= 400 && vga_in.hcount <= 600) && (vga_in.vcount >= 300 && vga_in.vcount <= 450)) begin
                    rgb_nxt = b_letter(vga_in.hcount, vga_in.vcount);
                end
    
                else                                    
                    rgb_nxt = 12'h8_8_8;                
        end
    end

endmodule