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

logic [WIDTH-3:0] prescaled_ecg_data;

/*
 * this function draw ecg signal
*/

function automatic logic [11:0] draw_ecg (
    input logic [WIDTH-3:0] prescaled_ecg_data,
    input logic [11:0] rgb_bg,
    input logic [11:0] vcount
);

localparam [11:0] signal_colour = 12'hf_0_0;
localparam [2:0] line_width = 3'd2;

logic [11:0] mapped_y = 12'd768 - prescaled_ecg_data; //y axis is upside down (negative)

logic width_overflow = (mapped_y > line_width) ? 1'b1 : 1'b0; //overflow check

if((width_overflow & (vcount >= (mapped_y - line_width)) && (vcount <= (mapped_y + line_width)))
    | !(width_overflow) & (vcount == mapped_y)) begin
    return signal_colour;
end
else begin
    return rgb_bg;
end
endfunction

//vga interface pipeline buffer
logic hblnk_buffer;
logic vblnk_buffer;
logic hsync_buffer;
logic vsync_buffer;
logic [11:0] vcount_buffer;
logic [11:0] hcount_buffer;
logic [11:0] rgb_buffer;

//2 stage pipeline | 2 clock cycles delay
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        hblnk_buffer <= '0; vblnk_buffer <= '0;
        hsync_buffer <= '0; vsync_buffer <= '0;
        vcount_buffer <= '0; hcount_buffer <= '0;
        rgb_buffer <= '0;

        vga_out.hblnk <= '0; vga_out.vblnk <= '0;
        vga_out.hsync <= '0; vga_out.vsync <= '0;
        vga_out.vcount <= '0; vga_out.hcount <= '0;
        vga_out.rgb <= '0;
    end
    else begin
        hblnk_buffer <= vga_in.hblnk; vblnk_buffer <= vga_in.vblnk;
        hsync_buffer <= vga_in.hsync; vsync_buffer <= vga_in.vsync;
        vcount_buffer <= vga_in.vcount; hcount_buffer <= vga_in.hcount;
        rgb_buffer <= vga_in.rgb;

        vga_out.hblnk <= hblnk_buffer; vga_out.vblnk <= vblnk_buffer;
        vga_out.hsync <= hsync_buffer; vga_out.vsync <= vsync_buffer;
        vga_out.vcount <= vcount_buffer; vga_out.hcount <= hcount_buffer;
        vga_out.rgb <= draw_ecg(prescaled_ecg_data, rgb_buffer, vcount_buffer); //rendering
    end
end

always_comb begin
    read_address = vga_in.hcount[ADDR-1:0];
    prescaled_ecg_data = ecg_data_read[WIDTH-1:2]; //prescaling ecg_data by dividing by 4 
end

endmodule