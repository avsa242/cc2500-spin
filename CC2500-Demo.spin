{
    --------------------------------------------
    Filename: CC1101-Test.spin
    Author: Jesse Burt
    Description: Test object for the cc1101 driver
    Copyright (c) 2019
    Started Mar 25, 2019
    Updated Apr 2, 2019
    See end of file for terms of use.
    --------------------------------------------
}

CON

    _clkmode        = cfg#_clkmode
    _xinfreq        = cfg#_xinfreq

    CS_PIN      = 3 'BLUE
    SCK_PIN     = 1 'YELLOW '2'
    MOSI_PIN    = 0 'ORANGE '3'
    MISO_PIN    = 2 'GREEN  '1'

    COL_REG         = 0
    COL_SET         = 12
    COL_READ        = 24
    COL_PF          = 40

    ST_IDLE         = $01
    ST_TX           = $13
    ST_RX           = $0D
    ST_TX_UNDER     = $16
    ST_RX_OVER      = $11
    ST_STARTCAL     = $08

    LED             = cfg#LED1

OBJ

    cfg : "core.con.boardcfg.flip"
    ser : "com.serial.terminal.ansi"
    time: "time"
    rf  : "wireless.transceiver.cc2500.spi"
    int : "string.integer"

VAR

    byte _ser_cog
    byte _FIFO[64]
    byte _rf_state
    byte _addr
    byte _pktlen

PUB Main

    dira[23] := 0
    outa[23] := 0
    Setup
'    rf.CarrierFreq(2_401_001)
'    ser.Dec(rf.CarrierFreq(-2))
'    ser.Hex(rf.CarrierFreq(2_483_500), 8)
'    time.sleep(2)
'    Flash(LED, 100)

    repeat
        ser.Str (string("Choose role (1 = TX, 2 = RX)"))
        case ser.CharIn
            "1":
                Init
                TXDemo

            "2":
                Init
                RXDemo
            OTHER:

