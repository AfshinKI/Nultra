# Nultra hardware

| To work on | Start here |
| --- | --- |
| Enclosure fit or assembly | [Single-switch STEP](mechanical/assemblies/single-switch.step) or [double-switch STEP](mechanical/assemblies/double-switch.step) |
| An individual machined or printed part | [STEP solids](mechanical/step/) and [print meshes](mechanical/prints/) |
| The circuit and PCB layout | [KiCad 10 project](electronics/kicad/Nultra.kicad_pro) |
| The original v2 fabrication run | [Gerbers, drills, BOM and pad connections](electronics/fabrication/v2/) |

## Enclosure

The STEP assemblies use millimetres and preserve the saved positions of the single and double switch designs. The single model contains the faceplate, wordmark, carrier, rear shell and bare PCB. The double model has one wide faceplate, one wordmark and two sets of the other parts. Their outside dimensions are approximately 70 × 115 × 31 mm and 116 × 115 × 31 mm. Each assembly imports as named components in a STEP-capable CAD application. The CAD export contains solid geometry and assembly placements. Parametric sketches and mechanical mates are unavailable in this exchange format.

Open a faceplate and its matching wordmark STL together as a multipart object to keep their shared print coordinates. Use one carrier and one rear shell per switch mechanism. The [v2 bare-board STEP](electronics/cad/bare-board-v2.step) preserves the board outline and holes from the original electronics export. The assembly models omit purchased components such as the cell, light pipe and board-mounted devices, so their clearances require separate review.

The five individual STEP files come from the enclosure part geometry. The assemblies use the saved component transforms from the original housing design. Every exported body passed an Open Cascade solid-validity check after reimport, including the six individual letters. The six STL triangle payloads match the original print exports.

## Electronics

Open the KiCad project from its own folder to resolve the local symbol and footprint libraries. The editable schematic and two-layer board come from the later Altium working files. The board has 50 placed footprints and the local library contains its 29 distinct land patterns.

**Use the KiCad project as an editing baseline.** KiCad 10.0.4 reported 10 schematic errors and 12 warnings. The board check reported 1,083 rule violations, one unconnected item and 152 schematic-to-board findings. These include apparent shorts, a missing ground connection and conflicting pin or net names. Compare any newly generated artwork with the v2 Gerbers and resolve electrical connectivity before making a changed board.

### Archived v2 production data

The manufacturing ZIP preserves the original layer and drill payloads from January 1, 2025. Top and bottom copper use `.GTL` and `.GBL`, solder mask uses `.GTS` and `.GBS`, silkscreen uses `.GTO` and `.GBO`, and solder paste uses `.GTP` and `.GBP`. The board outline is `.GM` and the keep-out drawing is `.GKO`. Include both the round-hole and slot Excellon files when viewing the job.

The BOM came from the same v2 fabrication folder. The pad connection table lists reference, pad number and board net for 155 distinct combinations across 36 named nets. It was extracted from the PCB saved 43 seconds before the archived Gerber report. Only named pads appear in the table. An empty net field means the board assigned no net. The antenna carries the original placeholder reference `*`. The archive contains no v2 pick-and-place file.

The editable schematic and PCB have later modification dates. For example, the historical board assigns battery contact BT1 pad `+` to `VBATT`, while the KiCad board lacks that numbered pad. U1 pins 25 and 27 also carry different net names between the two files. Use the archived pad table to check these differences alongside the artwork.

## Hardware notices

Original Nultra enclosure geometry, circuit design and board layout are released under [CERN-OHL-P-2.0](../LICENSES/CERN-OHL-P-2.0.txt). The project symbol and footprint libraries contain the component definitions used in this design. The Altium schematic identifies the author's component libraries and the Altium Content Vault as sources. Third-party component definitions retain their applicable terms.

The Keystone Electronics 5223 battery contact, BT1, includes SnapEDA sourcing metadata. Its symbol and footprint were converted to KiCad format. SnapMagic Search describes its individual component files as CC BY-SA 4.0 with Design Exception 1.0. The exception covers their use within a board design. [5223 part page](https://www.snapeda.com/parts/5223/Keystone/view-part/) · [SnapMagic license and design exception](https://www.snapeda.com/about/terms/) · [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
