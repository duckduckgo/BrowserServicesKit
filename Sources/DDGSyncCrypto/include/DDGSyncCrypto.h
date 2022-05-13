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
    DDGSYNCCRYPTO_ENCRYPTED_EXTRA_BYTES_SIZE = (crypto_secretbox_MACBYTES + crypto_secretbox_NONCEBYTES),
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
    DDGSYNCCRYPTO_ENCRYPTION_FAILED,
    DDGSYNCCRYPTO_DECRYPTION_FAILED,
} DDGSyncCryptoResult;

/**
 * Used to create data needed to create an account.  Once the server returns a JWT, store the primary and secret key.
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

/**
 * @param encryptedBytes OUT - the size of this should be equal to the size of data to encrypt, plus crypto_secretbox_MACBYTES (16 bytes) plus crypto_secretbox_NONCEBYTES (16).  The output will be the encrypted data, plus MAC, plus nonce.
 * @param rawBytes IN - the data to be encrypted.  Should be of size specified by rawDataLength
 * @param rawBytesLength IN - the length of the data to be encrypted
 * @param secretKey IN - the secret key (assumed to be of length DDGSYNCCRYPTO_SECRET_KEY_SIZE)
 */
extern DDGSyncCryptoResult ddgSyncEncrypt(
    unsigned char *encryptedBytes,
    unsigned char *rawBytes,
    unsigned long long rawBytesLength,
    unsigned char *secretKey
);

extern DDGSyncCryptoResult ddgSyncDecrypt(
    unsigned char *rawBytes,
    unsigned char *encryptedBytes,
    unsigned long long encryptedBytesLength,
    unsigned char *secretKey
);

#endif /* DDGSyncCrypto_h */
