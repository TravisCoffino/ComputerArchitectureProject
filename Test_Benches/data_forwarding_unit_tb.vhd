library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity data_forwarding_unit_tb is
end entity;

architecture sim of data_forwarding_unit_tb is

  -- DUT inputs
  signal instr_id        : std_logic_vector(24 downto 0) := (others => '0');
  signal rs1i, rs2i, rs3i: std_logic_vector(127 downto 0) := (others => '0');

  signal ex_addr         : std_logic_vector(4 downto 0) := (others => '0');
  signal ex_data         : std_logic_vector(127 downto 0) := (others => '0');
  signal ex_we           : std_logic := '0';

  signal wb_addr         : std_logic_vector(4 downto 0) := (others => '0');
  signal wb_data         : std_logic_vector(127 downto 0) := (others => '0');
  signal wb_we           : std_logic := '0';

  -- DUT outputs
  signal rs1, rs2, rs3   : std_logic_vector(127 downto 0);

  -- Some distinct patterns
  constant BASE_RS1  : std_logic_vector(127 downto 0) := x"11111111111111111111111111111111";
  constant BASE_RS2  : std_logic_vector(127 downto 0) := x"22222222222222222222222222222222";
  constant BASE_RS3  : std_logic_vector(127 downto 0) := x"33333333333333333333333333333333";

  constant EX_VAL    : std_logic_vector(127 downto 0) := x"EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE";
  constant WB_VAL    : std_logic_vector(127 downto 0) := x"--------------------------------";

begin

  ---------------------------------------------------------------------------
  -- DUT instantiation
  ---------------------------------------------------------------------------
  uut : entity work.data_forwarding_unit
    port map(
      instr_id => instr_id,
      rs1i     => rs1i,
      rs2i     => rs2i,
      rs3i     => rs3i,
      ex_addr  => ex_addr,
      ex_data  => ex_data,
      ex_we    => ex_we,
      wb_addr  => wb_addr,
      wb_data  => wb_data,
      wb_we    => wb_we,
      rs1      => rs1,
      rs2      => rs2,
      rs3      => rs3
    );

  ---------------------------------------------------------------------------
  -- Stimulus process
  ---------------------------------------------------------------------------
  stim_proc : process
  begin
    -------------------------------------------------------------------------
    -- Common base values
    -------------------------------------------------------------------------
    rs1i <= BASE_RS1;
    rs2i <= BASE_RS2;
    rs3i <= BASE_RS3;

    ex_we   <= '0';
    wb_we   <= '0';
    ex_addr <= (others => '0');
    wb_addr <= (others => '0');
    ex_data <= (others => '0');
    wb_data <= (others => '0');

    wait for 10 ns;

    -------------------------------------------------------------------------
    -- TEST 1: LI, no forwarding
    -- instr_id(24) = '0' => LI
    -- rd (also used as "source" in your logic) in bits [4:0] = 16 ("10000")
    -------------------------------------------------------------------------
    instr_id <= (others => '0');
    instr_id(24)         <= '0';       -- LI
    instr_id(4 downto 0) <= "10000";   -- rd / rs1 index

    wait for 5 ns;

    assert rs1 = BASE_RS1 report "TEST1: LI no-forward rs1 wrong" severity error;
    assert rs2 = BASE_RS2 report "TEST1: LI no-forward rs2 wrong" severity error;
    assert rs3 = BASE_RS3 report "TEST1: LI no-forward rs3 wrong" severity error;

    -------------------------------------------------------------------------
    -- TEST 2: LI, EX forwarding hit (EX wins)
    -- ex_we=1, ex_addr=rd, so rs1 should be ex_data
    -------------------------------------------------------------------------
    ex_we   <= '1';
    ex_addr <= "10000";      -- same as instr_id(4 downto 0)
    ex_data <= EX_VAL;

    wb_we   <= '1';
    wb_addr <= "10000";      -- same reg, but EX should win
    wb_data <= WB_VAL;

    wait for 5 ns;

    assert rs1 = EX_VAL
      report "TEST2: LI EX-forward failed (rs1 != EX_VAL)" severity error;

    assert rs2 = BASE_RS2
      report "TEST2: LI EX-forward rs2 changed unexpectedly" severity error;

    assert rs3 = BASE_RS3
      report "TEST2: LI EX-forward rs3 changed unexpectedly" severity error;

    -------------------------------------------------------------------------
    -- TEST 3: LI, no EX but WB forwarding hit
    -------------------------------------------------------------------------
    ex_we <= '0';            -- disable EX
    wb_we <= '1';            -- WB active
    wb_addr <= "10000";
    wb_data <= WB_VAL;

    wait for 5 ns;

    assert rs1 = WB_VAL
      report "TEST3: LI WB-forward failed (rs1 != WB_VAL)" severity error;

    -------------------------------------------------------------------------
    -- TEST 4: R3, EX forwarding on rs1 and rs2
    -- instr_id(24:23) = "11"
    -- rs1 index = bits [9:5] = 17 ("10001")
    -- rs2 index = bits [14:10] = 18 ("10010")
    -------------------------------------------------------------------------
    rs1i <= BASE_RS1;
    rs2i <= BASE_RS2;
    rs3i <= BASE_RS3;

    instr_id <= (others => '0');
    instr_id(24 downto 23) <= "11";      -- R3
    instr_id(9  downto 5)  <= "10001";   -- rs1 idx = 17
    instr_id(14 downto 10) <= "10010";   -- rs2 idx = 18

    -- EX forwarding to rs1 only
    ex_we   <= '1';
    ex_addr <= "10001";      -- matches rs1 index
    ex_data <= EX_VAL;

    -- WB forwarding to rs2 only
    wb_we   <= '1';
    wb_addr <= "10010";      -- matches rs2 index
    wb_data <= WB_VAL;

    wait for 5 ns;

    assert rs1 = EX_VAL
      report "TEST4: R3 EX-forward to rs1 failed" severity error;
    assert rs2 = WB_VAL
      report "TEST4: R3 WB-forward to rs2 failed" severity error;
    assert rs3 = BASE_RS3
      report "TEST4: R3 unexpected change to rs3" severity error;

    -------------------------------------------------------------------------
    -- TEST 5: R3, EX vs WB conflict on rs1 (EX priority)
    -------------------------------------------------------------------------
    rs1i <= BASE_RS1;
    rs2i <= BASE_RS2;
    rs3i <= BASE_RS3;

    instr_id <= (others => '0');
    instr_id(24 downto 23) <= "11";      -- R3
    instr_id(9  downto 5)  <= "01010";   -- rs1 index = 10

    ex_we   <= '1';
    ex_addr <= "01010";
    ex_data <= EX_VAL;

    wb_we   <= '1';
    wb_addr <= "01010";
    wb_data <= WB_VAL;

    wait for 5 ns;

    assert rs1 = EX_VAL
      report "TEST5: R3 EX vs WB conflict: EX did not win for rs1" severity error;

    -------------------------------------------------------------------------
    -- All tests done
    -------------------------------------------------------------------------
    report "All data_forwarding_unit tests PASSED." severity note;
    wait;
  end process;

end architecture;
