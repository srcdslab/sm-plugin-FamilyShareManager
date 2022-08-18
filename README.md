# sm-plugin-FamilyShareManager

[Family Share Manager](https://forums.alliedmods.net/showthread.php?t=293927) enables server owners to block family shared accounts and copies of the games, while at the same time enabling other family shared copies to play.

# Changelog

Updated to use SteamWorks on 4/29/2022 since valve removed or (seemingly broke?) IsPlayingSharedGame from the API

## Commands
- sm_reloadlist - Reloads the whitelist while plugin is running.
- sm_addtolist - Add a player to the white/blacklist.
- sm_removefromlist - Remove a player from the white/blacklist.
- sm_displaylist - Displays all Steam IDs currently in the list

## Configuration

### Whitelist

Format must be a list of steamid then new line with one steam id per line.

#### Example

```
STEAM_0:1:1854617
STEAM_0:1:123
```

## Misc

A question by ShogoMoe I answered:

If you wanted this to be a blacklist instead, allowing all family shared accounts besides the ones on the list, you could simply add one character to the code:

```
public OnClientPostAdminCheck(client)
{
    new bool:whiteListed = false;
    if(g_bParsed)
    {
        decl String:auth[2][64];
        GetClientAuthId(client, AuthId_Steam2, auth[0], sizeof(auth[]));
        whiteListed = GetTrieString(g_hWhitelistTrie, auth[0], auth[1], sizeof(auth[]));
        if(!whiteListed)
        {
            LogMessage("Whitelist found player: %N", client);
            return;
        }
    }

    if(CheckCommandAccess(client, "sm_admin", ADMFLAG_GENERIC) && GetConVarInt(g_hCvar_IgnoreAdmins) > 0)
    {
        return;
    }

    if(!IsFakeClient(client))
        checkFamilySharing(client);
}
```
