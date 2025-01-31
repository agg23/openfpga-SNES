// Software License Agreement

// The software supplied herewith by Analogue Enterprises Limited (the "Company”),
// the Analogue Pocket Framework (“APF”), is provided and licensed to you, the
// Company's customer, solely for use in designing, testing and creating
// applications for use with Company's Products or Services.  The software is
// owned by the Company and/or its licensors, and is protected under applicable
// laws, including, but not limited to, U.S. copyright law. All rights are
// reserved. By using the APF code you are agreeing to the terms of the End User
// License Agreement (“EULA”) located at [https://www.analogue.link/pocket-eula]
// and incorporated herein by reference. To the extent any use of the APF requires
// application of the MIT License or the GNU General Public License and terms of
// this APF Software License Agreement and EULA are inconsistent with such license,
// the applicable terms of the MIT License or the GNU General Public License, as
// applicable, will prevail.

// THE SOFTWARE IS PROVIDED "AS-IS" AND WE EXPRESSLY DISCLAIM ANY IMPLIED
// WARRANTIES TO THE FULLEST EXTENT PROVIDED BY LAW, INCLUDING BUT NOT LIMITED TO,
// ANY WARRANTY OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE OR
// NON-INFRINGEMENT. TO THE EXTENT APPLICABLE LAWS PROHIBIT TERMS OF USE FROM
// DISCLAIMING ANY IMPLIED WARRANTY, SUCH IMPLIED WARRANTY SHALL BE LIMITED TO THE
// MINIMUM WARRANTY PERIOD REQUIRED BY LAW, AND IF NO SUCH PERIOD IS REQUIRED,
// THEN THIRTY (30) DAYS FROM FIRST USE OF THE SOFTWARE. WE CANNOT GUARANTEE AND
// DO NOT PROMISE ANY SPECIFIC RESULTS FROM USE OF THE SOFTWARE. WITHOUT LIMITING
// THE FOREGOING, WE DO NOT WARRANT THAT THE SOFTWARE WILL BE UNINTERRUPTED OR
// ERROR-FREE.  IN NO EVENT WILL WE BE LIABLE TO YOU OR ANY OTHER PERSON FOR ANY
// INDIRECT, CONSEQUENTIAL, EXEMPLARY, INCIDENTAL, SPECIAL OR PUNITIVE DAMAGES,
// INCLUDING BUT NOT LIMITED TO, LOST PROFITS ARISING OUT OF YOUR USE, OR
// INABILITY TO USE, THE SOFTWARE, EVEN IF WE HAVE BEEN ADVISED OF THE POSSIBILITY
// OF SUCH DAMAGES. UNDER NO CIRCUMSTANCES SHALL OUR LIABILITY TO YOU FOR ANY
// CLAIM OR CAUSE OF ACTION WHATSOEVER, AND REGARDLESS OF THE FORM OF THE ACTION,
// WHETHER ARISING IN CONTRACT, TORT OR OTHERWISE, EXCEED THE AMOUNT PAID BY YOU
// TO US, IF ANY, DURING THE 90 DAY PERIOD IMMEDIATELY PRECEDING THE DATE ON WHICH
// YOU FIRST ASSERT ANY SUCH CLAIM. THE FOREGOING LIMITATIONS SHALL APPLY TO THE
// FULLEST EXTENT PERMITTED BY APPLICABLE LAW.
//
// bridge peripheral for socrates PMP bridge to heraclitus+aristotle
// 2020-2022 Analogue
//
// please note that while writes are immediate,
// reads are buffered by 1 word. this is necessary to maintain
// data throughput while reading from slower data sources like
// sdram.
// reads should always return the current bus value, and kickstart
// into the next read immediately. this way, you have the entire
// next word time to retrieve the data, instead of just a few
// cycles.
//
// the worst-case read/write timing is every 88 cycles @ 74.25mhz
// which is about 1180ns.

module io_bridge_peripheral (

input   wire            clk,
input   wire            reset_n,

input   wire            endian_little,

output  reg     [31:0]  pmp_addr,
output  reg             pmp_addr_valid,
output  reg             pmp_rd,
input   wire    [31:0]  pmp_rd_data,
output  reg             pmp_wr,
output  reg     [31:0]  pmp_wr_data,

inout   reg             phy_spimosi,
inout   reg             phy_spimiso,
inout   reg             phy_spiclk,
input   wire            phy_spiss

);

