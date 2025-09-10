# SourcePawn Plugin Development Guidelines - Family Share Manager

## Repository Overview
This repository contains the **Family Share Manager** SourcePawn plugin for SourceMod, which manages family shared Steam accounts by providing whitelist/blacklist functionality. The plugin detects family shared accounts and applies configurable punishments (kick/ban) while allowing whitelisted accounts to bypass restrictions.

## Technical Environment
- **Language**: SourcePawn
- **Platform**: SourceMod 1.11.0+ (configured for 1.11.0-git6934 in sourceknight.yaml)
- **Build System**: SourceKnight (see `sourceknight.yaml`)
- **Compiler**: SourcePawn compiler (spcomp) via SourceKnight
- **Primary File**: `addons/sourcemod/scripting/FamilyShareManager.sp`
- **Code Style**: Uses legacy patterns (CreateTrie, CloseHandle) - prefer modern patterns for new code

## Dependencies & Extensions
The plugin requires these dependencies (auto-managed by SourceKnight):
- **SourceMod**: 1.11.0-git6934 or newer
- **SteamWorks Extension**: For family sharing detection via `SteamWorks_OnValidateClient`
- **RipExt Extension**: For HTTP functionality (if needed)
- **MultiColors Plugin**: For colored chat messages
- **Optional**: SourceBans++ and MaterialAdmin for enhanced banning

## Code Style & Standards
Follow these SourcePawn conventions:

### Syntax Requirements
```sourcepawn
#pragma newdecls required
// Note: This plugin doesn't use #pragma semicolon 1
```

### Naming Conventions
- **Functions**: PascalCase (`ApplyPunishment`, `CheckWhiteList`)
- **Global Variables**: Prefix with `g_` and use PascalCase (`g_hWhitelistTrie`, `g_bParsed`)
- **Local Variables**: camelCase (`steamid`, `whiteListed`)
- **Constants**: UPPER_SNAKE_CASE (`PLATFORM_MAX_PATH`)

### Indentation & Formatting
- Use tabs (4 spaces equivalent)
- Delete trailing spaces
- Use descriptive variable and function names
- No unnecessary header comments or plugin descriptions

### Memory Management
This plugin uses legacy handle patterns but follow these guidelines for new code:

```sourcepawn
// EXISTING PATTERN (legacy): CloseHandle for files and old-style handles
Handle hFile = OpenFile(path, "r");
if (hFile != INVALID_HANDLE) {
    // ... use file
    CloseHandle(hFile);
}

// PREFERRED FOR NEW CODE: Use delete directly without null checks
delete handle;

// WRONG: Don't check for null before delete
if (handle != null) {
    delete handle;
}

// EXISTING: Legacy Trie usage
Handle g_hWhitelistTrie = CreateTrie();
// ... later
CloseHandle(g_hWhitelistTrie);

// PREFERRED FOR NEW CODE: Modern StringMap/ArrayList with delete
StringMap myStringMap = new StringMap();
// ... later
delete myStringMap;

// WRONG: .Clear() creates memory leaks
myStringMap.Clear();
```

## Plugin Architecture & Patterns

### Core Components
1. **Configuration Management**: ConVars for plugin behavior
2. **Whitelist System**: File-based storage using StringMap/Trie
3. **Family Share Detection**: SteamWorks integration
4. **Punishment System**: Configurable kick/ban with optional integration
5. **Admin Commands**: Management interface for whitelist

### Key Functions
- `OnPluginStart()`: Initialize ConVars, commands, and parse whitelist
- `SteamWorks_OnValidateClient()`: Main family sharing detection hook
- `CheckWhiteList()`: Validate if player is whitelisted or admin
- `ApplyPunishment()`: Execute configured punishment (kick/ban)
- `parseList()`: Load whitelist from configuration file

### Configuration Pattern
```sourcepawn
// Create ConVars in OnPluginStart()
g_hCvar_Reject = CreateConVar("sm_familyshare_reject", "1", "2 = ban, 1 = kick, 0 = ignore", FCVAR_NOTIFY);

// Cache values in OnConfigsExecuted()
public void OnConfigsExecuted()
{
    g_iReject = GetConVarInt(g_hCvar_Reject);
}

// Handle runtime changes
void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if(convar == g_hCvar_Reject)
        g_iReject = GetConVarInt(convar);
}
```

## File Structure & Organization
```
addons/sourcemod/
├── scripting/
│   └── FamilyShareManager.sp          # Main plugin source
├── configs/
│   └── familyshare_whitelist.cfg      # Whitelist configuration (runtime created)
└── plugins/
    └── FamilyShareManager.smx         # Compiled plugin (build output)
```

