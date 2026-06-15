/*
 * This module provides STEMI detection. STEMI stands for ST-Elevation Myocardial Infarction, which is 
 * ST segment elevation myocardial infarction. This is the most serious and sudden form of heart attack 
 * in which the main coronary artery is completely blocked.
 * 
 * To detect such patology we basically measure baseline level during PQ segment, then after R wave peak detection
 * which belongs to the QRS complex, we wait enough time for S wave to pass by and get to the J point which 
 * defines beginning of ST segment. It is sometimes recommended that ST segment deviation be measured in the J-60 point,
 * or J-80 point, which is located 60 and 80 milliseconds, respectively, after the J point. Therefore we wait enough samples
 * to achieve J-60 point and then we take 8 samples and average them and afterward we compare the average to baseline level.
 * Providing the elevation of ST segment is 0.1mV above the baseline level, we signalize STEMI.
 * 
*/

module stemi_detector #(
    parameter STEMI_THRESHOLD = ,
    parameter DATA_WIDTH = 16,
    parameter 
)(
    input  logic clk,
    input  logic rst_n,
    input logic [DATA_WIDTH-1:0] data_in
);


endmodule