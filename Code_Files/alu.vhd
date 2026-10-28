library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--==============================================================================
--  ALU (128-bit SIMD): LI / R4 MAC / R3 vector ops
--  instruction[24]    : 0 = LI, 1 = R3/R4
--  instruction[24:23] : "10" = R4  (MAC family, see table)
--                       "11" = R3  (packed ops, see table)
--==============================================================================

entity alu is
    port (
        instruction  : in  std_logic_vector(24 downto 0);
        rs1, rs2, rs3: in  std_logic_vector(127 downto 0);
        rd           : out std_logic_vector(127 downto 0)
    );
end entity;

architecture behavioral of alu is

--==============================================================================
--  CONSTANTS / SIZES
--==============================================================================
constant TOT_BITS    : integer := 128;

-- -- LI (load-immediate) shape: 8x16
constant li_LANES    : integer := 8;
constant li_LANE_W   : integer := 16;

-- -- R4 (MAC) shape: 2x64
constant r4_LANES    : integer := 2;
constant r4_LANE_W   : integer := 64;

-- -- R3 (packed ops) shape: 4x32 words, or 8x16 halfwords
constant r3_LANES    : integer := 4;
constant r3_LANE_W   : integer := 32;
constant WIDTH_BITS  : integer := r3_LANES * r3_LANE_W;  -- 128
constant HALF_W      : integer := 16;                    -- 16
constant NUM_HALVES  : integer := WIDTH_BITS / HALF_W;   -- 8
constant NUM_WORDS   : integer := r3_LANES;              -- 4

--==============================================================================
--  R4: Saturation helpers (per spec)
--==============================================================================

-- 32-bit saturate of a 64-bit accumulator
function sat32(x : signed(63 downto 0)) return signed is
  constant MAX32 : signed(31 downto 0) := signed(x"7FFFFFFF");
  constant MIN32 : signed(31 downto 0) := signed(x"80000000");
