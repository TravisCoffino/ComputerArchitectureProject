library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity reg_if_id is
  port(
    clk       : in  std_logic;
    rst       : in  std_logic;

    -- from IF stage (buffer)
    instr_in  : in  std_logic_vector(24 downto 0);
    pc_in     : in  unsigned(5 downto 0);

    -- to ID stage
    instr_out : out std_logic_vector(24 downto 0);
    pc_out    : out unsigned(5 downto 0)
  );
end entity;

architecture rtl of reg_if_id is
begin
  process(clk, rst)
  begin
    if rst = '1' then
      instr_out <= (others => '0');
      pc_out    <= (others => '0');
    elsif rising_edge(clk) then
      instr_out <= instr_in;
      pc_out    <= pc_in;
    end if;
  end process;
end architecture;
