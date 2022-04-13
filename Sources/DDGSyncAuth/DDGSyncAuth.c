
#include "DDGSyncAuth.h"
#include "argon2.h"

DDGSyncAuthResult test() {
    if (ARGON2_OK != argon2_ctx(NULL, Argon2_d)) {
        return DDGSYNCAUTH_ERROR;
    }

    return DDGSYNCAUTH_OK;
}
