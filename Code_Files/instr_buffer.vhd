library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

entity instr_buffer is
  port(
    clk       : in  std_logic;
    rst       : in  std_logic;
    instr_out : out std_logic_vector(24 downto 0); -- current instruction
    pc_out    : out unsigned(5 downto 0)           -- current PC (0..63)
  );
end entity instr_buffer;

architecture behavioral of instr_buffer is

  -- 64 x 25-bit memory
  type mem_t is array (0 to 63) of std_logic_vector(24 downto 0);
  signal mem : mem_t := (others => (others => '0'));

  -- program counter
  signal pc  : unsigned(5 downto 0) := (others => '0');

  -- helper: convert bit_vector -> std_logic_vector
  function bv_to_slv(b : bit_vector) return std_logic_vector is
    variable res : std_logic_vector(b'range);
  begin
    for i in b'range loop
      if b(i) = '0' then
        res(i) := '0';
      else
        res(i) := '1';
      end if;
    end loop;
    return res;
  end function;

begin

  ---------------------------------------------------------------------------
  -- ONE-TIME LOAD FROM "instructions.txt"
  --  Each line must be exactly 25 chars of 0/1, no spaces.
  ---------------------------------------------------------------------------
  file_load_proc : process
    file f  : text open read_mode is
      "instructions.mem";
    variable L  : line;
    variable bv : bit_vector(24 downto 0);
    variable i  : integer := 0;
  begin
    -- default clear
    for idx in 0 to 63 loop
      mem(idx) <= (others => '0');
    end loop;

    i := 0;
    while (not endfile(f)) and (i <= 63) loop
      readline(f, L);
      -- read 25 bits "000...1" into bit_vector
      read(L, bv);
      mem(i) <= bv_to_slv(bv);
      report "instr_buffer: loaded instruction " & integer'image(i);
      i := i + 1;
    end loop;

    report "instr_buffer: finished loading "
           & integer'image(i) & " line(s) from instructions.txt";

    wait;  -- run once
  end process;

  ---------------------------------------------------------------------------
  -- MAIN: on each clk, output mem(pc) and increment pc
  ---------------------------------------------------------------------------
  main_proc : process(clk, rst)
  begin
    if rst = '1' then
      pc        <= (others => '0');
      instr_out <= (others => '0');
      pc_out    <= (others => '0');

    elsif rising_edge(clk) then
      instr_out <= mem(to_integer(pc));
      pc_out    <= pc;

      if pc = "111111" then
        pc <= (others => '0');
      else
        pc <= pc + 1;
      end if;
    end if;
  end process;

end architecture behavioral;
