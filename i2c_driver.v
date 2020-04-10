// --------------------------------------------------------------------
// Copyright (c) 2019 by MicroPhase Technologies Inc. 
// --------------------------------------------------------------------
//
// Permission:
//
//   MicroPhase grants permission to use and modify this code for use
//   in synthesis for all MicroPhase Development Boards.
//   Other use of this code, including the selling 
//   ,duplication, or modification of any portion is strictly prohibited.
//
// Disclaimer:
//
//   This VHDL/Verilog or C/C++ source code is intended as a design reference
//   which illustrates how these types of functions can be implemented.
//   It is the user's responsibility to verify their design for
//   consistency and functionality through the use of formal
//   verification methods.  MicroPhase provides no warranty regarding the use 
//   or functionality of this code.
//
// --------------------------------------------------------------------
//           
//                     MicroPhase Technologies Inc
//                     Shanghai, China
//
//                     web: http://www.microphase.cn/   
//                     email: support@microphase.cn
//
// --------------------------------------------------------------------
// --------------------------------------------------------------------
//
// Major Functions: 
//
// --------------------------------------------------------------------
// --------------------------------------------------------------------
//
//  Revision History:
//  Date          By            Revision    Change Description
//---------------------------------------------------------------------
//2019-12-07      Chaochen Wei  1.0          Original
//2019/                         1.1          
// --------------------------------------------------------------------
// --------------------------------------------------------------------