//
// clock domain: clk (74.25mhz) rising edge
//
    wire reset_n_s;
synch_3 s00(reset_n, reset_n_s, clk);

    wire endian_little_s;
synch_3 s01(endian_little, endian_little_s, clk);

    wire phy_spiss_s, phy_spiss_r, phy_spiss_f;
synch_3 s02(phy_spiss, phy_spiss_s, clk, phy_spiss_r, phy_spiss_f);


    reg [4:0]   state;
    localparam  ST_RESET        = 'd0;
    localparam  ST_IDLE         = 'd1;
    localparam  ST_READ_0       = 'd2;
    localparam  ST_READ_1       = 'd3;
    localparam  ST_READ_2       = 'd4;
    localparam  ST_READ_3       = 'd5;
    localparam  ST_WRITE_0      = 'd6;
    localparam  ST_WRITE_1      = 'd7;
    localparam  ST_WRITE_2      = 'd8;
    localparam  ST_ADDR_0       = 'd9;

    reg [1:0]   addr_cnt;
    reg [1:0]   data_cnt;
    reg [6:0]   read_cnt;

    // synchronize rd byte flag's rising edge into clk
    wire rx_byte_done_s, rx_byte_done_r;
synch_3 s03(rx_byte_done, rx_byte_done_s, clk, rx_byte_done_r);

    reg [4:0]   spis;
    localparam  ST_SIDLE        = 'd1;
    localparam  ST_SEND_N       = 'd6;
    localparam  ST_SEND_0       = 'd2;
    localparam  ST_SEND_1       = 'd3;
    localparam  ST_SEND_2       = 'd4;
    localparam  ST_SEND_3       = 'd5;
    reg         spis_tx;
    reg [31:0]  spis_word_tx;
    reg [31:0]  spis_word;
    reg [4:0]   spis_count;
    reg         spis_done;

    reg         rx_byte_done_r_1, rx_byte_done_r_2;
    reg [7:0]   rx_byte_1, rx_byte_2;

    // handle reversing endianness on both ports
    reg [31:0]   pmp_wr_data_latch;
    reg [31:0]   pmp_rd_data_e; // asynchronous
    reg [31:0]   pmp_rd_data_buf; // buffer the last word for immediate response
always @(*) begin
    pmp_wr_data <= endian_little_s ? {  pmp_wr_data_latch[7:0],
                                        pmp_wr_data_latch[15:8],
                                        pmp_wr_data_latch[23:16],
                                        pmp_wr_data_latch[31:24]
                                    } : pmp_wr_data_latch;

    pmp_rd_data_e <= endian_little_s ? {pmp_rd_data[7:0],
                                        pmp_rd_data[15:8],
                                        pmp_rd_data[23:16],
                                        pmp_rd_data[31:24]
                                    } : pmp_rd_data;
end

