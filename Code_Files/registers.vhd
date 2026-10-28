library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;	   

entity registers is
  port( 
    instructioni : in  std_logic_vector(24 downto 0);
    instruction  : out std_logic_vector(24 downto 0);
    clk          : in  std_logic;

    wr_en        : in  std_logic;	 
    wr_addr      : in  std_logic_vector(4 downto 0);
    wr_data      : in  std_logic_vector(127 downto 0);

    rs1          : out std_logic_vector(127 downto 0);	   
    rs2          : out std_logic_vector(127 downto 0);
    rs3          : out std_logic_vector(127 downto 0)
  );
end entity;

architecture memory of registers is	
  subtype idx_t is integer range 0 to 31;
  type mem_t is array (idx_t) of std_logic_vector(127 downto 0);
  signal mem : mem_t := (others => (others => '0'));

  -- Constrain to 5 bits to avoid COMP96_0149
  function to_idx(a : std_logic_vector(4 downto 0)) return idx_t is
  begin
    return idx_t'(to_integer(unsigned(a)));
  end function;

  -- Helper: read one word from mem
  function fetch_data(addr : std_logic_vector(4 downto 0); m : mem_t)
    return std_logic_vector is
  begin
    return m(to_idx(addr));
  end function;
begin

  ------------------------------------------------------------------
  -- WRITE PORT: synchronous 1W
  ------------------------------------------------------------------
  write_proc : process(clk)
  begin
    if rising_edge(clk) then
      if wr_en = '1' then
        mem(to_idx(wr_addr)) <= wr_data; 
      end if;

      -- pass-through instruction (latched if you want it clocked)
      instruction <= instructioni;
    end if;
  end process;

  ------------------------------------------------------------------
  -- READ PORTS: combinational 3R based on current instructioni
  ------------------------------------------------------------------
  read_proc : process(instructioni, mem)
  begin
    -- defaults
    rs1 <= (others => '0');
    rs2 <= (others => '0');
    rs3 <= (others => '0');

    if instructioni(24) = '0' then                     -- LI
      -- LI uses rd as "source" when building new value
      rs1 <= fetch_data(instructioni(4 downto 0), mem);

    elsif instructioni(24 downto 23) = "10" then       -- R4
      rs1 <= fetch_data(instructioni(9  downto 5),  mem);
      rs2 <= fetch_data(instructioni(14 downto 10), mem);
      rs3 <= fetch_data(instructioni(19 downto 15), mem);

    elsif instructioni(24 downto 23) = "11" then       -- R3
      rs1 <= fetch_data(instructioni(9  downto 5),  mem);
      rs2 <= fetch_data(instructioni(14 downto 10), mem);
      -- rs3 unused for R3

    else
      -- illegal / unused opcode: keep zeros
      null;
    end if;
  end process;

end architecture memory;
