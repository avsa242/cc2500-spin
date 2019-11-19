# cc2500-spin 
-------------

This is a P8X32A/Propeller driver object for the TI CC2500 2.4GHz ISM-band transceiver chip.

## Salient Features

* SPI connection at 1MHz
* Supports setting carrier frequency from 2,400,000kHz to 2,483,500kHz
* Supports on-air baud rates from 1.2kbps to 500kbps
* Supports 2FSK, 4FSK, GFSK, MSK, ASK/OOK modulation
* Supports manchester encoding/decoding
* Supports on-chip CRC calculation/checking
* Supports Forward Error Correction (FEC)
* Supports setting intermediate frequency (IF) from 25kHz to 787kHz (5-bit resolution)
* Supports LNA gain control
* Supports arbitrary packet lengths
* Supports configurable number of preamble bytes
* Supports syncword configuration
* Supports data whitening
* Supports address checking

## Requirements

* 1 extra core/cog for the PASM SPI driver

## Limitations

* TX deviation only partially implemented
* Many chip functions untested
* Driver very early in development - may malfunction or outright fail to build

## TODO

- [ ] Implement & verify TX deviation functionality
- [ ] Verify RSSI functionality
