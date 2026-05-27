#include "RiptideSecurityShim.h"
#include <dlfcn.h>

typedef SecIdentityRef (*RiptideSecIdentityCreateFunction)(
    CFAllocatorRef _Nullable,
    SecCertificateRef,
    SecKeyRef
);

SecIdentityRef _Nullable RiptideSecIdentityCreate(
    CFAllocatorRef _Nullable allocator,
    SecCertificateRef certificate,
    SecKeyRef privateKey
) {
    void *symbol = dlsym(RTLD_DEFAULT, "SecIdentityCreate");
    if (symbol == NULL) {
        return NULL;
    }

    RiptideSecIdentityCreateFunction createIdentity = (RiptideSecIdentityCreateFunction) symbol;
    return createIdentity(allocator, certificate, privateKey);
}
