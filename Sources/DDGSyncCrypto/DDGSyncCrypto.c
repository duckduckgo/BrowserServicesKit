
#include <string.h>

#include "DDGSyncCrypto.h"
#include "sodium.h"

// Seems mad that you still need to define this?!
#define min(x, y) (x < y) ? x : y

// Contexts must be 8 characters long but are otherwise arbitrary
#define DDGSYNC_STRETCHED_PRIMARY_KEY_CONTEXT "Stretchy"
#define DDGSYNC_PASSWORD_HASH_CONTEXT "Password"

enum DDGSyncCryptoSubkeyIds : int {

    DDGSyncCryptoPasswordHashSubkey = 1,
    DDGSyncCryptoStretchedPrimaryKeySubkey,

};

DDGSyncCryptoResult ddgSyncGenerateAccountKeys(
    unsigned char primaryKey[DDGSYNCCRYPTO_PRIMARY_KEY_SIZE],
    unsigned char secretKey[DDGSYNCCRYPTO_SECRET_KEY_SIZE],
    unsigned char protectedSymmetricKey[DDGSYNCCRYPTO_PROTECTED_SYMMETRIC_KEY_SIZE],
    unsigned char passwordHash[DDGSYNCCRYPTO_HASH_SIZE],
    const char *userId,
    const char *password) {

    // Define vars

    unsigned char salt[crypto_pwhash_SALTBYTES];
    unsigned char stretchedPrimaryKey[DDGSYNCCRYPTO_STRETCHED_PRIMARY_KEY_SIZE];
    unsigned char nonceBytes[crypto_secretbox_NONCEBYTES];

    // Validate inputs

    if (NULL == userId) {
        return DDGSYNCCRYPTO_INVALID_USERID;
    }

    if (NULL == password) {
        return DDGSYNCCRYPTO_INVALID_PASSWORD;
    }

    // Prepare salt

    memset(salt, 0, crypto_pwhash_SALTBYTES);
    memcpy(salt, userId, min(crypto_pwhash_SALTBYTES, strlen(userId)));

    // Create hash and keys

    if (0 != crypto_pwhash(primaryKey,
                           DDGSYNCCRYPTO_PRIMARY_KEY_SIZE,
                           password,
                           strlen(password),
                           salt,
                           crypto_pwhash_OPSLIMIT_INTERACTIVE,
                           crypto_pwhash_MEMLIMIT_INTERACTIVE,
                           crypto_pwhash_ALG_DEFAULT)) {

        return DDGSYNCCRYPTO_CREATE_PRIMARY_KEY_FAILED;
    }

    if (0 != crypto_kdf_derive_from_key(passwordHash,
                                        DDGSYNCCRYPTO_HASH_SIZE,
                                        DDGSyncCryptoPasswordHashSubkey,
                                        DDGSYNC_PASSWORD_HASH_CONTEXT,
                                        primaryKey)) {

        return DDGSYNCCRYPTO_CREATE_PASSWORD_HASH_FAILED;
    }

    if (0 != crypto_kdf_derive_from_key(stretchedPrimaryKey,
                                        DDGSYNCCRYPTO_STRETCHED_PRIMARY_KEY_SIZE,
                                        DDGSyncCryptoStretchedPrimaryKeySubkey,
                                        DDGSYNC_STRETCHED_PRIMARY_KEY_CONTEXT,
                                        primaryKey)) {

        return DDGSYNCCRYPTO_CREATE_STRETCHED_PRIMARY_KEY_FAILED;
    }

    randombytes_buf(secretKey, DDGSYNCCRYPTO_SECRET_KEY_SIZE);
    randombytes_buf(nonceBytes, crypto_secretbox_NONCEBYTES);

    if (0 != crypto_secretbox_easy(protectedSymmetricKey,
                                   secretKey,
                                   DDGSYNCCRYPTO_SECRET_KEY_SIZE,
                                   nonceBytes,
                                   stretchedPrimaryKey)) {
        return DDGSYNCCRYPTO_CREATE_PROTECTED_SECRET_KEY_FAILED;
    }

    memcpy(&protectedSymmetricKey[crypto_secretbox_MACBYTES + DDGSYNCCRYPTO_SECRET_KEY_SIZE], nonceBytes, crypto_secretbox_NONCEBYTES);

    return DDGSYNCCRYPTO_OK;
}
