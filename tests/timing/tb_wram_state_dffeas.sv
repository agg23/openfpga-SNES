`timescale 1ns/1ps
module tb_wram_state_dffeas;
 reg clk=0,d=0,ena=1,sclr=0,sload=0,asdata=0;wire q;reg expected;integer previous,bits,count=0;
 dffeas #(.power_up("low"),.is_wysiwyg("true")) cell_under_test(.clk(clk),.d(d),.ena(ena),.sclr(sclr),.sload(sload),.asdata(asdata),.clrn(1'b1),.prn(1'b1),.aload(1'b0),.devclrn(1'b1),.devpor(1'b1),.q(q));
 initial begin
  #1;if(q!==1'b0)$fatal(1,"DFFEAS initial low mismatch");
  for(previous=0;previous<2;previous=previous+1)for(bits=0;bits<32;bits=bits+1)begin
   // Establish either prior Q through the real primitive, then enumerate all
   // supported binary D/ENA/SCLR/SLOAD/ASDATA combinations for one clock edge.
   clk=0;d=previous;ena=1;sclr=0;sload=0;#1;clk=1;#1;
   if(q!==previous[0])$fatal(1,"DFFEAS prior Q mismatch");
   clk=0;{d,ena,sclr,sload,asdata}=bits[4:0];
   expected=ena?(sclr?1'b0:(sload?asdata:d)):previous[0];
   #1;clk=1;#1;if(q!==expected)$fatal(1,"DFFEAS transition mismatch Q=%b inputs=%b got=%b expected=%b",previous[0],bits[4:0],q,expected);count=count+1;
  end
  $display("PASS official DFFEAS 64 exhaustive binary transitions match formal abstraction");$finish;
 end
endmodule
