#ifndef RIPTIDE_SECURITY_SHIM_H
#define RIPTIDE_SECURITY_SHIM_H

#include <CoreFoundation/CoreFoundation.h>
#include <Security/SecCertificate.h>
#include <Security/SecIdentity.h>
#include <Security/SecKey.h>

SecIdentityRef _Nullable RiptideSecIdentityCreate(
    CFAllocatorRef _Nullable allocator,
    SecCertificateRef _Nonnull certificate,
    SecKeyRef _Nonnull privateKey
);

#endif