`timescale 1ns / 1ps
module i2c_driver(
    input   wire            clk     ,//ϵͳʱ��
    input   wire            rst     ,//ϵͳ��λ
    input   wire            wr_req  ,//д�����ź�
    input   wire            rd_req  ,//�������ź�
    input   wire            start   ,//һ�ζ�д��ʼ�ź�
    input   wire    [7:0]   dev_addr,//�豸��ַ
    input   wire    [7:0]   mem_addr,//�Ĵ�����ַ
    input   wire    [7:0]   wr_data ,//д��Ĵ���������

    output  reg     [7:0]   rd_data ,//�ӼĴ�������������
    output  reg             rd_done ,//һ�ζ���������
    output  reg             wr_done ,//һ��д��������
    output 	reg 			err_flag,//���������ź�
    output  reg             scl     ,//i2cʱ��
    inout   wire            sda      //i2c��������   
    );

//==================================================
//parameter define
//==================================================
parameter   IDLE    = 10'b00_0000_0001;//����״̬
parameter   WR_START= 10'b00_0000_0010;//д��ʼ
parameter   WR_DEV  = 10'b00_0000_0100;//ȷ���豸��ַ
parameter   WR_MEM  = 10'b00_0000_1000;//ȷ�ϼĴ�����ַ
parameter   WR_DATA = 10'b00_0001_0000;//д����
parameter   RD_START= 10'b00_0010_0000;//����ʼ
parameter   RD_DEV  = 10'b00_0100_0000;//�豸��ַ������
parameter   RD_DATA = 10'b00_1000_0000;//������
parameter   STOP    = 10'b01_0000_0000;//ֹͣ
parameter	ERROR	= 10'b10_0000_0000;//����


parameter   SYS_CYCLE = 20;//ϵͳʱ��50M
parameter   IIC_CYCLE = 5000;//IIC ����Ƶ��200K
parameter   MAX      = (IIC_CYCLE/SYS_CYCLE) -1;//����ʱ�ӵļ������ֵ
parameter   T_HIGH   = 2000 ;//I2Cʱ�Ӹߵ�ƽ
parameter   T_LOW    = 3000 ;//I2Cʱ�ӵ͵�ƽ

parameter   FLAG0 = ((T_HIGH/SYS_CYCLE)>>1) - 1;//SCL�ߵ�ƽ�е�
parameter   FLAG1 = (T_HIGH/SYS_CYCLE) - 1;//SCL�½���
parameter   FLAG2  = (T_HIGH/SYS_CYCLE) + ((T_LOW/SYS_CYCLE)>>1) -1;//SCL�͵�ƽ�е�
parameter   FLAG3  = (T_HIGH/SYS_CYCLE) + (T_LOW/SYS_CYCLE) - 1;//SCL������
//==================================================
//internal signals
//==================================================
reg     [2:0]   cnt_freq    ;//����drive_flag ����I2Cʱ��
wire            add_cnt_freq;
wire            end_cnt_freq;


reg     [5:0]   cnt_flag    ;//������ǰ״̬�ж��ٸ�drive_flag
wire            add_cnt_flag;
wire            end_cnt_flag;
reg     [5:0]   x           ;//�ɱ�����������ֵ

reg     [9:0]   cnt         ;//�������������ź�drive_flag
wire            add_cnt     ;
wire            end_cnt     ;

reg             drive_flag  ;//����������ģ�鹤�����ź�
reg     [8:0]   state       ;//state register
reg             work_flag   ;//work flag
reg             wr_en       ;//��̬������дʹ��
reg     [7:0]   data_shift  ;//��λ�Ĵ���
reg 			ack_flag	;//��Ӧ�ź�

reg             wr_sda      ;
wire            rec_sda     ;

//��̬�˿�����
assign  sda = wr_en?wr_sda:1'bz;//������������������������д����ʱ��wr_en=1�������û����ݣ�����������ʱ����Ϊ����
assign  rec_sda = sda;
//--------------------state machine define--------------------
always @(posedge clk)begin
    if(rst == 1'b1)begin
        state <= IDLE;
    end
    else begin
        case(state)
            IDLE:begin
                if(start==1'b1 && (wr_req==1'b1 || rd_req==1'b1))
                    state <= WR_START;//���յ���ʼ�źţ�������ʼ״̬
                else
                    state <= IDLE;
            end

            WR_START:begin
                if(cnt_flag=='d6 && drive_flag)
                    state <= WR_DEV;//��ʼ״̬����������ȷ���豸��ַ״̬
                else
                    state <= WR_START;
            end

            WR_DEV:begin
                if(cnt_flag=='d35 && drive_flag && ack_flag==1'b1)//�������豸��ַ��������ȷ���յ���Ӧ
                    state <= WR_MEM;//ȷ�ϵ�ַ״̬����������ȷ�ϼĴ�����ַ״̬
                else if(cnt_flag=='d35 && drive_flag && ack_flag==1'b0)//�������豸��ַ������û�н��յ���Ӧ
                    state <= ERROR;//ȷ�ϵ�ַ״̬����������ȷ�ϼĴ�����ַ״̬
                else
                    state <= WR_DEV;
            end

            WR_MEM:begin
                if(cnt_flag=='d35 && drive_flag && ack_flag==1'b1)begin//�Ѿ�����д��ļĴ�����������ȷ���յ���Ӧ
                    if(wr_req==1'b1)
                        state <= WR_DATA;//ȷ�ϼĴ�����ַ״̬����������д����״̬
                    else if(wr_req==1'b0 && rd_req==1'b1)
                        state <= RD_START;//ȷ�ϼĴ�����ַ״̬����������д��ʼ״̬
                end
                else if(cnt_flag=='d35 && drive_flag && ack_flag==1'b0)//�������豸��ַ������û�н��յ���Ӧ
                    state <= ERROR;//ȷ�ϵ�ַ״̬����������ȷ�ϼĴ�����ַ״̬
                else 
                    state <= WR_MEM;
            end

            WR_DATA:begin
                if(cnt_flag=='d35 && drive_flag && ack_flag==1'b1)//�Ѿ�����д�����ݲ���ȷ���յ���Ӧ
                    state <= STOP;//����д����ɽ���ֹͣ״̬
                else if(cnt_flag=='d35 && drive_flag && ack_flag==1'b0)//�������豸��ַ������û�н��յ���Ӧ
                    state <= ERROR;//ȷ�ϵ�ַ״̬����������ȷ�ϼĴ�����ַ״̬
                else
                    state <= WR_DATA;
            end

            RD_START:begin
                if(cnt_flag=='d3 && drive_flag && rd_req)
                    state <= RD_DEV;//�����豸��ַ������
                else
                    state <= RD_START;
            end

            RD_DEV:begin
                if(cnt_flag=='d35 && drive_flag && ack_flag==1'b1)
                    state <= RD_DATA;//���������״̬
                else if(cnt_flag=='d35 && drive_flag && ack_flag==1'b0)//�������豸��ַ������û�н��յ���Ӧ
                    state <= ERROR;//ȷ�ϵ�ַ״̬����������ȷ�ϼĴ�����ַ״̬
                else
                    state <= RD_DEV;
            end

            RD_DATA:begin
                if(cnt_flag=='d35 && drive_flag && ack_flag==1'b1)
                    state <= STOP;
                else if(cnt_flag=='d35 && drive_flag && ack_flag==1'b0)//�������豸��ַ������û�н��յ���Ӧ
                    state <= ERROR;//ȷ�ϵ�ַ״̬����������ȷ�ϼĴ�����ַ״̬
                else
                    state <= RD_DATA;
            end

            STOP:begin
                if(cnt_flag=='d3 && drive_flag)
                    state <= IDLE;
                else
                    state <= STOP;
            end

            ERROR:begin
            	state <= IDLE;
            end

            default:begin
                state <= IDLE;
            end
        endcase
    end
end

//-------------------work_flag---------------------
always @(posedge clk)begin
    if(rst == 1'b1)begin
        work_flag <= 1'b0;
    end
    else if(state==WR_START)begin//���յ���ʼ�ź�
        work_flag <= 1'b1;
    end
    else if(state==IDLE)begin
        work_flag <= 1'b0;
    end
    else if(wr_done==1'b1 || rd_done==1'b1)begin//һ�ζ�д���
        work_flag <= 1'b0;
    end
end

//--------------------cnt--------------------
always @(posedge clk)begin
    if(rst==1'b1)begin
        cnt <= 0;
    end
    else if(add_cnt)begin
        if(end_cnt)
            cnt <= 0;
        else
            cnt <= cnt + 1'b1;
    end
    else begin
        cnt <= 'd0;
    end
end

assign add_cnt = work_flag;//���ڹ���״̬ʱһֱ����       
assign end_cnt = add_cnt && cnt== MAX;//���������ֵ����

//--------------------drive_flag--------------------
always @(posedge clk)begin
    if(rst == 1'b1)begin
        drive_flag <= 1'b0;
    end
    else if(cnt==FLAG0 || cnt==FLAG1 || cnt==FLAG2 || cnt==FLAG3)begin//����һ�������ź�
        drive_flag <= 1'b1;
    end
    else begin
        drive_flag <= 1'b0;
    end
end

//--------------------cnt_freq--------------------
//�������źŽ��м������Դ�������I2Cʱ��
always @(posedge clk)begin
    if(rst==1'b1)begin
        cnt_freq <= 0;
    end
    else if(work_flag == 1'b0)begin
    	cnt_freq <= 'd0;
    end
    else if(add_cnt_freq)begin
        if(end_cnt_freq)
            cnt_freq <= 0;
        else
            cnt_freq <= cnt_freq + 1'b1;
    end
    else begin
        cnt_freq <= cnt_freq;
    end
end

assign add_cnt_freq = drive_flag;       
assign end_cnt_freq = add_cnt_freq && cnt_freq== 4-1; 

//--------------------scl--------------------
always @(posedge clk)begin
    if(rst == 1'b1)begin
        scl <= 1'b1;
    end
    else if(work_flag==1'b1)begin
        if(cnt_freq=='d1 && drive_flag &&state==STOP)begin
            scl <= 1'b1;
        end
        else if(cnt_freq=='d1 && drive_flag && state!= STOP)begin
            scl <= 1'b0;
        end
        else if(cnt_freq=='d3 && drive_flag)begin
            scl <= 1'b1;
        end
    end
    else begin
        scl <= 1'b1;
    end
end

//--------------------cnt_flag--------------------
//������ǰ״̬���ж��ٸ�drive_flag
always @(posedge clk)begin
    if(rst==1'b1)begin
        cnt_flag <= 0;
    end
    else if(work_flag==1'b0)begin
    	cnt_flag <= 'd0;
    end
    else if(add_cnt_flag)begin
        if(end_cnt_flag)
            cnt_flag <= 0;
        else
            cnt_flag <= cnt_flag + 1'b1;
    end
    else begin
        cnt_flag <= cnt_flag;
    end
end

assign add_cnt_flag = drive_flag;       
assign end_cnt_flag = add_cnt_flag && cnt_flag== x ; 

//--------------------x--------------------
//xΪ��ͬ״̬�£��������ļ������ֵ
always  @(*)begin
    case(state)
        IDLE: x=0;
        WR_START: x= 7 - 1;
        WR_DEV,WR_MEM,WR_DATA,RD_DEV,RD_DATA: x=36 - 1;
        RD_START: x= 4 - 1;
        STOP: x = 4 - 1;
        default: x = 0;          
    endcase
end

//------------------wr_en----------------------
always @(posedge clk)begin
    if(rst == 1'b1)begin
        wr_en <= 1'b0;
    end
    else if(state==WR_START || state==RD_START || state==STOP)begin
        wr_en <= 1'b1;//��д��ʼ������ʼ���ͽ���״̬�����û������������ߣ�������ʼ����ֹͣ�źţ�����д����ʹ����Ч
    end
    else if(state==WR_DEV || state==WR_MEM ||state==WR_DATA || state==RD_DEV)begin
        if(cnt_flag < 'd32)begin//�����û�����ʱ��д����ʹ����Ч
            wr_en <= 1'b1;
        end
        else begin
            wr_en <= 1'b0;//�ȴ����豸��Ӧʱ��д����ʹ����Ч
        end
    end
    else if(state==RD_DATA)begin
        if(cnt_flag < 'd32)begin
            wr_en <= 1'b0;//��������״̬����ʱ�ɴӻ��������ݸ�������д����ʹ����Ч
        end
        else begin
            wr_en <= 1'b1;//����������ɣ�������Ҫ�Դӻ�����Ӧ��д����ʹ����Ч
        end
    end
    else begin
        wr_en <= 1'b0;
    end
end

//--------------------data_shift--------------------
always @(posedge clk)begin
    if(rst == 1'b1)begin
        data_shift <= 'd0;
    end
    else begin
        case(state)
            IDLE:begin
                data_shift <= 'd0;//����״̬������λ�Ĵ�������Ϊ0
            end

            WR_START:begin
                data_shift <= {dev_addr[7:1],1'b0};//д��ʼ״̬�������豸дָ��
            end

            WR_DEV:begin
                if(end_cnt_flag && ack_flag==1'b1)
                    data_shift <= mem_addr;//ȷ���豸״̬����ʱ�������Ĵ�����ַ
                else if(cnt_flag<'d32 && cnt_flag[1:0]==2'd3 && drive_flag)
                    data_shift <= {data_shift[6:0],1'b0};
            end

            WR_MEM:begin
                if(end_cnt_flag && ack_flag==1'b1 && wr_req==1'b1)//��������д����״̬
                    data_shift <= wr_data;//ȷ�ϼĴ�����ַ״̬���������Ҫд�������
                else if(cnt_flag<'d32 && cnt_flag[1:0]==2'd3 && drive_flag)
                    data_shift <= {data_shift[6:0],1'b0};
            end

            WR_DATA:begin
                if(cnt_flag<'d32 && cnt_flag[1:0]==2'd3 && drive_flag)
                    data_shift <= {data_shift[6:0],1'b0};//������д�뵽�Ĵ�����
                else
                   data_shift <= data_shift; 
            end

            RD_START:begin
                data_shift <=  {dev_addr[7:1],1'b1};//����ʼʱ�����������������λ�Ĵ���
            end


            RD_DEV:begin
                if(end_cnt_flag && ack_flag==1'b1)
                    data_shift <= 'd0;
                else if(cnt_flag<'d32 && cnt_flag[1:0]==2'd3 && drive_flag)
                    data_shift <= {data_shift[6:0],1'b0};
            end

            RD_DATA:begin
                if(cnt_flag<'d32 && cnt_flag[1:0]==2'd1 && drive_flag)
                    data_shift <= {data_shift[6:0],rec_sda};//���ӼĴ����ж����������������λ�Ĵ���
                else
                    data_shift <= data_shift;
            end

            default:begin
                data_shift <= data_shift;
            end
        endcase
    end
end



//--------------------wr_sda--------------------
always @(posedge clk)begin
    if(rst == 1'b1)begin
        wr_sda <= 1'b1;
    end
    else begin
        case(state)
            WR_START:begin
                if(cnt_flag=='d4 && drive_flag)
                    wr_sda <= 1'b0;//������ʼλ
                else
                    wr_sda <= wr_sda;
            end

            WR_DEV,WR_MEM,WR_DATA,RD_DEV:begin
                wr_sda <= data_shift[7];//�����ݷ���������������
            end

            RD_START:begin
                if(cnt_flag=='d0)
                    wr_sda <= 1'b1;//��������ʼλ
                else if(cnt_flag=='d1 && drive_flag)
                    wr_sda <= 1'b0;
            end

            RD_DATA:begin
                if(cnt_flag>='d32)
                    wr_sda <= 1'b1;//����NACK
                else
                    wr_sda <= wr_sda;
            end

            STOP:begin
                    if(cnt_flag=='d0 && wr_en)
                        wr_sda <= 1'b0;
                    else if(cnt_flag=='d1 && drive_flag)
                        wr_sda <= 1'b1;
            end
            
            default:wr_sda <= 1'b1;
        endcase
    end
end

//--------------------wr_done,rd_done--------------------
always @(posedge clk)begin
    if(rst == 1'b1)begin
        wr_done <= 1'b0;
        rd_done <= 1'b0;
    end
    else if(state==STOP && end_cnt_flag)begin//�����������ζ�д������ʱ�򣬲�������ź�
        if(wr_req==1'b1)
            wr_done <= 1'b1;
        else if(wr_req==1'b0 && rd_req==1'b1)
            rd_done <= 1'b1;
    end
    else begin
        wr_done <= 1'b0;
        rd_done <= 1'b0;
    end
end

//--------------------ack_flag--------------------
//�Ƿ���յ�ACK���߲���NACK
always @(posedge clk)begin
    if(rst == 1'b1)begin
    	ack_flag <= 1'b0;
    end
    else begin
    	case(state)
    		WR_DEV:begin
    			if(cnt_flag>='d32 && cnt_flag[1:0]=='d1 && drive_flag && sda==1'b0)
    				ack_flag <= 1'b1;//д���豸��ַ�����ҽ��յ���Ӧ
    			else if(end_cnt_flag)
    				ack_flag <= 1'b0;
    		end

    		WR_MEM:begin
    			if(cnt_flag>='d32 && cnt_flag[1:0]=='d1 && drive_flag && sda==1'b0)
    				ack_flag <= 1'b1;//д��Ĵ�����ַ�����յ���Ӧ
    			else if(end_cnt_flag)
    				ack_flag <= 1'b0;
    		end

    		WR_DATA:begin
    			if(cnt_flag>='d32 && cnt_flag[1:0]=='d1 && drive_flag && sda==1'b0)
    				ack_flag <= 1'b1;//д�����ݣ����ҽ��յ���Ӧ
    			else if(end_cnt_flag)
    				ack_flag <= 1'b0;
    		end

    		RD_DEV:begin
    			if(cnt_flag>='d32 && cnt_flag[1:0]=='d1 && drive_flag && sda==1'b0)
    				ack_flag <= 1'b1;//��ָ�����ϣ����յ���Ӧ
    			else if(end_cnt_flag)
    				ack_flag <= 1'b0;
    		end

    		RD_DATA:begin
    			if(cnt_flag>='d32 && cnt_flag[1:0]=='d1 && drive_flag && sda==1'b1)
    				ack_flag <= 1'b1;//����ȫ�����꣬��������NACK
    			else if(end_cnt_flag)
    				ack_flag <= 1'b0;
    		end

    		default: ack_flag <= 1'b0;
    	endcase
    end
end

//--------------------rd_data--------------------
always @(posedge clk)begin
    if(rst == 1'b1)begin
        rd_data <= 1'b0;
    end
    else if(rd_done)begin//�����������ζ�д������ʱ�򣬲�������ź�
    	rd_data <= data_shift;
    end
    else begin
        rd_data <= rd_data;
    end
end

always @(posedge clk)begin
    if(rst == 1'b1)begin
        err_flag <= 1'b0;
    end
    else if(state==ERROR)begin//�����������ζ�д������ʱ�򣬲�������ź�
    	err_flag <= 1'b1;
    end
    else begin
        err_flag <= 1'b0;
    end
end

endmodule
