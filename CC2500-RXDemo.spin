{
    --------------------------------------------
    Filename: CC2500-RXDemo.spin
    Author: Jesse Burt
    Description: Simple receive demo of the cc2500 driver
    Copyright (c) 2021
    Started Nov 23, 2019
    Updated Jan 10, 2021
    See end of file for terms of use.
    --------------------------------------------
}
CON

    _clkmode        = cfg#_clkmode
    _xinfreq        = cfg#_xinfreq

' -- User-modifiable constants
    LED             = cfg#LED1
    SER_BAUD        = 115_200

    CS_PIN          = 0
    SCK_PIN         = 1
    MOSI_PIN        = 2
    MISO_PIN        = 3

    NODE_ADDRESS    = $01                       ' this node's address $00..$ff
' --

OBJ

    ser         : "com.serial.terminal.ansi"
    cfg         : "core.con.boardcfg.flip"
    time        : "time"
    int         : "string.integer"
    cc2500      : "wireless.transceiver.cc2500.spi"

VAR

    long _fifo[16]
    byte _pktlen

PUB Main{}

    setup{}

    cc2500.gpio0(cc2500#IO_HI_Z)                ' set GPIO0 to hi-Z mode
    cc2500.autocal(cc2500#IDLE_RXTX)            ' calibrate on idle to RX/TX
    ser.str(string("Autocal setting: "))
    ser.dec(cc2500.autocal(-2))
    ser.newline{}
    cc2500.idle{}
    
    ser.str(string("Waiting for radio idle status..."))
    repeat until cc2500.state{} == 1
    ser.strln(string("done"))

    cc2500.carrierfreq(2_401_000)               ' set carrier frequency

    ser.str(string("Waiting for PLL lock..."))
    repeat until cc2500.plllocked{}             ' wait until PLL is locked
    ser.strln(string("done"))

    ser.strln(string("Press any key to begin receiving"))
    ser.charin{}

    receive{}

PUB Receive{} | rxbytes, tmp, from_node

    _pktlen := 10
    cc2500.nodeaddress(NODE_ADDRESS)            ' this node's address
    cc2500.payloadLenCfg(cc2500#PKTLEN_FIXED)   ' fixed payload length mode
    cc2500.payloadLen(_pktlen)                  ' set payload length
    cc2500.crccheckEnabled(TRUE)                ' enable CRC checks
    cc2500.syncmode(cc2500#SYNCMODE_3032_CS)    ' accept payload as valid if:
                                                ' 30 of 32 syncword bits match
                                                ' Carrier sense > threshold

    ser.clear{}
    ser.position(0, 0)
    ser.str(string("Receive mode - "))
    ser.dec(cc2500.carrierfreq(-2))
    ser.str(string("Hz"))
    ser.newline{}

    ser.str(string("Listening for traffic on node address $"))
    ser.hex(cc2500.nodeaddress(-2), 2)

    cc2500.afterrx(cc2500#RXOFF_IDLE)           ' change to state after rx

    ' filter rx'd packets based on address; no broadcast packets allowed
    cc2500.addresscheck(cc2500#ADRCHK_CHK_NO_BCAST)

    repeat
        bytefill(@_fifo, $00, 64)               ' clear RX fifo
        cc2500.rxmode{}                         ' set radio to receive mode
        ser.position(0, 5)
        ser.str(string("Radio state: "))
        ser.str(@MARC_STATE[17 * cc2500.State])

        repeat                                  ' wait to proceed until
            rxbytes := cc2500.fiforxbytes{}     ' expected # of bytes
        until rxbytes => _pktlen                ' received in FIFO

        cc2500.rxpayload(rxbytes, @_fifo)
        cc2500.flushrx{}

        from_node := _fifo.byte[1]              ' node packet is from
        ser.position(0, 9)
        ser.str(string("Received packet from node $"))
        ser.hex(from_node, 2)

        ' show packet, minus the 2 "header" bytes
        repeat tmp from 2 to rxbytes-1
            ser.position(((tmp-1) * 3), 10)
            ser.hex(_fifo.byte[tmp], 2)
            case _fifo.byte[tmp]
                32..127:
                    ser.position(((tmp-1) * 3), 11)
                    ser.char(_fifo.byte[tmp])
                other:
                    ser.position(((tmp-1) * 3), 11)
                    ser.char(".")

PUB Setup{}

    ser.start(SER_BAUD)
    time.msleep(30)
    ser.clear{}
    ser.strln(string("Serial terminal started"))
    if cc2500.start(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN)
        ser.strln(string("CC2500 driver started"))
    else
        ser.strln(string("CC2500 driver failed to start - halting"))
        repeat

DAT
' Radio states
MARC_STATE  byte    "SLEEP           ", 0 {0}
            byte    "IDLE            ", 0 {1}
            byte    "XOFF            ", 0 {2}
            byte    "VCOON_MC        ", 0 {3}
            byte    "REGON_MC        ", 0 {4}
            byte    "MANCAL          ", 0 {5}
            byte    "VCOON           ", 0 {6}
            byte    "REGON           ", 0 {7}
            byte    "STARTCAL        ", 0 {8}
            byte    "BWBOOST         ", 0 {9}
            byte    "FS_LOCK         ", 0 {10}
            byte    "IFADCON         ", 0 {11}
            byte    "ENDCAL          ", 0 {12}
            byte    "RX              ", 0 {13}
            byte    "RX_END          ", 0 {14}
            byte    "RX_RST          ", 0 {15}
            byte    "TXRX_SWITCH     ", 0 {16}
            byte    "RXFIFO_OVERFLOW ", 0 {17}
            byte    "FSTXON          ", 0 {18}
            byte    "TX              ", 0 {19}
            byte    "TX_END          ", 0 {20}
            byte    "RXRX_SWITCH     ", 0 {21}

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

