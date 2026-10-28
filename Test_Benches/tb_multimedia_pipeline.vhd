library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_multimedia_pipeline is
end entity;

architecture sim of tb_multimedia_pipeline is

  signal clk_if, clk_id, clk_ex, clk_wb : std_logic := '0';
  signal rst       : std_logic := '0';

  signal rd_out       : std_logic_vector(127 downto 0);
  signal instr_id_out : std_logic_vector(24 downto 0);
  signal pc_if_out    : unsigned(5 downto 0);
  signal wr_en_dbg    : std_logic;
  signal df_addr_dbg  : std_logic_vector(4 downto 0);

  constant PHASE : time := 5 ns;  -- spacing between edges

begin

  -------------------------------------------------------------------
  -- DUT
  -------------------------------------------------------------------
  U_DUT : entity work.pipelined_simd_multimedia_unit
    port map(
      clk_if       => clk_if,
      clk_id       => clk_id,
      clk_ex       => clk_ex,
      clk_wb       => clk_wb,
      rst          => rst,
      rd_out       => rd_out,
      instr_id_out => instr_id_out,
      pc_if_out    => pc_if_out,
      wr_en_dbg    => wr_en_dbg,
      df_addr_dbg  => df_addr_dbg
    );

  -------------------------------------------------------------------
  -- 4-phase clock generator: IF ? ID ? EX ? WB
  -------------------------------------------------------------------
  clk_proc : process
  begin
    -- apply reset
    rst <= '1';
    clk_if <= '0'; clk_id <= '0'; clk_ex <= '0'; clk_wb <= '0';
    wait for 4*PHASE;
    rst <= '0';

    -- run for some steps
    for step in 0 to 40 loop
      -- IF
      clk_if <= '1'; wait for PHASE; clk_if <= '0'; wait for PHASE;
      -- ID
      clk_id <= '1'; wait for PHASE; clk_id <= '0'; wait for PHASE;
      -- EX
      clk_ex <= '1'; wait for PHASE; clk_ex <= '0'; wait for PHASE;
      -- WB
      clk_wb <= '1'; wait for PHASE; clk_wb <= '0'; wait for PHASE;
    end loop;

    assert false report "tb_multimedia_pipeline finished"
      severity failure;
  end process;

  -------------------------------------------------------------------
  -- Monitor WB events (every WB rising edge)
  -------------------------------------------------------------------
  monitor_proc : process(clk_wb)
    variable low16 : unsigned(15 downto 0);
  begin
    if rising_edge(clk_wb) then
      low16 := unsigned(rd_out(15 downto 0));
      report "WB: PC_IF=" & integer'image(to_integer(pc_if_out)) &
             " instr_id=" & to_hstring(instr_id_out) &
             " wr_en=" & std_logic'image(wr_en_dbg) &
             " wb_addr=" & integer'image(to_integer(unsigned(df_addr_dbg))) &
             " rd_out[15:0]=" & integer'image(to_integer(low16));
    end if;
  end process;

end architecture;
