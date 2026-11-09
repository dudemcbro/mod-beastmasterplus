#include "BmpAddonMessageRouter.h"

// Some cores ship their own AddonMessageRouter (src/server/game/Chat/AddonMessageRouter.cpp),
// which already defines these functions. Only define them here for cores patched by
// older versions of this module's core patch, which add just a forward declaration of Handle().
#if !__has_include("AddonMessageRouter.h")

#include <vector>

namespace AddonMessageRouter
{
    static std::vector<Handler> s_handlers;

    void RegisterHandler(Handler handler)
    {
        if (handler)
            s_handlers.push_back(handler);
    }

    bool Handle(WorldSession* session, std::string const& msg)
    {
        for (Handler handler : s_handlers)
        {
            if (handler && handler(session, msg))
                return true;
        }

        return false;
    }
}

#endif
