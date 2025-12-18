{
----------------------------------------------------------------------------------------------------
    Filename:       wireless.transceiver.cc2500.spin
    Description:    Driver for TI's CC2500 ISM-band (2.4GHz) transceiver
    Author:         Jesse Burt
    Started:        Jul 7, 2019
    Updated:        Dec 18, 2025
    Copyright (c) 2025 - See end of file for terms of use.
----------------------------------------------------------------------------------------------------
}

CON

    { default I/O configuration - these can be overridden by the parent object }
    CS                      = 0
    SCK                     = 1
    MOSI                    = 2
    MISO                    = 3
    SPI_FREQ                = 1_000_000
    PPB                     = 0                 ' CC2500 xtal parts-per-billion (PPB/1000 = PPM)

    { crystal freq: adjust from nominal 26MHz: calculate offset using PPB figure }
    F_XOSC                  = round(26_000_000-(26_000_000 * (float(PPB) / float(1_000_000_000))))
{
    NOTE:
        If the actual resulting frequency synthesized by the chip is lower than the value
        set/returned by e.g., carrier_freq(), PPB should be set to a positive number.
        If it's higher, however, PPB should be a negative number.
}

    TWO13                   = 1 << 13           ' 2^13
    TWO14                   = 1 << 14           ' 2^14
    TWO16                   = 1 << 16           ' 2^16
    TWO17                   = 1 << 17           ' 2^17
    TWO18                   = 1 << 18           ' 2^18
    TWO20                   = 1 << 20           ' 2^20
    TWO28                   = 1 << 28           ' 2^28
    U64SCALE                = 1_000_000         ' Unsigned math scale
    U64_FREQ_RES            = 396_728515        ' (F_XOSC / TWO16) * 1_000_000
    CHANSPC_RES             = 99_182128         ' (F_XOSC / TWO18) * 1_000_000

' Auto-calibration state
    NEVER                   = 0
    IDLE_RXTX               = 1
    RXTX_IDLE               = 2
    RXTX_IDLE4              = 3

' RXOff states
    RXOFF_IDLE              = 0
    RXOFF_FSTXON            = 1
    RXOFF_TX                = 2
    RXOFF_RX                = 3

' TXOff states
    TXOFF_IDLE              = 0
    TXOFF_FSTXON            = 1
    TXOFF_TX                = 2
    TXOFF_RX                = 3

' Modulation formats
    FSK2                    = %000
    GFSK                    = %001
    ASKOOK                  = %011
    FSK4                    = %100
    MSK                     = %111

' CC2500 I/O pin output signals
    TRIG_RXTHRESH           = $00
    TRIG_RXTHRESH_END_PKT   = $01
    TRIG_RXOVERFLOW         = $04
    TRIG_TXUNDERFLOW        = $05
    TRIG_SYNCWORD_TXRX      = $06
    TRIG_PREAMBLE_QUALITY   = $08
    TRIG_CARRIER            = $0E
    IO_CHIP_RDYn            = $29
    IO_XOSC_STABLE          = $2B
    IO_HI_Z                 = $2E
    IO_CLK_XODIV1           = $30
    IO_CLK_XODIV192         = $3F

' Packet Length configuration modes
    PKTLEN_FIXED            = 0
    PKTLEN_VAR              = 1
    PKTLEN_INF              = 2

' Syncword qualifier modes
    SYNCMODE_NONE           = 0
    SYNCMODE_1516           = 1
    SYNCMODE_1616           = 2
    SYNCMODE_3032           = 3
    SYNCMODE_CS_ONLY        = 4
    SYNCMODE_1516_CS        = 5
    SYNCMODE_1616_CS        = 6
    SYNCMODE_3032_CS        = 7

' Address check modes
    ADRCHK_NONE             = 0
    ADRCHK_CHK_NO_BCAST     = 1
    ADRCHK_CHK_00_BCAST     = 2
    ADRCHK_CHK_00_FF_BCAST  = 3

' AGC modes
    AGC_NORMAL              = %00
    AGC_FREEZE_ON_SYNC      = %01
    AGC_FREEZE_A_AUTO_D     = %10
    AGC_OFF                 = %11


VAR

    byte _CS
    byte _status


OBJ

