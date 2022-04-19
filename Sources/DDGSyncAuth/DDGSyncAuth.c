
#include "DDGSyncAuth.h"
#include "sodium.h"
#include <string.h>

DDGSyncAuthResult ddgSyncCreateKeyAndPasswordHash(
    char *userId,                                      // IN - use a UUID
    char *password,                                    // IN - use a UUID
    char primaryKey[DDGSYNCAUTH_PRIMARY_KEY_SIZE],    // OUT - store this securely
    char passwordHash[DDGSYNCAUTH_HASH_SIZE]           // OUT - Use in API calls but don't store it
) {

    if (NULL == userId || NULL == password) {
        return DDGSYNCAUTH_INVALID_ARGS;
    }

    return DDGSYNCAUTH_OK;
}

DDGSyncAuthResult ddgSyncCreatePasswordHash(
    const char primaryKey[DDGSYNCAUTH_PRIMARY_KEY_SIZE],   // IN
    char passwordHash[DDGSYNCAUTH_HASH_SIZE]                // OUT - Use in API calls but don't store it
) {

    if (0 != crypto_pwhash_str(passwordHash,
                                primaryKey,
                                strlen(primaryKey),
                                crypto_pwhash_OPSLIMIT_SENSITIVE,
                                crypto_pwhash_MEMLIMIT_INTERACTIVE)) {
        return DDGSYNCAUTH_UNKNOWN_ERROR;
    }

    return DDGSYNCAUTH_OK;
}
