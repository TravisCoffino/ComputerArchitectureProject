library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pipelined_simd_multimedia_unit is
  port(
    clk_if       : in  std_logic;
    clk_id       : in  std_logic;
    clk_ex       : in  std_logic;
    clk_wb       : in  std_logic;
    rst          : in  std_logic;

    rd_out       : out std_logic_vector(127 downto 0); -- ALU result (EX)
    instr_id_out : out std_logic_vector(24 downto 0);  -- instr in ID/EX
    pc_if_out    : out unsigned(5 downto 0);           -- PC in IF

    -- debug: WB control
    wr_en_dbg    : out std_logic;
    df_addr_dbg  : out std_logic_vector(4 downto 0)
  );
end entity;

architecture rtl of pipelined_simd_multimedia_unit is

  -- IF stage
  signal instr_if  : std_logic_vector(24 downto 0);
  signal pc_if     : unsigned(5 downto 0);

  -- ID stage
  signal instr_id  : std_logic_vector(24 downto 0);
  signal pc_id     : unsigned(5 downto 0);

  -- register file outputs
  signal rs1_rf, rs2_rf, rs3_rf : std_logic_vector(127 downto 0);

  -- EX stage regs (ID/EX outputs)
  signal instr_ex  : std_logic_vector(24 downto 0);
  signal rs1_ex, rs2_ex, rs3_ex : std_logic_vector(127 downto 0);

  -- forwarded operands into ALU
  signal rs1_fwd, rs2_fwd, rs3_fwd : std_logic_vector(127 downto 0);

  -- ALU output
  signal rd_alu : std_logic_vector(127 downto 0);

  -- EX forwarding source **registered**
  signal ex_addr_reg : std_logic_vector(4 downto 0);
  signal ex_data_reg : std_logic_vector(127 downto 0);
  signal ex_we_reg   : std_logic;

  -- WB forwarding / regfile writeback source
  signal wb_addr_sig : std_logic_vector(4 downto 0);
  signal wb_data_sig : std_logic_vector(127 downto 0);
  signal wb_we_sig   : std_logic;

  -- same function as in exwb_reg
  function will_write(i : std_logic_vector(24 downto 0)) return std_logic is
  begin
    if    i(24) = '0' then                     -- LI
      return '1';
    elsif i(24 downto 23) = "10" then          -- R4
      return '1';
    elsif i(24 downto 23) = "11" then          -- R3
      if i(18 downto 15) = "0000" then         -- NOP
        return '0';
      else
        return '1';
      end if;
    else
      return '0';
    end if;
  end function;

begin
  --------------------------------------------------------------------
  -- IF stage: instruction buffer based on pc
  --------------------------------------------------------------------
  U_IF : entity work.instr_buffer
    port map(
      clk       => clk_if,
      rst       => rst,
      instr_out => instr_if,
      pc_out    => pc_if
    );

  pc_if_out <= pc_if;

  --------------------------------------------------------------------
  -- IF/ID pipeline register
  --------------------------------------------------------------------
  U_IF_ID : entity work.reg_if_id
    port map(
      clk       => clk_id,
      rst       => rst,
      instr_in  => instr_if,
      pc_in     => pc_if,
      instr_out => instr_id,
      pc_out    => pc_id
    );

  instr_id_out <= instr_id;

  --------------------------------------------------------------------
  -- Register file (3R/1W) in ID stage
  --------------------------------------------------------------------
  U_RF : entity work.registers
    port map(
      instructioni => instr_id,
      instruction  => open,
      clk          => clk_id,

      wr_en        => wb_we_sig,
      wr_addr      => wb_addr_sig,
      wr_data      => wb_data_sig,

      rs1          => rs1_rf,
      rs2          => rs2_rf,
      rs3          => rs3_rf
    );

  --------------------------------------------------------------------
  -- ID/EX pipeline register
  --------------------------------------------------------------------
  U_ID_EX : entity work.reg_id_ex
    port map(
      instructioni => instr_id,
      instruction  => instr_ex,
      clk          => clk_ex,

      rs1in        => rs1_rf,
      rs2in        => rs2_rf,
      rs3in        => rs3_rf,

      rs1          => rs1_ex,
      rs2          => rs2_ex,
      rs3          => rs3_ex
    );

  --------------------------------------------------------------------
  -- EX forwarding source REGISTER
  --   These hold the result/rd of the instruction that just finished EX
  --   and are used as the EX->ID/EX forwarding source *next* time.
  --------------------------------------------------------------------
  ex_reg_proc : process(clk_ex, rst)
  begin
    if rst = '1' then
      ex_addr_reg <= (others => '0');
      ex_data_reg <= (others => '0');
      ex_we_reg   <= '0';
    elsif rising_edge(clk_ex) then
      ex_addr_reg <= instr_ex(4 downto 0);
      ex_data_reg <= rd_alu;
      ex_we_reg   <= will_write(instr_ex);
    end if;
  end process;

  --------------------------------------------------------------------
  -- Forwarding unit: EX(reg) + WB -> operands
  --------------------------------------------------------------------
  U_FWD : entity work.data_forwarding_unit
    port map(
      instr_id => instr_ex,
      rs1i     => rs1_ex,
      rs2i     => rs2_ex,
      rs3i     => rs3_ex,

      ex_addr  => ex_addr_reg,
      ex_data  => ex_data_reg,
      ex_we    => ex_we_reg,

      wb_addr  => wb_addr_sig,
      wb_data  => wb_data_sig,
      wb_we    => wb_we_sig,

      rs1      => rs1_fwd,
      rs2      => rs2_fwd,
      rs3      => rs3_fwd
    );

  --------------------------------------------------------------------
  -- ALU (pure combinational)
  --------------------------------------------------------------------
  U_ALU : entity work.alu
    port map(
      instruction => instr_ex,
      rs1         => rs1_fwd,
      rs2         => rs2_fwd,
      rs3         => rs3_fwd,
      rd          => rd_alu
    );

  rd_out <= rd_alu;  -- observe EX result

  --------------------------------------------------------------------
  -- EX/WB register, produces WB forwarding source + RF writeback
  --------------------------------------------------------------------
  U_EXWB : entity work.exwb_reg
    port map(
      clk         => clk_wb,
      instruction => instr_ex,
      rd_data     => rd_alu,

      df_addr     => wb_addr_sig,
      df_data     => wb_data_sig,
      wr_en       => wb_we_sig
    );

  -- debug exports
  wr_en_dbg   <= wb_we_sig;
  df_addr_dbg <= wb_addr_sig;

end architecture;
