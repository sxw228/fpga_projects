`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2020/03/25 09:38:10
// Design Name: 
// Module Name: hdmi_rx_rst_controller
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module hdmi_rx_interface(
    input	wire			clk_50m	,
	input 	wire 			locked 		,
	input 	wire 			hdmi_rx_clk	,//����ʱ��
    input     wire             hdmi_rx_de     ,//����������Ч�ź�
    input     wire               hdmi_rx_vs    ,//���볡ͬ���ź�
    input     wire             hdmi_rx_hs    ,//������ͬ���ź�
    input     wire     [23:0]    hdmi_rd     ,//����Ľ�������
    output  wire             hdmi_rx_rst ,
    output     wire             hdmi_tx_clk    ,
    output     reg             hdmi_tx_de     ,
    output     reg               hdmi_tx_vs    ,
    output     reg             hdmi_tx_hs    ,
    output     reg     [23:0]    hdmi_td     
		
    );
    parameter       CNT_MAX = 26000000;
   
    reg 	[24:0]	cnt 		;
    wire             rst         ;
    wire             ready         ;
    
    reg     [2:0]    rx_de_dd     ;//����������Ч�źŴ�����
    reg     [2:0]    rx_vs_dd    ;//���볡ͬ���źŴ�����
    reg     [2:0]    rx_hs_dd     ;//������ͬ���źŴ�����
    reg     [71:0]    rd_dd         ;//�������ݴ�����
    
    assign rst = ~locked;
    assign hdmi_tx_clk = hdmi_rx_clk;
    assign hdmi_rx_rst = ready;
    
    
    
    
    
    
    always@(posedge clk_50m )begin
        if(locked==1'b0)
            cnt <= 'd0;
        else if(cnt <CNT_MAX)
            cnt <= cnt + 1'b1;
        else
            cnt <= cnt;
    end
    assign  ready = (cnt==CNT_MAX)?1'b1:1'b0;
    
    always @(posedge hdmi_rx_clk) begin
        if (rst==1'b1) begin
            rx_de_dd <=1'b0     ;
            rx_vs_dd <=1'b0    ;
            rx_hs_dd <=1'b0    ;
            rd_dd <='d0    ;
            hdmi_tx_de <= 1'b0    ;//���������Ч�ź�
            hdmi_tx_vs <= 1'b0    ;//�����ͬ���ź�
            hdmi_tx_hs <= 1'b0    ;//�����ͬ���ź�
            hdmi_td <='d0;//�������
        end
        else begin
            rx_de_dd <= {rx_de_dd[1:0],hdmi_rx_de}     ;
            rx_vs_dd <= {rx_vs_dd[1:0],hdmi_rx_vs}    ;
            rx_hs_dd <= {rx_hs_dd[1:0],hdmi_rx_hs}    ;
            rd_dd <= {rd_dd[47:0],hdmi_rd}    ;
            hdmi_tx_de <= rx_de_dd[2]    ;//���������Ч�ź�
            hdmi_tx_vs <= rx_vs_dd[2]    ;//�����ͬ���ź�
            hdmi_tx_hs <= rx_hs_dd[2]    ;//�����ͬ���ź�
            hdmi_td <= rd_dd[71:48];//�������
        end
    end

    
endmodule
