#ifndef AZEROTHCORE_ADDON_MESSAGE_ROUTER_H
#define AZEROTHCORE_ADDON_MESSAGE_ROUTER_H

#include <string>

class WorldSession;

namespace AddonMessageRouter
{
    using Handler = bool(*)(WorldSession* session, std::string const& msg);

    void RegisterHandler(Handler handler);
    bool Handle(WorldSession* session, std::string const& msg);
}

#endif
