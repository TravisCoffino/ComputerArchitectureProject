library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- EX/WB register / writeback metadata for forwarding
entity exwb_reg is
  port(
    clk          : in  std_logic;
    instruction  : in  std_logic_vector(24 downto 0);  -- current instr in EX stage
    rd_data      : in  std_logic_vector(127 downto 0); -- ALU result from EX

    -- To forwarding unit + register file writeback
    df_addr      : out std_logic_vector(4 downto 0);   -- rd
    df_data      : out std_logic_vector(127 downto 0); -- value to forward/write
    wr_en        : out std_logic                       -- valid write this instr?
  );
end entity;

architecture behavioral of exwb_reg is
  -- returns '1' if this instruction writes rd, else '0'
  function will_write(i : std_logic_vector(24 downto 0)) return std_logic is
  begin
    if    i(24) = '0' then                  -- LI
      return '1';
    elsif i(24 downto 23) = "10" then       -- R4
      return '1';
    elsif i(24 downto 23) = "11" then       -- R3
      -- NOP is opcode 0000 at [18:15]; others write
      if i(18 downto 15) = "0000" then
        return '0';
      else
        return '1';
      end if;
    else                                     -- illegal / reserved -> no write
      return '0';
    end if;
  end function;
begin
  process(clk)
  begin
    if rising_edge(clk) then
      df_addr <= instruction(4 downto 0);        -- rd field
      df_data <= rd_data;                        -- EX result
      wr_en   <= will_write(instruction);        -- write valid?
    end if;
  end process;
end architecture;
