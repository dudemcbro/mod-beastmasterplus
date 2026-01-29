#include "Chat.h"
#include "DatabaseEnv.h"
#include "Log.h"
#include "BmpAddonMessageRouter.h"
#include "Common.h"
#include "Group.h"
#include "Opcodes.h"
#include "Pet.h"
#include "Player.h"
#include "WorldPacket.h"
#include "WorldSession.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace
{
    constexpr char kWirePrefix[] = "BMP\t";

    static std::vector<std::string> Split(std::string const& s, char delim)
    {
        std::vector<std::string> out;
        std::string cur;
        for (char c : s)
        {
            if (c == delim)
            {
                out.push_back(cur);
                cur.clear();
            }
            else
                cur.push_back(c);
        }
        out.push_back(cur);
        return out;
    }

    static bool IsNumber(std::string const& s)
    {
        if (s.empty())
            return false;

        return std::all_of(s.begin(), s.end(), [](unsigned char c) { return std::isdigit(c); });
    }

    static void SendBmp(WorldSession* session, std::string const& payload)
    {
        if (!session)
            return;

        Player* player = session->GetPlayer();
        if (!player)
            return;

        // Addon wire format: "PREFIX\tpayload"
        std::string msg = std::string(kWirePrefix) + payload;

        WorldPacket data;
        ChatHandler::BuildChatPacket(data, CHAT_MSG_WHISPER, LANG_ADDON, player, player, msg);
        session->SendPacket(&data);
    }

    static void SendError(WorldSession* session, std::string const& msg)
    {
        SendBmp(session, "ERROR|" + msg);
    }

    static void SendOk(WorldSession* session, std::string const& msg)
    {
        SendBmp(session, "OK|" + msg);
    }

    static std::string SanitizeName(std::string name)
    {
        for (char& c : name)
        {
            unsigned char uc = static_cast<unsigned char>(c);
            if (c == '|' || c == ';' || uc < 0x20 || uc >= 0x7F)
                c = '_';
        }

        if (name.size() > 20)
            name.resize(20);

        return name;
    }

    static void SendChunkedList(WorldSession* session, std::vector<std::string> const& records)
    {
        static constexpr size_t kMaxPayload = 200;
        std::string chunk;
        chunk.reserve(kMaxPayload + 32);

        for (auto const& rec : records)
        {
            size_t extra = rec.size() + (chunk.empty() ? 0 : 1);
            if (!chunk.empty() && (chunk.size() + extra) > kMaxPayload)
            {
                SendBmp(session, "PETS_CHUNK|" + chunk);
                chunk.clear();
            }

            if (!chunk.empty())
                chunk.push_back(';');
            chunk += rec;
        }

        if (!chunk.empty())
            SendBmp(session, "PETS_CHUNK|" + chunk);

        SendBmp(session, "PETS_END");
    }

    static bool EnsurePetInfo(Player* player, uint32 petGuid)
    {
        if (!player)
            return false;

        PetStable* stable = &player->GetOrInitPetStable();

        if (stable->CurrentPet && stable->CurrentPet->PetNumber == petGuid)
            return true;

        for (PetStable::PetInfo const& pet : stable->UnslottedPets)
        {
            if (pet.PetNumber == petGuid)
                return true;
        }

        for (Optional<PetStable::PetInfo> const& pet : stable->StabledPets)
        {
            if (pet && pet->PetNumber == petGuid)
                return true;
        }

        return false;
    }

    static bool InsertPetInfoFromDb(Player* player, uint32 petGuid, uint32 petNumber)
    {
        if (!player)
            return false;

        PetStable* stable = &player->GetOrInitPetStable();

        ObjectGuid::LowType ownerLow = player->GetGUID().GetCounter();
        QueryResult result = CharacterDatabase.Query(
            "SELECT id, entry, modelid, level, exp, Reactstate, slot, name, renamed, curhealth, curmana, curhappiness, abdata, savetime, CreatedBySpell, PetType "
            "FROM character_pet WHERE owner = {} AND id = {} LIMIT 1",
            ownerLow, petNumber);

        if (!result)
            return false;

        Field* fields = result->Fetch();
        if (!fields)
            return false;

        PetStable::PetInfo petInfo;
        petInfo.PetNumber = fields[0].Get<uint32>();
        petInfo.CreatureId = fields[1].Get<uint32>();
        petInfo.DisplayId = fields[2].Get<uint32>();
        petInfo.Level = fields[3].Get<uint16>();
        petInfo.Experience = fields[4].Get<uint32>();
        petInfo.ReactState = ReactStates(fields[5].Get<uint8>());
        petInfo.Name = fields[7].Get<std::string>();
        petInfo.WasRenamed = fields[8].Get<bool>();
        petInfo.Health = fields[9].Get<uint32>();
        petInfo.Mana = fields[10].Get<uint32>();
        petInfo.Happiness = fields[11].Get<uint32>();
        petInfo.ActionBar = fields[12].Get<std::string>();
        petInfo.LastSaveTime = fields[13].Get<uint32>();
        petInfo.CreatedBySpellId = fields[14].Get<uint32>();
        petInfo.Type = PetType(fields[15].Get<uint8>());

        if (petInfo.PetNumber != petGuid)
            return false;

        stable->UnslottedPets.push_back(std::move(petInfo));
        return true;
    }

    static void NormalizeSlotZero(Player* player, uint32 activePetNumber)
    {
        if (!player)
            return;

        ObjectGuid::LowType ownerLow = player->GetGUID().GetCounter();
        QueryResult result = CharacterDatabase.Query(
            "SELECT id FROM character_pet WHERE owner = {} AND slot = {} AND id <> {}",
            ownerLow, uint32(PET_SAVE_AS_CURRENT), activePetNumber);

        if (!result)
            return;

        do
        {
            uint32 petNumber = result->Fetch()[0].Get<uint32>();
            CharacterDatabasePreparedStatement* stmt = CharacterDatabase.GetPreparedStatement(CHAR_UPD_CHAR_PET_SLOT_BY_ID);
            stmt->SetData(0, uint8(PET_SAVE_NOT_IN_SLOT));
            stmt->SetData(1, ownerLow);
            stmt->SetData(2, petNumber);
            CharacterDatabase.Execute(stmt);
        } while (result->NextRow());
    }

    static void DetachActivePetNoSave(Player* player)
    {
        if (!player)
            return;

        Pet* pet = player->GetPet();
        if (!pet)
            return;

        if (!pet->IsHunterPet())
            return;

        CharmInfo* charm = pet->GetCharmInfo();
        if (!charm)
            return;

        NormalizeSlotZero(player, charm->GetPetNumber());
        player->RemovePet(pet, PET_SAVE_NOT_IN_SLOT, false);
    }

    static void HandleBmp(WorldSession* session, std::string const& payload)
    {
        Player* player = session ? session->GetPlayer() : nullptr;
        if (!player)
            return;

        if (player->getClass() != CLASS_HUNTER)
        {
            SendError(session, "NOT_HUNTER");
            return;
        }

        if (payload.size() > 512)
        {
            SendError(session, "PAYLOAD_TOO_LARGE");
            return;
        }

        if (payload.rfind("HELLO|", 0) == 0)
        {
            auto parts = Split(payload, '|');
            if (parts.size() == 2 && parts[1] == "1")
                SendOk(session, "HELLO|1");
            else
                SendError(session, "BAD_VERSION");
            return;
        }

        if (payload == "LIST")
        {
            struct PetRow
            {
                uint32 petNumber = 0;
                uint32 entry = 0;
                uint16 level = 0;
                std::string name;
                uint32 slot = 0;
            };

            struct FamilyInfo
            {
                uint32 familyId = 0;
            };

            std::vector<PetRow> rows;
            std::unordered_set<uint32> entries;

            Pet* activePet = player->GetPet();
            ObjectGuid::LowType ownerLow = player->GetGUID().GetCounter();
            LOG_DEBUG("module.bmp", "BMP LIST: player={} guidLow={}", player->GetName(), ownerLow);
            LOG_DEBUG("module.bmp", "BMP LIST SQL: SELECT id, entry, level, name, slot FROM character_pet WHERE owner = {} ORDER BY id", ownerLow);

            auto LoadRows = [&](uint32& outRowCount)
            {
                QueryResult result = CharacterDatabase.Query(
                    "SELECT id, entry, level, name, slot FROM character_pet WHERE owner = {} ORDER BY id",
                    ownerLow);
                outRowCount = 0;
                if (result)
                {
                    do
                    {
                        Field* f = result->Fetch();
                        PetRow row;
                        row.petNumber = f[0].Get<uint32>();
                        row.entry = f[1].Get<uint32>();
                        row.level = f[2].Get<uint16>();
                        row.name = SanitizeName(f[3].Get<std::string>());
                        row.slot = f[4].Get<uint32>();
                        rows.push_back(row);
                        if (row.entry)
                            entries.insert(row.entry);
                        ++outRowCount;
                    } while (result->NextRow());
                }
            };

            uint32 rowCount = 0;
            LoadRows(rowCount);
            if (rowCount == 0 && activePet && activePet->IsHunterPet())
            {
                LOG_DEBUG("module.bmp", "BMP LIST: no DB rows; attempting SavePetToDB for active pet");
                activePet->SavePetToDB(PET_SAVE_AS_CURRENT);
                rows.clear();
                entries.clear();
                LoadRows(rowCount);
            }
            uint32 slot0Count = 0;
            uint32 slot100Count = 0;
            for (PetRow const& row : rows)
            {
                if (row.slot == PET_SAVE_AS_CURRENT)
                    ++slot0Count;
                else if (row.slot == PET_SAVE_NOT_IN_SLOT)
                    ++slot100Count;
            }
            LOG_DEBUG("module.bmp", "BMP LIST: rows={} slot0={} slot100={}", rowCount, slot0Count, slot100Count);

            ObjectGuid::LowType activePetGuid = 0;
            if (activePet)
                activePetGuid = activePet->GetCharmInfo() ? activePet->GetCharmInfo()->GetPetNumber() : 0;

            for (PetRow& row : rows)
            {
                if (row.slot == PET_SAVE_AS_CURRENT && (!activePetGuid || row.petNumber != activePetGuid))
                {
                    CharacterDatabasePreparedStatement* stmt = CharacterDatabase.GetPreparedStatement(CHAR_UPD_CHAR_PET_SLOT_BY_ID);
                    stmt->SetData(0, uint8(PET_SAVE_NOT_IN_SLOT));
                    stmt->SetData(1, ownerLow);
                    stmt->SetData(2, row.petNumber);
                    CharacterDatabase.Execute(stmt);
                    row.slot = PET_SAVE_NOT_IN_SLOT;
                }
            }

            std::unordered_map<uint32, FamilyInfo> familyByEntry;
            if (!entries.empty())
            {
                std::string inList;
                inList.reserve(entries.size() * 8);
                for (uint32 entry : entries)
                {
                    if (!inList.empty())
                        inList.push_back(',');
                    inList += std::to_string(entry);
                }

                QueryResult worldRes = WorldDatabase.Query(
                    "SELECT entry, family FROM creature_template WHERE entry IN ({})",
                    inList);

                if (worldRes)
                {
                    do
                    {
                        Field* wf = worldRes->Fetch();
                        uint32 entry = wf[0].Get<uint32>();
                        uint32 familyId = wf[1].Get<uint32>();
                        FamilyInfo info;
                        info.familyId = familyId;
                        familyByEntry.emplace(entry, std::move(info));
                    } while (worldRes->NextRow());
                }
            }

            std::vector<std::string> records;
            records.reserve(rows.size());
            for (PetRow const& row : rows)
            {
                uint32 flags = ((activePetGuid && row.petNumber == activePetGuid) || row.slot == PET_SAVE_AS_CURRENT) ? 1u : 0u;

                FamilyInfo info;
                auto it = familyByEntry.find(row.entry);
                if (it != familyByEntry.end())
                    info = it->second;

                std::string rec =
                    std::to_string(row.petNumber) + "|" +
                    std::to_string(row.entry) + "|" +
                    std::to_string(row.level) + "|" +
                    row.name + "|" +
                    std::to_string(flags) + "|" +
                    std::to_string(info.familyId);

                records.push_back(std::move(rec));
            }

            SendChunkedList(session, records);
            return;
        }

        if (payload == "NORMALIZE")
        {
            if (session->GetSecurity() < SEC_GAMEMASTER)
            {
                SendError(session, "NO_PERM");
                return;
            }

            uint32 toNormalize = 0;
            QueryResult countRes = CharacterDatabase.Query(
                "SELECT COUNT(*) FROM character_pet cp "
                "JOIN ("
                "  SELECT owner, MAX(id) AS keep_id "
                "  FROM character_pet "
                "  WHERE slot = 0 AND PetType = 1 "
                "  GROUP BY owner "
                "  HAVING COUNT(*) > 1"
                ") k ON cp.owner = k.owner "
                "WHERE cp.slot = 0 AND cp.PetType = 1 AND cp.id <> k.keep_id");

            if (countRes)
                toNormalize = countRes->Fetch()[0].Get<uint32>();

            if (toNormalize > 0)
            {
                CharacterDatabase.Execute(
                    "UPDATE character_pet cp "
                    "JOIN ("
                    "  SELECT owner, MAX(id) AS keep_id "
                    "  FROM character_pet "
                    "  WHERE slot = 0 AND PetType = 1 "
                    "  GROUP BY owner "
                    "  HAVING COUNT(*) > 1"
                    ") k ON cp.owner = k.owner "
                    "SET cp.slot = 100 "
                    "WHERE cp.slot = 0 AND cp.PetType = 1 AND cp.id <> k.keep_id");
            }

            SendOk(session, "NORMALIZED|" + std::to_string(toNormalize));
            return;
        }

        if (payload.rfind("SUMMON|", 0) == 0)
        {
            std::string arg = payload.substr(7);
            if (!IsNumber(arg))
            {
                SendError(session, "BAD_SUMMON");
                return;
            }

            uint32 petNumber = static_cast<uint32>(std::strtoul(arg.c_str(), nullptr, 10));
            ObjectGuid::LowType ownerLow = player->GetGUID().GetCounter();
            QueryResult result = CharacterDatabase.Query(
                "SELECT id, name FROM character_pet WHERE owner = {} AND id = {} LIMIT 1",
                ownerLow, petNumber);

            if (!result)
            {
                SendError(session, "NO_PET");
                return;
            }

            Field* fields = result->Fetch();
            uint32 petGuid = fields[0].Get<uint32>();
            std::string petName = fields[1].Get<std::string>();

            if (!player->IsAlive())
            {
                SendError(session, "PLAYER_DEAD");
                return;
            }

            if (Pet* oldPet = player->GetPet())
            {
                if (!oldPet->IsHunterPet())
                {
                    SendError(session, "ACTIVE_NOT_HUNTER_PET");
                    return;
                }
                DetachActivePetNoSave(player);
            }

            if (!EnsurePetInfo(player, petGuid))
            {
                if (!InsertPetInfoFromDb(player, petGuid, petNumber))
                {
                    SendError(session, "PETINFO_MISSING");
                    return;
                }
            }

            Pet* newPet = new Pet(player, HUNTER_PET);
            if (!newPet->LoadPetFromDB(player, 0, petGuid, false))
            {
                delete newPet;

                PetStable* stable = player->GetPetStable();
                if (stable)
                {
                    auto itr = std::find_if(stable->UnslottedPets.begin(), stable->UnslottedPets.end(),
                        [petGuid](PetStable::PetInfo const& pet) { return pet.PetNumber == petGuid; });
                    if (itr != stable->UnslottedPets.end())
                        stable->UnslottedPets.erase(itr);
                }

                SendError(session, "SUMMON_FAILED");
                return;
            }

            SendBmp(session, "SUMMONED|" + SanitizeName(petName));
            SendOk(session, "SUMMONED|" + SanitizeName(petName));
            return;
        }

        if (payload == "DISMISS" || payload.rfind("DISMISS|", 0) == 0)
        {
            uint32 requestedPetNumber = 0;
            if (payload.size() > 7)
            {
                std::string arg = payload.substr(8);
                if (!IsNumber(arg))
                {
                    SendError(session, "BAD_DISMISS");
                    return;
                }
                requestedPetNumber = static_cast<uint32>(std::strtoul(arg.c_str(), nullptr, 10));
            }

            Pet* activePet = player->GetPet();
            if (!activePet || !activePet->IsHunterPet())
            {
                SendError(session, "NO_ACTIVE_PET");
                return;
            }

            CharmInfo* charm = activePet->GetCharmInfo();
            if (!charm)
            {
                SendError(session, "NO_ACTIVE_PET");
                return;
            }

            if (requestedPetNumber && charm->GetPetNumber() != requestedPetNumber)
            {
                SendError(session, "NOT_ACTIVE");
                return;
            }

            std::string petName = activePet->GetName();
            LOG_DEBUG("module.bmp", "BMP DISMISS REQ: player={} guidLow={} activePet={} requestedPet={}",
                player->GetName(), player->GetGUID().GetCounter(), charm->GetPetNumber(), requestedPetNumber);
            player->RemovePet(activePet, PET_SAVE_NOT_IN_SLOT, false);
            if (QueryResult q = CharacterDatabase.Query(
                "SELECT COUNT(*), SUM(slot = 0), SUM(slot = 100) FROM character_pet WHERE owner = {}",
                player->GetGUID().GetCounter()))
            {
                Field* f = q->Fetch();
                LOG_DEBUG("module.bmp", "BMP DISMISS DB: owner={} total={} slot0={} slot100={}",
                    player->GetGUID().GetCounter(), f[0].Get<uint64>(), f[1].Get<uint64>(), f[2].Get<uint64>());
            }
            SendBmp(session, "DISMISSED|" + SanitizeName(petName));
            SendOk(session, "DISMISSED|" + SanitizeName(petName));
            return;
        }

        SendError(session, "UNKNOWN_CMD");
    }
}

namespace BmpRouter
{
    // This function is called by your core from ChatHandler.cpp when CHAT_MSG_ADDON is received.
    bool TryHandleAddon(WorldSession* session, std::string const& rawMsg)
    {
        if (!session)
            return false;

        bool hadPrefix = rawMsg.rfind(kWirePrefix, 0) == 0;
        std::string payload = rawMsg;
        if (hadPrefix)
            payload.erase(0, std::string(kWirePrefix).size());

        if (payload.empty())
            return hadPrefix;

        if (!hadPrefix)
        {
            if (!(payload == "LIST" || payload == "NORMALIZE" || payload.rfind("SUMMON|", 0) == 0 || payload == "DISMISS" || payload.rfind("DISMISS|", 0) == 0 || payload.rfind("HELLO|", 0) == 0))
                return false;
        }

        HandleBmp(session, payload);
        return true;
    }

    void Register()
    {
        AddonMessageRouter::RegisterHandler(&TryHandleAddon);
    }
}
