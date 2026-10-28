library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity reg_id_ex is
  port(
    instructioni  : in  std_logic_vector(24 downto 0);  
    instruction   : out std_logic_vector(24 downto 0);
    clk           : in  std_logic;

    rs1in         : in  std_logic_vector(127 downto 0);	   
    rs2in         : in  std_logic_vector(127 downto 0);
    rs3in         : in  std_logic_vector(127 downto 0);

    rs1           : out std_logic_vector(127 downto 0);	   
    rs2           : out std_logic_vector(127 downto 0);
    rs3           : out std_logic_vector(127 downto 0)
  );
end entity;

architecture buff of reg_id_ex is
begin
  process(clk)
  begin
    if rising_edge(clk) then
      -- latch operands into EX
      rs1        <= rs1in;
      rs2        <= rs2in;
      rs3        <= rs3in;

      -- ?? latch instruction for EX stage
      instruction <= instructioni;
    end if;
  end process;
end architecture;
