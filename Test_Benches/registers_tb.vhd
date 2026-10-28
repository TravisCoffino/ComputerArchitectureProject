library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity registers_tb is
end entity;

architecture sim of registers_tb is

  -- DUT ports
  signal instructioni : std_logic_vector(24 downto 0) := (others => '0');
  signal instruction  : std_logic_vector(24 downto 0);  -- DUT output
  signal clk          : std_logic := '0';

  signal wr_en        : std_logic := '0';
  signal wr_addr      : std_logic_vector(4 downto 0) := (others => '0');
  signal wr_data      : std_logic_vector(127 downto 0) := (others => '0');

  signal rs1          : std_logic_vector(127 downto 0);
  signal rs2          : std_logic_vector(127 downto 0);
  signal rs3          : std_logic_vector(127 downto 0);

  constant TCK        : time := 10 ns;

  -- Patterns:
  -- R16: lane1 = 0xABCD, lane0 = 0xEF01, rest zero
  constant R16_VAL : std_logic_vector(127 downto 0) :=
    x"000000000000000000000000ABCD" & x"EF01";

  -- R17: lane1 = 0xFFFF, lane0 = 0x0A0A, rest zero
  constant R17_VAL : std_logic_vector(127 downto 0) :=
    x"000000000000000000000000FFFF" & x"0A0A";

  -- R18: lane0 = 0x8000, rest zero
  constant R18_VAL : std_logic_vector(127 downto 0) :=
    x"0000000000000000000000000000" & x"8000";

  constant ZERO128 : std_logic_vector(127 downto 0) := (others => '0');

begin

  ---------------------------------------------------------------------------
  -- Clock generator
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
  uut : entity work.registers
    port map(
      instructioni => instructioni,
      instruction  => instruction,
      clk          => clk,
      wr_en        => wr_en,
      wr_addr      => wr_addr,
      wr_data      => wr_data,
      rs1          => rs1,
      rs2          => rs2,
      rs3          => rs3
    );

  ---------------------------------------------------------------------------
  -- Stimulus
  ---------------------------------------------------------------------------
  stim_proc : process
  begin
    -- Init
    wr_en        <= '0';
    wr_addr      <= (others => '0');
    wr_data      <= (others => '0');
    instructioni <= (others => '0');

    -- Let things settle
    wait for 2 * TCK;

    -------------------------------------------------------------------------
    -- 1) Write R16, R17, R18 via the write port
    -------------------------------------------------------------------------

    -- Write r16 (addr 16 = "10000") with R16_VAL
    wr_en   <= '1';
    wr_addr <= "10000";       -- 16
    wr_data <= R16_VAL;
    wait until rising_edge(clk);

    -- Write r17 (addr 17 = "10001") with R17_VAL
    wr_addr <= "10001";       -- 17
    wr_data <= R17_VAL;
    wait until rising_edge(clk);

    -- Write r18 (addr 18 = "10010") with R18_VAL
    wr_addr <= "10010";       -- 18
    wr_data <= R18_VAL;
    wait until rising_edge(clk);

    -- Stop writing
    wr_en   <= '0';
    wr_addr <= (others => '0');
    wr_data <= (others => '0');

    -------------------------------------------------------------------------
    -- 2) Issue an R4 instruction:
    --    instruction[24:23] = "10"  => R4 format
    --    rs1 = r16 -> bits [9:5]   = 10000
    --    rs2 = r17 -> bits [14:10] = 10001
    --    rs3 = r18 -> bits [19:15] = 10010
    --    other bits don't matter to the register file
    -------------------------------------------------------------------------
    instructioni <= (others => '0');
    instructioni(24 downto 23) <= "10";        -- R4
    instructioni(9  downto 5)  <= "10000";     -- rs1 = r16
    instructioni(14 downto 10) <= "10001";     -- rs2 = r17
    instructioni(19 downto 15) <= "10010";     -- rs3 = r18

    -- Wait for synchronous read (if your RF is sync), then small delay
    wait until rising_edge(clk);
    wait for 1 ns;

    -------------------------------------------------------------------------
    -- 3) Check results
    -------------------------------------------------------------------------
    assert rs1 = R16_VAL
      report "R4 test: rs1 != R16_VAL (r16)" severity error;

    assert rs2 = R17_VAL
      report "R4 test: rs2 != R17_VAL (r17)" severity error;

    assert rs3 = R18_VAL
      report "R4 test: rs3 != R18_VAL (r18)" severity error;

    report "Register file R4 rs1/rs2/rs3 test PASSED." severity note;

    -- Keep sim running so you can inspect waveforms
    wait;
  end process;

end architecture;