{ decide: Bytecode SPI engine, or PASM? Default is PASM if BC isn't specified }
#ifdef CC2500_SPI_BC
    spi:    "com.spi.25khz.nocog"               ' BC SPI engine
#else
    spi:    "com.spi.1mhz"                      ' PASM SPI engine
#endif
    core:   "core.con.cc2500"                   ' HW-specific constants
    time:   "time"                              ' timekeeping methods
    u64:    "math.unsigned64"                   ' unsigned 64-bit math routines


PUB null()
' This is not a top-level object


PUB start(): status
' Start the driver using default I/O settings
    return startx(CS, SCK, MOSI, MISO, SPI_FREQ)


PUB startx(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN, SCK_FREQ): status
' Start the driver using custom I/O settings
'   CS_PIN:     Chip select
'   SCK_PIN:    serial clock
'   MOSI_PIN:   master-out slave-in (Propeller to device)
'   MISO_PIN:   master-in slave-out (device to Propeller)
    if ( lookdown(CS_PIN: 0..31) and lookdown(SCK_PIN: 0..31) and lookdown(MOSI_PIN: 0..31) and ...
        lookdown(MISO_PIN: 0..31) )
        if ( status := spi.init(SCK_PIN, MOSI_PIN, MISO_PIN, core.SPI_MODE) )
            time.usleep(core.T_POR)
            _CS := CS_PIN
            outa[_CS] := 1
            dira[_CS] := 1
            if ( dev_id() == core.DEVID_RESP )
                reset()
                return
    ' if this point is reached, something above failed
    ' Double check I/O pin assignments, connections, power
    ' Lastly - make sure you have at least one free core/cog
    return FALSE


PUB stop()
' Stop the driver
    spi.deinit()
    dira[_CS] := 0
    _CS := _status := 0


PUB defaults()
' Factory default settings
{'  This is what _would_ be set:
    node_addr($00)
    addr_check(ADRCHK_NONE)
    payld_status_ena(TRUE)
    carrier_freq(2_463_999)
    channel(0)
    crc_auto_flush_ena(FALSE)
    crc_check_ena(TRUE)
    data_rate(115_200)
    dc_block_ena(TRUE)
    freq_dev(47_607)
    fec(FALSE)
    gpio0(IO_CLK_XODIV192)
    gpio1(IO_HI_Z)
    gpio2(IO_CHIP_RDYn)
    interm_freq(381)
    manchest_enc_ena(FALSE)
    modulation(FSK2)
    payld_len(255)
    payld_len_cfg(PKTLEN_VAR)
    preamble_len(2)
    preamble_qual(0)
    rx_bw(203)
    rx_fifo_thresh(32)
    syncwd_mode(SYNCMODE_1616)
    set_syncwd($D391)
    data_whiten_ena(TRUE)
}'   but to save code space, we'll just reset(), instead
    reset()


PUB preset_fixed_pkt_len()
' Like preset_robust1(), but sets packet length config mode to fixed-length
    preset_robust1()
    payld_len_cfg(PKTLEN_FIXED)


PUB preset_robust1()
' Like defaults, but with some basic improvements in robustness:
' * check/filter address field in payload (2nd byte), ignore broadcast address
' * perform oscillator auto-cal when transitioning from idle to RX or TX
' * reject packets with a bad CRC (i.e., flush from receive buffer)
' * turn off oscillator output on gpio0 (GDO0)
    reset()                                     ' start with POR defaults
    addr_check(ADRCHK_CHK_NO_BCAST)
    auto_cal_mode(IDLE_RXTX)
    crc_auto_flush_ena(TRUE)
    gpio0(IO_HI_Z)


PUB addr_check(md=-2): c
' Enable address checking/matching/filtering
'   Valid values:
'      *ADRCHK_NONE (0): No address check
'       ADRCHK_CHK_NO_BCAST (1): Check address, but ignore broadcast addresses
'       ADRCHK_CHK_00_BCAST (2): Check address, and also respond to $00 broadcast address
'       ADRCHK_CHK_00_FF_BCAST (3): Check address, and also respond to both $00 and $FF broadcast addresses
'   Any other value polls the chip and returns the current setting
    c := readreg(core.PKTCTRL1)
    case md
        0..3:
            md := md & core.ADR_CHK_BITS
            md := ((c & core.ADR_CHK_MASK) | md) & core.PKTCTRL1_MASK
            writereg(core.PKTCTRL1, md)
        other:
            return c & core.ADR_CHK_BITS


PUB after_rx(s=-2): c
' Defines the state the radio transitions to after a packet is successfully received
'   Valid values:
'      *RXOFF_IDLE (0) - Idle state
'       RXOFF_FSTXON (1) - Turn frequency synth on and ready at TX freq. To transmit, call TX
'       RXOFF_TX (2) - Start sending preamble
'       RXOFF_RX (3) - Wait for more packets
'   Any other value polls the chip and returns the current setting
    c := readreg(core.MCSM1)
    case s
        0..3:
            s := s << core.RXOFF_MODE
            s := ((c & core.RXOFF_MODE_MASK) | s)
            writereg(core.MCSM1, s)
        other:
            return (c >> core.RXOFF_MODE) & core.RXOFF_MODE_BITS


PUB after_tx(s=-2): c
' Defines the state the radio transitions to after a packet is successfully transmitted
'   Valid values:
'      *TXOFF_IDLE (0) - Idle state
'       TXOFF_FSTXON (1) - Turn frequency synth on and ready at TX freq. To transmit, call TX
'       TXOFF_TX (2) - Start sending preamble
'       TXOFF_RX (3) - Wait for packets (RX)
'   Any other value polls the chip and returns the current setting
    c := readreg(core.MCSM1)
    case s
        0..3:
            s := s << core.TXOFF_MODE
            s := ((c & core.TXOFF_MODE_MASK) | s)
            writereg(core.MCSM1, s)
        other:
            return (c >> core.TXOFF_MODE) & core.TXOFF_MODE_BITS


PUB agc_filt_len(len=-2): c
' For 2FSK, 4FSK, MSK, set averaging length for amplitude from the channel filter, in samples
' For OOK/ASK, set decision boundary for reception
'   Valid values:
'       FSK/MSK     OOK/ASK
'       Samples     decision boundary
'       8           4dB
'       16          8dB
'       32          12dB
'       64          16dB
'   Any other value polls the chip and returns the current setting
    c := readreg(core.AGCCTRL0)
    case len
        8, 16, 32, 64:
            len := lookdownz(len: 8, 16, 32, 64) & core.FILT_LEN_BITS
            len := ((c & core.FILT_LEN_MASK) | len) & core.AGCCTRL0_MASK
            writereg(core.AGCCTRL0, len)
        other:
            c := c & core.FILT_LEN_BITS
            return lookupz(c: 8, 16, 32, 64)


PUB agc_mode(md=-2): c
' Set AGC mode
'   Valid values:
'      *AGC_NORMAL (0): Always adjust gain when required
'       AGC_FREEZE_ON_SYNC (1): Gain setting is frozen when a sync word has been found
'       AGC_FREEZE_A_AUTO_D (2): Freeze analog gain, but autmatically adjust digital gain
'       AGC_OFF (3): Freeze both analog and digital gain settings
'   Any other value polls the chip and returns the current setting
    c := readreg(core.AGCCTRL0)
    case md
        AGC_NORMAL, AGC_FREEZE_ON_SYNC, AGC_FREEZE_A_AUTO_D, AGC_OFF:
            md <<= core.AGC_FREEZE
            md := ((c & core.AGC_FREEZE_MASK) | md) & core.AGCCTRL0_MASK
            writereg(core.AGCCTRL0, md)
        other:
            return (c >> core.AGC_FREEZE) & core.AGC_FREEZE_BITS


PUB auto_cal_mode(md=-2): c
' When to perform auto-calibration
'   Valid values:
'      *NEVER (0) - Never (manually calibrate)
'       IDLE_RXTX (1) - When transitioning from IDLE to RX/TX
'       RXTX_IDLE (2) - When transitioning from RX/TX to IDLE
'       RXTX_IDLE4 (3) - Every 4th time md transitioning from RX/TX to IDLE (power-saving)
    c := readreg(core.MCSM0)
    case md
        NEVER, IDLE_RXTX, RXTX_IDLE, RXTX_IDLE4:
            md := md << core.FS_AUTOCAL
            md := ((c & core.FS_AUTOCAL_MASK) | md)
            writereg(core.MCSM0, md)
        other:
            return (c >> core.FS_AUTOCAL) & core.FS_AUTOCAL_BITS


PUB cal_freq_synth()
' Calibrate the frequency synthesizer
    writereg(core.CS_SCAL)


PUB carrier_freq(frq=-2): c
' Set carrier/center frequency, in kHz
'   Valid values:
'       2_400_000..2_483_500
'   Default value: Approx 2_464_000
'   Any other value polls the chip and returns the current setting
'   NOTE: The actual set frequency has a resolution of fXOSC/2^16 (i.e., approx 397Hz)
    c := readreg(core.FREQ2, 3)
    case frq
        2_400_000..2_483_500:
            frq := u64.multdiv(F_XOSC, U64SCALE, frq)
            frq := u64.multdiv(TWO16, U64SCALE*1_000, frq)
            writereg(core.FREQ2, frq, 3)
        other:
            return u64.multdiv(c, U64_FREQ_RES, 1_000_000_000)


PUB carrier_sense_thresh(thr=-2): c
' Set relative change threshold for asserting carrier sense, in dB
'   Valid values:
'      *0: Disabled
'       6: 6dB increase in RSSI
'       10: 10dB increase in RSSI
'       14: 14dB increase in RSSI
'   Any other value polls the chip and returns the current setting
    c := readreg(core.AGCCTRL1)
    case thr
        0, 6, 10, 14:
            thr := lookdownz(thr: 0, 6, 10, 14) << core.CSENSE_REL_THR
            thr := ((c & core.CSENSE_REL_THR_MASK) | thr) & core.AGCCTRL1_MASK
            writereg(core.AGCCTRL1, thr)
        other:
            c := (c >> core.CSENSE_REL_THR) & core.CSENSE_REL_THR_BITS
            return lookupz(c: 0, 6, 10, 14)


PUB carrier_sense_abs_thresh(thr=-2): c
' Set absolute change threshold for asserting carrier sense, in dB
'   Valid values:
'       %0000..%1111
'   Default value: %0000
'   Any other value polls the chip and returns the current setting
    c := readreg(core.AGCCTRL1)
    case thr
        %0000..%1111:
            thr := thr & core.CSENSE_ABS_THR_BITS
            thr := ((c & core.CSENSE_ABS_THR_MASK) | thr) & core.AGCCTRL1_MASK
            writereg(core.AGCCTRL1, thr)
        other:
            return c & core.CSENSE_ABS_THR_BITS


PUB channel(ch=-2): c
' Set channel number
'   Valid values: 0..255
'   Default value: 0
'   Any other value polls the chip and returns the current setting
'   NOTE: Resulting frequency = (channel number * channel spacing) + base freq
    c := readreg(core.CHANNR)
    case ch
        0..255:
            ch &= core.CHANNR_MASK
            writereg(core.CHANNR, ch)
        other:
            return c


PUB channel_spacing(spc=-2): c | chanspc_e, chanspc_m
' Set channel spacing, in Hz
'   Valid values: 25_390..405_456 (default: 199_951)
'   Any other value polls the chip and returns the current setting
    longfill(@chanspc_e, 0, 3)
    c := readreg(core.MDMCFG1, 2)
    case spc
        25_390..405_456:
            repeat chanspc_e from 0 to 3
                chanspc_m :=  (spc / (99 * (1 << chanspc_e)) - 256)
                if ( (chanspc_m => 0) and (chanspc_m < 256) )
                    quit
            spc.byte[0] &= core.CHANSPC_E_MASK
            spc.byte[0] |= chanspc_e
            spc.byte[1] := chanspc_m
            writereg(core.MDMCFG1, spc, 2)
        other:
            chanspc_e := c.byte[0] & core.CHANSPC_E_BITS
            chanspc_m := c.byte[1]
            c := (256 + chanspc_m) * (1 << chanspc_e)
            return u64.multdiv(CHANSPC_RES, c, 1_000_000)


PUB crc_check_ena(md=-2): c
' Enable CRC calc (TX mode) and check (RX mode)
'   Valid values:
'      *TRUE (-1 or 1)
'       FALSE (0)
'   Any other value polls the chip and returns the current setting
    c := readreg(core.PKTCTRL0)
    case ||(md)
        0, 1:
            md := ||(md) << core.CRC_EN
            md := ((c & core.CRC_EN_MASK) | md) & core.PKTCTRL0_MASK
            writereg(core.PKTCTRL0, md)
        other:
            return ((c >> core.CRC_EN) & 1) == 1


PUB crc_auto_flush_ena(e=-2): c
' Enable automatic flush of RX FIFO when CRC check fails
'   Valid values:
'       TRUE (-1 or 1)
'      *FALSE (0)
'   Any other value polls the chip and returns the current setting
    c := readreg(core.PKTCTRL1)
    case ||(e)
        0, 1:
            e := ||(e) << core.CRC_AUTOFLUSH
            e := ((c & core.CRC_AUTOFLUSH_MASK) | e) & core.PKTCTRL1_MASK
            writereg(core.PKTCTRL1, e)
        other:
            return ((c >> core.CRC_AUTOFLUSH) & 1) == 1


PUB data_rate(r=-2): c | curr_exp, curr_mant, dr_exp, dr_mant
' Set on-air data rate, in bps
'   Valid values: 600..500_000
'   Default value: 115_051
'   Any other value polls the chip and returns the current setting
    longfill(@curr_exp, 0, 4)

    curr_exp := readreg(core.MDMCFG4)
    curr_mant := readreg(core.MDMCFG3)
    case r
        600..500_000:
            dr_exp := >|( u64.multdiv(r, TWO20, F_XOSC) )-1
            dr_mant := (u64.multdiv (   r, ...
                                        TWO28, ...
                                        u64.multdiv(    F_XOSC, ...
                                                        (1 << dr_exp), ...
                                                        1_000) ...
                                    )-256_000) / 1_000
            if ( dr_mant > 255 )                ' mantissa overflow?
                dr_mant := 0                    '   clear and carry it into the exponent
                dr_exp := (dr_exp + 1) <# $0E
            curr_exp &= core.DRATE_E_MASK
            curr_exp := (curr_exp | dr_exp)
            writereg(core.MDMCFG4, curr_exp)
            writereg(core.MDMCFG3, dr_mant)
        other:
            curr_exp &= core.DRATE_E_BITS
            c := u64.multdiv( (256+curr_mant) * (1 << curr_exp), U64SCALE, TWO28)
            return u64.multdiv(c, F_XOSC, U64SCALE)


PUB data_whiten_ena(e=-2): c
' Enable data whitening
'   Valid values: *TRUE (-1 or 1), FALSE (0)
'   Any other value polls the chip and returns the current setting
'   NOTE: Applies to all data, except the preamble and sync word.
    c := readreg(core.PKTCTRL0)
    case ||(e)
        0, 1:
            e := ||(e) << core.WHITE_DATA
            e := ((c & core.WHITE_DATA_MASK) | e)
            writereg(core.PKTCTRL0, e)
        other:
            return ((c >> core.WHITE_DATA) & 1) == 1


PUB dc_block_ena(e=-2): c
' Enable digital DC blocking filter (before demod)
'   Valid values: *TRUE (-1 or 1), FALSE
'   Any other value polls the chip and returns the current setting
'   NOTE: Enable for better sensitivity (default).
'       Disable for optimizing current usage. Only for data rates 250kBaud and lower
    c := readreg(core.MDMCFG2)
    case e := ||(e)
        0, 1:
            e := ((e ^ 1) << core.DCFILT_OFF)
            e := ((c & core.DCFILT_OFF_MASK) | e)
            writereg(core.MDMCFG2, e)
        other:
            return (((c >> core.DCFILT_OFF) & 1) ^ 1) == 1


PUB dev_id(): id
' Chip version number
'   Returns: $03
'   NOTE: Datasheet states this value is subject to change without notice
    return readreg(core.VERSION)


PUB dvga_gain(g=-2): c
' Set Digital Variable Gain Amplifier gain maximum level
'   Valid values:
'       *0 - Highest gain setting
'       -1 - Highest gain setting-1
'       -2 - Highest gain setting-2
'       -3 - Highest gain setting-3
'   Any other value polls the chip and returns the current setting
    c := readreg(core.AGCCTRL2)
    case g
        -3..0:
            g := ||(g) << core.MAX_DVGA_GAIN
            g := ((c & core.MAX_DVGA_GAIN_MASK) | g)
            writereg(core.AGCCTRL2, g)
        other:
            c := (c >> core.MAX_DVGA_GAIN) & core.MAX_DVGA_GAIN_BITS
            return c * -1


PUB fec_ena(md=-2): c
' Enable forward error correction with interleaving
'   Valid values: TRUE (-1 or 1), *FALSE (0)
'   Any other value polls the chip and returns the current setting
'   NOTE: Only supported when payld_len_cfg() == PKTLEN_FIXED
    c := readreg(core.MDMCFG1)
    case ||(md)
        0, 1:
            md := ||(md) << core.FEC_EN
            md := ((c & core.FEC_EN_MASK) | md) & core.MDMCFG1_MASK
            writereg(core.MDMCFG1, md)
        other:
            return ((c >> core.FEC_EN) & 1) == 1


PUB fifo_rx_bytes(): n
' Returns number of bytes in RX FIFO
' NOTE: The MSB indicates if the RX FIFO has overflowed.
    return readreg(core.RXBYTES)


PUB fifo_tx_bytes(): n
' Returns number of bytes in TX FIFO
' NOTE: The MSB indicates if the TX FIFO is underflowed.
    return readreg(core.TXBYTES)


PUB flush_rx()
' Flush receive FIFO/buffer
    writereg(core.CS_SFRX)


PUB flush_tx()
' Flush transmit FIFO/buffer
    writereg(core.CS_SFTX)


PUB freq_dev(frq=-2): c | tmp, deviat_m, deviat_e, tmp_m
' Set frequency deviation from carrier, in Hz
'   Valid values:
'       1_586..380_859
'   Default value: 47_607
'   NOTE: This setting has no effect when Modulation format is ASK/OOK.
'   NOTE: This setting applies to both TX and RX roles. When role is RX, setting must be
'           approximately correct for reliable demodulation.
'   Any other value polls the chip and returns the current setting
    longfill(@tmp, 0, 4)
    tmp := readreg(core.DEVIATN)
    case frq
        1_587..380_859:
            deviat_e := u64.multdiv(frq, TWO14, F_XOSC)
            deviat_e := (>|(deviat_e))-1
            tmp_m := F_XOSC * (1 << deviat_e)
            deviat_m := u64.multdiv(frq, TWO17, tmp_m)
            frq := (deviat_e << core.DEVIAT_E) | deviat_m
            frq &= core.DEVIATN_MASK
            writereg(core.DEVIATN, frq)
        other:
            deviat_m := tmp & core.DEVIAT_M_BITS
            deviat_e := (tmp >> core.DEVIAT_E) & core.DEVIAT_E_BITS
            return F_XOSC / TWO17 * (8 + deviat_m) * (1 << deviat_e)


PUB freq_synth_ena()
' Enable frequency synthesizer and calibrate
    writereg(core.CS_SFSTXON)


PUB gpio0(md=-2): c 'XXX review: consolidation with other like methods? (API change)
' Configure test signal output on GDO0 pin
'   Valid values: $00..$0F, $16..$17, $1B..$1D, $24..$39, $41, $43, $46..$3F (see IO_* constants near top of this file)
'   Default value: $3F
'   Any other value polls the chip and returns the current setting
'   NOTE: The default setting is IO_CLK_XODIV192, which outputs the CC1101's XO clock, divided by 192 on the pin.
'       TI recommends the clock outputs be disabled when the radio is active, for best performance.
'       Only one IO pin at a time can be mdured as a clock output.
    c := readreg(core.IOCFG0)
    case md
        $00..$0F, $16..$17, $1B..$1D, $24..$27, $29, $2B, $2E..$3F:
            md &= core.GDO0_CFG_BITS
            md := ((c & core.GDO0_CFG_MASK) | md)
            writereg(core.IOCFG0, md)
        other:
            return c & core.GDO0_CFG_BITS


PUB gpio1(md=-2): c
' Configure test signal output on GDO1 pin
'   Valid values: $00..$0F, $16..$17, $1B..$1D, $24..$39, $41, $43, $46..$3F
'   Any other value polls the chip and returns the current setting
'   NOTE: This pin is shared with the SPI signal SO, and is valid only when CS is high.
'   NOTE: The default setting is IO_HI_Z ($2E): Hi-Z/High-impedance/Tri-state
    c := readreg(core.IOCFG1)
    case md
        $00..$0F, $16..$17, $1B..$1D, $24..$27, $29, $2B, $2E..$3F:
            md &= core.GDO1_CFG_BITS
            md := ((c & core.GDO1_CFG_MASK) | md)
            writereg(core.IOCFG1, md)
        other:
            return c & core.GDO1_CFG_BITS


PUB gpio2(md=-2): c
' Configure test signal output on GDO2 pin
'   Valid values: $00..$0F, $16..$17, $1B..$1D, $24..$39, $41, $43, $46..$3F
'   Any other value polls the chip and returns the current setting
'   NOTE: The default setting is IO_CHIP_RDYn ($29)
    c := readreg(core.IOCFG2)
    case md
        $00..$0F, $16..$17, $1B..$1D, $24..$27, $29, $2B, $2E..$3F:
            md &= core.GDO2_CFG_BITS
            md := ((c & core.GDO2_CFG_MASK) | md)
            writereg(core.IOCFG2, md)
        other:
            return c & core.GDO2_CFG_BITS


PUB idle()
' Change chip state to IDLE
    writereg(core.CS_SIDLE)


PUB interm_freq(frq=-2): c
' Intermediate Frequency (IF), in Hz
'   Valid values: 25_390..787_109 (result will be rounded to the nearest 5-bit result)
'   Default value: 380_859
'   Any other value polls the chip and returns the current setting
    c := readreg(core.FSCTRL1)
    case frq
        25_390..787_109:
            frq := 1024 / (F_XOSC/frq)
            writereg(core.FSCTRL1, frq)
        other:
            return c * (F_XOSC / 1024)


PUB last_crc_good(): c
' Flag indicating CRC of last reception matched
'   Returns: TRUE (-1) if comparison matched, FALSE (0) otherwise
    c := readreg(core.LQI)
    return ((c >> core.CRC_OK) & 1) == 1


PUB lna_gain(g=-255): c
' Set maximum LNA+LNA2 gain (relative to maximum possible gain)
'   Valid values:
'       *0 - Maximum possible LNA+LNA2 gain
'       -2 - ~2.6dBm below maximum
'       -6 - ~6.1dBm below maximum
'       -7 - ~7.4dBm below maximum
'       -9 - ~9.2dBm below maximum
'       -11 - ~11.5dBm below maximum
'       -14 - ~14.6dBm below maximum
'       -17 - ~17.1dBm below maximum
'   Any other value polls the chip and returns the current setting
    c := readreg(core.AGCCTRL2)
    case g
        0, -2, -6, -7, -9, -11, -14, -17:
            g := lookdownz(g: 0, -2, -6, -7, -9, -11, -14, -17) << core.MAX_LNA_GAIN
            g := ((c & core.MAX_LNA_GAIN_MASK) | g)
            writereg(core.AGCCTRL2, g)
        other:
            c := (c >> core.MAX_LNA_GAIN) & core.MAX_LNA_GAIN_BITS
            return lookupz(c: 0, -2, -6, -7, -9, -11, -14, -17)


PUB magn_target(m=-2): c
' Set target value for averaged amplitude from digital channel filter, in dB
'   Valid values:
'       24, 27, 30, *33, 36, 38, 40, 42
'   Any other value polls the chip and returns the current setting
    c := readreg(core.AGCCTRL2)
    case m
        24, 27, 30, 33, 36, 38, 40, 42:
            m := lookdownz(m: 24, 27, 30, 33, 36, 38, 40, 42) & core.MAGN_TARGET_BITS
            m := ((c & core.MAGN_TARGET_MASK) | m)
            writereg(core.AGCCTRL2, m)
        other:
            c := c & core.MAGN_TARGET_BITS
            return lookupz(c: 24, 27, 30, 33, 36, 38, 40, 42)


PUB manchest_enc_ena(e=-2): c
' Enable Manchester encoding/decoding
'   Valid values: TRUE (-1 or 1), *FALSE (0)
'   Any other value polls the chip and returns the current setting
    c := readreg(core.MDMCFG2)
    case ||(e)
        0, 1:
            e := ||(e) << core.MANCHST_EN
            e := ((c & core.MANCHST_EN_MASK) | e)
            writereg(core.MDMCFG2, e)
        other:
            return ((c >> core.MANCHST_EN) & 1) == 1


PUB modulation(md=-2): c
' Set modulation of transmitted (TX) or expected (RX) signal
'   Valid values:
'      *FSK2 (%000): 2-level or binary Frequency Shift-Keyed
'       GFSK (%001): Gaussian FSK
'       ASKOOK (%011): Amplitude Shift-Keyed or On Off-Keyed
'       FSK4 (%100): 4-level FSK
'       MSK (%111): Minimum Shift-Keyed
'   Any other value polls the chip and returns the current setting
'   NOTE: MSK supported only when data_rate() is greater than 26k
    c := readreg(core.MDMCFG2)
    case md
        FSK2, GFSK, ASKOOK, FSK4, MSK:
            md := md << core.MOD_FORMAT
            md := ((c & core.MOD_FORMAT_MASK) | md)
            writereg(core.MDMCFG2, md)
        other:
            return (c >> core.MOD_FORMAT) & core.MOD_FORMAT_BITS


PUB node_addr(a=-2): c
' Set address used for packet filtration
'   Valid values: $00..$FF (000-255)
'   Default value: $00
'   Any other value polls the chip and returns the current setting
'   NOTE: $00 and $FF can be used as broadcast addresses.
    c := readreg(core.ADDR)
    case a
        $00..$FF:
            a &= core.ADDR_MASK
            writereg(core.ADDR, a)
        other:
            return c


PUB pa_read(p_dest)
' Read PA table into p_dest
'   NOTE: p_dest must be at least 8 bytes in length
    readreg(core.PATABLE | core.BURST, 8, p_dest)


PUB part_num(): n
' Part number of device
'   Returns: $00
    return readreg(core.PARTNUM)


PUB pa_write(p_src)
' Write 8-byte PA table from p_src
'   NOTE: Table will be written starting at index 0 from the LSB of p_src
    writereg(core.PATABLE | core.BURST, p_src, 8)


PUB payld_len(len=-2): c
' Set payload length, when using fixed payload length mode,
'   or maximum payload length when using variable payload length mode.
'   Valid values: 1..*255
'   Any other value polls the chip and returns the current setting
    c := readreg(core.PKTLEN)
    case len
        1..255:
            len &= core.PKTLEN_MASK
            writereg(core.PKTLEN, len)
        other:
            return c & core.PKTLEN_MASK


PUB payld_len_cfg(md=-2): c
' Set payload length mode
'   Valid values:
'       PKTLEN_FIXED (0): Fixed payload length mode. Payload length is set by payld_len()
'      *PKTLEN_VAR (1): Variable payload length mode. Payload length is set by first byte of
'           payload data (default)
'       PKTLEN_INF (2): Infinite payload length mode.
'   Any other value polls the chip and returns the current setting
    c := readreg(core.PKTCTRL0)
    case md
        0..2:
            md := ((c & core.LEN_CFG_MASK) | md) & core.PKTCTRL0_MASK
            writereg(core.PKTCTRL0, md)
        other:
            return c & core.LEN_CFG_BITS


PUB payld_status_ena(md=-2): c
' Append status bytes to packet payload (RSSI, LQI, CRC OK)
'   Valid values:
'      *TRUE (-1 or 1)
'       FALSE (0)
'   Any other value polls the chip and returns the current setting
    c := readreg(core.PKTCTRL1)
    case ||(md)
        0, 1:
            md := ||(md) << core.APPEND_STATUS
            md := ((c & core.APPEND_STATUS_MASK) | md) & core.PKTCTRL1_MASK
            writereg(core.PKTCTRL1, md)
        other:
            return ((c >> core.APPEND_STATUS) & 1) == 1


PUB pll_locked(): l
' Flag indicating PLL is locked
'   Returns: TRUE (-1) if locked, FALSE otherwise
    l := readreg(core.FSCAL1)
    return (l <> $3F)


PUB preamble_len(len=-2): c
' Set number of preamble bytes
'   Valid values: 2, 3, *4, 6, 8, 12, 16, 24
'   Any other value polls the chip and returns the current setting
    c := readreg(core.MDMCFG1)
    case len
        2, 3, 4, 6, 8, 12, 16, 24:
            len := (lookdownz(len: 2, 3, 4, 6, 8, 12, 16, 24)) << core.NUM_PREAMBLE
            len := ((c & core.NUM_PREAMBLE_MASK) | len)
            writereg(core.MDMCFG1, len)
        other:
            c := (c >> core.NUM_PREAMBLE) & core.NUM_PREAMBLE_BITS
            return lookupz(c: 2, 3, 4, 6, 8, 12, 16, 24)


PUB preamble_quality_thresh(thr=-2): c
' Set Preamble quality estimator threshold
'   Valid values: *0, 4, 8, 12, 16, 20, 24, 28
'   NOTE: If 0, the sync word is always accepted.
'   Any other value polls the chip and returns the current setting
    c := readreg(core.PKTCTRL1)
    case thr
        0, 4, 8, 12, 16, 20, 24, 28:
            thr := lookdownz(thr: 0, 4, 8, 12, 16, 20, 24, 28) << core.PQT
            thr := ((c & core.PQT_MASK) | thr) & core.PKTCTRL1_MASK
            writereg(core.PKTCTRL1, thr)
        other:
            c := ((c >> core.PQT) & core.PQT_BITS)
            return lookupz(c: 0, 4, 8, 12, 16, 20, 24, 28)


PUB reset()
' Reset the chip
    writereg(core.CS_SRES)
    time.msleep(5)


PUB rssi(): l
' Received Signal Strength Indicator
'   Returns: Signal strength seen by transceiver, in dBm
    l := readreg(core.RSSI)
    l := (~l / 2) - 74


PUB rx_bandwidth = rx_bw
PUB rx_bw(bw=-2): c
' Set receiver channel filter bandwidth, in kHz
'   Valid values: 812, 650, 541, 464, 406, 325, 270, 232, *203, 162, 135, 116, 102, 81, 68, 58
'   Any other value polls the chip and returns the current setting
    c := readreg(core.MDMCFG4)
    case bw
        812, 650, 541, 464, 406, 325, 270, 232, 203, 162, 135, 116, 102, 81, 68, 58:
            bw := (lookdown(bw:   812, 650, 541, 464, 406, 325, 270, 232, 203, 162, 135, ...
                                        116, 102, 81, 68, 58)-1) << core.CHANBW
            bw := ((c & core.CHANBW_MASK) | bw)
            writereg(core.MDMCFG4, bw)
        other:
            c := ((c >> core.CHANBW) & core.CHANBW_BITS)+1
            return lookup(c: 812, 650, 541, 464, 406, 325, 270, 232, 203, 162, 135, 116, ...
                                    102, 81, 68, 58)


PUB rx_fifo_thresh(thr=-2): c
' Set receive FIFO threshold, in bytes
'   The threshold is exceeded when the number of bytes in the FIFO is greater
'       than or equal to this value.
'   Valid values: 4, 8, 12, 16, 20, 24, 28, *32, 36, 40, 44, 48, 52, 56, 60, 64
'   Any other value polls the chip and returns the current setting
'   NOTE: This affects the TX FIFO, inversely
    c := readreg(core.FIFOTHR)
    case thr
        4..64:
            thr := (thr / 4) - 1
            thr := ((c & core.FIFO_THR_MASK) | thr) & core.FIFOTHR_MASK
            writereg(core.FIFOTHR, thr)
        other:
            return ((c & core.FIFO_THR_BITS) + 1) * 4


PUB rx_mode()
' Change chip state to RX (receive)
    writereg(core.CS_SRX)


PUB rx_payld(len, p_src)
' Read data queued in the RX FIFO
'   len Valid values: 1..64
'   Any other value is ignored
'   NOTE: Ensure buffer at address p_src is at least as big as the number of bytes you're reading
    readreg(core.FIFO, len, p_src)


PUB sleep()
' Power down chip
    writereg(core.CS_SPWD)


PUB state(): c
' Read state-machine register
    return readreg(core.MARCSTATE)


PUB syncwd_mode(md=-2): c
' Set sync-word qualifier mode
'   Valid values:
'       SYNCMODE_NONE (0): Ignore preamble, sync-word and carrier level
'       SYNCMODE_1516 (1): 15 of 16 sync-word bits must match
'      *SYNCMODE_1616 (2): 16 of 16 sync-word bits must match
'       SYNCMODE_3032 (3): 30 of 32 sync-word bits must match
'       SYNCMODE_CS_ONLY (4): Ignore preamble and sync-word,
'           but carrier must be above threshold
'       SYNCMODE_1516_CS (5): 15 of 16 sync-word bits must match,
'           and carrier must be above threshold
'       SYNCMODE_1616_CS (6): 16 of 16 sync-word bits must match,
'           and carrier must be above threshold
'       SYNCMODE_3032_CS (7): 30 of 32 sync-word bits must match,
'           and carrier must be above threshold
'   Any other value polls the chip and returns the current setting
'   NOTE: A 32-bit sync-word can be emulated by setting this method to
'       SYNCMODE_3032 or SYNCMODE_3032_CS. In these cases, the sync-word
'       specified by syncwd() will be transmitted twice.
    c := readreg(core.MDMCFG2)
    case md
        0..7:
            md := ((c & core.SYNC_MODE_MASK) | md) & core.MDMCFG2_MASK
            writereg(core.MDMCFG2, md)
        other:
            return c & core.SYNC_MODE_BITS


PUB set_syncwd(p_src)
' Set transmitted (TX) or expected (RX) syncword
'   p_src: pointer to syncword data
'   Valid values: $0000..$FFFF (default: $D391)
    writereg(core.SYNC1, p_src, 2)


PUB syncwd(p_dest)
' Get current syncword
'   p_dest: pointer to copy syncword data to
    readreg(core.SYNC1, 2, p_dest)


PUB tx_mode()
' Change chip state to TX (transmit)
    writereg(core.CS_STX)


PUB tx_payld(len, p_src)
' Queue data to transmit in the TX FIFO
'   len Valid values: 1..64
'   Any other value is ignored
    writereg(core.FIFO, p_src, len)


PUB tx_pwr(p=-255): c
' Set transmit power, in dBm
'   Valid values: -55, -30, -28, -26, -24, -22, -20, -18, -16, -14, -12, -10,
'        -8, -6, -4, -2, 0, 1
'   Any other value polls the chip and returns the current setting
    c := readreg(core.PATABLE)
    case p
        -55, -30, -28, -26, -24, -22, -20, -18, -16, -14, -12, -10, -8, -6, -4, -2, 0, 1:
            p := lookdown(p:    -55, -30, -28, -26, -24, -22, -20, -18, -16, -14, -12, -10, ...
                                    -8, -6, -4, -2, 0, 1)
            p := lookup(p:  $00, $50, $44, $C0, $84, $81, $46, $93, $55, $8D, $C6, $97, $6E,...
                                $7F, $A9, $BB, $FE, $FF)
            writereg(core.PATABLE, p)
        other:
            c := lookdown(c:  $00, $50, $44, $C0, $84, $81, $46, $93, $55, $8D, ...
                                            $C6, $97, $6E, $7F, $A9, $BB, $FE, $FF)
            return lookup(c: -55, -30, -28, -26, -24, -22, -20, -18, -16, -14, -12, -10, ...
                                    -8, -6, -4, -2, 0, 1)



PUB tx_pwr_i(i=-2): c
' Set index within PA table to write TX power to (used for FSK power ramping, or ASK shaping)
'   Valid values: 0..1
'   Any other value polls the chip and returns the current setting
'   NOTE: For simple transmit power setting without ramping,
'       set this value to 0 and then set TXPower to desired output power.
    c := readreg(core.FREND0)
    case i
        0..1:
            c := ((c & core.PA_PWR_MASK) | i)
            writereg(core.FREND0, c)
        other:
            return c & core.PA_PWR_BITS


PUB wake_on_radio()
' Change chip state to WOR (Wake-on-Radio)
    writereg(core.CS_SWOR)


PUB xtal_off()
' Turn off crystal oscillator
    writereg(core.CS_SXOFF)


PRI getstatus(): curr_status
' Read the status byte
    writereg(core.CS_SNOP)
    return _status


PRI readreg(reg_nr, len=1, p_dest=0): v
' Read nr_bytes from device into ptr_buff
    if ( (len > 1) or lookdown(reg_nr: core.PARTNUM..core.RCCTRL0_STATUS) )
        reg_nr |= core.BURST                    ' indicate multi-byte transfer or a status register

    outa[_CS] := 0
        spi.wr_byte(reg_nr | core.R)
        if ( ( (reg_nr & $3f) == core.FIFO) or ( (reg_nr & $3f) == core.SYNC1) )
            spi.rdblock_lsbf(p_dest, len)
        else
            v := 0
            spi.rdblock_msbf(@v, len)
    outa[_CS] := 1


PRI writereg(reg_nr, val=1, len=1)
' Write nr_bytes to device from ptr_buff
    if ( len > 1 )
        reg_nr |= core.BURST                    ' indicate multi-byte write transfer

    outa[_CS] := 0
        case reg_nr
            core.CS_SRES..core.CS_SNOP:
                spi.wr_byte(reg_nr)             ' command strobe
                _status := spi.rd_byte()        ' update status
            other:
                spi.wr_byte(reg_nr)
                if ( ( (reg_nr & $3f) == core.FIFO) or ( (reg_nr & $3f) == core.SYNC1) )
                    spi.wrblock_lsbf(val, len)  ' "array"-type registers
                else
                    spi.wrblock_msbf(@val, len) ' single or multibyte value registers
    outa[_CS] := 1

DAT
{
Copyright 2025 Jesse Burt

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
}

