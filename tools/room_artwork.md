# Room artwork

The opening scene uses four original ImageGen images. The lamp-off and lamp-on views share a camera within each pair. The images provide the room, lamp and reflected light. The renderer adds the CAD switch, phone, screen and recessed wall box. The box is an illustrative single-gang steel enclosure. Its mounting tabs align with the Nultra carrier’s holes, 83.3 mm apart. [Interactive room renderer](../docs/room.js)

| Plate | Input | Image direction |
| --- | --- | --- |
| [Desktop, lamp off](../docs/assets/room/interior-off-wide.webp) | Original generation | Photograph a contemporary reading corner at blue hour in landscape. Smoke-gray limewashed walls meet behind a satin walnut credenza with a limestone top. Place an unlit opaline mushroom lamp with a short brushed-bronze pedestal near the right edge. Leave the left 42% quietly shaded for the title, the foreground open for the phone and continuous plaster at 66% across for the wall switch. Use grazing window light, a 45 mm architectural lens and natural material detail. |
| [Desktop, lamp on](../docs/assets/room/interior-on-wide.webp) | Desktop, lamp off | Turn on the existing opal dome at approximately 2850 K. Add its warm pool of light to the immediate plaster, limestone and bronze. Lock the camera and preserve the architecture, lamp silhouette, book, wood grain and ambient exposure. |
| [Portrait, lamp off](../docs/assets/room/interior-off-tall.webp) | Desktop, lamp off | Recompose the same corner vertically. Leave the upper left in shadow for the title. Place the smaller opal lamp in the lower right, with its base at 72% of frame height. Keep the lower left open for the phone and the wall above it clear for the switch. Retain the limestone, walnut, bronze and evening window light. |
| [Portrait, lamp on](../docs/assets/room/interior-on-tall.webp) | Portrait, lamp off | Turn on the lamp in this exact portrait composition. Give the existing dome a warm-white center and softly illuminate the wall, stone and bronze nearby. Preserve the silhouette of each object, the cabinet lines and the exposure of the upper left. |

To refresh the static previews after changing the scene, run `node tools/capture_room_posters.mjs "/path/to/chrome"` from the repository root. The preview images include the 3D product and native app artwork.
