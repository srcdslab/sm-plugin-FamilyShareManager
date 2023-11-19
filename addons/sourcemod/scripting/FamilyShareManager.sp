#pragma newdecls required

#include <utilshelper>
#include <ripext>
#include <multicolors>
#tryinclude <SteamWorks>

#define TAG "{green}[Family Share Manager]"

Handle g_hCvar_Reject = INVALID_HANDLE;
Handle g_hCvar_RejectDuration = INVALID_HANDLE;
Handle g_hCvar_RejectMessage = INVALID_HANDLE;
Handle g_hCvar_Whitelist = INVALID_HANDLE;
Handle g_hCvar_IgnoreAdmins = INVALID_HANDLE;
Handle g_hWhitelistTrie = INVALID_HANDLE;
Handle g_hCvar_Method = INVALID_HANDLE;

char g_sWhitelist[PLATFORM_MAX_PATH];

bool g_bParsed = false;

int g_iAppID = -1;

bool g_bLateLoad = false;

public Plugin myinfo =
{
    name = "Family Share Manager",
    author = "Sidezz (+bonbon, 11530, maxime1907, .Rushaway)",
    description = "Whitelist or ban family shared accounts",
    version = "1.7.3",
    url = ""
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
   g_bLateLoad = late;
   return APLRes_Success;
}

