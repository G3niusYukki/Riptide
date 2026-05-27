#include "RiptideSecurityShim.h"

SecIdentityRef _Nullable RiptideSecIdentityCreate(
    CFAllocatorRef _Nullable allocator,
    SecCertificateRef certificate,
    SecKeyRef privateKey
) {
    return SecIdentityCreate(allocator, certificate, privateKey);
}
