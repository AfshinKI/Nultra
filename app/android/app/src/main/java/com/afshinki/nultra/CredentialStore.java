package com.afshinki.nultra;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class CredentialStore {
  private final SharedPreferences prefs;
  private static final String ALIAS = "nultra-master";

  CredentialStore(Context c) {
    prefs = c.getSharedPreferences("credentials", Context.MODE_PRIVATE);
  }

  private SecretKey key() throws Exception {
    KeyStore store = KeyStore.getInstance("AndroidKeyStore");
    store.load(null);
    if (!store.containsAlias(ALIAS)) {
      KeyGenerator generator =
          KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
      generator.init(
          new KeyGenParameterSpec.Builder(
                  ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
              .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
              .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
              .build());
      generator.generateKey();
    }
    return (SecretKey) store.getKey(ALIAS, null);
  }

  String get(String account) throws Exception {
    String value = prefs.getString(account + ".value", null);
    if (value == null) return "";
    Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
    c.init(
        Cipher.DECRYPT_MODE,
        key(),
        new GCMParameterSpec(128, Base64.decode(prefs.getString(account + ".iv", ""), Base64.NO_WRAP)));
    String result =
        new String(c.doFinal(Base64.decode(value, Base64.NO_WRAP)), StandardCharsets.US_ASCII);
    Protocol.ascii(result);
    return result;
  }

  void save(String account, String value) throws Exception {
    byte[] bytes = Protocol.ascii(value);
    Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
    c.init(Cipher.ENCRYPT_MODE, key());
    if (!prefs
        .edit()
        .putString(account + ".value", Base64.encodeToString(c.doFinal(bytes), Base64.NO_WRAP))
        .putString(account + ".iv", Base64.encodeToString(c.getIV(), Base64.NO_WRAP))
        .commit()) throw new Exception("Could not save password.");
  }

  void reset(String account) throws Exception {
    if (!prefs.edit().remove(account + ".iv").remove(account + ".value").commit())
      throw new Exception("Could not forget the credential.");
  }
}
