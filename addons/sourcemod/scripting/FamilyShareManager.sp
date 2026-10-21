#pragma newdecls required

#include <ripext>
#include <multicolors>
#include <SteamWorks>

#undef REQUIRE_PLUGIN
#tryinclude <materialadmin>
#tryinclude <sourcebanspp>
#define REQUIRE_PLUGIN

#define TAG "{green}[Family Share Manager]"

ConVar g_hCvar_Reject;
ConVar g_hCvar_RejectDuration;
ConVar g_hCvar_RejectMessage;
ConVar g_hCvar_Whitelist;
ConVar g_hCvar_IgnoreAdmins;
ConVar g_hCvarAdminFlags;

StringMap g_hWhitelistTrie = null;

char g_sWhitelist[PLATFORM_MAX_PATH];

bool g_bParsed = false;
bool g_bIgnoreAdmins = false;
bool g_bSourceBans = false;
bool g_bMaterialAdmin = false;

int g_iAppID = -1;
int g_iReject;
int g_iRejectDuration;
int g_iAdminFlags;

public Plugin myinfo =
{
    name = "Family Share Manager",
    author = "Sidezz (+bonbon, 11530, maxime1907, .Rushaway)",
    description = "Whitelist or ban family shared accounts",
    version = "1.8.3",
    url = ""
}

