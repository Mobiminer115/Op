#import "GameBoostShared.h"

%group GameBoostIdentityHooks

%hookf(int, sysctlbyname, const char *name, void *oldValue, size_t *oldLength, void *newValue, size_t newLength) {
    if (GBIsIpadModeActive() && newValue == nullptr && name != nullptr &&
        std::strcmp(name, "hw.machine") == 0) {
        return GBWriteSpoofedCString(GBIpadMachineIdentifier(),
                                     oldValue,
                                     oldLength);
    }
    return %orig;
}


%hookf(int, uname, struct utsname *systemInfo) {
    int result = %orig;
    if (result == 0 && GBIsIpadModeActive() && systemInfo != nullptr) {
        const char *identifier = GBIpadMachineIdentifier();
        std::memset(systemInfo->machine, 0, sizeof(systemInfo->machine));
        std::strncpy(systemInfo->machine,
                     identifier,
                     sizeof(systemInfo->machine) - 1);
    }
    return result;
}

%end

%ctor {
    @autoreleasepool {
        if (GBShouldLoadInCurrentProcess()) {
            GBInitializeRuntimeState();
            %init(GameBoostIdentityHooks);
        }
    }
}
