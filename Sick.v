// basic sizes of things
`define WORD  [15:0]
`define Opcode  [15:12]
`define Immed [11:0]
`define OP  [7:0]
`define PRE [3:0]
`define REGSIZE [511:0] // 256 for each PID
`define REGNUM  [7:0]
`define MEMSIZE [65535:0]

// pid-dependent things
`define PID0  (pid)
`define PID1  (!pid)
`define PC0 pc[`PID0]
`define PC1 pc[`PID1]
`define PRESET0 preset[`PID0]
`define PRESET1 preset[`PID1]
`define PRE0  pre[`PID0]
`define PRE1  pre[`PID1]
`define TORF0 torf[`PID0]
`define TORF1 torf[`PID1]
`define SP0 sp[`PID0]
`define SP1 sp[`PID1]
`define HALT0 halts[`PID0]
`define HALT1 halts[`PID1]

// opcode values hacked into state numbers
`define OPAdd {4'h0, 4'h0}
`define OPSub {4'h0, 4'h1}
`define OPTest  {4'h0, 4'h2}
`define OPLt  {4'h0, 4'h3}

`define OPDup {4'h0, 4'h4}
`define OPAnd {4'h0, 4'h5}
`define OPOr  {4'h0, 4'h6}
`define OPXor {4'h0, 4'h7}

`define OPLoad  {4'h0, 4'h8}
`define OPStore {4'h0, 4'h9}

`define OPRet {4'h0, 4'ha}
`define OPSys {4'h0, 4'hb}

`define OPPush  {4'h1, 4'h0}

`define OPCall  {4'h4, 4'h0}
`define OPJump  {4'h5, 4'h0}
`define OPJumpF {4'h6, 4'h0}
`define OPJumpT {4'h7, 4'h0}

`define OPGet {4'h8, 4'h0}
`define OPPut {4'h9, 4'h0}
`define OPPop {4'ha, 4'h0}
`define OPPre {4'hb, 4'h0}

`define OPNOP {4'hf, 4'hf}

`define NOREG   255

//Slow mem 
`define PID [1:0]
`define WORD [15:0]
`define MEMSIZE [65535:0]
`define MEMDELAY 4

//Cache
`define CACHESIZE [7:0] //variable size

module processor(halt, reset, clk);
output halt;
input reset, clk;

reg `WORD r `REGSIZE; 
reg `WORD pc `PID;
wire `OP op;
reg `OP s0op, s1op, s2op;
reg `REGNUM sp `PID;
reg `REGNUM s0d, s1d, s2d, s0s, s1s;
reg `WORD s0immed, s1immed, s2immed;
reg `WORD s1sv, s1dv, s2sv, s2dv;
reg `WORD ir;
wire `WORD ir0, ir1;
reg `WORD immed;
wire teststall, retstall, writestall;
reg `PID torf, preset, halts;
reg `PRE pre `PID;
reg pid;
wire `PID hit; //hit or miss for each thread
wire mfc;
wire `WORD rdata, wdata;
reg `WORD addr;
wire rnotw, strobe;
 

 always @(posedge reset) begin
  `SP0 <= 0;
  `SP1 <= 0;
  `PC0 <= 0;
  `PC1 <= 16'h8000;
  `HALT0 <= 0;
  `HALT1 <= 0;
end

// Halted?
assign halt = (`HALT0 && `HALT1);

// Stall for Test?
assign teststall = (s1op == `OPTest);

// Stall for Ret?
 assign retstall = (s1op == `OPRet);

always @(posedge clk)
  begin
    pid <= !pid; //toggle threads
  end
  //toggle between inst registers
