library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity data_forwarding_unit is
  port(
    instr_id  : in  std_logic_vector(24 downto 0); -- ID/EX instr
    rs1i, rs2i, rs3i : in std_logic_vector(127 downto 0);

    -- EX source
    ex_addr   : in  std_logic_vector(4 downto 0);
    ex_data   : in  std_logic_vector(127 downto 0);
    ex_we     : in  std_logic;

    -- WB source
    wb_addr   : in  std_logic_vector(4 downto 0);
    wb_data   : in  std_logic_vector(127 downto 0);
    wb_we     : in  std_logic;

    rs1, rs2, rs3 : out std_logic_vector(127 downto 0)
  );
end entity;

architecture rtl of data_forwarding_unit is
begin
  process(all)
  begin
    rs1 <= rs1i;
    rs2 <= rs2i;
    rs3 <= rs3i;

    if instr_id(24) = '0' then             -- LI
      -- rs1 = rd(4:0)
      if ex_we='1' and instr_id(4 downto 0)=ex_addr then
        rs1 <= ex_data;
      elsif wb_we='1' and instr_id(4 downto 0)=wb_addr then
        rs1 <= wb_data;
      end if;

    elsif instr_id(24 downto 23) = "11" then  -- R3
      -- rs1 = 9:5, rs2 = 14:10
      if ex_we='1' and instr_id(9 downto 5)=ex_addr then
        rs1 <= ex_data;
      elsif wb_we='1' and instr_id(9 downto 5)=wb_addr then
        rs1 <= wb_data;
      end if;

      if ex_we='1' and instr_id(14 downto 10)=ex_addr then
        rs2 <= ex_data;
      elsif wb_we='1' and instr_id(14 downto 10)=wb_addr then
        rs2 <= wb_data;
      end if;

      -- (R4 case similar, adding rs3 checks)
    end if;
  end process;
end architecture;
