// top_ecg.sv
module top_ecg (
        input  logic clk_100MHz,
        input  logic clk_65MHz,
        input  logic rst_n,
        inout  logic ps2_clk,
        inout  logic ps2_data,
        inout wire i2c_sda,
        output wire i2c_scl,
        output logic vs,
        output logic hs,
        output logic [3:0] r,
        output logic [3:0] g,
        output logic [3:0] b
    );

    timeunit 1ns;
    timeprecision 1ps;
    /*
     * INTER-MODULAR CONNECTIONS
    */
    wire start_sampling;
    wire data_ready;
    wire data_write_enable;
    wire data_ready_notch;
    wire data_ready_baseline;
    wire data_filtered_0;
    wire [15:0] filtered_data_0; //after bandpass fir filter
    wire [15:0] filtered_data_1; //after notch fir filter
    wire [15:0] data_baseline;
    wire [11:0] display_data; 
    wire [9:0] read_address;
    wire [11:0] ecg_data_read;
    wire [15:0] ecg_data_received;
    wire [11:0] x_pos;
    wire [11:0] y_pos;

    logic [23:0] mouse_cords_s1;
    logic [23:0] mouse_cords_s2;

    vga_if if_tim();
    vga_if if_grid();
    vga_if if_render();
    vga_if if_mouse();

    assign vs = if_mouse.vsync;
    assign hs = if_mouse.hsync;
    assign {r,g,b} = if_mouse.rgb; 

    /*
     * INSTANCES OF MODULES
    */
    vga_timing u_vga_timing (
        .clk     (clk_65MHz),
        .rst_n   (rst_n),
        .vga_out (if_tim) 
    );

    draw_grid u_draw_grid (
        .clk      (clk_65MHz),
        .rst_n    (rst_n),
        .vga_in   (if_tim),
        .vga_out  (if_grid)
    );

    sampling_timer u_sampling_timer (
        .clk            (clk_100MHz),
        .rst_n          (rst_n),
        .start_sampling (start_sampling)
    );

    i2c_master u_i2c_master (
        .clk     (clk_100MHz),
        .rst_n   (rst_n),
        .start_sampling (start_sampling),
        .SDA     (i2c_sda),
        .SCL     (i2c_scl),
        .adc_data(ecg_data_received),
        .data_ready(data_ready)
    );

    /*
     * FIR BANDPASS FILTER INSTANCE FROM IP CATALOG
    */
    fir_compiler_0 u_fir_compiler_0 (
        .aclk(clk_100MHz),                              // input wire clk
        .s_axis_data_tvalid(data_ready),  // input wire s_axis_data_tvalid
        .s_axis_data_tready(),  // output wire s_axis_data_tready
        .s_axis_data_tdata(ecg_data_received),    // input wire [15 : 0] s_axis_data_tdata
        .m_axis_data_tvalid(data_filtered_0),  // output wire m_axis_data_tvalid
        .m_axis_data_tdata(filtered_data_0)    // output wire [15 : 0] m_axis_data_tdata
    );

    /*
     * FIR NOTCH FILTER INSTANCE FROM IP CATALOG
    */
    fir_compiler_notch u_fir_compiler_notch (
        .aclk(clk_100MHz),                              // input wire aclk
        .s_axis_data_tvalid(data_filtered_0),  // input wire s_axis_data_tvalid
        .s_axis_data_tready(),  // output wire s_axis_data_tready
        .s_axis_data_tdata(filtered_data_0),    // input wire [15 : 0] s_axis_data_tdata
        .m_axis_data_tvalid(data_ready_notch),  // output wire m_axis_data_tvalid
        .m_axis_data_tdata(filtered_data_1)    // output wire [15 : 0] m_axis_data_tdata
    );

    /*
     * BASELINE RESTORE: ADJUST BASELINE LEVEL TO COMPENASTE OFFSET WANDERING
    */
    baseline_restore u_baseline_restore (
        .clk(clk_100MHz),
        .rst_n(rst_n),
        .sample_valid_in(data_ready_notch),
        .data_in(filtered_data_1),
        .data_out(data_baseline),
        .sample_valid_out(data_ready_baseline)
    );

    /*
     * VGA FORMAT: PREPARE SIGNAL FOR DISPLAY ON VGA
    */
    vga_formatter u_vga_formatter (
        .clk(clk_100MHz),
        .rst_n(rst_n),
        .sample_valid_in(data_ready_baseline),
        .data_in(data_baseline),
        .data_out(display_data),
        .data_ready(data_write_enable)
    );

    ring_buffer u_ring_buffer (
        .clk_read(clk_65MHz),
        .clk_write(clk_100MHz),
        .rst_n(rst_n),
        .write_enable(data_write_enable),
        .ecg_data_write(display_data),
        .read_address(read_address),
        .ecg_data_read(ecg_data_read)
    );

    render_signal u_render_signal (
        .clk(clk_65MHz),
        .rst_n(rst_n),
        .ecg_data_read(ecg_data_read),
        .vga_in(if_grid),
        .vga_out(if_render),
        .read_address(read_address)
    );

    /*
     * 100MHz to 65MHz 2 stage pipeline
    */
   always_ff @(posedge clk_65MHz or negedge rst_n) begin
        if (!rst_n) begin
            mouse_cords_s1 <= '0;  
            mouse_cords_s2 <= '0;
        end
        else begin
            mouse_cords_s1 <= {x_pos,y_pos};
            mouse_cords_s2 <= mouse_cords_s1;
        end
   end

   /*
    * MOUSE
   */
    MouseCtl u_MouseCtl (
        .clk      (clk_100MHz),
        .rst      (!rst_n),
        .ps2_clk  (ps2_clk),
        .ps2_data (ps2_data),
        .xpos     (x_pos),
        .ypos     (y_pos),

        //MouseCtl module unused outputs
        .zpos     (),
        .left     (),
        .middle   (),
        .right    (),
        .new_event(),

        //MouseCtl module unused inputs
        .value    (12'b0),
        .setx     (1'b0),
        .sety     (1'b0),
        .setmax_x (1'b0),
        .setmax_y (1'b0)
    );
   draw_mouse u_draw_mouse (
        .clk(clk_65MHz),
        .rst_n(rst_n),
        .x_start(mouse_cords_s2[23:12]),
        .y_start(mouse_cords_s2[11:0]),
        .vga_in(if_render),
        .vga_out(if_mouse)
    );


endmodule