public void OnPluginStart()
{
    char sBuffer[PLATFORM_MAX_PATH];
    g_hCvar_Reject = CreateConVar("sm_familyshare_reject", "1", "2 = ban, 1 = kick, 0 = ignore", FCVAR_NOTIFY);
    g_hCvar_RejectDuration = CreateConVar("sm_familyshare_reject_duration", "10", "How much time is the player banned", FCVAR_NOTIFY);
    g_hCvar_RejectMessage = CreateConVar("sm_familyshare_reject_message", "Family sharing is disabled on this server.", "Message to display in sourcebans/on ban/on kick", FCVAR_NOTIFY);
    g_hCvar_IgnoreAdmins = CreateConVar("sm_familyshare_ignoreadmins", "1", "Ignore admins using family shared accounts", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvarAdminFlags = CreateConVar("sm_familyshare_ignoreadmins_flags", "z", "Set flags for admins to be automaticly whitelisted. Set several flags if necessary. Ex: \"abcz\"");
    g_hCvarAdminFlags.GetString(sBuffer, sizeof(sBuffer));
    g_iAdminFlags = ReadFlagString(sBuffer);
    g_hCvar_Whitelist = CreateConVar("sm_familyshare_whitelist", "familyshare_whitelist.cfg", "File to use for whitelist configuration");

    g_iAppID = GetAppID();
    if (g_iAppID <= -1)
        SetFailState("Could not determine the game app id (cstrike/steam.inf)");

    g_bParsed = false;
    g_hWhitelistTrie = new StringMap();

    char file[PLATFORM_MAX_PATH], filePath[PLATFORM_MAX_PATH];
    g_hCvar_Whitelist.GetString(file, sizeof(file));
    BuildPath(Path_SM, g_sWhitelist, sizeof(g_sWhitelist), "configs/%s", file);
    LogMessage("Built Filepath to: %s", g_sWhitelist);

    BuildPath(Path_SM, filePath, sizeof(filePath), "configs");
    CreateDirectory(filePath, 511);

    AutoExecConfig(true);

    parseList();

    g_hCvar_Reject.AddChangeHook(OnConVarChanged);
    g_hCvar_RejectDuration.AddChangeHook(OnConVarChanged);
    g_hCvar_IgnoreAdmins.AddChangeHook(OnConVarChanged);

    RegAdminCmd("sm_reloadlist", command_reloadWhiteList, ADMFLAG_ROOT, "Reload the whitelist");
    RegAdminCmd("sm_addtolist", command_addToList, ADMFLAG_ROOT, "Add a player to the whitelist");
    RegAdminCmd("sm_removefromlist", command_removeFromList, ADMFLAG_ROOT, "Remove a player from the whitelist");
    RegAdminCmd("sm_displaylist", command_displayList, ADMFLAG_ROOT, "View current whitelist");
}

public void OnLibraryAdded(const char []name)
{
    if( strcmp(name, "sourcebans++") == 0 )
        g_bSourceBans = true;
    else if( strcmp(name, "materialadmin") == 0 )
        g_bMaterialAdmin = true;
}

public void OnLibraryRemoved(const char []name)
{
    if( strcmp(name, "sourcebans++") == 0 )
        g_bSourceBans = false;
    else if( strcmp(name, "materialadmin") == 0 )
        g_bMaterialAdmin = false;
}

public void OnConfigsExecuted()
{
    char sBuffer[PLATFORM_MAX_PATH];
    g_iReject = g_hCvar_Reject.IntValue;
    g_iRejectDuration = g_hCvar_RejectDuration.IntValue;
    g_bIgnoreAdmins = g_hCvar_IgnoreAdmins.BoolValue;
    g_hCvarAdminFlags.GetString(sBuffer, sizeof(sBuffer));
    g_iAdminFlags = ReadFlagString(sBuffer);
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if(convar==g_hCvar_Reject)
        g_iReject = convar.IntValue;
    else if(convar==g_hCvar_RejectDuration)
        g_iRejectDuration = convar.IntValue;
    else if(convar==g_hCvar_IgnoreAdmins)
        g_bIgnoreAdmins = convar.BoolValue;
    else if(convar==g_hCvarAdminFlags)
        g_iAdminFlags = ReadFlagString(newValue);
}

public Action command_removeFromList(int client, int args)
{
    File hFile = OpenFile(g_sWhitelist, "a+");

    if(hFile == null)
    {
        LogError("[Family Share Manager] Critical Error: hFile is Invalid. --> command_removeFromList");
        CPrintToChat(client, "%s {red}Plugin has encountered a critial error with the list file.", TAG);
        delete hFile;
        return Plugin_Handled;
    }

    if(args == 0)
    {
        CPrintToChat(client, "%s {default}Invalid Syntax: sm_removefromlist <steam id>", TAG);
        return Plugin_Handled;
    }

    char steamid[32], playerSteam[32];
    GetCmdArgString(playerSteam, sizeof(playerSteam));

    StripQuotes(playerSteam);
    TrimString(playerSteam);

    bool found = false;
    ArrayList fileArray = new ArrayList(32);

    while(!hFile.EndOfFile() && hFile.ReadLine(steamid, sizeof(steamid)))
    {
        if(strlen(steamid) < 1 || IsCharSpace(steamid[0])) continue;

        ReplaceString(steamid, sizeof(steamid), "\n", "", false);

        CPrintToChat(client, "{lightgreen}%s {default}- {olive}%s", steamid, playerSteam);
        //Not found, add to next file.
        if(!StrEqual(steamid, playerSteam, false))
        {
            fileArray.PushString(steamid);
        }

        //Found, remove from file.
        else
        {
            found = true;
        }
    }

    delete hFile;

    //Delete and rewrite list if found..
    if(found)
    {
        DeleteFile(g_sWhitelist); //I hate this, scares the shit out of me.
        File newFile = OpenFile(g_sWhitelist, "a+");

        if(newFile == null)
        {
            LogError("[Family Share Manager] Critical Error: newFile is Invalid. --> command_removeFromList");
            CPrintToChat(client, "%s {red}Plugin has encountered a critial error with the list file.", TAG);
            return Plugin_Handled;
        }

        CPrintToChat(client, "%s {default}Found Steam ID: {lightgreen}%s{default}, removing from list...", TAG, playerSteam);
        
        LogMessage("Begin rewrite of list..");

        for(int i = 0; i < fileArray.Length; i++)
        {
            char writeLine[32];
            fileArray.GetString(i, writeLine, sizeof(writeLine));
            newFile.WriteLine(writeLine);
            LogMessage("Wrote %s to list.", writeLine);
        }

        delete newFile;
        delete fileArray;
        parseList();
        return Plugin_Handled;
    }
    else CPrintToChat(client, "%s {default}Steam ID: {lightgreen}%s {default}not found, no action taken.", TAG, playerSteam);
    return Plugin_Handled;
}

public Action command_addToList(int client, int args)
{
    File hFile = OpenFile(g_sWhitelist, "a+");
    
    //Argument Count:
    switch(args)
    {
        //Create Player List:
        case 0:
        {
            Menu playersMenu = new Menu(playerMenuHandle);
            for(int i = 1; i <= MaxClients; i++)
            {
                if(IsClientAuthorized(i) && i != client)
                {
                    playersMenu.SetTitle("Viewing all players...");

                    char formatItem[2][32];
                    Format(formatItem[0], sizeof(formatItem[]), "%i", GetClientUserId(i));
                    Format(formatItem[1], sizeof(formatItem[]), "%N", i);

                    //Adds menu item per player --> Client User ID, Display as Username.
                    playersMenu.AddItem(formatItem[0], formatItem[1]);
                }
            }

            playersMenu.ExitButton = true;
            playersMenu.Pagination = 7;
            playersMenu.Display(client, MENU_TIME_FOREVER);

            CPrintToChat(client, "%s {default}Displaying players menu...", TAG);

            delete hFile;
            return Plugin_Handled;
        }

        //Directly write Steam ID:
        default:
        {
            char steamid[32];
            GetCmdArgString(steamid, sizeof(steamid));

            StripQuotes(steamid);
            TrimString(steamid);

            if(StrContains(steamid, "STEAM_", false) == -1)
            {
                CPrintToChat(client, "%s {default}Invalid Input - Not a Steam 2 ID. (STEAM_0:X:XXXX)", TAG);
                delete hFile;
                return Plugin_Handled;
            }

            if(hFile == null)
            {
                LogError("[Family Share Manager] Critical Error: hFile is Invalid. --> command_addToList");
                CPrintToChat(client, "%s {red}Plugin has encountered a critial error with the list file.", TAG);
                delete hFile;
                return Plugin_Handled;
            }

            hFile.WriteLine(steamid);
            CPrintToChat(client, "%s {default}Successfully added {lightgreen}%s {default}to the list.", TAG, steamid);
            delete hFile;
            parseList();
        }
    }

    return Plugin_Handled;
}

public int playerMenuHandle(Menu playerMenu, MenuAction action, int client, int menuItem)
{
    if (action == MenuAction_Select) 
    {   
        //Should be our Client's User ID.
        char menuItems[32]; 
        playerMenu.GetItem(menuItem, menuItems, sizeof(menuItems));

        int target = GetClientOfUserId(StringToInt(menuItems));
        
        //Invalid UserID/Client Index:
        if(target == 0)
        {
            LogError("[Family Share Manager] Critical Error: Invalid Client of User Id --> playerMenuHandle");
            delete playerMenu;
            return 0;
        }

        char steamid[32];
        GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid), false);

        StripQuotes(steamid);
        TrimString(steamid);

        if(StrContains(steamid, "STEAM_", false) == -1)
        {
            CPrintToChat(client, "%s {default}Invalid Input - Not a Steam 2 ID. (STEAM_0:X:XXXX)", TAG);
            return 0;
        }

        File hFile = OpenFile(g_sWhitelist, "a+");
        if(hFile == null)
        {
            LogError("[Family Share Manager] Critical Error: hFile is Invalid. --> playerMenuHandle");
            CPrintToChat(client, "%s {red}Plugin has encountered a critial error with the list file.", TAG);
            delete hFile;
            return 0;
        }

        hFile.WriteLine(steamid);
        CPrintToChat(client, "%s {default}Successfully added {lightgreen}%s {default}({olive}%N{default}) to the list.", TAG, steamid, target);
        LogMessage("[Family Share Manager] Successfully added %s (%N) to the list.", steamid, target);
        delete hFile;
        parseList();
        return 0;
    }

    else if(action == MenuAction_End)
    {
        delete playerMenu;
    }
    return 0;
}

