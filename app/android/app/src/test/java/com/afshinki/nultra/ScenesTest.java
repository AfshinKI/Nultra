package com.afshinki.nultra;

import org.junit.Test;
import java.util.*;
import static org.junit.Assert.*;

public class ScenesTest {
  @Test public void overlappingScenesDeduplicateAndNeverExpandUnknownTargets() {
    Scenes.Scene a = new Scenes.Scene(UUID.randomUUID().toString(), " Downstairs ", Arrays.asList("a", "b", "a", "missing"));
    Scenes.Scene b = new Scenes.Scene(UUID.randomUUID().toString(), "Evening", Arrays.asList("b"));
    assertEquals("Downstairs", a.name);
    assertEquals(Arrays.asList("a", "b"), a.targets(Arrays.asList("a", "b")));
    assertEquals(Arrays.asList("b"), b.targets(Arrays.asList("a", "b")));
    assertTrue(a.targets(Collections.emptyList()).isEmpty());
  }
  @Test public void roundTripRenameDeleteAndCorruptData() {
    Scenes.Scene a = new Scenes.Scene(UUID.randomUUID().toString(), "Living room", Arrays.asList("a", "b"));
    Scenes.Scene b = new Scenes.Scene(UUID.randomUUID().toString(), "Evening", Arrays.asList("b"));
    List<Scenes.Scene> restored = Scenes.decode(Scenes.encode(Arrays.asList(a, b)));
    assertEquals(a.id, restored.get(0).id); assertEquals(a.members, restored.get(0).members);
    restored.get(0).name = "Downstairs";
    assertEquals(a.target(), Scenes.decode(Scenes.encode(restored)).get(0).target());
    restored.remove(0);
    assertEquals(b.id, Scenes.decode(Scenes.encode(restored)).get(0).id);
    assertTrue(Scenes.decode("bad json").isEmpty());
  }
}
