// top_ecg.sv
module top_ecg (
        input  logic clk_100MHz,
        input  logic clk_65MHz,
        input  logic rst_n,
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
    wire data_filtered_0;
    wire [15:0] filtered_data_0; //after bandpass fir filter
    wire [15:0] filtered_data_1; //after notch fir filter
    wire [9:0] read_address;
    wire [11:0] ecg_data_read;
    wire [15:0] ecg_data_received;

    vga_if if_tim();
    vga_if if_grid();
    vga_if if_render();

    assign vs = if_render.vsync;
    assign hs = if_render.hsync;
    assign {r,g,b} = if_render.rgb; //zmienic na rect na render

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
    fir_compiler_notch your_instance_name (
        .aclk(clk_100MHz),                              // input wire aclk
        .s_axis_data_tvalid(data_filtered_0),  // input wire s_axis_data_tvalid
        .s_axis_data_tready(),  // output wire s_axis_data_tready
        .s_axis_data_tdata(filtered_data_0),    // input wire [15 : 0] s_axis_data_tdata
        .m_axis_data_tvalid(data_write_enable),  // output wire m_axis_data_tvalid
        .m_axis_data_tready(1'b1),  // input wire m_axis_data_tready
        .m_axis_data_tdata(filtered_data_1)    // output wire [15 : 0] m_axis_data_tdata
    );

    ring_buffer u_ring_buffer (
        .clk_read(clk_65MHz),
        .clk_write(clk_100MHz),
        .rst_n(rst_n),
        .write_enable(data_write_enable),
        .ecg_data_write(filtered_data_1[15:4]),
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


endmodule