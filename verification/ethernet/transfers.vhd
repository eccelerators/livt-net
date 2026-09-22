library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.livt_lang_package.all;
use work.livt_lang_icontext_package.all;
use work.livt_net_iaxi4liteethernetlitemaster_package.all;
use work.@PACKAGE@.all;

entity frame_transfers is end;
architecture test of frame_transfers is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal ctx : t_icontext_in;
  signal master : t_iaxi4liteethernetlitemaster_out;
  signal slave : t_iaxi4liteethernetlitemaster_in := (
    m_axi_awready => '0', m_axi_wready => '0', m_axi_bresp => "00",
    m_axi_bvalid => '0', m_axi_arready => '0', m_axi_rdata => x"00000000",
    m_axi_rresp => "00", m_axi_rvalid => '0');
  signal offer_rx : integer := 0;
  signal rx_released : integer := 0;
  signal rx_words_seen : integer := 0;
  signal tx_completed : integer := 0;
  signal expected_length : integer := 0;
  signal block_bus : boolean := false;
  signal mac_programmed : boolean := false;
  @DECLARATIONS@
  function payload(i: integer) return std_logic_vector is
  begin return std_logic_vector(to_unsigned((i * 17 + 128) mod 256, 8)); end;
begin
  clk <= not clk after 5 ns;
  ctx <= (clk, rst, to_unsigned(100000000, 32), to_unsigned(10, 32),
          to_unsigned(5, 32), to_unsigned(5, 32));
  dut: entity work.@ENTITY@ @RESET_GENERIC@ port map(
    ctor_axi_in => slave, ctor_axi_out => master,
    ctor_local_mac => (others => (others => '0')), ctor_lvt_context_in => ctx,
    @MAPPINGS@);
  watchdog: process begin
    wait for 20 ms;
    assert false report "Ethernet verification timed out" severity failure;
  end process;

  -- Independent, staggered address/data acceptance and delayed held responses.
  bus_model: process(clk)
    variable cycle: natural := 0;
    variable have_aw, have_w, have_ar: boolean := false;
    variable aw, ar, write_count, read_count, tx_length: integer := 0;
    variable data, expected, held_w: std_logic_vector(31 downto 0);
    variable held_aw, held_ar: std_logic_vector(12 downto 0);
    variable stall_aw, stall_w, stall_ar: boolean := false;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        slave.m_axi_awready <= '0'; slave.m_axi_wready <= '0';
        slave.m_axi_arready <= '0'; slave.m_axi_bvalid <= '0'; slave.m_axi_rvalid <= '0';
        have_aw := false; have_w := false; have_ar := false;
        stall_aw := false; stall_w := false; stall_ar := false;
        cycle := 0; write_count := 0; read_count := 0;
        tx_completed <= 0; rx_released <= 0; rx_words_seen <= 0; mac_programmed <= false;
      else
        cycle := cycle + 1;
        if stall_aw then assert master.m_axi_awvalid = '1' and master.m_axi_awaddr = held_aw report "AW changed under stall" severity failure; end if;
        if stall_w then assert master.m_axi_wvalid = '1' and master.m_axi_wdata = held_w and master.m_axi_wstrb = "1111" report "W changed under stall" severity failure; end if;
        if stall_ar then assert master.m_axi_arvalid = '1' and master.m_axi_araddr = held_ar report "AR changed under stall" severity failure; end if;
        stall_aw := master.m_axi_awvalid = '1' and slave.m_axi_awready = '0'; held_aw := master.m_axi_awaddr;
        stall_w := master.m_axi_wvalid = '1' and slave.m_axi_wready = '0'; held_w := master.m_axi_wdata;
        stall_ar := master.m_axi_arvalid = '1' and slave.m_axi_arready = '0'; held_ar := master.m_axi_araddr;
        if master.m_axi_awvalid = '1' and slave.m_axi_awready = '1' then
          assert not have_aw report "Duplicate AW acceptance" severity failure;
          aw := to_integer(unsigned(master.m_axi_awaddr)); have_aw := true;
        end if;
        if master.m_axi_wvalid = '1' and slave.m_axi_wready = '1' then
          assert not have_w report "Duplicate W acceptance" severity failure;
          assert master.m_axi_wstrb = "1111" severity failure;
          data := master.m_axi_wdata; have_w := true;
        end if;
        slave.m_axi_awready <= '0'; slave.m_axi_wready <= '0';
        if not block_bus and not have_aw and slave.m_axi_bvalid = '0' and cycle mod 7 = 0 then slave.m_axi_awready <= '1'; end if;
        if not block_bus and not have_w and slave.m_axi_bvalid = '0' and cycle mod 5 = 0 then slave.m_axi_wready <= '1'; end if;
        if slave.m_axi_bvalid = '1' and master.m_axi_bready = '1' then
          slave.m_axi_bvalid <= '0'; have_aw := false; have_w := false;
        elsif have_aw and have_w and slave.m_axi_bvalid = '0' and cycle mod 11 = 0 then
          slave.m_axi_bvalid <= '1';
          if aw = 16#7fc# then
            if data = x"00000003" then
              mac_programmed <= true; write_count := 0;
            else
              assert data = x"00000001" and tx_length = expected_length report "Bad TX start/length" severity failure;
              assert write_count = (expected_length + 3) / 4 report "Wrong number of TX words" severity failure;
              tx_completed <= tx_completed + 1; write_count := 0;
            end if;
          elsif aw = 16#7f4# then
            tx_length := to_integer(unsigned(data));
            assert tx_length = expected_length report "TX length mismatch" severity failure;
          elsif aw = 16#17fc# or aw = 16#1ffc# then
            assert data = x"00000000" and read_count = 32 report "RX released before full capture" severity failure;
            rx_released <= offer_rx; read_count := 0;
          elsif mac_programmed then
            assert aw = write_count * 4 and aw < 16#7f4# report "TX address/register overlap" severity failure;
            expected := (others => '0');
            for lane in 0 to 3 loop
              if aw + lane < expected_length then expected(lane*8+7 downto lane*8) := payload(aw + lane); end if;
            end loop;
            assert data = expected report "TX byte order, payload or padding mismatch" severity failure;
            write_count := write_count + 1;
          else
            assert (aw = 0 or aw = 4) and data = x"00000000" report "Bad MAC programming" severity failure;
          end if;
        end if;
        if master.m_axi_arvalid = '1' and slave.m_axi_arready = '1' then
          assert not have_ar report "Duplicate AR acceptance" severity failure;
          ar := to_integer(unsigned(master.m_axi_araddr)); have_ar := true;
        end if;
        slave.m_axi_arready <= '0';
        if not block_bus and not have_ar and slave.m_axi_rvalid = '0' and cycle mod 3 = 0 then slave.m_axi_arready <= '1'; end if;
        if slave.m_axi_rvalid = '1' and master.m_axi_rready = '1' then
          slave.m_axi_rvalid <= '0'; have_ar := false;
        elsif have_ar and slave.m_axi_rvalid = '0' and cycle mod 11 = 0 then
          slave.m_axi_rvalid <= '1'; slave.m_axi_rdata <= x"00000000";
          if (ar = 16#17fc# and offer_rx = 1 and rx_released = 0) or
             (ar = 16#1ffc# and offer_rx = 2 and rx_released = 1) then
            slave.m_axi_rdata <= x"00000001";
          elsif ar >= 16#1000# and ar mod 2048 < 128 then
            assert ar mod 2048 = read_count * 4 report "RX read order" severity failure;
            for lane in 0 to 3 loop slave.m_axi_rdata(lane*8+7 downto lane*8) <= payload(read_count*4 + lane + offer_rx); end loop;
            read_count := read_count + 1; rx_words_seen <= read_count;
          end if;
        end if;
      end if;
    end if;
  end process;

  stimulus: process
    procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
    @PROCEDURES@
    procedure reset is begin
      wait until falling_edge(clk); rst <= '1';
      for i in 1 to 5 loop tick; end loop;
      wait until falling_edge(clk); rst <= '0';
      for i in 1 to 10 loop tick; end loop;
    end;
    procedure wait_mac is begin
      for i in 1 to 3000 loop tick; exit when mac_programmed; end loop;
      assert mac_programmed report "MAC programming did not finish" severity failure;
      for i in 1 to 50 loop tick; end loop;
    end;
    variable before_count: integer;
    variable started: time;
    type lengths_t is array(natural range <>) of integer;
    constant lengths: lengths_t := (1, 2, 3, 4, 5, 60, 2036, 1);
  begin
    block_bus <= true;
    reset;
    -- Queue before MAC programming finishes; startup must not discard the frame.
    expected_length <= 1;
    call_trybegintxframe(1, true); call_trywritetxbyte(0, payload(0), true);
    call_trysubmittxframe(true);
    assert not mac_programmed severity failure;
    block_bus <= false;
    wait_mac;
    for i in 1 to 5000 loop tick; exit when tx_completed = 1; end loop;
    assert tx_completed = 1 report "MAC startup discarded queued TX" severity failure;
    for i in 1 to 100 loop tick; end loop;
    call_trybegintxframe(-1, false); call_trybegintxframe(0, false);
    call_trybegintxframe(2037, false); call_trysubmittxframe(false);
    call_getrxbyte(0, x"00");
    for n in lengths'range loop
      expected_length <= lengths(n);
      call_trybegintxframe(lengths(n), true);
      call_trywritetxbyte(-1, x"00", false);
      call_trywritetxbyte(lengths(n), x"00", false);
      call_trysubmittxframe(false);
      for i in 0 to lengths(n)-1 loop call_trywritetxbyte(i, payload(i), true); end loop;
      before_count := tx_completed; started := now;
      call_trysubmittxframe(true);
      call_trysubmittxframe(false);
      for i in 1 to 300000 loop tick; exit when tx_completed > before_count; end loop;
      assert tx_completed = before_count + 1 report "TX completion missing" severity failure;
      report "TX bytes=" & integer'image(lengths(n)) & " submit-to-device=" & time'image(now-started);
      for i in 1 to 100 loop tick; end loop;
      call_hassentframetoaxi(true); call_hastxframe(false);
    end loop;
    for frame in 1 to 2 loop
      offer_rx <= frame;
      for i in 1 to 30000 loop tick; exit when rx_released = frame; end loop;
      assert rx_released = frame report "RX completion missing" severity failure;
      for i in 1 to 100 loop tick; end loop;
      call_isframeavailable(true);
      for i in 0 to 127 loop call_getrxbyte(i, payload(i + frame)); end loop;
      call_getrxbyte(-1, x"00"); call_getrxbyte(128, x"00");
      call_consumerxframe; call_isframeavailable(false); call_getrxbyte(0, x"00");
    end loop;
    -- Reset with queued work and retained payload; restart the slave as well.
    block_bus <= true;
    call_trybegintxframe(4, true);
    for i in 0 to 3 loop call_trywritetxbyte(i, payload(i), true); end loop;
    call_trysubmittxframe(true);
    for i in 1 to 200 loop tick; end loop;
    offer_rx <= 0; reset;
    call_hastxframe(false); call_gettxbyte(0, x"00");
    call_getrxbyte(0, x"00"); call_trysubmittxframe(false);
    block_bus <= false; wait_mac;
    -- Interrupt a scheduled RAM write after request acceptance.
    call_trybegintxframe(4, true);
    wait until falling_edge(clk);
    trywritetxbyte_in <= (index => to_signed(0, 32), value => x"EE", run => '1');
    tick;
    wait until falling_edge(clk); trywritetxbyte_in.run <= '0';
    for i in 1 to 20 loop tick; exit when trywritetxbyte_out.busy = '1'; end loop;
    assert trywritetxbyte_out.busy = '1' severity failure;
    reset;
    assert trywritetxbyte_out.busy = '0' report "Reset did not cancel API write" severity failure;
    call_gettxbyte(0, x"00"); call_trysubmittxframe(false);
    wait_mac;
    -- Interrupt capture after at least one AXI RX word was accepted.
    offer_rx <= 1;
    for i in 1 to 5000 loop tick; exit when rx_words_seen > 0; end loop;
    assert rx_words_seen > 0 report "RX reset probe never started" severity failure;
    offer_rx <= 0; reset;
    call_isframeavailable(false); call_getrxbyte(0, x"00");
    wait_mac;
    expected_length <= 1;
    call_trybegintxframe(1, true); call_trywritetxbyte(0, payload(0), true);
    call_trysubmittxframe(true);
    for i in 1 to 5000 loop tick; exit when tx_completed = 1; end loop;
    assert tx_completed = 1 report "Post-reset TX failed" severity failure;
    report "Simulation finished: Ethernet transfers";
    std.env.stop;
    wait;
  end process;
end;
