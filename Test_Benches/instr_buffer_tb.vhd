library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity instr_buffer_tb is
end entity;

architecture sim of instr_buffer_tb is

  -- DUT ports
  signal clk       : std_logic := '0';
  signal rst       : std_logic := '0';
  signal instr_out : std_logic_vector(24 downto 0);
  signal pc_out    : unsigned(5 downto 0);

  constant TCK     : time := 10 ns;

  -- helper: convert std_logic_vector to "0101..." string
  function slv_to_str(s : std_logic_vector) return string is
    variable result : string(1 to s'length);
    variable idx    : integer := 1;
  begin
    for i in s'range loop
      if s(i) = '1' then
        result(idx) := '1';
      else
        result(idx) := '0';
      end if;
      idx := idx + 1;
    end loop;
    return result;
  end function;

begin

  ---------------------------------------------------------------------------
  -- Clock generation
  ---------------------------------------------------------------------------
  clk_proc : process
  begin
    while true loop
      clk <= '0';
      wait for TCK/2;
      clk <= '1';
      wait for TCK/2;
    end loop;
  end process;

  ---------------------------------------------------------------------------
  -- DUT instantiation
  ---------------------------------------------------------------------------
  uut : entity work.instr_buffer
    port map(
      clk       => clk,
      rst       => rst,
      instr_out => instr_out,
      pc_out    => pc_out
    );

  ---------------------------------------------------------------------------
  -- Stimulus
  ---------------------------------------------------------------------------
  stim_proc : process
    constant NUM_CYCLES : integer := 20;  -- how many instructions to step through
  begin
    -------------------------------------------------------------------------
    -- Apply reset
    -------------------------------------------------------------------------
    rst <= '1';
    wait for 3 * TCK;  -- hold reset a few cycles
    rst <= '0';

    -------------------------------------------------------------------------
    -- Step through a number of instructions, printing PC + instr_out
    -------------------------------------------------------------------------
    for n in 0 to NUM_CYCLES-1 loop
      wait until rising_edge(clk);
      wait for 1 ns;  -- small delay to let instr_out/pc_out settle

      report "Cycle " & integer'image(n) &
             "  PC = " & integer'image(to_integer(pc_out)) &
             "  instr = " & slv_to_str(instr_out);
    end loop;

    report "instr_buffer_tb finished after " &
           integer'image(NUM_CYCLES) & " cycles." severity note;

    -- end simulation
    assert false report "End of simulation" severity failure;
  end process;

end architecture;