public Action command_displayList(int client, int args)
{
    char auth[32];
    File hFile = OpenFile(g_sWhitelist, "a+");

    while(!hFile.EndOfFile() && hFile.ReadLine(auth, sizeof(auth)))
    {
        TrimString(auth);
        StripQuotes(auth);

        if(strlen(auth) < 1) continue;
        ReplaceString(auth, sizeof(auth), "\n", "", false);

        if(StrContains(auth, "STEAM_", false) != -1)
        {
            if(!client) return Plugin_Handled;
            PrintToChat(client, "%s", auth); 
        }
    }

    delete hFile;
    return Plugin_Handled;
}

public Action command_reloadWhiteList(int client, int args)
{
    CPrintToChat(client, "%s Rebuilding whitelist...", TAG);
    parseList(true, client);
    return Plugin_Handled;
}

stock void parseList(bool rebuild = false, int client = 0)
{
    char auth[32];
    File hFile = OpenFile(g_sWhitelist, "a+");

    while(!hFile.EndOfFile() && hFile.ReadLine(auth, sizeof(auth)))
    {
        TrimString(auth);
        StripQuotes(auth);

        if(strlen(auth) < 1) continue;

        if(StrContains(auth, "STEAM_", false) != -1)
        {
            g_hWhitelistTrie.SetString(auth, auth);
            LogMessage("Added %s to whitelist", auth);
        }
    }

    if (rebuild && client)
        CPrintToChat(client, "%s {default}Rebuild complete!", TAG);

    g_bParsed = true;
    delete hFile;
}

