-- ============================================================
--  ALU SIMD Testbench (2 lanes × 64-bit = 128-bit datapath)
--  This TB exercises:
--    - LI (load-immediate to 16b lane halves)
--    - R4 family (MAC-style INT/LONG ops; forms 000..111)
--    - R3 family (packed ops; opcodes 0000..1111)
--  All checks are self-verifying with assertions.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alu_sc_tb is
end entity;

architecture sim of alu_sc_tb is

  ----------------------------------------------------------------
  -- Constant configuration of the datapath under test
  ----------------------------------------------------------------
  constant LANE_W : integer := 64;  -- width of a lane (bits)
  constant LANES  : integer := 2;   -- number of lanes (total datapath = 128 bits)

  ----------------------------------------------------------------
  -- DUT ports (driven/observed by the testbench)
  ----------------------------------------------------------------
  signal instruction : std_logic_vector(24 downto 0);                -- 25-bit instruction
  signal rs1, rs2, rs3 : std_logic_vector(LANE_W*LANES-1 downto 0);  -- 128-bit source regs
  signal rd : std_logic_vector(LANE_W*LANES-1 downto 0);             -- 128-bit dest reg

  ----------------------------------------------------------------
  -- === HELPERS ===
  -- Helpers build specific instruction encodings as 25-bit vectors.
  -- Bit layout (common):
  --   [24:23]  : major class  (00=LI, 10=R4, 11=R3)
  --   [22:..]  : class-specific payload
  ----------------------------------------------------------------

  ----------------------------------------------------------------
  -- LOAD IMMEDIATE (LI) instruction builder
  -- Format (this TB’s convention):
  --   [24]     = 0                    ? identify LI class
  --   [23:21]  = lane index (0..7)    ? which 64b lane to target
  --   [20:5]   = imm16                ? 16-bit immediate written into that lane
  --   [4:0]    = 0
  --
  -- Result (per your DUT): the 16-bit imm is injected into the selected lane position
  -- and accumulated (rs1 <= rd) across several LI writes to assemble the 128-bit constant.
  ----------------------------------------------------------------
  function mk_li(lane : integer; imm16 : std_logic_vector(15 downto 0))
    return std_logic_vector is
    variable t : std_logic_vector(24 downto 0) := (others => '0');
  begin
    t(24)            := '0';                               -- class = LI
    t(23 downto 21)  := std_logic_vector(to_unsigned(lane, 3));
    t(20 downto 5)   := imm16;                             -- payload
    t(4 downto 0)    := (others => '0');
    return t;
  end function;

  ----------------------------------------------------------------
  -- R4 INSTRUCTIONS (MAC family) builder
  -- Format:
  --   [24:23] = "10"               ? class = R4
  --   [22:20] = form[2:0]          ? longInt / subAdd / highLow (after your fix)
  --   [19:0]  = 0
  ----------------------------------------------------------------
  function mk_r4(form : std_logic_vector(2 downto 0))
    return std_logic_vector is
    variable t : std_logic_vector(24 downto 0) := (others => '0');
  begin
    t(24 downto 23) := "10";           -- class = R4
    t(22 downto 20) := form;           -- form bits (000..111)
    t(19 downto 0)  := (others => '0');
    return t;
  end function;

  ----------------------------------------------------------------
  -- R3 INSTRUCTIONS (packed ops) builder
  -- Format (matches your decoder):
  --   [24:23] = "11"               ? class = R3
  --   [22:19] = 0000               ? reserved/unused in this TB
  --   [18:15] = opcode[3:0]        ? packed-op code (0000..1111)
  --   [14:10] = shift/imm5         ? opcode-specific (e.g., SHRHI/MLHCU/ROTW)
  --   [9:0]   = 0
  ----------------------------------------------------------------
  function mk_r3(code : std_logic_vector(3 downto 0); shift : std_logic_vector(4 downto 0))
    return std_logic_vector is
    variable t : std_logic_vector(24 downto 0) := (others => '0');
  begin
    t(24 downto 23) := "11";           -- class = R3
    t(22 downto 19) := (others => '0');-- reserved (kept zero for clarity)
    t(18 downto 15) := code;           -- opcode
    t(14 downto 10) := shift;          -- 5-bit field (imm/shift per opcode)
    return t;
  end function;

