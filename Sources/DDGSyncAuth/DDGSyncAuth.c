
#include <string.h>

#include "DDGSyncAuth.h"
#include "sodium.h"

// Seems mad that you still need to define this?!
#define min(x, y) (x < y) ? x : y

// Contexts must be 8 characters long but are otherwise arbitrary
#define DDGSYNC_STRETCHED_PRIMARY_KEY_CONTEXT "Stretchy"
#define DDGSYNC_PASSWORD_HASH_CONTEXT "Password"

// Other private macros
#define DDGSYNCAUTH_STRETCHED_PRIMARY_KEY_SIZE DDGSYNCAUTH_PRIMARY_KEY_SIZE * 2

enum DDGSyncAuthSubkeyIds : int {

    DDGSyncAuthPasswordHashSubkey = 1,
    DDGSyncAuthStretchedPrimaryKeySubkey,

};

DDGSyncAuthResult ddgSyncCreateAccount(
    unsigned char primaryKey[DDGSYNCAUTH_PRIMARY_KEY_SIZE],
    unsigned char protectedSymmetricKey[DDGSYNCAUTH_PROTECTED_SYMMETRIC_KEY_SIZE],
    unsigned char passwordHash[DDGSYNCAUTH_HASH_SIZE],
    const char *userId,
    const char *password) {

    // Define VARS
    unsigned char salt[crypto_pwhash_SALTBYTES];
    unsigned char stretchedPrimaryKey[DDGSYNCAUTH_STRETCHED_PRIMARY_KEY_SIZE];
    unsigned char secretKey[crypto_secretbox_KEYBYTES];
    unsigned char nonceBytes[crypto_secretbox_NONCEBYTES];

    // Validate inputs
    if (NULL == userId) {
        return DDGSYNCAUTH_INVALID_USERID;
    }

    if (NULL == password) {
        return DDGSYNCAUTH_INVALID_PASSWORD;
    }

    // Prepare salt
    memset(salt, 0, crypto_pwhash_SALTBYTES);
    memcpy(salt, userId, min(crypto_pwhash_SALTBYTES, strlen(userId)));

    // Create hash and keys

    if (0 != crypto_pwhash(primaryKey,
                           DDGSYNCAUTH_PRIMARY_KEY_SIZE,
                           password,
                           strlen(password),
                           salt,
                           crypto_pwhash_OPSLIMIT_INTERACTIVE,
                           crypto_pwhash_MEMLIMIT_INTERACTIVE,
                           crypto_pwhash_ALG_DEFAULT)) {

        return DDGSYNCAUTH_CREATE_PRIMARY_KEY_FAILED;
    }

    if (0 != crypto_kdf_derive_from_key(passwordHash,
                                        DDGSYNCAUTH_HASH_SIZE,
                                        DDGSyncAuthPasswordHashSubkey,
                                        DDGSYNC_PASSWORD_HASH_CONTEXT,
                                        primaryKey)) {
        return DDGSYNCAUTH_CREATE_PASSWORD_HASH_FAILED;
    }

    if (0 != crypto_kdf_derive_from_key(stretchedPrimaryKey,
                                        DDGSYNCAUTH_STRETCHED_PRIMARY_KEY_SIZE,
                                        DDGSyncAuthStretchedPrimaryKeySubkey,
                                        DDGSYNC_STRETCHED_PRIMARY_KEY_CONTEXT,
                                        primaryKey)) {
        return DDGSYNCAUTH_CREATE_STRETCHED_PRIMARY_KEY_FAILED;
    }

    randombytes_buf(secretKey, crypto_secretbox_KEYBYTES);
    randombytes_buf(nonceBytes, crypto_secretbox_NONCEBYTES);

    if (0 != crypto_secretbox_easy(protectedSymmetricKey,
                                   stretchedPrimaryKey,
                                   DDGSYNCAUTH_STRETCHED_PRIMARY_KEY_SIZE,
                                   nonceBytes,
                                   secretKey)) {
        return DDGSYNCAUTH_CREATE_PROTECTED_SECRET_KEY_FAILED;
    }

    return DDGSYNCAUTH_OK;
}