always @(posedge clk) begin

    rx_byte_2 <= rx_byte_1;
    rx_byte_1 <= rx_byte;

    rx_byte_done_r_1 <= rx_byte_done_r;
    rx_byte_done_r_2 <= rx_byte_done_r_1;

    case(state)
    ST_RESET: begin
        addr_cnt <= 0;
        data_cnt <= 0;
        pmp_wr <= 0;
        pmp_rd <= 0;
        pmp_addr_valid <= 0;
        spis_tx <= 0;

        state <= ST_ADDR_0;
    end
    ST_ADDR_0: begin
        // transaction has started

        if(rx_byte_done_r_2) begin
            case(addr_cnt)
            0: pmp_addr[31:24] <= rx_byte_2;
            1: pmp_addr[23:16] <= rx_byte_2;
            2: pmp_addr[15: 8] <= rx_byte_2;
            3: begin
                pmp_addr[ 7: 0] <= {rx_byte_2[7:2], 2'b00};
                // address is latched
                if( rx_byte_2[0] ) begin
					data_cnt <= 0;
                    state <= ST_WRITE_0;
                end else begin
                    data_cnt <= 0;
                    read_cnt <= 0;
                    state <= ST_READ_0;
                end
            end
            endcase

            addr_cnt <= addr_cnt + 1'b1;
        end
    end
    ST_WRITE_0: begin
        // give notice, address has become valid
        pmp_addr_valid <= 1;

        if(rx_byte_done_r_2) begin
            case(data_cnt)
            0: pmp_wr_data_latch[31:24] <= rx_byte_2;
            1: pmp_wr_data_latch[23:16] <= rx_byte_2;
            2: pmp_wr_data_latch[15: 8] <= rx_byte_2;
            3: begin
                pmp_wr_data_latch[ 7: 0] <= rx_byte_2;
                state <= ST_WRITE_1;
            end
            endcase
            data_cnt <= data_cnt + 1'b1;
        end
    end
    ST_WRITE_1: begin
        pmp_wr <= 1;
        state <= ST_WRITE_2;
    end
    ST_WRITE_2: begin
        // exited upon new transaction
        pmp_wr <= 0;
    end
    ST_READ_0: begin
        pmp_addr_valid <= 1;

        // delay a few cycles
        read_cnt <= read_cnt + 1'b1;
        if(read_cnt == 4-1) begin
            // load the buffer with the current data
            // and give the current buffer contents to bridge
            spis_word_tx <= pmp_rd_data_e;
            spis_tx <= 1;

            state <= ST_READ_1;
        end
    end
    ST_READ_1: begin
        pmp_rd <= 1;
        state <= ST_READ_2;
    end
    ST_READ_2: begin
        pmp_rd <= 0;
        if(spis_done) begin
            spis_tx <= 0;
            state <= ST_READ_3;
        end
    end
    ST_READ_3: begin
        // exited upon new transaction
    end
    endcase




    //
    // word transmit
    //
    spis_done <= 0;
    case(spis)
    ST_SIDLE: begin
        spis_count <= 0;

        phy_spiclk <= 1'bZ;
        phy_spimosi <= 1'bZ;
        phy_spimiso <= 1'bZ;

        if(spis_tx) begin
            spis_word <= spis_word_tx;
            spis <= ST_SEND_N;
        end
    end
    // drive high first
    ST_SEND_N: begin
        phy_spiclk <= 1'b1;
        phy_spimosi <= 1'b1;
        phy_spimiso <= 1'b1;
        spis <= ST_SEND_0;
    end
    // tx, shift out bits
    ST_SEND_0: begin
        phy_spiclk <= 0;
        spis <= ST_SEND_1;
        phy_spimosi <= spis_word[31];
        phy_spimiso <= spis_word[30];
        spis_word <= {spis_word[29:0], 2'b00};
    end
    ST_SEND_1: begin
        phy_spiclk <= 1;
        spis <= ST_SEND_0;
        spis_count <= spis_count + 1'b1;
        if(spis_count == 15) spis <= ST_SEND_2;
    end
    ST_SEND_2: begin
        phy_spiclk <= 1'b1;
        phy_spimosi <= 1'b1;
        phy_spimiso <= 1'b1;
        spis <= ST_SEND_3;
        spis_done <= 1;
    end
    ST_SEND_3: begin
        spis <= ST_SIDLE;
    end
    endcase

    if(phy_spiss_s) begin
        // select is high, go back to reset
        state <= ST_RESET;
        spis <= ST_SIDLE;
    end

end


//
// clock domain: phy_spiclk rising edge
//
    reg [1:0]   rx_latch_idx;
    reg [7:0]   rx_dat;
    reg [7:0]   rx_byte;    // latched by clk, but upon a synchronized trigger
    reg         rx_byte_done;

always @(posedge phy_spiclk or posedge phy_spiss) begin

    if(phy_spiss) begin
        // reset
        rx_byte_done <= 0;
        rx_latch_idx <= 0;

    end else begin
        // spiclk rising edge, latch data
        rx_byte_done <= 0;

        case(rx_latch_idx)
        0: begin    rx_dat[7:6] <= {phy_spimosi, phy_spimiso}; rx_latch_idx <= 1;   end
        1: begin    rx_dat[5:4] <= {phy_spimosi, phy_spimiso}; rx_latch_idx <= 2;   end
        2: begin    rx_dat[3:2] <= {phy_spimosi, phy_spimiso}; rx_latch_idx <= 3;   end
        3: begin
            // last bit of the byte
            rx_byte <= {rx_dat[7:2], phy_spimosi, phy_spimiso};
            rx_latch_idx <= 0;
            rx_byte_done <= 1;
        end
        endcase
    end
end

endmodule