## Build & Development Process

### Building with SourceKnight
```bash
# Install SourceKnight and build
sourceknight build

# Output location: .sourceknight/package/addons/sourcemod/plugins/
```

### Local Development
1. Edit `addons/sourcemod/scripting/FamilyShareManager.sp`
2. Run `sourceknight build` to compile
3. Test on development server
4. Verify no compilation errors or warnings

### CI/CD Process
- GitHub Actions automatically builds on push/PR
- Uses `maxime1907/action-sourceknight@v1`
- Creates releases with compiled plugins
- Uploads artifacts for testing

## Database & SQL Guidelines
This plugin uses file-based storage, but if adding SQL functionality:
- **All queries MUST be asynchronous** using Database methodmaps
- Use transactions for multiple related operations
- Always escape strings and prevent SQL injection
- Example pattern:
```sourcepawn
Database db = SQL_Connect("default");
char query[256];
db.Format(query, sizeof(query), "SELECT * FROM table WHERE field = '%s'", escapedValue);
db.Query(OnQueryComplete, query);
```

## Error Handling & Best Practices

### Handle Management
```sourcepawn
// File operations
Handle hFile = OpenFile(path, "r");
if (hFile == INVALID_HANDLE) {
    LogError("Failed to open file: %s", path);
    return;
}
// ... use file
CloseHandle(hFile);
```

### Admin Permission Checks
```sourcepawn
// Check specific flags
bool IsAdmin(int client) {
    return view_as<bool>(GetUserFlagBits(client) & g_iAdminFlags);
}

// Check command access
if (!CheckCommandAccess(client, "", ADMFLAG_ROOT)) {
    ReplyToCommand(client, "No access");
    return Plugin_Handled;
}
```

### Translation Support
Use translation files for user-facing messages:
```sourcepawn
// Instead of hardcoded strings
LoadTranslations("familyshare.phrases");
CPrintToChat(client, "%t", "Player_Banned_Message");
```

## Testing & Validation

### Manual Testing Checklist
1. Plugin loads without errors
2. ConVars are created and functional
3. Admin commands work correctly
4. Family sharing detection functions
5. Whitelist persistence across map changes
6. Integration with SourceBans++/MaterialAdmin (if available)

### Performance Considerations
- Minimize operations in `SteamWorks_OnValidateClient` (called frequently)
- Cache ConVar values rather than calling `GetConVarInt()` repeatedly
- Use efficient data structures (StringMap vs arrays)
- Avoid unnecessary string operations in hot paths

## Common Issues & Solutions

### Memory Leaks
- Always use `delete` instead of `.Clear()` for containers
- Close all file handles after use
- Don't check for null before calling `delete`

### SteamWorks Integration
- Ensure SteamWorks extension is loaded before using callbacks
- Handle cases where client index might be invalid
- Use proper Steam ID validation

### File Operations
- Create directory structure if it doesn't exist
- Handle file read/write errors gracefully
- Use proper path building with `BuildPath()`

## Version Control & Releases
- Use semantic versioning in plugin info
- Update version in `myinfo` structure
- Tag releases appropriately
- Keep plugin version synchronized with repository tags

## Plugin-Specific Notes

### Whitelist Management
- Whitelist stored in `configs/familyshare_whitelist.cfg`
- One Steam ID per line (STEAM_0:X:XXXXX format)
- Uses legacy Trie (StringMap predecessor) for storage: `CreateTrie()`
- Automatically creates file if it doesn't exist
- Supports runtime reloading via `sm_reloadlist`
- File operations use legacy `OpenFile()` and `CloseHandle()` pattern

### Admin Commands
- `sm_reloadlist`: Reload whitelist configuration
- `sm_addtolist [steamid]`: Add player to whitelist (menu if no args)
- `sm_removefromlist <steamid>`: Remove player from whitelist  
- `sm_displaylist`: Show current whitelist entries

### Configuration Variables
- `sm_familyshare_reject`: 0=ignore, 1=kick, 2=ban
- `sm_familyshare_reject_duration`: Ban duration in minutes
- `sm_familyshare_reject_message`: Message shown to rejected players
- `sm_familyshare_ignoreadmins`: Ignore admins with family shared accounts
- `sm_familyshare_ignoreadmins_flags`: Admin flags to ignore

When working on this plugin, focus on maintaining the existing architecture while ensuring code quality and following SourcePawn best practices. Always test changes thoroughly and consider the performance impact on the game server.