# cc2500-spin 
-------------

This is a P8X32A/Propeller, P2X8C4M64P/Propeller 2 driver object for the TI CC2500 2.4GHz ISM-band transceiver chip.

**IMPORTANT**: This software is meant to be used with the [spin-standard-library](https://github.com/avsa242/spin-standard-library) (P8X32A) or [p2-spin-standard-library](https://github.com/avsa242/p2-spin-standard-library) (P2X8C4M64P). Please install the applicable library first before attempting to use this code, otherwise you will be missing several files required to build the project.

## Salient Features

* SPI connection at up to 1MHz (P1), up to 6.5MHz (P2)
* Supports setting carrier frequency from 2,400,000kHz to 2,483,500kHz
* Set common RF parameters: Receive bandwidth, IF, carrier freq, DC block filter, RX Gain (LNA, DVGA), TX power, FSK deviation freq, modulation (2/4FSK, GFSK, MSK, ASK/OOK)
* Supports on-air baud rates from 600bps to 500kbps
* Set number of preamble bytes
* Set function of CC2500's GPIO pins
* Optional address filtering
* Options for increasing transmission robustness: Data whitening, Manchester encoding, FEC, syncword, CRC calculation/checking
* Packet radio options: arbitrary payload lengths (1..255), fixed or variable-length payloads
* Supports appending optional packet reception statistics to packet payload (RX role)
* Supports setting frequency by channel number (0..255), and modifiable channel spacing
* RSSI measurement
* FIFO: Read RX, TX states, flush

## Requirements

P1/SPIN1:
* spin-standard-library
* P1: 1 extra core/cog for the PASM SPI engine

P2/SPIN2:
* p2-spin-standard-library

## Compiler Compatibility

* P1/SPIN1 OpenSpin (bytecode): Untested (deprecated)
* P1/SPIN1 FlexSpin (bytecode): OK, tested with 5.9.7-beta
* P1/SPIN1 FlexSpin (native): OK, tested with 5.9.7-beta
* ~~P2/SPIN2 FlexSpin (nu-code): FTBFS, tested with 5.9.7-beta~~
* P2/SPIN2 FlexSpin (native): OK, tested with 5.9.7-beta
* ~~BST~~ (incompatible - no preprocessor)
* ~~Propeller Tool~~ (incompatible - no preprocessor)
* ~~PNut~~ (incompatible - no preprocessor)

## Limitations

* Very early in development - may malfunction or outright fail to build