always @(posedge clk) 
  begin
     if (`PID0) begin 
       ir = ir0; 
     end
     else begin
       ir = ir1; 
     end
end

  //instantiate instruction cache for both threads and slow mem
  //doing it using modules allows for straightforward access between the different
  //modules
  slowmem(mfc, rdata, addr, wdata, rnotw, strobe, clk);
  I_Cache I_CACHE0(clk, reset, `PC0, ir0, hit[0], rdata, addr, rnotw, mfc, strobe);
  I_Cache I_CACHE1(clk, reset, `PC1, ir1, hit[1], rdata, addr, rnotw, mfc, strobe);
  D_Cache D_CACHE0(clk, reset, strobe, rnotw, mfc, wdata, rdata, addr, hit[0]);
  D_Cache D_CACHE1(clk, reset, strobe, rnotw, mfc, wdata, rdata, addr, hit[1]);

  //pull instruction from instruction cache
  assign op = {(ir `Opcode), (((ir `Opcode) == 0) ? ir[3:0] : 4'd0)};

// Instruction fetch interface 
// Instruction fetch
 always @(posedge clk) begin
  // set immed, accounting for pre
  case (op)
    //$display("op = %b", op);
    `OPPre: begin
      //$display("Pre called"); 
      `PRE0 <= ir `PRE;
      `PRESET0 <= 1;
      immed = ir `Immed;
      end
    `OPCall,
    `OPJump,
    `OPJumpF,
    `OPJumpT: begin
      //$display("Call, Jump, Jumpf, JumpT called");
      if (`PRESET0) begin
  			immed = {`PRE0, ir `Immed};
  			`PRESET0 <= 0;
      end 
      else begin
  		// Take top bits of pc
  		immed <= {`PC0[14:12], ir `Immed};
      end
     end
    `OPPush: begin
      //$display("Push called");
      if (`PRESET0) begin
  		immed = {`PRE0, ir `Immed};
  		`PRESET0 <= 0;
      end 
      else begin
 	 // Sign extend
  		immed = {{4{ir[11]}}, ir `Immed};
      end
     end
    default:
      immed = ir `Immed;
  endcase

  // set s0immed, pc, s0op, halt
  case (op)
    `OPPre: begin
      s0op <= `OPNOP;
      `PC0 <= `PC0 + 1;
     end
    `OPCall: begin
      s0immed <= `PC0 + 1;
      `PC0 <= immed;
      s0op <= `OPCall;
     end
    `OPJump: begin
      `PC0 <= immed;
      s0op <= `OPNOP;
     end
    `OPJumpF: begin
      if (teststall == 0) begin
  		`PC0 <= (`TORF0 ? (`PC0 + 1) : immed);
      end 
      else begin
  		`PC0 <= `PC0 + 1;
      end
      s0op <= `OPNOP;
    end
    `OPJumpT: begin
      if (teststall == 0) begin
  		`PC0 <= (`TORF0 ? immed : (`PC0 + 1));
      end 
      else begin
  		`PC0 <= `PC0 + 1;
      end
      s0op <= `OPNOP;
    end
    `OPRet: begin
      if (retstall) begin
  			s0op <= `OPNOP;
      end 
      else if (s2op == `OPRet) begin
  			s0op <= `OPNOP;
  			`PC0 <= s1sv;
      end 
      else begin
  			s0op <= op;
      end
    end
    `OPSys: begin
      // basically idle this thread
       s0op <= `OPNOP;
      `HALT0 <= ((s0op == `OPNOP) && (s1op == `OPNOP) && (s2op == `OPNOP));
    end
    default: begin
      s0op <= op;
      s0immed <= immed;
      `PC0 <= `PC0 + 1;
    end
  endcase
end

// Instruction decode
always @(posedge clk) begin
  case (s0op)
    `OPAdd,
    `OPSub,
    `OPLt,
    `OPAnd,
    `OPOr,
    `OPXor,
    `OPStore:
      begin s1d <= `SP1-1; s1s <= `SP1; `SP1 <= `SP1-1; end
    `OPTest:
      begin s1d <= `NOREG; s1s <= `SP1; `SP1 <= `SP1-1; end
    `OPDup:
      begin s1d <= `SP1+1; s1s <= `SP1; `SP1 <= `SP1+1; end
    `OPLoad:
      begin s1d <= `SP1; s1s <= `SP1; end
    `OPRet:
      begin s1d <= `NOREG; s1s <= `NOREG; `PC1 <= r[{`PID1, `SP1}]; `SP1 <= `SP1-1; end
    `OPPush:
      begin s1d <= `SP1+1; s1s <= `NOREG; `SP1 <= `SP1+1; end
    `OPCall:
      begin s1d <= `SP1+1; s1s <= `NOREG; `SP1 <= `SP1+1; end
    `OPGet:
      begin s1d <= `SP1+1; s1s <= `SP1-(s0immed `REGNUM); `SP1 <= `SP1+1; end
    `OPPut:
      begin s1d <= `SP1-(s0immed `REGNUM); s1s <= `SP1; end
    `OPPop:
      begin s1d <= `NOREG; s1s <= `NOREG; `SP1 <= `SP1-(s0immed `REGNUM); end
    default:
      begin s1d <= `NOREG; s1s <= `NOREG; end
  endcase
  s1op <= s0op;
  s1immed <= s0immed;
end

// Register read
always @(posedge clk) begin
  s2dv <= ((s1d == `NOREG) ? 0 : r[{`PID0, s1d}]);
  s2sv <= ((s1s == `NOREG) ? 0 : r[{`PID0, s1s}]);
  s2d <= s1d;
  s2op <= s1op;
  s2immed <= s1immed;
end

// ALU or data memory access and write
always @(posedge clk) begin
  case (s2op)
    `OPAdd: begin r[{`PID1, s2d}] <= s2dv + s2sv; end
    `OPSub: begin r[{`PID1, s2d}] <= s2dv - s2sv; end
    `OPTest: begin `TORF1 <= (s2sv != 0); end
    `OPLt: begin r[{`PID1, s2d}] <= (s2dv < s2sv); end
    `OPDup: begin r[{`PID1, s2d}] <= s2sv; end
    `OPAnd: begin r[{`PID1, s2d}] <= s2dv & s2sv; end
    `OPOr: begin r[{`PID1, s2d}] <= s2dv | s2sv; end
    `OPXor: begin r[{`PID1, s2d}] <= s2dv ^ s2sv; end
    `OPLoad: begin r[{`PID1, s2d}] <= wdata; end
    `OPStore: begin addr = s2sv; end
    `OPPush,
    `OPCall: begin r[{`PID1, s2d}] <= s2immed; end
    `OPGet,
    `OPPut: begin r[{`PID1, s2d}] <= s2sv; end
  endcase
end
endmodule

//////SLOW MEM//////////////////////////////////////////////////           
module slowmem(mfc, rdata, addr, wdata, rnotw, strobe, clk);
output reg mfc;
output reg `WORD rdata;
input `WORD addr, wdata;
input rnotw, strobe, clk;
reg [7:0] pend;
reg `WORD raddr;
reg `WORD m `MEMSIZE;

//initially set pend to 0 and read the memory  
initial begin
  pend <= 0;
  $readmemh0(m);
end

always @(posedge clk) begin
  if (strobe && rnotw) begin
    // new read request
    raddr <= addr;//raddr gets input addr
    pend <= `MEMDELAY;//pend for delay of 4
  end 
  else begin
    if (strobe && !rnotw) begin
      // do write
      m[addr] <= wdata; //memory at input addr gets wdata input
    end

    // pending read?
    if (pend) begin
      // write satisfies pending read
      //if current read addr is the same as input address, strobing and writing,
      //then the data going out gets the data going in, memory fetch is complete-clear pend
      if ((raddr == addr) && strobe && !rnotw) begin
        rdata <= wdata;
        mfc <= 1;
        pend <= 0;
      end 
      //if pend is 1, data going out gets data in memory, mfc complete-clear pend
      else if (pend == 1) begin
        // finally ready
        rdata <= m[raddr];
        mfc <= 1;
        pend <= 0;
      end 
      //otherwise, keep pending by decrementing counter
      else begin
        pend <= pend - 1;
      end
    end 
    
    else begin
      // return invalid data
      rdata <= 16'hxxxx;
      mfc <= 0;
    end
  end
end
endmodule

//D-Cache /////////////////////
//Read from D-cache in read stage and write from it in write stage
//hold a copy of load and stores for processor to check from while executing instructions
//if time permits, look into a write buffer      
module D_Cache(clk, reset, strobe, rnotw, mfc, wdata, rdata, addr, hit);
input wire clk, reset;
input wire mfc;
input wire `WORD rdata;
input wire `WORD addr;
output reg `WORD wdata;
output reg rnotw, strobe;
output wire hit;
//right now cache data/addr are 8 lines of 16 bit words
//cache address should be mem addr % num blocks in cache
//NOTE may need to add tag to this if blocks contain data from other addresses
reg `WORD c_data `CACHESIZE; 
reg `WORD c_addr `CACHESIZE;
//CPU thinks its talking to slow mem and vice versa
//data cache is the middle man, responsible for writing to slow mem 
always @(posedge clk) begin
    //got request read from memory and its time to examine
    if(rnotw && strobe)
      begin
        //check if the addr matches the one mapped in cache by using modulo trick
        if(addr == c_addr[addr%`CACHESIZE] begin
           //write data gets the data from cache and its a hit!
           wdata <= c_data[addr%`CACHESIZE];
           hit = 1;
        end
        else
         //its a miss
          hit = 0;
      end
  end

always @(posedge clk) begin
  //if we have a cache miss and memory fetch isnt completed
  if(hit == 0 && !mfc) begin
       hit <= 0;
       rnotw = 1;
       strobe = 1;
       addr = addr;      
  end 
  //else if memory fetch is completed
  //cache data at the specified address gets input read data
  //the cache address is at the specified address
  else begin
    if(mfc) begin
      c_data[addr%`CACHESIZE] = rdata;
      c_addr[addr%`CACHESIZE] = addr;
      end
  end
end  
endmodule

//I-Cache/////////////////////////////////////////
//Prefetch and dispatch
//pull several instructions from memory,place ones youre not working on in a queue
//when queue is empty, go to memory to fetch more
//good I caches should have constant flow into the instruction queue
  
module I_Cache(clk, reset, i_addr, instr, hit, rdata, addr, rnotw, mfc, strobe);
input wire clk;
input wire reset;
input wire mfc; //need to know if memory fetch is complete
input wire `WORD i_addr; //instruction address
input wire `WORD rdata; //read data input
output hit; //signals whether or not a hit has occurred
output reg rnotw;
output reg strobe; 
output reg `WORD instr; //going to output an instruction, either from cache or slow mem
output reg `WORD addr; //also going to deliver the instruction address for future use
//cache address should be mem addr % num blocks in cache
//NOTE may need to add tag to this if blocks contain data from other addresses
reg `WORD c_addr `CACHESIZE; 
//if time permits, use more associative implementation
reg `WORD c_data `CACHESIZE;

  
 //begin prefetching process 
  always @(posedge clk) begin
    //requesting execution of read from mem (fetch instruction)
    if(rnotw && strobe)
      begin
        //if the instruction is in cache, we have a hit-load the instruction from cache
        if(i_addr == c_addr[i_addr%`CACHESIZE]) begin 
          //the instruction address matched the one mapped to cache (using modulo technique)
           instr <= c_data[i_addr%`CACHESIZE]; //send it out to CPU
           hit = 1;
        end
        //otherwise, we have a miss
        else
          hit = 0; //set miss flag
      end
  end
//when a miss occurs, cache must go to slow mem to load instruction
always @(posedge clk) begin
  //if we have a miss but fetching instruction from memory hasnt completed 
  if(hit == 0 && !mfc) begin
    instr <= `OPNOP; //load no op instruction to idle thread while reading
  end 
  
  else begin
    //if we have finished fetching the instruction from memory, then load it into cache
    if(mfc) begin
        c_data[i_addr%`CACHESIZE] = rdata;
        c_addr[i_addr%`CACHESIZE] = i_addr;
      	instr <= rdata; //load instruction for immed use
      end
      else begin
    //request read from memory, set the addr to instruction address
         hit <= 0;
         rnotw = 1;
         strobe = 1;
         addr = i_addr;         
      end
     
  end
end
endmodule
  



module testbench;
reg reset = 0;
reg clk = 0;
wire halted;
processor PE(halted, reset, clk);
initial begin
  $dumpfile;
  $dumpvars(0, PE);
  #10 reset = 1;
  #10 reset = 0;
  while (!halted) begin
    #10 clk = 1;
    #10 clk = 0;
  end
  $finish;
end
endmodule
