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
// 2-stage synchronizer
//
module synch_2 #(parameter WIDTH = 1) (
    input  wire [WIDTH-1:0] i,      // input signal
    output reg  [WIDTH-1:0] o,      // synchronized output
    input  wire             clk,    // clock to synchronize on
    output wire             rise,   // one-cycle rising edge pulse
    output wire             fall    // one-cycle falling edge pulse
);

reg [WIDTH-1:0] stage_1;
reg [WIDTH-1:0] stage_2;
reg [WIDTH-1:0] stage_3;

assign rise = (WIDTH == 1) ? (o & ~stage_2) : 1'b0;
assign fall = (WIDTH == 1) ? (~o & stage_2) : 1'b0;
always @(posedge clk)
   {stage_2, o, stage_1} <= {o, stage_1, i};

endmodule


//
// 3-stage synchronizer
//
module synch_3 #(parameter WIDTH = 1) (
   input  wire [WIDTH-1:0] i,     // input signal
   output reg  [WIDTH-1:0] o,     // synchronized output
   input  wire             clk,   // clock to synchronize on
   output wire             rise,   // one-cycle rising edge pulse
   output wire             fall    // one-cycle falling edge pulse
);

reg [WIDTH-1:0] stage_1;
reg [WIDTH-1:0] stage_2;
reg [WIDTH-1:0] stage_3;

assign rise = (WIDTH == 1) ? (o & ~stage_3) : 1'b0;
assign fall = (WIDTH == 1) ? (~o & stage_3) : 1'b0;
always @(posedge clk)
   {stage_3, o, stage_2, stage_1} <= {o, stage_2, stage_1, i};

endmodule


module bram_block_dp #(
   parameter DATA = 32,
   parameter ADDR = 7
) (
   input  wire            a_clk,
   input  wire            a_wr,
   input  wire [ADDR-1:0] a_addr,
   input  wire [DATA-1:0] a_din,
   output reg  [DATA-1:0] a_dout,

   input  wire            b_clk,
   input  wire            b_wr,
   input  wire [ADDR-1:0] b_addr,
   input  wire [DATA-1:0] b_din,
   output reg  [DATA-1:0] b_dout
);

reg [DATA-1:0] mem [(2**ADDR)-1:0];

always @(posedge a_clk) begin
   if(a_wr) begin
      a_dout <= a_din;
      mem[a_addr] <= a_din;
   end else
      a_dout <= mem[a_addr];
end

always @(posedge b_clk) begin
   if(b_wr) begin
      b_dout <= b_din;
      mem[b_addr] <= b_din;
   end else
      b_dout <= mem[b_addr];
end

endmodule


module bram_block_dp_nonstd #(
   parameter DATA = 32,
   parameter ADDR = 7,
   parameter DEPTH = 128
) (
   input  wire            a_clk,
   input  wire            a_wr,
   input  wire [ADDR-1:0] a_addr,
   input  wire [DATA-1:0] a_din,
   output reg  [DATA-1:0] a_dout,

   input  wire            b_clk,
   input  wire            b_wr,
   input  wire [ADDR-1:0] b_addr,
   input  wire [DATA-1:0] b_din,
   output reg  [DATA-1:0] b_dout
);

reg [DATA-1:0] mem [DEPTH-1:0];

always @(posedge a_clk) begin
   if(a_wr) begin
      a_dout <= a_din;
      mem[a_addr] <= a_din;
   end else
      a_dout <= mem[a_addr];
end

always @(posedge b_clk) begin
   if(b_wr) begin
      b_dout <= b_din;
      mem[b_addr] <= b_din;
   end else
      b_dout <= mem[b_addr];
end

endmodule