begin
  if    x > resize(MAX32, x'length) then return MAX32;
  elsif x < resize(MIN32, x'length) then return MIN32;
  else                                  return resize(x, 32);
  end if;
end function;

-- 64-bit saturate of a 128-bit accumulator
function sat64(x : signed(127 downto 0)) return signed is
  constant MAX64 : signed(63 downto 0) := signed(x"7FFFFFFFFFFFFFFF");
  constant MIN64 : signed(63 downto 0) := signed(x"8000000000000000");
begin
  if    x > resize(MAX64, x'length) then return MAX64;
  elsif x < resize(MIN64, x'length) then return MIN64;
  else                                  return resize(x, 64);
  end if;
end function;

--==============================================================================
--  R3: Opcode nibble (instruction[18:15]) definitions
--  (Matches your table: NOP, SHRHI, AU, CNT1H, AHS, OR, BCW, MAXWS, MINWS,
--   MLHU, MLHCU, AND, CLZW, ROTW, SFWU, SFHS)
--==============================================================================
constant OPC_NOP   : std_logic_vector(3 downto 0) := "0000";
constant OPC_SHRHI : std_logic_vector(3 downto 0) := "0001";
constant OPC_AU    : std_logic_vector(3 downto 0) := "0010";
constant OPC_CNT1H : std_logic_vector(3 downto 0) := "0011";
constant OPC_AHS   : std_logic_vector(3 downto 0) := "0100";
constant OPC_OR    : std_logic_vector(3 downto 0) := "0101";
constant OPC_BCW   : std_logic_vector(3 downto 0) := "0110";
constant OPC_MAXWS : std_logic_vector(3 downto 0) := "0111";
constant OPC_MINWS : std_logic_vector(3 downto 0) := "1000";
constant OPC_MLHU  : std_logic_vector(3 downto 0) := "1001";
constant OPC_MLHCU : std_logic_vector(3 downto 0) := "1010";
constant OPC_AND   : std_logic_vector(3 downto 0) := "1011";
constant OPC_CLZW  : std_logic_vector(3 downto 0) := "1100";
constant OPC_ROTW  : std_logic_vector(3 downto 0) := "1101";
constant OPC_SFWU  : std_logic_vector(3 downto 0) := "1110";
constant OPC_SFHS  : std_logic_vector(3 downto 0) := "1111";

--==============================================================================
--  R3: Halfword saturation helpers
--==============================================================================
constant S16_MAX : signed(15 downto 0) := to_signed( 32767, 16); -- 0x7FFF
constant S16_MIN : signed(15 downto 0) := to_signed(-32768, 16); -- 0x8000

function clamp16(x17 : signed(16 downto 0)) return signed is
begin
  if    x17 > to_signed( 32767, 17) then return S16_MAX;
  elsif x17 < to_signed(-32768, 17) then return S16_MIN;
  else                                  return signed(resize(x17, 16));
  end if;
end function;

function sat16(x : signed(15 downto 0)) return signed is
begin
  if    x > S16_MAX then return S16_MAX;
  elsif x < S16_MIN then return S16_MIN;
  else                 return x;
  end if;
end function;

begin
process(all)

  --===========================================================================
  --  LI (instruction[24] = '0'): load 16-bit immediate into one of 8 lanes
  --  Lane index = instruction[23:21], imm16 = instruction[20:5]
  --===========================================================================
  variable li_tmp      : std_logic_vector(TOT_BITS-1 downto 0);
  variable li_lane_idx : integer range 0 to li_LANES-1;
  variable li_imm16    : std_logic_vector(li_LANE_W-1 downto 0);

  --===========================================================================
  --  R4 (instruction[24:23] = "10"): MAC family (see your R4 table)
  --    bit22=longInt (0=int halves, 1=long 64)
  --    bit21=highLow (0=low, 1=high half selection)
  --    bit20=subAdd  (0=add, 1=sub)
  --===========================================================================
  variable longInt, subAdd, highLow : std_logic;
  variable outv    : std_logic_vector(r4_LANES*r4_LANE_W-1 downto 0);

  -- per-lane 64-bit signed views
  variable x1_64, x2_64, x3_64 : signed(r4_LANE_W-1 downto 0);

  -- INT mode temps (2x32 halves inside each 64)
  variable dst_64              : signed(63 downto 0);
  variable a16, b16            : signed(15 downto 0);
  variable prod32              : signed(31 downto 0);
  variable acc64               : signed(63 downto 0);

  -- LONG mode temps (select 32-bit half, 32x32->64, accumulate into 64)
  variable a32, b32            : signed(31 downto 0);
  variable prod64              : signed(63 downto 0);
  variable acc128              : signed(127 downto 0);
  variable res64               : signed(63 downto 0);

  variable lo32, hi32          : integer;

  --===========================================================================
  --  R3 (instruction[24:23] = "11"): packed ops case on instruction[18:15]
  --===========================================================================
  variable r3_tmp : std_logic_vector(WIDTH_BITS-1 downto 0);
  variable opc4   : std_logic_vector(3 downto 0);

  variable sh4  : integer  range 0 to 15;         -- rs2[13:10]
  variable imm5 : unsigned(4 downto 0);           -- rs2[14:10]

  -- temps
  variable r3_a16, r3_b16, r3_r16 : signed(15 downto 0);
  variable aw, bw, rw             : signed(31 downto 0);
  variable u16, v16               : unsigned(15 downto 0);
  variable u32, v32, r32          : unsigned(31 downto 0);
  variable r3_prod32              : unsigned(31 downto 0);
  variable cnt                    : integer range 0 to 32;
  variable k                      : integer range 0 to 31;
  variable word_slv               : std_logic_vector(31 downto 0);

begin
  if instruction(24) = '0' then
    --=== LI ==================================================================
    li_tmp := rs1;
    li_lane_idx := to_integer(unsigned(instruction(23 downto 21)));
    li_imm16    := instruction(20 downto 5);

    if (li_lane_idx >= 0) and (li_lane_idx < li_LANES) then
      li_tmp((li_lane_idx+1)*li_LANE_W-1 downto li_lane_idx*li_LANE_W) := li_imm16;
    end if;

    rd <= li_tmp;

  elsif instruction(24 downto 23) = "10" then
    --=== R4: MAC family ======================================================
    outv    := (others => '0');
    longInt := instruction(22);	
	subAdd  := instruction(21);
    highLow := instruction(20);
    

    for lane in 0 to r4_LANES-1 loop
      x1_64 := signed(rs1((lane+1)*64-1 downto lane*64));
      x2_64 := signed(rs2((lane+1)*64-1 downto lane*64));
      x3_64 := signed(rs3((lane+1)*64-1 downto lane*64));

      if longInt = '0' then
        -- -- INT (000/001/010/011): 16x16->32 add/sub into each 32-bit half with saturation
        dst_64 := x1_64;

        for half in 0 to 1 loop
          lo32 := half*32;
          hi32 := lo32+31;

          if highLow = '0' then
            -- Low 16 of each 32 field (000 / 010)
            a16 := signed(x2_64(lo32+15 downto lo32));
            b16 := signed(x3_64(lo32+15 downto lo32));
          else
            -- High 16 of each 32 field (001 / 011)
            a16 := signed(x2_64(hi32 downto hi32-15));
            b16 := signed(x3_64(hi32 downto hi32-15));
          end if;

          prod32 := signed(a16) * signed(b16);

          if subAdd = '0' then
            -- Add with saturation (000/001)
            acc64 := resize(signed(dst_64(hi32 downto lo32)), 64) + resize(signed(prod32), 64);
          else
            -- Sub with saturation (010/011)
            acc64 := resize(signed(dst_64(hi32 downto lo32)), 64) - resize(signed(prod32), 64);
          end if;

          dst_64(hi32 downto lo32) := sat32(acc64);  -- clamp to 32-bit
        end loop;

        outv((lane+1)*64-1 downto lane*64) := std_logic_vector(dst_64);

      else
        -- -- LONG (100/101/110/111): pick 32 half, 32x32->64, add/sub into 64 with saturation
        if highLow = '0' then
          -- Low 32 (100 / 110)
          a32 := signed(x2_64(31 downto 0));
          b32 := signed(x3_64(31 downto 0));
        else
          -- High 32 (101 / 111)
          a32 := signed(x2_64(63 downto 32));
          b32 := signed(x3_64(63 downto 32));
        end if;

        prod64 := signed(a32) * signed(b32);

        if subAdd = '0' then
          -- Add (100/101)
          acc128 := resize(signed(x1_64), 128) + resize(signed(prod64), 128);
        else
          -- Sub (110/111)
          acc128 := resize(signed(x1_64), 128) - resize(signed(prod64), 128);
        end if;

        res64 := sat64(acc128);  -- clamp to 64-bit
        outv((lane+1)*64-1 downto lane*64) := std_logic_vector(res64);
      end if;
    end loop;

    rd <= outv;

  elsif instruction(24 downto 23) = "11" then
    --=== R3: packed ops ======================================================
    r3_tmp := (others => '0');
    opc4   := instruction(18 downto 15);
    sh4    := to_integer(unsigned(instruction(13 downto 10)));
    imm5   := unsigned(instruction(14 downto 10));

    case opc4 is

      -- xxxx0000 : NOP (do nothing)
      when OPC_NOP =>
        null;

      -- xxxx0001 : SHRHI  (packed 16-bit logical right shift by sh4)
      when OPC_SHRHI =>
        for i in 0 to NUM_HALVES-1 loop
          r3_tmp(i*HALF_W+15 downto i*HALF_W) :=
            std_logic_vector(shift_right(unsigned(rs1(i*HALF_W+15 downto i*HALF_W)), sh4));
        end loop;

      -- xxxx0010 : AU     (packed 32-bit unsigned add)
      when OPC_AU =>
        for w in 0 to NUM_WORDS-1 loop
          r3_tmp(w*32+31 downto w*32) :=
            std_logic_vector(unsigned(rs1(w*32+31 downto w*32)) +
                             unsigned(rs2(w*32+31 downto w*32)));
        end loop;

      -- xxxx0011 : CNT1H  (count ones in each 16-bit halfword)
      when OPC_CNT1H =>
        for i in 0 to NUM_HALVES-1 loop
          cnt := 0;
          for b in 0 to 15 loop
            if rs1(i*HALF_W + b) = '1' then cnt := cnt + 1; end if;
          end loop;
          r3_tmp(i*HALF_W+15 downto i*HALF_W) := std_logic_vector(to_unsigned(cnt, 16));
        end loop;

      -- xxxx0100 : AHS    (packed 16-bit signed add with saturation)
      when OPC_AHS =>
        for i in 0 to NUM_HALVES-1 loop
          r3_a16 := signed(rs1(i*16+15 downto i*16));
          r3_b16 := signed(rs2(i*16+15 downto i*16));
          r3_r16 := clamp16(resize(r3_a16,17) + resize(r3_b16,17));
          r3_tmp(i*16+15 downto i*16) := std_logic_vector(r3_r16);
        end loop;

      -- xxxx0101 : OR     (bitwise OR)
      when OPC_OR =>
        r3_tmp := rs1 or rs2;

      -- xxxx0110 : BCW    (broadcast word: rs1[127:96] into all four 32 slots)
      when OPC_BCW =>
        for w in 0 to NUM_WORDS-1 loop
          r3_tmp(w*32+31 downto w*32) := rs1(127 downto 96);
        end loop;

      -- xxxx0111 : MAXWS  (per-word signed max)
      when OPC_MAXWS =>
        for w in 0 to NUM_WORDS-1 loop
          aw := signed(rs1(w*32+31 downto w*32));
          bw := signed(rs2(w*32+31 downto w*32));
          if aw >= bw then rw := aw; else rw := bw; end if;
          r3_tmp(w*32+31 downto w*32) := std_logic_vector(rw);
        end loop;

      -- xxxx1000 : MINWS  (per-word signed min)
      when OPC_MINWS =>
        for w in 0 to NUM_WORDS-1 loop
          aw := signed(rs1(w*32+31 downto w*32));
          bw := signed(rs2(w*32+31 downto w*32));
          if aw <= bw then rw := aw; else rw := bw; end if;
          r3_tmp(w*32+31 downto w*32) := std_logic_vector(rw);
        end loop;

      -- xxxx1001 : MLHU   (low16*low16 -> 32, unsigned)
      when OPC_MLHU =>
        for w in 0 to NUM_WORDS-1 loop
          u16        := unsigned(rs1(w*32+15 downto w*32));
          v16        := unsigned(rs2(w*32+15 downto w*32));
          r3_prod32  := u16 * v16;  -- 16x16 -> 32
          r3_tmp(w*32+31 downto w*32) := std_logic_vector(r3_prod32);
        end loop;

      -- xxxx1010 : MLHCU  (low16 * imm5 -> 32, unsigned)
      when OPC_MLHCU =>
        for w in 0 to NUM_WORDS-1 loop
          u16        := unsigned(rs1(w*32+15 downto w*32));
          r3_prod32  := u16 * resize(imm5, 16);
          r3_tmp(w*32+31 downto w*32) := std_logic_vector(r3_prod32);
        end loop;

      -- xxxx1011 : AND    (bitwise AND)
      when OPC_AND =>
        r3_tmp := rs1 and rs2;

      -- xxxx1100 : CLZW   (count leading zeros per 32-bit word)
      when OPC_CLZW =>
        for w in 0 to NUM_WORDS-1 loop
          word_slv := rs1(w*32+31 downto w*32);
          cnt := 0;
          for b in 31 downto 0 loop
            if word_slv(b) = '0' then cnt := cnt + 1; else exit; end if;
          end loop;
          r3_tmp(w*32+31 downto w*32) := std_logic_vector(to_unsigned(cnt, 32));
        end loop;

      -- xxxx1101 : ROTW   (rotate-right per 32-bit word by rs2[4:0])
      when OPC_ROTW =>
        for w in 0 to NUM_WORDS-1 loop
          u32 := unsigned(rs1(w*32+31 downto w*32));
          v32 := unsigned(rs2(w*32+31 downto w*32));
          k   := to_integer(v32(4 downto 0)) mod 32;
          if k = 0 then
            r32 := u32;
          else
            r32 := shift_right(u32, k) or shift_left(u32, 32 - k);
          end if;
          r3_tmp(w*32+31 downto w*32) := std_logic_vector(r32);
        end loop;

      -- xxxx1110 : SFWU   (per-word unsigned subtract: rs2 - rs1)
      when OPC_SFWU =>
        for w in 0 to NUM_WORDS-1 loop
          r3_tmp(w*32+31 downto w*32) :=
            std_logic_vector(unsigned(rs2(w*32+31 downto w*32)) -
                             unsigned(rs1(w*32+31 downto w*32)));
        end loop;

      -- xxxx1111 : SFHS   (per-halfword signed subtract with saturation: rs2 - rs1)
      when OPC_SFHS =>
        for i in 0 to NUM_HALVES-1 loop
          r3_a16 := signed(rs1(i*16+15 downto i*16));
          r3_b16 := signed(rs2(i*16+15 downto i*16));
          r3_r16 := clamp16(resize(r3_b16,17) - resize(r3_a16,17));
          r3_tmp(i*16+15 downto i*16) := std_logic_vector(r3_r16);
        end loop;

      when others =>
        null;

    end case;

    rd <= r3_tmp;

  end if;
end process;
end architecture;
