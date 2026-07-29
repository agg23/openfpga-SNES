library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Hardware accurate SNES SA-1 arithmetic-unit divider (sign-magnitude division).
-- Based on the SA-1 reverse engineering effort by Vitor Vilela, his test rom and the
-- validation table on sneslab.net.

-- This logic is resource optimized for the Cyclone V because ALMs are getting scarce.
-- ALMs are reclaimed by offloading the remainder math to a multiplier in a DSP block.

-- Access timing is out of scope and modeled by the SA-1 state machine.

entity SA1DIV is
    port (
        numer    : in  std_logic_vector(15 downto 0);       -- numerator, signed
        denom    : in  std_logic_vector(15 downto 0);       -- denominator, unsigned
        quotient : out std_logic_vector(15 downto 0);       -- quotient, signed (sign of numerator)
        remain   : out std_logic_vector(15 downto 0)        -- remainder, unsigned magnitude
    );
end entity;

architecture rtl of SA1DIV is
begin
    process(numer, denom)
        variable n_s  : signed(16 downto 0);                -- sign-extended numerator
        variable nmag : unsigned(16 downto 0);              -- |numerator|, 0..32768
        variable d_u  : unsigned(16 downto 0);              -- denominator, 0..65535
        variable qmag : unsigned(16 downto 0);              -- |quotient|
        variable r_u  : unsigned(16 downto 0);              -- |remainder|
        variable q_s  : signed(17 downto 0);                -- signed quotient (holds -|q| for |q|=32768)
    begin
        n_s := resize(signed(numer), 17);
        d_u := unsigned('0' & denom);
        nmag := unsigned(abs(n_s));

        if d_u = 0 then                                     -- Reproduce the SA-1 divide-by-zero quirk
            r_u := nmag;
            if n_s < 0 then
                q_s := to_signed(1, 18);
            else
                q_s := to_signed(-1, 18);
            end if;
        else
            qmag := nmag / d_u;                             -- unsigned magnitude division
            r_u := nmag - resize(qmag * d_u, 17);           -- remainder = nmag - qmag*denominator
            q_s  := signed(resize(qmag, 18));               -- apply the numerator's sign
            if n_s < 0 then
                q_s := -q_s;
            end if;
        end if;

        quotient <= std_logic_vector(q_s(15 downto 0));
        remain   <= std_logic_vector(r_u(15 downto 0));
    end process;
end architecture;
