module memory_upload
(
   input                       clk,
   output                      reset_rq,
   input                       ioctl_download,
   input                [15:0] ioctl_index,
   input                [26:0] ioctl_addr,
   input                       rom_eject,
   input                       reload,
   output logic         [27:0] ddr3_addr,
   output logic                ddr3_rd,
   output logic                ddr3_wr,
   input                 [7:0] ddr3_dout,
   input                       ddr3_ready,
   output                      ddr3_request,

   output logic         [26:0] ram_addr,
   output                [7:0] ram_din,
   input                 [7:0] ram_dout,
   output                      ram_ce,
   input                       sdram_ready,
   output                      sdram_rq,
   output                      bram_rq,
   output logic                kbd_request,
   output logic          [8:0] kbd_addr,
   output logic          [7:0] kbd_din,
   output logic                kbd_we,
   input                 [1:0] sdram_size,
   output logic                load_sram,
   output MSX::block_t         slot_layout[64],
   output MSX::lookup_RAM_t    lookup_RAM[16],
   output MSX::lookup_SRAM_t   lookup_SRAM[4],
   output MSX::bios_config_t   bios_config,
   input  MSX::config_cart_t   cart_conf[2],
   output                [1:0] rom_loaded,
   output dev_typ_t            cart_device[2],
   output dev_typ_t            msx_device,
   output                [3:0] msx_dev_ref_ram[8]
);
   /*verilator tracing_off*/
   logic [26:0] ioctl_size [4];
   logic        load;
   logic [27:0] save_addr;

   always @(posedge clk) begin
      logic ioctl_download_last;
      load <= 0;
      if (~ioctl_download & ioctl_download_last )  begin
         case(ioctl_index[5:0])
            6'd1: begin ioctl_size[0] <= ioctl_addr; load <= 1; end
            6'd2: begin ioctl_size[1] <= ioctl_addr; load <= 1; end
            6'd3: begin ioctl_size[2] <= ioctl_addr; load <= 1; end
            6'd4: begin ioctl_size[3] <= ioctl_addr; load <= 1; end
            default: ;
         endcase
      end
      if (rom_eject) begin
         ioctl_size[2] <= 0;
         ioctl_size[3] <= 0; 
         //load <= 1;
      end
      if (reload) load <= 1;
      ioctl_download_last <= ioctl_download;
   end 

   assign rom_loaded = {|ioctl_size[3],|ioctl_size[2]};

   typedef enum logic [3:0] {STATE_IDLE, STATE_CLEAN, STATE_READ_CONF, STATE_READ_CONF2, STATE_CHECK_CONFIG, STATE_FILL_RAM, STATE_FILL_RAM2, STATE_STORE_SLOT_CONFIG, STATE_FIND_ROM, STATE_FILL_KBD, STATE_ERROR} state_t;
   state_t state;
   logic  [7:0] conf[16];
   logic  [7:0] fw_conf[8];
   logic  [2:0] pattern;
   logic  [1:0] subslot;   
   logic  [3:0] ref_ram;
   assign reset_rq = ! (state == STATE_IDLE | state == STATE_ERROR);
   
   
   wire [8:0] fill_poss = 9'(ram_addr - lookup_RAM[ref_ram].addr);
   assign ram_din = pattern == 3'd0 ? ddr3_dout :
                    pattern == 3'd1 ? 8'hFF     :
                    pattern == 3'd2 ? 8'h00     :
                    pattern == 3'd3 ? fill_poss[8] ? fill_poss[1] ? 8'hff : 8'h00 : fill_poss[1] ? 8'h00 : 8'hff :
                    pattern == 3'd4 ? fill_poss[8] ? fill_poss[0] ? 8'h00 : 8'hff : fill_poss[0] ? 8'hff : 8'h00 :  //Tested 8245
                    pattern == 3'd5 ? fill_poss[7] ? 8'hff : 8'h00                                               :
                                    8'hFF;
   wire [3:0] curr_conf = config_typ_t'(conf[3][7:4]);
   always @(posedge clk) begin
      logic  [5:0] block_num;
      logic  [3:0] config_head_addr;
      logic [24:0] data_size;
      logic [24:0] sram_size;
      logic  [1:0] ref_sram;
      mapper_typ_t mapper;
      device_typ_t mem_device;
      data_ID_t    data_id;
      logic [7:0]  mode;
      logic [7:0]  param;
      logic [3:0]  slotSubslot;
      logic        refAdd;
      logic [26:0] sram_addr;
      logic [26:0] save_ram_addr;
      logic  [3:0] cart_slot_expander_en;
      logic        external;
      ddr3_wr   <= 1'b0;
      load_sram <= 1'b0;
      if (ram_ce)               begin ram_ce  <= 1'b0; ram_addr  <= ram_addr + 1'd1; end
      if (ddr3_ready & ddr3_rd) begin ddr3_rd <= 1'b0; ddr3_addr <= ddr3_addr + 1'd1; end
      if (load) begin
         state <= STATE_CLEAN;
         ddr3_addr             <= 0;
         ram_addr              <= 27'd0;
         sram_addr             <= 27'd0;
         save_ram_addr         <= 27'd0;
         block_num             <= 6'd0;
         config_head_addr      <= 4'd0;
         ref_ram               <= 4'd0;
         ddr3_rd               <= 1'd0;        
         save_addr             <= 0;
         refAdd                <= 1'b0;
         subslot               <= 2'd0; 
         cart_slot_expander_en <= 4'd0;
         cart_device           <= '{0, 0};
         bios_config.ram_size  <= 8'h00;
         bios_config.use_FDC   <= 1'b0;
         lookup_SRAM[0].size   <= 16'd0;
         lookup_SRAM[1].size   <= 16'd0;
         lookup_SRAM[2].size   <= 16'd0;
         lookup_SRAM[3].size   <= 16'd0;
      end
      if (ddr3_ready & ~ddr3_rd) begin
         case(state)
            STATE_ERROR,
            STATE_IDLE: begin
               ddr3_request     <= 1'd0;
            end
            STATE_CLEAN: begin
               ddr3_request  <= 1'd1;
               slot_layout[block_num].mapper   <= MAPPER_UNUSED;
               slot_layout[block_num].device   <= DEVICE_NONE;
               slot_layout[block_num].external <= 1'b0;
               block_num                       <= block_num + 1'd1;
               if (block_num == 63) begin
                  state      <= STATE_READ_CONF;
                  block_num  <= 0;
               end else begin
                  block_num  <= block_num + 1'd1;
               end
            end
            STATE_READ_CONF: begin
               subslot <= 2'd0; 
               state   <= STATE_READ_CONF2;
               if (save_addr == 0) begin
                  if (ddr3_addr >= 28'(ioctl_size[0])) begin
                     state     <= STATE_IDLE;
                     load_sram <= 1'b1;
                  end else begin
                     ddr3_rd    <= 1'b1;
                  end
               end else begin
                  ddr3_rd       <= 1'b1;
               end
            end
            STATE_READ_CONF2: begin
               config_head_addr <= config_head_addr + 4'd1;              
               ddr3_rd          <= 1'b1;
               conf[config_head_addr] <= ddr3_dout;         
               if (config_head_addr == 4'b1111) begin
                  state <= STATE_CHECK_CONFIG;
                  ddr3_rd          <= 1'd0;
                  config_head_addr <= 4'd0;
               end
            end
            STATE_CHECK_CONFIG: begin
               state <= STATE_IDLE;
               data_size <= 25'd0;
               sram_size <= 25'd0;
               external  <= 1'd0;
               if ({conf[0],conf[1],conf[2]} == {"M","S","X"}) begin
                  state <= STATE_FILL_RAM;
                  slotSubslot <= conf[3][3:0];
                  $display("CONF slot: %d subslot: %d (expand subslot: %d) mem_dev:%02X ram_size:%04X device:%02X mapper:%02X mode:%0x-%x-%x-%x param:%x-%x-%x-%x pattern:%02X", conf[3][3:2], conf[3][1:0], subslot, conf[4], {conf[6],conf[5]}, conf[7], conf[8], conf[9][7:6],conf[9][5:4],conf[9][3:2],conf[9][1:0], conf[10][7:6],conf[10][5:4],conf[10][3:2],conf[10][1:0],conf[11]);
                  case(curr_conf)
                     CONFIG_SLOT_A,
                     CONFIG_SLOT_B: begin
                        //if (cart_conf[curr_conf == CONFIG_SLOT_B].typ != CART_TYP_EMPTY) begin
                        if (cart_mapper != MAPPER_UNUSED | cart_mem_device != DEVICE_NONE ) begin
                           //mapper      <= cart_conf[curr_conf == CONFIG_SLOT_B].selected_mapper;
                           $display("  CONFIG CART %d selected mapper:%d stored mapper:%d", curr_conf == CONFIG_SLOT_B, cart_conf[curr_conf == CONFIG_SLOT_B].selected_mapper, cart_mapper);
                           mapper      <= cart_mapper;
                           mem_device  <= cart_mem_device;
                           mode        <= cart_mode;
                           param       <= cart_param;
                           data_id     <= cart_rom_id;
                           external    <= 1'd1;
                           if (cart_rom_id == ROM_ROM) begin
                              if (curr_conf == CONFIG_SLOT_A) begin
                                 sram_size <= 25'({cart_sram_size, 10'd0});
                                 ref_sram  <= 2'd0;
                              end
                           end else begin
                              sram_size   <= 25'({cart_sram_size, 10'd0});
                              ref_sram <= curr_conf == CONFIG_SLOT_A ? 2'd1 : 2'd2;   
                           end  
                           slotSubslot <= {conf[3][3:2], subslot};
                           case(cart_rom_id)
                              ROM_NONE: ;                          
                              ROM_ROM: begin
                                 if (ioctl_size[curr_conf == CONFIG_SLOT_A ? 2 : 3] > 0) begin                           
                                    save_addr <= ddr3_addr;   
                                    ddr3_addr <= curr_conf == CONFIG_SLOT_A ? 28'hC00000 : 28'h1100000 ;    //ROM Store
                                    data_size <= ioctl_size[curr_conf == CONFIG_SLOT_A ? 2 : 3][24:0];
                                 end else begin
                                    state     <= STATE_READ_CONF;
                                 end
                              end
                              ROM_RAM: begin
                                 data_size <= 25'({cart_ram_size,14'h0});
                                 pattern   <= 3'd1;       
                              end
                              default: begin
                                 save_addr <= ddr3_addr;   
                                 ddr3_addr <= 28'h300000;                                                            //FW Store
                                 ddr3_rd   <= 1'b1;                                                                  //Prefetch
                                 state     <= STATE_FIND_ROM;
                              end
                           endcase
                           if (subslot != 0) begin
                              cart_slot_expander_en <= cart_slot_expander_en | 4'b0001 << conf[3][3:2];
                              $display("    Enabled Expanded slot");
                           end
                        end else begin
                           if (subslot < 2'd3) begin
                              subslot <= subslot + 1'd1;
                              state <= STATE_CHECK_CONFIG;
                           end else begin
                              subslot <= 0;
                              state <= STATE_READ_CONF;
                           end
                        end
                     end
                     CONFIG_KBD_LAYOUT: begin
                         $display("  LOAD KBD LAYOUT");
                         kbd_addr <= 9'h0;
                         kbd_request <= 1'd1;
                         ddr3_rd   <= 1'b1;
                         state     <= STATE_FILL_KBD;
                     end
                     CONFIG_CONFIG: begin
                        bios_config.slot_expander_en <= conf[4][3:0] | cart_slot_expander_en;
                        bios_config.MSX_typ          <= MSX_typ_t'(conf[4][5:4]);
                        state                        <= STATE_READ_CONF;
                        $display("  STORE CONFIG  MSX:%d SLOT_EXPANDER:%x (%x %x)",MSX_typ_t'(conf[4][5:4]), conf[4][3:0] | cart_slot_expander_en, conf[4][3:0], cart_slot_expander_en);
                     end
                     CONFIG_DEVICE: begin
                        $display("  ADD DEVICE ID: %d",conf[7]);
                        msx_device                    <= msx_device | 1 << conf[7];
                        msx_dev_ref_ram[conf[7][2:0]] <= ref_ram;
                        data_size                     <= {conf[5][2:0], conf[6],14'h0};
                        sram_size                     <= 25'd0;
                        data_id                       <= ROM_ROM;
                        mode                          <= 0;
                     end
                     CONFIG_SLOT_INTERNAL: begin
                        $display("  SLOT INTERNAL");
                        mapper      <= mapper_typ_t'(conf[8]);
                        mem_device  <= device_typ_t'(conf[4]);
                        data_size   <= {conf[5][2:0], conf[6],14'h0};
                        sram_size   <= 25'd0;
                        data_id     <= data_ID_t'(conf[4]);
                        mode        <= conf[9];
                        param       <= conf[10];
                        pattern     <= conf[11][2:0]; //2'd3;
                        if(conf[7] != 8'hFF) begin
                           $display("     ADD DEVICE ID: %d",conf[7]);
                           msx_device                    <= msx_device | 1 << conf[7];
                           msx_dev_ref_ram[conf[7][2:0]] <= ref_ram;
                        end
                        if (device_typ_t'(conf[4]) == DEVICE_FDC) bios_config.use_FDC <= 1'b1;
                        if (data_ID_t'(conf[4]) == ROM_RAM)
                           if (bios_config.ram_size < conf[6]) begin
                              bios_config.ram_size <= conf[6];
                           end
                     end
                     default: ;
                  endcase
               end
            end
            STATE_FILL_KBD: begin
               if (kbd_we) begin
                  kbd_we <= 1'b0;
                  kbd_addr <= kbd_addr + 9'd1;
                  if (kbd_addr == 9'h1FF) begin
                     kbd_request <= 0;
                     state <= STATE_READ_CONF;
                  end
               end else begin
                  kbd_din <= ddr3_dout;
                  kbd_we  <= 1'b1;
                  if (kbd_addr != 9'h1FF) begin
                     ddr3_rd <= 1'b1;
                  end
               end
            end
            STATE_FIND_ROM: begin
               config_head_addr <= config_head_addr + 4'd1;              
               ddr3_rd          <= 1'd1;
               fw_conf[config_head_addr[2:0]] <= ddr3_dout;         
               if (config_head_addr == 4'd7) begin
                  config_head_addr <= 4'd0;
                  if ({fw_conf[0],fw_conf[1],fw_conf[2]} == {"M","S","X"}) begin
                     if (data_ID_t'(fw_conf[4]) == data_id) begin  
                        data_size <= {fw_conf[5][2:0], fw_conf[6],14'h0};
                        ddr3_addr <= ddr3_addr + 28'd7;
                        state     <= STATE_FILL_RAM;
                        $display("        FILL FW ROM size:%X", {fw_conf[5][2:0], fw_conf[6],14'h0});
                     end else begin          
                        if ((ddr3_addr - 28'h100000 + (28'({fw_conf[5],fw_conf[6]}) << 14) + 28'd8) >= 28'(ioctl_size[1])) begin
                           ddr3_addr <= save_addr;
                           state <= STATE_READ_CONF;                                                           //not find skip load
                        end else begin
                           ddr3_addr <= ddr3_addr + (28'({fw_conf[5],fw_conf[6]}) << 14) + 28'd8;              //not usable next header
                        end
                     end
                  end else begin
                     // Havarie. sem jsme se dostali chybou
                     ddr3_addr <= save_addr;
                     state <= STATE_READ_CONF;
                  end
               end
            end
            STATE_FILL_RAM: begin
               if (~ram_ce) begin
                  state <= STATE_FILL_RAM2;
                  if (bram_rq) sram_addr <= ram_addr;
                  sdram_rq <= 0;
                  bram_rq  <= 0;
                  if (save_ram_addr != 27'd0) begin
                     ram_addr <= save_ram_addr;
                     save_ram_addr <= 27'd0;
                  end
                  if (data_size != 25'd0) begin
                     refAdd                   <= 1'b1; // Add reference po ulozeni
                     lookup_RAM[ref_ram].addr <= ram_addr;
                     lookup_RAM[ref_ram].size <= 16'(data_size[24:14]);               
                     $display("           FILL RAM ID:%d addr:%x size:%d kB (save:%x)",ref_ram, ram_addr, 16'(data_size[24:14])*16, save_ram_addr);
                     case(data_id)
                        ROM_RAM: begin
                           lookup_RAM[ref_ram].ro   <= 1'd0;
                        end
                        default: begin
                           lookup_RAM[ref_ram].ro   <= 1'd1;
                           pattern                  <= 3'd0; 
                           ddr3_rd                  <= 1'd1;       //Prefetch
                        end
                     endcase
                     sdram_rq                 <= sdram_size != 0;
                     bram_rq                  <= sdram_size == 0;
                  end else 
                     if (sram_size != 25'd0) begin
                        lookup_SRAM[ref_sram].addr <= 18'(sram_addr);
                        lookup_SRAM[ref_sram].size <= 16'(sram_size[24:10]);
                        pattern       <= 3'd1; 
                        data_size     <= sram_size;
                        sram_size     <= 25'd0;
                        bram_rq       <= 1'b1;
                        data_id       <= ROM_RAM;
                        if (~bram_rq) ram_addr <= sram_addr;
                        if (sdram_size != 0) save_ram_addr <= ram_addr;
                        $display("           FILL SRAM ID:%d addr:%x size:%d kB (save:%x)",ref_sram, ~bram_rq ? sram_addr : ram_addr, sram_size, save_ram_addr);
                     end else state <= STATE_STORE_SLOT_CONFIG;
               end
            end
            STATE_FILL_RAM2: begin
               if (sdram_ready & ~ram_ce) begin
                  data_size  <= data_size - 25'd1;
                  ram_ce     <= 1;
                  if (data_size == 25'd1) begin
                     state    <= STATE_FILL_RAM;
                     if (save_addr > 0) begin
                        ddr3_addr <= save_addr; //restore
                        save_addr <= 28'd0;
                        if (curr_conf  == CONFIG_SLOT_A | curr_conf  == CONFIG_SLOT_B) begin
                           if (cart_conf[curr_conf == CONFIG_SLOT_B].typ == CART_TYP_ROM) begin
                              mapper <= cart_mapper;
                              if (cart_mapper == MAPPER_NONE) begin
                                 param <= detect_param;
                                 mode  <= detect_mode;
                              end
                           end
                        end
                     end
                  end else begin
                     if (data_id != ROM_RAM) ddr3_rd <= 1'b1;
                  end
               end
            end
            STATE_STORE_SLOT_CONFIG: begin
               if (curr_conf  == CONFIG_SLOT_A | curr_conf  == CONFIG_SLOT_B) begin
                  cart_device[curr_conf == CONFIG_SLOT_B] <= cart_device[curr_conf == CONFIG_SLOT_B] | conf_device;
               end
               $display("              FINAL mode:%0x-%x-%x-%x param:%x-%x-%x-%x", conf[9][7:6],conf[9][5:4],conf[9][3:2],conf[9][1:0], conf[10][7:6],conf[10][5:4],conf[10][3:2],conf[10][1:0]);
               if (mode[1:0] != 2'd0) begin
                  $display("              STORE block 0 mapper:%d mode:%d param:%d mem_device:%d", mapper, mode[1:0], param[1:0], mem_device);
                  slot_layout[{slotSubslot,2'd0}].mapper      <= mode[1:0] == 2'd1 ? slot_layout[{slotSubslot,param[1:0]}].mapper  :
                                                                 mode[1:0] == 2'd2 ? mapper                                        :
                                                                                     MAPPER_UNUSED                                 ;

                  slot_layout[{slotSubslot,2'd0}].device      <= mode[1:0] == 2'd2 ? mem_device                                    :
                                                                 mode[1:0] == 2'd3 ? mem_device                                    :
                                                                                     DEVICE_NONE                                   ;

                  slot_layout[{slotSubslot,2'd0}].ref_ram     <= mode[1:0] == 2'd1 ? slot_layout[{slotSubslot,param[1:0]}].ref_ram : data_id == ROM_NONE ? 4'd0 : ref_ram;
                  slot_layout[{slotSubslot,2'd0}].offset_ram  <= mode[1:0] == 2'd1 ? slot_layout[{slotSubslot,param[1:0]}].offset_ram : param[1:0];
                  slot_layout[{slotSubslot,2'd0}].cart_num    <= curr_conf == CONFIG_SLOT_B;
                  slot_layout[{slotSubslot,2'd0}].ref_sram    <= ref_sram;
                  slot_layout[{slotSubslot,2'd0}].external    <= external;
               end
               if (mode[3:2] != 2'd0) begin
                  $display("              STORE block 1 mapper:%d mode:%d param:%d mem_device:%d", mapper, mode[3:2], param[3:2], mem_device);
                  slot_layout[{slotSubslot,2'd1}].mapper      <= mode[3:2] == 2'd1 ? slot_layout[{slotSubslot,param[3:2]}].mapper  :
                                                                 mode[3:2] == 2'd2 ? mapper                                        :
                                                                                     MAPPER_UNUSED                                 ;

                  slot_layout[{slotSubslot,2'd1}].device      <= mode[3:2] == 2'd2 ? mem_device                                    :
                                                                 mode[3:2] == 2'd3 ? mem_device                                    :
                                                                                     DEVICE_NONE                                   ;

                  slot_layout[{slotSubslot,2'd1}].ref_ram     <= mode[3:2] == 2'd1 ? slot_layout[{slotSubslot,param[3:2]}].ref_ram : data_id == ROM_NONE ? 4'd0 : ref_ram;
                  slot_layout[{slotSubslot,2'd1}].offset_ram  <= mode[3:2] == 2'd1 ? slot_layout[{slotSubslot,param[3:2]}].offset_ram : param[3:2];
                  slot_layout[{slotSubslot,2'd1}].cart_num    <= curr_conf == CONFIG_SLOT_B;
                  slot_layout[{slotSubslot,2'd1}].ref_sram    <= ref_sram;
                  slot_layout[{slotSubslot,2'd1}].external    <= external;
               end
               if (mode[5:4] != 2'd0) begin
                  $display("              STORE block 2 mapper:%d mode:%d param:%d mem_device:%d", mapper, mode[5:4], param[5:4],mem_device);
                  slot_layout[{slotSubslot,2'd2}].mapper      <= mode[5:4] == 2'd1 ? slot_layout[{slotSubslot,param[5:4]}].mapper  :
                                                                 mode[5:4] == 2'd2 ? mapper                                        :
                                                                                     MAPPER_UNUSED                                 ;

                  slot_layout[{slotSubslot,2'd2}].device      <= mode[5:4] == 2'd2 ? mem_device                                    :
                                                                 mode[5:4] == 2'd3 ? mem_device                                    :
                                                                                     DEVICE_NONE                                   ;

                  slot_layout[{slotSubslot,2'd2}].ref_ram     <= mode[5:4] == 2'd1 ? slot_layout[{slotSubslot,param[5:4]}].ref_ram : data_id == ROM_NONE ? 4'd0 : ref_ram;
                  slot_layout[{slotSubslot,2'd2}].offset_ram  <= mode[5:4] == 2'd1 ? slot_layout[{slotSubslot,param[5:4]}].offset_ram : param[5:4];
                  slot_layout[{slotSubslot,2'd2}].cart_num    <= curr_conf == CONFIG_SLOT_B;
                  slot_layout[{slotSubslot,2'd2}].ref_sram    <= ref_sram;
                  slot_layout[{slotSubslot,2'd2}].external    <= external;
               end
               if (mode[7:6] != 2'd0) begin
                  $display("              STORE block 3 mapper:%d mode:%d param:%d mem_device:%d", mapper, mode[7:6], param[7:6], mem_device);
                  slot_layout[{slotSubslot,2'd3}].mapper      <= mode[7:6] == 2'd1 ? slot_layout[{slotSubslot,param[7:6]}].mapper  :
                                                                 mode[7:6] == 2'd2 ? mapper                                        :
                                                                                     MAPPER_UNUSED                                 ;

                  slot_layout[{slotSubslot,2'd3}].device      <= mode[7:6] == 2'd2 ? mem_device                                        :
                                                                 mode[7:6] == 2'd3 ? mem_device                                        :
                                                                                     DEVICE_NONE                                   ;

                  slot_layout[{slotSubslot,2'd3}].ref_ram     <= mode[7:6] == 2'd1 ? slot_layout[{slotSubslot,param[7:6]}].ref_ram : data_id == ROM_NONE ? 4'd0 : ref_ram;
                  slot_layout[{slotSubslot,2'd3}].offset_ram  <= mode[7:6] == 2'd1 ? slot_layout[{slotSubslot,param[7:6]}].offset_ram : param[7:6];
                  slot_layout[{slotSubslot,2'd3}].cart_num    <= curr_conf == CONFIG_SLOT_B;
                  slot_layout[{slotSubslot,2'd3}].ref_sram    <= ref_sram;
                  slot_layout[{slotSubslot,2'd3}].external    <= external;
               end
               state <= STATE_READ_CONF;
               ref_ram <= ref_ram + 4'(refAdd);
               refAdd  <= 1'b0;

               if (curr_conf == CONFIG_SLOT_A | curr_conf == CONFIG_SLOT_B) begin
                  if (subslot < 2'd3) begin
                     subslot <= subslot + 1'd1;
                     state <= STATE_CHECK_CONFIG;
                  end else begin
                     subslot <= 0;
                  end
             
               end              
            end
            default: ;
         endcase
      end
   end

mapper_typ_t detect_mapper;
wire [3:0] detect_offset;
wire [7:0] detect_mode, detect_param;
mapper_detect mapper_detect 
(
   .clk(clk),
   .rst(state == STATE_READ_CONF),
   .data(ddr3_dout),
   .wr(ram_ce),
   .rom_size(ioctl_size[curr_conf == CONFIG_SLOT_A ? 2'd2 : 2'd3]),
   .mapper(detect_mapper),
   .offset(detect_offset),
   .mode(detect_mode),
   .param(detect_param)
);

mapper_typ_t cart_mapper;
device_typ_t cart_mem_device;
dev_typ_t    conf_device;
data_ID_t    cart_rom_id;
logic  [7:0] cart_sram_size, cart_mode, cart_param, cart_ram_size;

cart_confDecoder cart_decoder
(
   .typ(cart_conf[curr_conf == CONFIG_SLOT_B].typ),
   .selected_mapper(cart_conf[curr_conf == CONFIG_SLOT_B].selected_mapper),
   .detected_mapper(detect_mapper),
   .selected_sram_size(cart_conf[curr_conf == CONFIG_SLOT_B].selected_sram_size),
   .subslot(subslot),
   .mapper(cart_mapper), 
   .mem_device(cart_mem_device),
   .rom_id(cart_rom_id),
   .sram_size(cart_sram_size),
   .ram_size(cart_ram_size),
   .mode(cart_mode),
   .param(cart_param),
   .device(conf_device)
);

endmodule

module cart_confDecoder
(
   input  cart_typ_t   typ,
   input  mapper_typ_t selected_mapper,
   input  mapper_typ_t detected_mapper,
   input  logic  [7:0] selected_sram_size,
   input         [1:0] subslot,
   output mapper_typ_t mapper, 
   output device_typ_t mem_device,
   output data_ID_t    rom_id,
   output logic  [7:0] sram_size,
   output logic  [7:0] ram_size,
   output logic  [7:0] mode,
   output logic  [7:0] param,
   output dev_typ_t device
);
mapper_typ_t rom_mapper;
dev_typ_t rom_device;

assign rom_mapper = selected_mapper  == MAPPER_AUTO ? detected_mapper : selected_mapper;

assign rom_device = rom_mapper == MAPPER_KONAMI_SCC ? DEV_SCC  :
                                                      DEV_NONE ;     


assign                                        {mapper             , mem_device    , rom_id             , mode  , param , sram_size          , ram_size,   device               } = 
   typ == CART_TYP_ROM    & subslot == 2'd0 ? {rom_mapper         , DEVICE_NONE   , ROM_ROM            , 8'hAA , 8'hE4 , selected_sram_size , 8'd0    ,   rom_device           } :
   typ == CART_TYP_SCC    & subslot == 2'd0 ? {MAPPER_KONAMI_SCC  , DEVICE_NONE   , ROM_ROM            , 8'hAA , 8'h00 , 8'd0               , 8'd0    ,   DEV_SCC              } :
   typ == CART_TYP_SCC2   & subslot == 2'd0 ? {MAPPER_KONAMI_SCC  , DEVICE_NONE   , ROM_RAM            , 8'hAA , 8'h00 , 8'd0               , 8'd8    ,   DEV_SCC2             } :
   typ == CART_TYP_FM_PAC & subslot == 2'd0 ? {MAPPER_FMPAC       , DEVICE_NONE   , ROM_FMPAC          , 8'h08 , 8'h00 , 8'd8               , 8'd0    ,   DEV_OPL3             } : //4000 - 7FFF
   typ == CART_TYP_MFRSD  & subslot == 2'd0 ? {MAPPER_NONE        , DEVICE_MFRSD0 , ROM_MFRSD          , 8'hAA , 8'h00 , 8'd0               , 8'd0    ,   DEV_FLASH            } :
   typ == CART_TYP_MFRSD  & subslot == 2'd1 ? {MAPPER_MFRSD1      , DEVICE_NONE   , ROM_NONE           , 8'hAA , 8'h00 , 8'd0               , 8'd0    ,   DEV_SCC2 | DEV_FLASH } :
   typ == CART_TYP_MFRSD  & subslot == 2'd2 ? {MAPPER_MFRSD2      , DEVICE_NONE   , ROM_RAM            , 8'hAA , 8'h00 , 8'd0               , 8'd32   ,   DEV_MFRSD2 | DEV_PSG } :
   typ == CART_TYP_MFRSD  & subslot == 2'd3 ? {MAPPER_MFRSD3      , DEVICE_NONE   , ROM_NONE           , 8'hAA , 8'h00 , 8'd0               , 8'd0    ,   DEV_FLASH            } :
   typ == CART_TYP_GM2    & subslot == 2'd0 ? {MAPPER_GM2         , DEVICE_NONE   , ROM_GM2            , 8'hAA , 8'h00 , 8'd8               , 8'd0    ,   DEV_NONE             } :
   typ == CART_TYP_FDC    & subslot == 2'd0 ? {MAPPER_NONE        , DEVICE_FDC    , ROM_FDC            , 8'h08 , 8'h00 , 8'd0               , 8'd0    ,   DEV_NONE             } :
   /*typ == CART_TYP_EMPTY*/                  {MAPPER_UNUSED      , DEVICE_NONE   , ROM_NONE           , 8'h00 , 8'h00 , 8'd0               , 8'd0    ,   DEV_NONE             } ;

endmodule