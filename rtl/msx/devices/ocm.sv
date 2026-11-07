// OCM device
//
// Copyright (c) 2024-2025 Molekula
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//
// * Redistributions in synthesized form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of other contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written agreement from the author.
//
// * License is granted for non-commercial use only.  A fee may not be charged
//   for redistributions as source code or in synthesized/hardware form without
//   specific prior written agreement from the author.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

module dev_ocm
(
   cpu_bus_if.device_mp            cpu_bus,                                // Interface for CPU communication
   clock_bus_if.base_mp            clock_bus,
   input  MSX::io_device_t         io_device[3],                          // Array of IO devices with port and mask info
   input  MSX::io_device_mem_ref_t io_memory[8],
   input                     [7:0] ff_dip_req,
   output                          ram_cs,
   output                   [26:0] ram_addr,
   output                    [7:0] data,
   output                          mapper_limit,

   output  logic                        warmRESET,
   output  logic                        RstReq_sta,
   output  logic [7:0]                  ff_dip_ack,
  output   logic [7:0]                  io42_id212,
  output   logic [7:0]                  io41_id212_n,
  output   logic [7:0]                  io44_id212,
  output   logic [7:0]                  io43_id212,
  output   logic [7:0]                  io40_n,
  output                                rst_key_lock,
  output                                swio_reset ,
  output                                megaSD_enable,
  output   logic                        Slot1Mode,                             
  output   logic [1:0]                  Slot2Mode
);

    logic en = 0;
    
    wire  io_cs = io_device[0].enable && cpu_bus.iorq && ~cpu_bus.m1 && cpu_bus.addr[7:4] == 4'b0100;

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            en <= io_device[0].enable;
            if (io_device[0].enable && en == 0) $display("OCM Boot START");       
        end else begin
            if (cpu_bus.addr[7:3] == 5'b10101 && cpu_bus.iorq && ~cpu_bus.m1 &&  cpu_bus.wr && cpu_bus.req) begin      //First write to slot select disable pre boot sekvence
                en <= 0;
                if (en) $display("OCM Boot STOP");       
            end
        end
    end

    wire [26:0] memory      = io_memory[io_device[0].mem_ref].memory;
    wire  [7:0] memory_size = io_memory[io_device[0].mem_ref].memory_size;

    assign ram_cs = cpu_bus.mreq && cpu_bus.rd && en && (cpu_bus.addr[15:14] == 2'b00 || cpu_bus.addr[15:14] == 2'b10);
    assign ram_addr = ram_cs ? memory + {16'b0, cpu_bus.addr[9:0]} : '1;




    assign mapper_limit = mapper_ack;
    assign rst_key_lock = io43_id212[5];
    assign megaSD_enable = MegaSD_ack || en || 1; //TODO tempoary enable

    logic [1:0] ff_rst_seq;

    always_ff @(posedge clock_bus.clk) begin
        if (cpu_bus.reset) begin
            ff_rst_seq <= '0;
        end else begin
            if (clock_bus.ce_10hz) begin
                ff_rst_seq <= {ff_rst_seq[0], ~ff_rst_seq[1]};
            end
        end
    end
    
    //reset enabler
    logic RstEna = '0;
    logic FirstBoot_n = '0;
    always_ff @(posedge clock_bus.clk) begin
        if (cpu_bus.reset) begin
            RstEna <= '0;
        end else begin
            if ( ff_rst_seq == 2'b11 && ~warmRESET) begin
                RstEna      <= '1;
                FirstBoot_n <= '1;
            end
        end
    end
    
    // virtual DIP-SW assignment (2/2)
    always_ff @(posedge clock_bus.clk) begin
        if ( /* ~SdPaus && */ (~FirstBoot_n || RstEna )) begin
            if (clock_bus.ce_10hz) begin
                // CmtScro           <=  swioCmt;
                // DisplayMode(1)    <=  io42_id212(1);
                //DisplayMode(0)    <=  io42_id212(2);
                Slot1Mode         <=  io42_id212[3];
                Slot2Mode[1]      <=  io42_id212[4];
                Slot2Mode[0]      <=  io42_id212[5];
            end
        end
    end


//Budoucí input/output
    // logic       warmRESET = '0;
    
    // logic       mapper_req, mapper_ack, RstReq_sta;
    // logic [7:0] ff_dip_ack, io42_id212, io41_id212_n, io44_id212, io40_n, io43_id212;
    
    logic swioReset = '0;
    logic MegaSD_req, MegaSD_ack, mapper_req, mapper_ack;

    always_comb begin : Port_read
        data = '1;
        if (io_cs && cpu_bus.rd && 1 == 0) begin //TODO disabled
            if (cpu_bus.data[3:0] == 4'b0000) begin
                data = io40_n;     // $40 => read_n/write ($41 ID008 BIT-0 is not here, it's a write_n only signal)
            end else begin
                case(io40_n)
                    8'b00101011: begin
                        case(cpu_bus.data[3:0])
                            4'b0001: data = io41_id212_n;       // $41 ID212 smart commands => read_n/write
                            4'b0010: data = io42_id212;         // $42 ID212 states of virtual dip-sw => read/write_n
                            4'b0011: data = io43_id212;         // $43 ID212 lock mask => read/write_n; [MSB] megasd/mapper/resetkey/slot2/slot1/cmt/display/turbo [LSB]
                            4'b0100: data = io44_id212;         // $44 ID212 green leds mask of lights mode => read/write_n
                            4'b1100: data = ff_dip_req;         // $4C ID212 states of physical dip-sw => read only
                            default: ;
                        endcase
                    end
                    8'b11110111: begin
                        case(cpu_bus.data[3:0])
                            4'b0011: data = '0;                 // $43 ID008 for compatibility => read only
                            default: ;
                        endcase
                    end
                    default: ;
                endcase
            end
        end
    end
    
    
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            io40_n     <= '1;
            swioReset <= '0;
            if (warmRESET) begin // Warm reset
                io42_id212[6] <= mapper_req;
                io42_id212[7] <= MegaSD_req;
                mapper_ack    <= mapper_req;
                MegaSD_ack    <= MegaSD_req;

            end else begin  // Cold Reset
                io42_id212 <= ff_dip_req;
                io43_id212 <= {2'b00, 1'bX, 5'b00000};
                io44_id212 <= '0;
                ff_dip_ack <= ff_dip_req;
                mapper_req <= ff_dip_req[6];
                mapper_ack <= ff_dip_req[6];
                MegaSD_req <= ff_dip_req[7];
                MegaSD_ack <= ff_dip_req[7];
            end       
        end else begin
            if (warmRESET || 1 == 1) begin  //TODO temp disabled
                warmRESET <= '0;
            end else begin
                
                // Reset Request State' (internal signal)
                if (mapper_req != io42_id212[6] || MegaSD_req != io42_id212[7]) begin 
                    RstReq_sta <= '1;
                end else begin
                    RstReq_sta <= '0;
                end

                if (ff_dip_req[1] != ff_dip_ack[1]) begin   // DIP-SW2      is  DISPLAY(A) state
                    if (~io43_id212[1]) begin                   
                        io42_id212[1] <= ff_dip_req[1];
                        ff_dip_ack[1] <= ff_dip_req[1];
                    end
                end                
                
                if (ff_dip_req[2] != ff_dip_ack[2]) begin   // DIP-SW3      is  DISPLAY(B) state
                    if (~io43_id212[2]) begin                   
                        io42_id212[2] <= ff_dip_req[2];
                        ff_dip_ack[2] <= ff_dip_req[2];
                    end
                end

                if (ff_dip_req[3] != ff_dip_ack[3]) begin   // DIP-SW4      is  SLOT1 state
                    if (~io43_id212[3]) begin                   
                        io42_id212[3] <= ff_dip_req[3];
                        ff_dip_ack[3] <= ff_dip_req[3];
                    end
                end

                if (ff_dip_req[4] != ff_dip_ack[4]) begin   // DIP-SW5      is  SLOT2(A) state
                    if (~io43_id212[4]) begin                   
                        io42_id212[4] <= ff_dip_req[4];
                        ff_dip_ack[4] <= ff_dip_req[4];
                    end
                end

                if (ff_dip_req[6] != ff_dip_ack[6]) begin   // DIP-SW7      is  MAPPER state
                    if (~io43_id212[6]) begin                   
                        mapper_req    <= ff_dip_req[6];
                        ff_dip_ack[6] <= ff_dip_req[6];
                    end
                end

                if (ff_dip_req[6] != ff_dip_ack[6]) begin   // DIP-SW8      is  MEGASD state
                    if (~io43_id212[7]) begin                   
                        MegaSD_req    <= ff_dip_req[7];
                        ff_dip_ack[7] <= ff_dip_req[7];
                    end
                end

                //Port 40 [ID Manufacturers/Devices]' (read_n/write)
                if (cpu_bus.req && io_cs && cpu_bus.wr && cpu_bus.addr[3:0] == 4'b0000 ) begin 
                    $display("%t SWIO WRITE 0x4%x <= %x", $time(), cpu_bus.addr[3:0], cpu_bus.data);
                    case (cpu_bus.data)
                        8'b00001000: io40_n <= 8'b11110111; // ID 008 => $08
                        8'b11010100: io40_n <= 8'b00101011; // ID 212 => $D4 => 1chipMSX
                        default:     io40_n <= 8'b11111111; // invalid ID
                    endcase
                end

                // Port 41 ID212 [Smart Commands]' (write only)
                if (cpu_bus.req && io_cs && cpu_bus.wr && cpu_bus.addr[3:0] == 4'b0001 && io40_n == 8'b00101011 ) begin 
                    $display("%t SWIO WRITE 0x4%x <= %x", $time(), cpu_bus.addr[3:0], cpu_bus.data);
                    io41_id212_n <= ~cpu_bus.data;
                    casez(cpu_bus.data) 
                        8'b0001110?: begin
                            MegaSD_req    <= ~cpu_bus.data[0];  // 29, 30 MegaSD On/Off       (warm reset is required)
                        end    
                        8'b0010100?: begin
                            io43_id212[0] <= cpu_bus.data[0];   // 41, 42 Turbo Locked/Unlocked
                        end
                        8'b0010101?: begin
                            io43_id212[1] <= cpu_bus.data[0];   // 43, 44 Display Locked/Unlocked
                        end
                        8'b0010110?: begin
                            io43_id212[2] <= cpu_bus.data[0];   // 45, 46 Audio Mixer & CMT Locked/Unlocked
                        end
                        8'b0010111?: begin
                            io43_id212[3] <= cpu_bus.data[0];   // 47, 48 Slot1 Locked/Unlocked
                        end
                        8'b0011000?: begin
                            io43_id212[4] <= cpu_bus.data[0];   // 49, 50 Slot2 Locked/Unlocked
                        end
                        8'b0011001?: begin
                            io43_id212[3] <= cpu_bus.data[0];   // 51,52 Slot1 + Slot2 Locked/Unlocked
                            io43_id212[4] <= cpu_bus.data[0];
                        end
                        8'b0011010?: begin
                            io43_id212[5] <= cpu_bus.data[0];   // 53, 54 Reset Key Locked/Unlocked
                        end
                        8'b0011011?: begin
                            io43_id212[6] <= cpu_bus.data[0];   // 55, 56, Mapper 2048/4096 kb
                        end
                        8'b0011100?: begin
                            io43_id212[6] <= cpu_bus.data[0];   // 57, 58, MegaSD Locked/Unlocked
                        end
                        8'b00111011: begin
                            io43_id212    <= '1;                // 59, Full Locked
                        end
                        8'b00111100: begin
                            io43_id212    <= '0;                // 60, Full Unlocked
                        end

                        8'b11111100: begin                      // 251, Mapper 2048 kB   + Warm Reset (Volume will not reset)
                            swioReset    <= '1;
                            mapper_req   <= '0;
                            warmRESET    <= '1;
                        end
                        8'b11111101: begin                      // 252, Warm Reset (Volume will not reset)
                            swioReset    <= '1;
                            warmRESET    <= '1;
                        end
                        8'b11111110: begin                      // 253, Mapper 4096 kB   + Warm Reset (Volume will not reset)
                            swioReset    <= '1;
                            mapper_req   <= '1;
                            warmRESET    <= '1;
                        end
                        8'b11111111: begin                      // 255, System Restore
                            swioReset       <= '1;
                            io42_id212[5:0] <= ff_dip_req[5:0];
                            ff_dip_ack[5:0] <= ff_dip_req[5:0];
                            mapper_req      <= ff_dip_req[6];
                            MegaSD_req      <= ff_dip_req[7];
                            io43_id212      <= '0;
                            io44_id212      <= '0;
                        end
                        default:
                            io41_id212_n    <= '1;
                    endcase
                end
                
                // Port 42 ID212 ID212 [Virtual DIP-SW]' (read/write_n, always unlocked)
                if (cpu_bus.req && io_cs && cpu_bus.wr && cpu_bus.addr[3:0] == 4'b0010 && io40_n == 8'b00101011 ) begin 
                    $display("%t SWIO WRITE 0x4%x <= %x", $time(), cpu_bus.addr[3:0], cpu_bus.data);
                    io42_id212[5:0] <= ~cpu_bus.data[5:0];
                    mapper_req      <= ~cpu_bus.data[6];
                    MegaSD_req      <= ~cpu_bus.data[7];
                end

                // Port 43 ID212 [Lock Mask]' (read/write_n)
                if (cpu_bus.req && io_cs && cpu_bus.wr && cpu_bus.addr[3:0] == 4'b0011 && io40_n == 8'b00101011 ) begin 
                    $display("%t SWIO WRITE 0x4%x <= %x", $time(), cpu_bus.addr[3:0], cpu_bus.data);
                    io43_id212 <= ~cpu_bus.data;
                end

                // Port 44 ID212 [Green Leds Mask]' (read/write_n)
                if (cpu_bus.req && io_cs && cpu_bus.wr && cpu_bus.addr[3:0] == 4'b0011 && io40_n == 8'b00101011 ) begin 
                    $display("%t SWIO WRITE 0x4%x <= %x", $time(), cpu_bus.addr[3:0], cpu_bus.data);
                    io44_id212 <= ~cpu_bus.data;
                end
            end
        end
    end

endmodule