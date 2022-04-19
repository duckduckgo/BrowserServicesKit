#import "sodium/crypto_pwhash.h"
#import "sodium/crypto_kdf.h"

#ifndef DDGSyncAuth_h
#define DDGSyncAuth_h

#define DDGSYNCAUTH_HASH_SIZE crypto_pwhash_STRBYTES
#define DDDGSYNCAUTH_PRIMARY_KEY_SIZE crypto_kdf_KEYBYTES

#define DDGSYNC_KEY_CONTEXT "DuckSync" // must be 8 characters long but is otherwise arbitrary

typedef enum : int {
    DDGSYNCAUTH_OK,
    DDGSYNCAUTH_UNKNOWN_ERROR,
    DDGSYNCAUTH_INVALID_ARGS,
} DDGSyncAuthResult;

/*
 * Use when creating a new account.
 */
extern DDGSyncAuthResult ddgSyncCreateKeyAndPasswordHash(
    char *userId,                                       // IN - use a UUID
    char *password,                                     // IN - use a UUID
    char key[crypto_kdf_KEYBYTES],                      // OUT - store this securely
    char passwordHash[crypto_pwhash_STRBYTES]           // OUT - Use in API calls but don't store it
);

/*
 * Use when you need to make an API call.
 */
extern DDGSyncAuthResult ddgSyncCreatePasswordHash(
    const char key[crypto_kdf_KEYBYTES],                      // IN
    char passwordHash[crypto_pwhash_STRBYTES]           // OUT - Use in API calls but don't store it
);

#endif /* DDGSyncAuth_h */
