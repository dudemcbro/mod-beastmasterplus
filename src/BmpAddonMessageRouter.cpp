#include "BmpAddonMessageRouter.h"

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
