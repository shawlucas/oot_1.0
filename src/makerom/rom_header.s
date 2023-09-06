/*
 * The Legend of Zelda: Ocarina of Time ROM header
 */

.byte  0x80, 0x37, 0x12, 0x40   /* PI BSD Domain 1 register */
.word  0x0000000F               /* Clockrate setting */
.word  0x80000400               /* Entrypoint function (`entrypoint`) */
.word  0x00001449               /* Revision */
.word  0xEC7011B7               /* Checksum 1 */
.word  0x7616D72B               /* Checksum 2 */
.word  0x00000000               /* Unknown */
.word  0x00000000               /* Unknown */
.ascii "THE LEGEND OF ZELDA "   /* Internal ROM name */
.word  0x00000000               /* Unknown */
.word  0x00000043               /* Cartridge */
.ascii "ZL"                     /* Cartridge ID */
.ascii "J"                      /* Region */
.byte  0x00                     /* Version */