public void OnPluginStart()
{
    // Get one here
    // https://steamcommunity.com/dev
    g_hCvar_Reject = CreateConVar("sm_familyshare_reject", "1", "2 = ban, 1 = kick, 0 = ignore", FCVAR_NOTIFY);
    g_hCvar_RejectDuration = CreateConVar("sm_familyshare_reject_duration", "10", "How much time is the player banned", FCVAR_NOTIFY);
    g_hCvar_RejectMessage = CreateConVar("sm_familyshare_reject_message", "Family sharing is disabled on this server.", "Message to display in sourcebans/on ban/on kick", FCVAR_NOTIFY);
    g_hCvar_IgnoreAdmins = CreateConVar("sm_familyshare_ignoreadmins", "1", "Ignore admins using family shared accounts", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hCvar_Whitelist = CreateConVar("sm_familyshare_whitelist", "familyshare_whitelist.cfg", "File to use for whitelist configuration");
    g_hCvar_Method = CreateConVar("sm_familyshare_method", "0", "Method to detect family sharing [0 = Steam API, 1 = SteamWorks extension]");

    g_iAppID = GetAppID();
    if (g_iAppID <= -1)
        SetFailState("Could not determine the game app id (cstrike/steam.inf)");

    g_bParsed = false;
    g_hWhitelistTrie = CreateTrie();

    char file[PLATFORM_MAX_PATH], filePath[PLATFORM_MAX_PATH];
    GetConVarString(g_hCvar_Whitelist, file, sizeof(file));
    BuildPath(Path_SM, g_sWhitelist, sizeof(g_sWhitelist), "configs/%s", file);
    LogMessage("Built Filepath to: %s", g_sWhitelist);

    BuildPath(Path_SM, filePath, sizeof(filePath), "configs");
    CreateDirectory(filePath, 511);

    AutoExecConfig(true);

    parseList();

    RegAdminCmd("sm_reloadlist", command_reloadWhiteList, ADMFLAG_ROOT, "Reload the whitelist");
    RegAdminCmd("sm_addtolist", command_addToList, ADMFLAG_ROOT, "Add a player to the whitelist");
    RegAdminCmd("sm_removefromlist", command_removeFromList, ADMFLAG_ROOT, "Remove a player from the whitelist");
    RegAdminCmd("sm_displaylist", command_displayList, ADMFLAG_ROOT, "View current whitelist");

    if (g_bLateLoad)
    {
        for (int i = 1; i < MaxClients; i++)
        {
            if (IsClientInGame(i) && IsClientAuthorized(i))
                OnClientPostAdminCheck(i);
        }
    }
}

public Action command_removeFromList(int client, int args)
{
    Handle hFile = OpenFile(g_sWhitelist, "a+");

    if(hFile == INVALID_HANDLE)
    {
        LogError("[Family Share Manager] Critical Error: hFile is Invalid. --> command_removeFromList");
        CPrintToChat(client, "%s {red}Plugin has encountered a critial error with the list file.", TAG);
        CloseHandle(hFile);
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
    Handle fileArray = CreateArray(32);

    while(!IsEndOfFile(hFile) && ReadFileLine(hFile, steamid, sizeof(steamid)))
    {
        if(strlen(steamid) < 1 || IsCharSpace(steamid[0])) continue;

        ReplaceString(steamid, sizeof(steamid), "\n", "", false);

        CPrintToChat(client, "{lightgreen}%s {default}- {olive}%s", steamid, playerSteam);
        //Not found, add to next file.
        if(!StrEqual(steamid, playerSteam, false))
        {
            PushArrayString(fileArray, steamid);
        }

        //Found, remove from file.
        else
        {
            found = true;
        }
    }

    CloseHandle(hFile);

    //Delete and rewrite list if found..
    if(found)
    {
        DeleteFile(g_sWhitelist); //I hate this, scares the shit out of me.
        Handle newFile = OpenFile(g_sWhitelist, "a+");

        if(newFile == INVALID_HANDLE)
        {
            LogError("[Family Share Manager] Critical Error: newFile is Invalid. --> command_removeFromList");
            CPrintToChat(client, "%s {red}Plugin has encountered a critial error with the list file.", TAG);
            return Plugin_Handled;
        }

        CPrintToChat(client, "%s {default}Found Steam ID: {lightgreen}%s{default}, removing from list...", TAG, playerSteam);
        
        LogMessage("Begin rewrite of list..");

        for(int i = 0; i < GetArraySize(fileArray); i++)
        {
            char writeLine[32];
            GetArrayString(fileArray, i, writeLine, sizeof(writeLine));
            WriteFileLine(newFile, writeLine);
            LogMessage("Wrote %s to list.", writeLine);
        }

        CloseHandle(newFile);
        CloseHandle(fileArray);
        parseList();
        return Plugin_Handled;
    }
    else CPrintToChat(client, "%s {default}Steam ID: {lightgreen}%s {default}not found, no action taken.", TAG, playerSteam);
    return Plugin_Handled;
}

public Action command_addToList(int client, int args)
{
    Handle hFile = OpenFile(g_sWhitelist, "a+");
    
    //Argument Count:
    switch(args)
    {
        //Create Player List:
        case 0:
        {
            Handle playersMenu = CreateMenu(playerMenuHandle);
            for(int i = 1; i <= MaxClients; i++)
            {
                if(IsClientAuthorized(i) && i != client)
                {
                    SetMenuTitle(playersMenu, "Viewing all players...");

                    char formatItem[2][32];
                    Format(formatItem[0], sizeof(formatItem[]), "%i", GetClientUserId(i));
                    Format(formatItem[1], sizeof(formatItem[]), "%N", i);

                    //Adds menu item per player --> Client User ID, Display as Username.
                    AddMenuItem(playersMenu, formatItem[0], formatItem[1]);
                }
            }

            SetMenuExitButton(playersMenu, true);
            SetMenuPagination(playersMenu, 7);
            DisplayMenu(playersMenu, client, MENU_TIME_FOREVER);

            CPrintToChat(client, "%s {default}Displaying players menu...", TAG);

            CloseHandle(hFile);
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
                CloseHandle(hFile);
                return Plugin_Handled;
            }

            if(hFile == INVALID_HANDLE)
            {
                LogError("[Family Share Manager] Critical Error: hFile is Invalid. --> command_addToList");
                CPrintToChat(client, "%s {red}Plugin has encountered a critial error with the list file.", TAG);
                CloseHandle(hFile);
                return Plugin_Handled;
            }

            WriteFileLine(hFile, steamid);
            CPrintToChat(client, "%s {default}Successfully added {lightgreen}%s {default}to the list.", TAG, steamid);
            CloseHandle(hFile);
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
        GetMenuItem(playerMenu, menuItem, menuItems, sizeof(menuItems));

        int target = GetClientOfUserId(StringToInt(menuItems));
        
        //Invalid UserID/Client Index:
        if(target == 0)
        {
            LogError("[Family Share Manager] Critical Error: Invalid Client of User Id --> playerMenuHandle");
            CloseHandle(playerMenu);
            return 0;
        }

        char steamid[32];
        GetClientAuthId(target, AuthId_Steam2, steamid, sizeof(steamid));

        StripQuotes(steamid);
        TrimString(steamid);

        if(StrContains(steamid, "STEAM_", false) == -1)
        {
            CPrintToChat(client, "%s {default}Invalid Input - Not a Steam 2 ID. (STEAM_0:X:XXXX)", TAG);
            return 0;
        }

        Handle hFile = OpenFile(g_sWhitelist, "a+");
        if(hFile == INVALID_HANDLE)
        {
            LogError("[Family Share Manager] Critical Error: hFile is Invalid. --> playerMenuHandle");
            CPrintToChat(client, "%s {red}Plugin has encountered a critial error with the list file.", TAG);
            CloseHandle(hFile);
            return 0;
        }

        WriteFileLine(hFile, steamid);
        CPrintToChat(client, "%s {default}Successfully added {lightgreen}%s {default}({olive}%N{default}) to the list.", TAG, steamid, target);
        LogMessage("[Family Share Manager] Successfully added %s (%N) to the list.", steamid, target);
        CloseHandle(hFile);
        parseList();
        return 0;
    }

    else if(action == MenuAction_End)
    {
        CloseHandle(playerMenu);
    }
    return 0;
}

public Action command_displayList(int client, int args)
{
    char auth[32];
    Handle hFile = OpenFile(g_sWhitelist, "a+");

    while(!IsEndOfFile(hFile) && ReadFileLine(hFile, auth, sizeof(auth)))
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

    CloseHandle(hFile);
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
    Handle hFile = OpenFile(g_sWhitelist, "a+");

    while(!IsEndOfFile(hFile) && ReadFileLine(hFile, auth, sizeof(auth)))
    {
        TrimString(auth);
        StripQuotes(auth);

        if(strlen(auth) < 1) continue;

        if(StrContains(auth, "STEAM_", false) != -1)
        {
            SetTrieString(g_hWhitelistTrie, auth, auth);
            LogMessage("Added %s to whitelist", auth);
        }
    }

    if (rebuild && client)
        CPrintToChat(client, "%s {default}Rebuild complete!", TAG);

    g_bParsed = true;
    CloseHandle(hFile);
}

public void OnClientPostAdminCheck(int client)
{
    bool whiteListed = false;
    if (g_bParsed)
    {
        char auth[2][64];
        GetClientAuthId(client, AuthId_Steam2, auth[0], sizeof(auth[]));
        whiteListed = GetTrieString(g_hWhitelistTrie, auth[0], auth[1], sizeof(auth[]));
        if(whiteListed)
        {
            LogMessage("Whitelist found player: %N", client);
            return;
        }
    }

    if (CheckCommandAccess(client, "sm_admin", ADMFLAG_GENERIC) && GetConVarInt(g_hCvar_IgnoreAdmins) > 0)
    {
        return;
    }

    if (GetConVarInt(g_hCvar_Method) == 0 && !IsFakeClient(client))
        checkFamilySharing(client);
}

stock void checkFamilySharing(int client)
{
	char sSteam64ID[32];
	GetClientAuthId(client, AuthId_SteamID64, sSteam64ID, sizeof(sSteam64ID));

	char sSteamAPIEndpoint[255];
	GetSteamAPIEndpoint(sSteamAPIEndpoint, sizeof(sSteamAPIEndpoint));

	char sSteamAPIKey[64];
	GetSteamAPIKey(sSteamAPIKey, sizeof(sSteamAPIKey));

	char sRequest[256];
	FormatEx(sRequest, sizeof(sRequest), "http://%s/IPlayerService/IsPlayingSharedGame/v0001/?key=%s&steamid=%s&appid_playing=%d&format=json", sSteamAPIEndpoint, sSteamAPIKey, sSteam64ID, g_iAppID);

	HTTPRequest request = new HTTPRequest(sRequest);

	request.Get(OnFamilyShareReceived, client);
}

stock void OnFamilyShareReceived(HTTPResponse response, any client)
{
    if (response.Status != HTTPStatus_OK)
        return;

    // Indicate that the response contains a JSON object
    JSONObject responseData = view_as<JSONObject>(response.Data);

    if (!responseData.HasKey("lender_steamid"))
        return;

    int lenderSteamid = responseData.GetInt("lender_steamid");

    char rejectMessage[255];
    GetConVarString(g_hCvar_RejectMessage, rejectMessage, sizeof(rejectMessage));

    if (lenderSteamid == 0)
        return;

    int iReject = GetConVarInt(g_hCvar_Reject);

    switch (iReject)
    {
        case (2):
        {
            LogMessage("Banning %L for %d minutes (Family share)", client, GetConVarInt(g_hCvar_RejectDuration));
            ServerCommand("sm_ban #%i %d \"%s\"", GetClientUserId(client), GetConVarInt(g_hCvar_RejectDuration), rejectMessage);
        }
        case (1):
        {
            LogMessage("Kicking %L (Family share)", client);
            ServerCommand("sm_kick #%i \"%s\"", GetClientUserId(client), rejectMessage);
        }
    }
}

// Credit to Dr. McKay
// https://forums.alliedmods.net/showthread.php?t=233257
stock int GetAppID() {
    Handle file = OpenFile("steam.inf", "r");
    if(file == INVALID_HANDLE) {
        return -1;
    }

    char line[128], parts[2][64];
    while(ReadFileLine(file, line, sizeof(line))) {
        ExplodeString(line, "=", parts, sizeof(parts), sizeof(parts[]));
        if(StrEqual(parts[0], "appID")) {
            CloseHandle(file);
            return StringToInt(parts[1]);
        }
    }

    CloseHandle(file);
    return -1;
}

#if defined _SteamWorks_Included
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
    if (GetConVarInt(g_hCvar_Method) != 1)
        return;

    int client = GetClientOfAuthId(authid);

    bool whiteListed = false;
    if (g_bParsed)
    {
        char auth[2][64];
        GetClientAuthId(client, AuthId_Steam2, auth[0], sizeof(auth[]));
        whiteListed = GetTrieString(g_hWhitelistTrie, auth[0], auth[1], sizeof(auth[]));
        if(whiteListed)
        {
            LogMessage("Whitelist found player: %N", client);
            return;
        }
    }

    if (CheckCommandAccess(client, "sm_admin", ADMFLAG_GENERIC) && GetConVarInt(g_hCvar_IgnoreAdmins) > 0)
    {
        return;
    }

    if(ownerauthid != authid)
    {
        LogMessage("Kicking %L (Family share)", client);
        char rejectMessage[255]; GetConVarString(g_hCvar_RejectMessage, rejectMessage, sizeof(rejectMessage));
        KickClient(client, rejectMessage);
    }

    /*
    //Now using SteamWorks:
    EUserHasLicenseForAppResult result = SteamWorks_HasLicenseForApp(client, g_hCvar_AppId.IntValue);

    //Debug text: PrintToServer("Client %N License Value: %i", client, view_as<int>(result));

    //No License, kick em:
    if(result > k_EUserHasLicenseResultHasLicense)
    {
        char rejectMessage[255]; GetConVarString(g_hCvar_RejectMessage, rejectMessage, sizeof(rejectMessage));
        KickClient(client, rejectMessage);
    }
    */
}
#endif
