#import "sodium/crypto_pwhash.h"
#import "sodium/crypto_box.h"
#import "sodium/crypto_secretbox.h"

#ifndef DDGSyncCrypto_h
#define DDGSyncCrypto_h

typedef enum : int {
    DDGSYNCCRYPTO_HASH_SIZE = 32,
    DDGSYNCCRYPTO_PRIMARY_KEY_SIZE = 32,
    DDGSYNCCRYPTO_SECRET_KEY_SIZE = 32,
    DDGSYNCCRYPTO_STRETCHED_PRIMARY_KEY_SIZE = 32,
    DDGSYNCCRYPTO_PROTECTED_SYMMETRIC_KEY_SIZE = (crypto_secretbox_MACBYTES + DDGSYNCCRYPTO_STRETCHED_PRIMARY_KEY_SIZE + crypto_secretbox_NONCEBYTES),
} DDGSyncCryptoSizes;

typedef enum : int {
    DDGSYNCCRYPTO_OK,
    DDGSYNCCRYPTO_UNKNOWN_ERROR,
    DDGSYNCCRYPTO_INVALID_USERID,
    DDGSYNCCRYPTO_INVALID_PASSWORD,
    DDGSYNCCRYPTO_CREATE_PRIMARY_KEY_FAILED,
    DDGSYNCCRYPTO_CREATE_PASSWORD_HASH_FAILED,
    DDGSYNCCRYPTO_CREATE_STRETCHED_PRIMARY_KEY_FAILED,
    DDGSYNCCRYPTO_CREATE_PROTECTED_SECRET_KEY_FAILED,
} DDGSyncCryptoResult;

/**
 * Used to create data needed to create an account.  Once the server returns a JWT, then store primary and secret key.
 *
 * @param primaryKey OUT - store this.  In combination with user id, this is the recovery key.
 * @param secretKey OUT - store this. This is used to encrypt an decrypt e2e data.
 * @param protectedSymmetricKey OUT - do not store this.  Send to /sign up endpoint.
 * @param passwordHash OUT - do not store this.  Send to /signup endpoint.
 * @param userId IN
 * @param password IN
 */
extern DDGSyncCryptoResult ddgSyncGenerateAccountKeys(
    unsigned char primaryKey[DDGSYNCCRYPTO_PRIMARY_KEY_SIZE],
    unsigned char secretKey[DDGSYNCCRYPTO_SECRET_KEY_SIZE],
    unsigned char protectedSymmetricKey[DDGSYNCCRYPTO_PROTECTED_SYMMETRIC_KEY_SIZE],
    unsigned char passwordHash[DDGSYNCCRYPTO_HASH_SIZE],
    const char *userId,
    const char *password
);

#endif /* DDGSyncCrypto_h */