begin
  ----------------------------------------------------------------
  -- Device Under Test
  ----------------------------------------------------------------
  dut : entity work.alu
    port map(
      instruction => instruction,
      rs1 => rs1, rs2 => rs2, rs3 => rs3,
      rd => rd
    );

  ----------------------------------------------------------------
  -- Stimulus process: drives instructions and operands,
  -- checks results with a golden expected vector (exp).
  ----------------------------------------------------------------
  stim : process
    variable exp : std_logic_vector(LANE_W*LANES-1 downto 0);
  begin

    ----------------------------------------------------------------
    -- == LOAD IMMEDIATE ==
    -- Build a 128-bit constant by writing one 16-bit lane piece at a time.
    -- After each LI write, we assert rd and then copy rd back to rs1, so
    -- we “accumulate” the full constant across the lanes.
    --
    -- Final target constant (top..bottom):
    --   L7:L6:L5:L4:L3:L2:L1:L0 = DEAD FEED 8000 8135 6969 ABAD CAB0 AEFC
    ----------------------------------------------------------------
    rs1 <= (others => '0');
    rs2 <= (others => '0');
    rs3 <= (others => '0');

    -- LANE 0 (lowest 16 bits of the 128-bit word)
    instruction <= mk_li(0, x"AEFC");  wait for 1 ns;
    exp := x"0000000000000000000000000000AEFC";
    assert rd = exp report "LI in Lane 0 mismatched..." severity error;
    rs1 <= rd;  wait for 1 ns;  -- accumulate

    -- LANE 1
    instruction <= mk_li(1, x"CAB1");  wait for 1 ns;
    exp := x"000000000000000000000000CAB1AEFC";
    assert rd = exp report "LI in Lane 1 mismatched..." severity error;
    rs1 <= rd;  wait for 1 ns;

    -- LANE 2
    instruction <= mk_li(2, x"ABAD");  wait for 1 ns;
    exp := x"00000000000000000000ABADCAB1AEFC";
    assert rd = exp report "LI in Lane 2 mismatched..." severity error;
    rs1 <= rd;  wait for 1 ns;

    -- LANE 3
    instruction <= mk_li(3, x"6969");  wait for 1 ns;
    exp := x"00000000000000006969ABADCAB1AEFC";
    assert rd = exp report "LI in Lane 3 mismatched..." severity error;
    rs1 <= rd;  wait for 1 ns;

    -- LANE 4
    instruction <= mk_li(4, x"8135");  wait for 1 ns;
    exp := x"00000000000081356969ABADCAB1AEFC";
    assert rd = exp report "LI in Lane 4 mismatched..." severity error;
    rs1 <= rd;  wait for 1 ns;

    -- LANE 5
    instruction <= mk_li(5, x"8000");  wait for 1 ns;
    exp := x"00000000800081356969ABADCAB1AEFC";
    assert rd = exp report "LI in Lane 5 mismatched..." severity error;
    rs1 <= rd;  wait for 1 ns;

    -- LANE 6
    instruction <= mk_li(6, x"FEED");  wait for 1 ns;
    exp := x"0000FEED800081356969ABADCAB1AEFC";
    assert rd = exp report "LI in Lane 6 mismatched..." severity error;
    rs1 <= rd;  wait for 1 ns;

    -- LANE 7 (top-most 16b)
    instruction <= mk_li(7, x"DEAD");  wait for 1 ns;
    exp := x"DEADFEED800081356969ABADCAB1AEFC";
    assert rd = exp report "LI in Lane 7 mismatched..." severity error;
    rs1 <= rd;  wait for 1 ns;

    -- Overwrite lane 1 (prove we can update any slot)
    instruction <= mk_li(1, x"CAB0");  wait for 1 ns;
    exp := x"DEADFEED800081356969ABADCAB0AEFC";
    assert rd = exp report "LI in Lane 1 overwrite mismatched..." severity error;
    rs1 <= rd;  wait for 1 ns;

    -- (Optional) Spacer/reset section — using '-' may propagate unknowns in sim.
    -- Prefer zeros to keep waves clean.
    instruction <= (others => '-');  wait for 1 ns;
    rs1 <= (others => '-');          wait for 1 ns;

    ----------------------------------------------------------------
    -- == R4 INSTRUCTIONS ==
    -- One or two tests per form:
    --   000/001: INT add (LOW/HIGH 16x16?32 into 32-bit halves with sat)
    --   010/011: INT sub (LOW/HIGH 16x16?32 into 32-bit halves with sat)
    --   100/101: LONG add (choose 32 half, 32x32?64 into 64-bit with sat)
    --   110/111: LONG sub (...)
    ----------------------------------------------------------------

    -- FORM 000 : INT · LOW · ADD (two 32-bit halves per lane)
    rs1 <= x"00000000800000017FFFFFFEFFFFFFFF";
    rs2 <= x"FFFFFFFDFFFF8000FFFF7FFFFFFF0002";
    rs3 <= x"FFFF0008FFFF0001FFFF7FFFFFFF0003";
    instruction <= mk_r4("000");
    wait for 5 ns;
    exp := x"FFFFFFE8800000007FFFFFFF00000005";
    assert rd = exp report "FORM 000: INT LOW ADD ERROR ... " severity error;

    -- FORM 001 : INT · HIGH · ADD
    rs1 <= x"00000000800000017FFFFFFEFFFFFFFF";
    rs2 <= x"FFFDFFFF8000FFFF7FFFFFFF0002FFFF";
    rs3 <= x"0008FFFF0001FFFF7FFFFFFF0003FFFF";
    instruction <= mk_r4("001");
    wait for 5 ns;
    exp := x"FFFFFFE8800000007FFFFFFF00000005";
    assert rd = exp report "FORM 001: INT HIGH ADD ERROR ... " severity error;

    -- FORM 010 : INT · LOW · SUB
    rs1 <= x"00000000800000107FFFFFF0FFFFFFFE";
    rs2 <= x"000000000000800000007FFF00000003";
    rs3 <= x"0000000000008000000080000000FFFF";
    instruction <= mk_r4("010");
    wait for 5 ns;
    exp := x"00000000800000007FFFFFFF00000001";
    assert rd = exp report "FORM 010: INT LOW SUB ERROR ... " severity error;

    -- FORM 011 : INT · HIGH · SUB
    rs1 <= x"00000000800000107FFFFFF0FFFFFFFE";
    rs2 <= x"00000000800000007FFF000000030000";
    rs3 <= x"000000008000000080000000FFFF0000";
    instruction <= mk_r4("011");
    wait for 5 ns;
    exp := x"00000000800000007FFFFFFF00000001";
    assert rd = exp report "FORM 011: INT HIGH SUB ERROR ... " severity error;

    -- FORM 100 : LONG · LOW · ADD (32x32?64, 64-bit sat)
    -- Test 1: positive overflow (top lane) and negative underflow (bottom)
    rs1 <= x"7FFFFFFFFFFFFFF08000000000000010";
    rs2 <= x"000000007FFFFFFF0000000080000000";
    rs3 <= x"000000007FFFFFFF000000007FFFFFFF";
    instruction <= mk_r4("100");
    wait for 5 ns;
    exp := x"7FFFFFFFFFFFFFFF8000000000000000";
    assert rd = exp report "FORM 100: Sat. LONG LOW ADD ERROR ..." severity error;

    -- Test 2: normal computation (clean numbers)
    rs1 <= x"000000000000000B0000000000000079";
    rs2 <= x"00000000FFFFFFFE00000000FFFFFFFD";
    rs3 <= x"00000000FFFFFFFA0000000000000002";
    instruction <= mk_r4("100");
    wait for 5 ns;
    exp := x"00000000000000170000000000000073";
    assert rd = exp report "FORM 100: Comp. LONG LOW ADD ERROR ..." severity error;

    -- FORM 101 : LONG · HIGH · ADD (same as 100 but high32 multiplicands)
    -- Test 1: saturation
    rs1 <= x"7FFFFFFFFFFFFFF08000000000000010";
    rs2 <= x"7FFFFFFF000000008000000000000000";
    rs3 <= x"7FFFFFFF000000007FFFFFFF00000000";
    instruction <= mk_r4("101");
    wait for 5 ns;
    exp := x"7FFFFFFFFFFFFFFF8000000000000000";
    assert rd = exp report "FORM 101: Sat. LONG HIGH ADD ERROR ..." severity error;

    -- Test 2: computation
    rs1 <= x"000000000000000B0000000000000079";
    rs2 <= x"FFFFFFFE00000000FFFFFFFD00000000";
    rs3 <= x"FFFFFFFA000000000000000200000000";
    instruction <= mk_r4("101");
    wait for 5 ns;
    exp := x"00000000000000170000000000000073";
    assert rd = exp report "FORM 101: Comp. LONG HIGH ADD ERROR ..." severity error;

    -- FORM 110 : LONG · LOW · SUB
    -- Test 1: saturation
    rs1 <= x"7FFFFFFFFFFFFFF08000000000000010";
    rs2 <= x"0000000080000000000000007FFFFFFF";
    rs3 <= x"000000007FFFFFFF000000007FFFFFFF";
    instruction <= mk_r4("110");
    wait for 5 ns;
    exp := x"7FFFFFFFFFFFFFFF8000000000000000";
    assert rd = exp report "FORM 110: Sat. LONG LOW SUB ERROR ..." severity error;

    -- Test 2: computation
    rs1 <= x"000000000000000DFFFFFFFFFFFFFC17";
    rs2 <= x"00000000FFFFFFFA00000000FFFFFF9C";
    rs3 <= x"00000000FFFFFFFE000000000000000A";
    instruction <= mk_r4("110");
    wait for 5 ns;
    exp := x"0000000000000001FFFFFFFFFFFFFFFF";
    assert rd = exp report "FORM 110: Comp. LONG LOW SUB ERROR ..." severity error;

    -- FORM 111 : LONG · HIGH · SUB
    -- Test 1: saturation
    rs1 <= x"7FFFFFFFFFFFFFF08000000000000010";
    rs2 <= x"80000000000000007FFFFFFF00000000";
    rs3 <= x"7FFFFFFF000000007FFFFFFF00000000";
    instruction <= mk_r4("111");
    wait for 5 ns;
    exp := x"7FFFFFFFFFFFFFFF8000000000000000";
    assert rd = exp report "FORM 111: Sat. LONG HIGH SUB ERROR ..." severity error;

    -- Test 2: computation
    rs1 <= x"000000000000000DFFFFFFFFFFFFFC17";
    rs2 <= x"FFFFFFFA00000000FFFFFF9C00000000";
    rs3 <= x"FFFFFFFE000000000000000A00000000";
    instruction <= mk_r4("111");
    wait for 5 ns;
    exp := x"0000000000000001FFFFFFFFFFFFFFFF";
    assert rd = exp report "FORM 111: Comp. LONG HIGH SUB ERROR ..." severity error;

    ----------------------------------------------------------------
    -- == R3 INSTRUCTIONS ==
    -- Opcodes (per your map):
    --   0000 NOP     | 0001 SHRHI    | 0010 AU      | 0011 CNT1H
    --   0100 AHS     | 0101 OR       | 0110 BCW     | 0111 MAXWS
    --   1000 MINWS   | 1001 MLHU     | 1010 MLHCU   | 1011 AND
    --   1100 CLZW    | 1101 ROTW     | 1110 SFWU    | 1111 SFHS
    --
    -- For ops that *use* instruction(14:10) as an immediate/shift (e.g., SHRHI, MLHCU),
    -- we pass the desired 5-bit value via mk_r3’s second arg.
    ----------------------------------------------------------------

    -- 0000 : NOP (no operation) — rd should be unchanged/zero (given zeroed rs*)
    rs1 <= x"ABCDEFABCDEFABCD80008135DEADFEED";
    rs2 <= x"10000100000011111110000000111010";
    rs3 <= x"10000100000011111110000000111010";
    instruction <= mk_r3("0000", "00000");
    wait for 5 ns;
    exp := x"00000000000000000000000000000000";
    assert rd = exp report "OPCODE 0000: NOP ERROR ..." severity error;

    -- 0001 : SHRHI (per-halfword logical right shift by imm4 = 31 here)
    rs1 <= x"ABCDEFABCDEFABCD80008135DEADFEED";
    rs2 <= (others => '0');
    rs3 <= (others => '0');
    instruction <= mk_r3("0001", "11111"); -- shift amount = 31 (lower 4 bits used)
    wait for 5 ns;
    exp := x"00010001000100010001000100010001";
    assert rd = exp report "OPCODE 0001: SHRHI ERROR ..." severity error;

    -- 0010 : AU (add word unsigned) — 4 independent 32-bit adds (mod 2^32)
    rs1 <= x"11111111222222223333333344444444";
    rs2 <= x"0102030405060708090A0B0C0D0E0F10";
    rs3 <= (others => '0');
    instruction <= mk_r3("0010", "11111");
    wait for 5 ns;
    exp := x"121314152728292A3C3D3E3F51525354";
    assert rd = exp report "OPCODE 0010: AU ERROR ..." severity error;

    -- 0011 : CNT1H (count ones per 16-bit halfword)
    rs1 <= x"0000FFFF5555AAAA80007FFF00FFFF00";
    rs2 <= x"0102030405060708090A0B0C0D0E0F10";
    rs3 <= (others => '0');
    instruction <= mk_r3("0011", "11111");
    wait for 5 ns;
    exp := x"00000010000800080001000F00080008";
    assert rd = exp report "OPCODE CNT1H ERROR ..." severity error;

    -- 0100 : AHS (add halfword signed with saturation)
    rs1 <= x"FFFF12348000C000400080007FFF0003";
    rs2 <= x"0002EDCC8000C0004000FFFF00010004";
    rs3 <= (others => '0');
    instruction <= mk_r3("0100", "11111");
    wait for 5 ns;
    exp := x"00010000800080007FFF80007FFF0007";
    assert rd = exp report "OPCODE AHS ERROR ..." severity error;

    -- 0101 : OR (bitwise OR)
    rs1 <= x"0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F";
    rs2 <= x"F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0";
    rs3 <= (others => '0');
    instruction <= mk_r3("0101", "11111");
    wait for 5 ns;
    exp := x"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF";
    assert rd = exp report "OPCODE OR ERROR ..." severity error;

    -- 0110 : BCW (broadcast top word W3 into all 4 words)
    rs1 <= x"DEADBEEF11223344A1B2C3D401020304";
    rs2 <= (others => '0');
    rs3 <= (others => '0');
    instruction <= mk_r3("0110", "11111");
    wait for 5 ns;
    exp := x"DEADBEEFDEADBEEFDEADBEEFDEADBEEF";
    assert rd = exp report "OPCODE BCW ERROR ..." severity error;

    -- 0111 : MAXWS (per-word signed max; ties pick rs1 per your >=)
    rs1 <= x"AAAAAAAA5555555500000000FFFFFFFF";
    rs2 <= x"AAAAAAAA44444444FFFFFFFF00000000";
    rs3 <= (others => '0');
    instruction <= mk_r3("0111", "11111");
    wait for 5 ns;
    exp := x"AAAAAAAA555555550000000000000000";
    assert rd = exp report "OPCODE MAXWS ERROR ..." severity error;

    -- 1000 : MINWS (per-word signed min; ties pick rs1 per your <=)
    rs1 <= x"7FFFFFFF80000000FFFFFFFF00000001";
    rs2 <= x"7FFFFFFE80000001FFFFFFFE00000002";
    rs3 <= (others => '0');
    instruction <= mk_r3("1000", "11111");
    wait for 5 ns;
    exp := x"7FFFFFFE80000000FFFFFFFE00000001";
    assert rd = exp report "OPCODE MINWS ERROR ..." severity error;

    -- 1001 : MLHU (low16×low16 unsigned ? 32 per word)
    rs1 <= x"AAAAFFFFBBBB8000CCCC0001DDDD1234";
    rs2 <= x"EEEEFFFFFFFF80000000000099990002";
    rs3 <= (others => '0');
    instruction <= mk_r3("1001", "11111");
    wait for 5 ns;
    exp := x"FFFE0001400000000000000000002468";
    assert rd = exp report "OPCODE MLHU ERROR ..." severity error;

    -- 1010 : MLHCU (low16×imm5 unsigned ? 32 per word; imm5=5)
    rs1 <= x"A1A1FFFFB2B21234C3C300FFD4D40003";
    rs2 <= (others => '0');
    rs3 <= (others => '0');
    instruction <= mk_r3("1010", "00101");  -- imm5 = 5
    wait for 5 ns;
    exp := x"0004FFFB00005B04000004FB0000000F";
    assert rd = exp report "OPCODE MLHCU ERROR ..." severity error;

    -- 1011 : AND (bitwise AND)
    rs1 <= x"A1A1FFFFB2B21234C3C300FFD4D40003";
    rs2 <= x"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF";
    rs3 <= (others => '0');
    instruction <= mk_r3("1011", "00101");
    wait for 5 ns;
    exp := x"A1A1FFFFB2B21234C3C300FFD4D40003";
    assert rd = exp report "OPCODE AND ERROR ..." severity error;

    -- 1100 : CLZW (count leading zeros per word)
    rs1 <= x"80000000400000000000000100000000";
    rs2 <= (others => '0');
    rs3 <= (others => '0');
    instruction <= mk_r3("1100", "00101");
    wait for 5 ns;
    exp := x"00000000000000010000001F00000020";
    assert rd = exp report "OPCODE CLZW ERROR ..." severity error;

    -- 1101 : ROTW (rotate-right per word by rs2[4:0] per word)
    rs1 <= x"0000000180000000DEADBEEF01234567";
    rs2 <= x"000000010000001F0000002000000010";
    rs3 <= (others => '0');
    instruction <= mk_r3("1101", "00101");
    wait for 5 ns;
    exp := x"8000000000000001DEADBEEF45670123";
    assert rd = exp report "OPCODE ROTW ERROR ..." severity error;

    -- 1110 : SFWU (unsigned per-word: rd = rs2 - rs1)
    rs2 <= x"A5A5A5A55555AAAA123456780F0F0F0F";
    rs1 <= x"87BAC9B76432654312344DE844105451";
    rs3 <= x"1A3DEADBFECAFEFABCDEF23456790101";
    instruction <= mk_r3("1110", "00101");
    wait for 5 ns;
    exp := x"1DEADBEEF123456700000890CAFEBABE";
    assert rd = exp report "OPCODE SFWU ERROR ..." severity error;

    -- 1111 : SFHS (signed per-halfword with saturation: rd = rs2 - rs1)
    rs2 <= x"00017FFF80007FFF40007FFF80000000";
    rs1 <= x"FFFF000100017FFF4000FFFFFFFF0001";
    rs3 <= (others => '0');
    instruction <= mk_r3("1111", "00101");
    wait for 5 ns;
    exp := x"00027FFE8000000000007FFF8001FFFF";
    assert rd = exp report "OPCODE SFHS ERROR ..." severity error;

    ----------------------------------------------------------------
    -- End of suite — clear inputs and finish
    ----------------------------------------------------------------
    rs2 <= (others => '0');
    rs1 <= (others => '0');
    rs3 <= (others => '0');
    instruction <= (others => '0');
    wait for 5 ns;

    wait;
  end process;
end architecture;