PUB Init

    _pktlen := 27
    rf.Reset
    rf.AutoCal (rf#IDLE_RXTX)
    rf.CalFreqSynth
    rf.CRCCheck (TRUE)
    rf.GDO0 (rf#IO_HI_Z)
    rf.GDO1 (rf#IO_HI_Z)
    rf.Modulation (rf#FSK2)
    rf.SyncWord ($7CD2)
    rf.SyncMode (rf#SYNCMODE_1516)'(rf#SYNCMODE_3032_CS)
    rf.Idle
    rf.CarrierFreq (2_463_000)
'    rf.Deviation (10000)
    rf.DataRate (9600)
    rf.Preamble (4)
    rf.AppendStatus (TRUE)
    rf.PacketLenCfg (rf#PKTLEN_FIXED)
    rf.PacketLen (_pktlen)
    ser.Clear

PUB RXDemo | i, iter, gdopin

    iter := 0
    _addr := 242
    rf.Address (_addr)
    rf.GDO2 ($07) '$07
    rf.AddressCheck ( rf#ADRCHK_CHK_NO_BCAST)
    iter := 0
'    rf.CarrierSense (6)
    rf.PreambleQual (4)
    rf.CRCAutoFlush (TRUE)
    rf.RXOff (rf#RXOFF_RX)
    rf.RX
    ser.Position (45, 0)
    ser.Str(string("Address: "))
    ser.Dec (rf.Address (-2))
    gdopin := 11
    dira[gdopin] := 0
    dira[cfg#LED1] := 1

    repeat
        bytefill(@_FIFO, $00, 64)
        waitpeq(|<gdopin, |<gdopin, 0)
        outa[cfg#LED1] := 1
        iter++
        ser.Position (0, 1)
        ser.Str (string("Packet # "))
        ser.Dec (iter)

        rf.RXData (_pktlen+2, @_FIFO)   'Read '_pktlen' num. bytes from FIFO plus 2 more (RSSI and LQI/CRC bytes)

        ser.Position (30, 0)
        ser.Str (string("RSSI: "))
        ser.Str (int.DecPadded (RSSI(_FIFO.byte[_pktlen]), 3))

        ser.Position (58, 0)
        ser.Str (string("CRC: "))
        if _FIFO.byte[28] >> 7
            ser.Str (string("OK"))
        else
            ser.Str (string("XX"))

        ser.Position (67, 0)
        ser.Str (string("LQI: "))
        ser.Str (int.DecPadded (_FIFO.byte[_pktlen+1] & $7F, 3))

        repeat i from 1 to _pktlen+1
            ReadState
            ser.Position ((i*3)-3, 4)
            ser.Dec (i)
            ser.Position ((i*3)-3, 5)
            ser.Hex (_FIFO.byte[i], 2)
            ser.Position ((i*3)-3, 6)
            ser.Char (_FIFO.byte[i])

        rf.Idle
        rf.FlushRX

        waitpne(|<gdopin, |<gdopin, 0)
        outa[cfg#LED1] := 0

        rf.RX

PUB RSSI(raw_rssi)

    if raw_rssi => 128
        result := ((raw_rssi - 256)/2) - 74
    else
        result := (raw_rssi/ 2) - 74

PUB TXDemo | i, iter, addr

    iter := 0
    addr := 242
    bytefill(@_FIFO, $00, 64)

    _FIFO.byte[0] := addr
    repeat i from 1 to 26
        _FIFO.byte[i] := 64+(i)

    repeat i from 1 to 26
        ser.Position ((i*3)-3, 4)
        ser.Dec (i)

        ser.Position ((i*3)-3, 5)
        ser.Hex (_FIFO.byte[i], 2)

        ser.Position ((i*3)-3, 6)
        ser.Char (_FIFO.byte[i])

    rf.FSTX
    rf.TX
    rf.TXOff (rf#TXOFF_IDLE)

    repeat
        case _rf_state := rf.State
            ST_IDLE:
                rf.FlushTX
                ReadState
                time.Sleep (3)
                rf.TX
                iter++
                ser.Position (0, 1)
                ser.Str (string("Packet # "))
                ser.Dec (iter)

            ST_TX:
                ReadState
                ser.Position (45, 0)
                ser.Str (string("Address: "))
                ser.Dec (addr)
                rf.TXData (27, @_FIFO)
                time.MSleep (50)
            OTHER:
                ReadState
                time.MSleep (50)

PUB ReadState | tmp

    ser.Position (0, 0)
    ser.Str (string("Radio state: "))
    ser.Str (@MARC_STATE[17 * _rf_state])
'    ser.Position (30, 0)
'    ser.Str (string("RSSI: "))
'    ser.Str (int.DecPadded (rf.RSSI, 4))

PUB Setup

    repeat until _ser_cog := ser.Start (115_200)
    time.sleep(1)
    ser.Clear
    ser.Str(string("Serial terminal started", ser#NL, ser#LF))
    if rf.Start (CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN)
        ser.Str (string("CC2500 driver started", ser#NL, ser#LF))
    else
        ser.Str (string("CC2500 driver failed to start - halting", ser#NL, ser#LF))
        rf.Stop
        time.MSleep (500)
        ser.Stop

PUB Flash(pin, delay_ms)

    dira[pin] := 1
    repeat
        !outa[pin]
        time.MSleep (delay_ms)

DAT

MARC_STATE  byte    "SLEEP           ", 0
            byte    "IDLE            ", 0
            byte    "XOFF            ", 0
            byte    "VCOON_MC        ", 0
            byte    "REGON_MC        ", 0
            byte    "MANCAL          ", 0
            byte    "VCOON           ", 0
            byte    "REGON           ", 0
            byte    "STARTCAL        ", 0
            byte    "BWBOOST         ", 0
            byte    "FS_LOCK         ", 0
            byte    "IFADCON         ", 0
            byte    "ENDCAL          ", 0
            byte    "RX              ", 0
            byte    "RX_END          ", 0
            byte    "RX_RST          ", 0
            byte    "TXRX_SWITCH     ", 0
            byte    "RXFIFO_OVERFLOW ", 0
            byte    "FSTXON          ", 0
            byte    "TX              ", 0
            byte    "TX_END          ", 0
            byte    "RXRX_SWITCH     ", 0
            byte    "TXFIFO_UNDERFLOW", 0

DAT
{
    --------------------------------------------------------------------------------------------------------
    TERMS OF USE: MIT License

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
    associated documentation files (the "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
    following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial
    portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
    LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
    WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    --------------------------------------------------------------------------------------------------------
}