stock bool CheckWhiteList(int client)
{
    bool whiteListed = false;
    if (g_bParsed)
    {
        char auth[2][64];
        GetClientAuthId(client, AuthId_Steam2, auth[0], sizeof(auth[]), false);
        whiteListed = g_hWhitelistTrie.GetString(auth[0], auth[1], sizeof(auth[]));
        if(whiteListed)
        {
            LogMessage("Whitelist found player: %N", client);
            return true;
        }
    }

    if (g_bIgnoreAdmins && IsAdmin(client))
    {
        return true;
    }

    return false;
}

// Credit to Dr. McKay
// https://forums.alliedmods.net/showthread.php?t=233257
stock int GetAppID() {
    File file = OpenFile("steam.inf", "r");
    if(file == null) {
        return -1;
    }

    char line[128], parts[2][64];
    while(file.ReadLine(line, sizeof(line))) {
        ExplodeString(line, "=", parts, sizeof(parts), sizeof(parts[]));
        if(StrEqual(parts[0], "appID")) {
            delete file;
            return StringToInt(parts[1]);
        }
    }

    delete file;
    return -1;
}

stock int GetClientOfAuthId(int authid)
{
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientConnected(i))
        {
            char steamid[32]; GetClientAuthId(i, AuthId_Steam3, steamid, sizeof(steamid));
            char split[3][32]; 
            ExplodeString(steamid, ":", split, sizeof(split), sizeof(split[]));
            ReplaceString(split[2], sizeof(split[]), "]", "");
            //Split 1: [U:
            //Split 2: 1:
            //Split 3: 12345]

            int auth = StringToInt(split[2]);
            if(auth == authid) return i;
        }
    }

    return -1;
}

public void SteamWorks_OnValidateClient(int ownerauthid, int authid)
{
    if (g_iReject < 1)
        return;

    int client = GetClientOfAuthId(authid);

    if (client < 1 || client > MaxClients)
        return;

    if (IsFakeClient(client) || IsClientSourceTV(client))
        return;

    if (CheckWhiteList(client))
        return;

    if (ownerauthid != authid)
    {
        ApplyPunishement(client);
    }
}

stock void ApplyPunishement(int client)
{
    char rejectMessage[255];
    g_hCvar_RejectMessage.GetString(rejectMessage, sizeof(rejectMessage));

    switch (g_iReject)
    {
        case (2):
        {
            LogAction(-1, -1, "Banning %L for %d minutes (Family share)", client, g_iRejectDuration);

            if (g_bSourceBans && GetFeatureStatus(FeatureType_Native, "SBPP_BanPlayer") == FeatureStatus_Available)
            {
        #if defined _sourcebanspp_included
                SBPP_BanPlayer(0, client, g_iRejectDuration, rejectMessage);
        #endif
            }
            else if (g_bMaterialAdmin && GetFeatureStatus(FeatureType_Native, "MABanPlayer") == FeatureStatus_Available)
            {
        #if defined _materialadmin_included
                MABanPlayer(0, client, MA_BAN_STEAM, g_iRejectDuration, rejectMessage);
        #endif
            }
            else
                BanClient(client, g_iRejectDuration, BANFLAG_AUTO, rejectMessage);
        }
        case (1):
        {
            LogAction(-1, -1, "Kicking %L (Family share)", client);
            KickClient(client, rejectMessage);
        }
    }
}

stock bool IsAdmin(int client)
{
    return view_as<bool>(GetUserFlagBits(client) & g_iAdminFlags);
}
