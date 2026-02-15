#define API_BASE_URL "https://offstyles.tommyy.dev/api"

#pragma semicolon 1
#pragma newdecls required
#pragma dynamic 131072

#include <sourcemod>
#include <convar_class>
#include <ripext>
#include <sha1>

int tickrate;

Convar gCV_URL = null;
Convar gCV_AuthKey = null;
Convar gCV_GameDir = null;
Convar gCV_ReplaysDir = null;
Convar gCV_Hostname = null;

char gS_ODBAuthKey[64];
ConVar gCV_Authentication = null;
ConVar gCV_PublicIP = null;
ConVar gCV_Debug = null;

char gS_URL[128];
char gS_AuthKey[64];
char gS_GameDir[PLATFORM_MAX_PATH];
char gS_StyleHash[160];

bool gB_Debug = false;

char gS_MySQLPrefix[32];
Database gH_Database = null;

StringMap gM_StyleMapping = null;

public Plugin myinfo =
{
    name = "odb-wr-sender",
	author = "happydez",
	description = "✿˘✧.*☆*✲☆⋆❤˘━✧.*",
	version = "1.0.0",
    url = "https://github.com/akanora/odb-wr-sender"
}

native float Shavit_GetWorldRecord(int style, int track);
forward void Shavit_OnReplaySaved(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, bool istoolong, ArrayList replaypaths, ArrayList frames, int preframes, int postframes, const char[] name);

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("Shavit_GetWorldRecord");

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
    gH_Database = GetTimerDatabaseHandle();
    strcopy(gS_MySQLPrefix, sizeof(gS_MySQLPrefix), "");
	GetTimerSQLPrefix(gS_MySQLPrefix, sizeof(gS_MySQLPrefix));
}

public void OnPluginStart()
{
    tickrate = RoundToZero(1.0 / GetTickInterval());

    gCV_PublicIP = new Convar("odb_public_ip", "127.0.0.1:27015", "Input the IP:PORT of the game server here. It will be used to identify the game server.");
	gCV_Authentication = new Convar("odb_private_key", "", "Fill in your OffstyleDB API access key here. This key can be used to submit records to the database using your server key - abuse will lead to removal.");
    gCV_Debug = new Convar("odb_wr_debug", "0", "Enable debug logs for odb-wr-sender (0/1).", _, true, 0.0, true, 1.0);

    gCV_AuthKey = new Convar("odb_wr_sender_auth_key", "authKey1", "API Key");
    gCV_URL = new Convar("odb_wr_sender_url", "http://127.0.0.1:4176/offstyledb/send-wr", "URL");
    gCV_GameDir = new Convar("odb_wr_game_dir", "/app/cstrike", "Game dir");
    gCV_ReplaysDir = new Convar("odb_wr_replays_dir", "replaybot/0", "Replays dir");
    gCV_Hostname = new Convar("odb_wr_hostname", "insert your hostname here", "hostname");

    gCV_AuthKey.AddChangeHook(OnConVarChanged);
    gCV_URL.AddChangeHook(OnConVarChanged);
    gCV_GameDir.AddChangeHook(OnConVarChanged);
    gCV_Debug.AddChangeHook(OnConVarChanged);

    Convar.AutoExecConfig();

    gM_StyleMapping = new StringMap();

    // RegAdminCmd("sm_send_wr", Command_SendWR, ADMFLAG_RCON);
}

public void OnPluginEnd()
{
    if (gM_StyleMapping != null)
    {
        DebugLog("[OSdb] Cleaning up StyleMapping StringMap");
        delete gM_StyleMapping;
        gM_StyleMapping = null;
    }
}

public void OnConfigsExecuted()
{
    GetStyleMapping();
}

void GetStyleMapping(bool forceRefresh = false)
{
    DebugLog("[OSdb] Starting style mapping request (forceRefresh: %s)", forceRefresh ? "true" : "false");
    
    if (!forceRefresh)
    {
        char temp[160];
        // In Pawn, use strcopy for strings, not '='
        strcopy(temp, sizeof(temp), gS_StyleHash); 
        HashStyleConfig();

        if (strcmp(temp, gS_StyleHash) == 0)
        {
            DebugLog("[OSdb] Style hash unchanged, skipping mapping request");
            return;
        }
    }
    else
    {
        DebugLog("[OSdb] Force refresh requested, bypassing hash check");
    }

    DebugLog("[OSdb] Style hash changed or forced refresh, requesting new mapping from server");

    // FIX: Format the URL properly instead of using ...
    char sFullURL[256];
    Format(sFullURL, sizeof(sFullURL), "%s/style_mapping", API_BASE_URL);

    HTTPRequest hHTTPRequest = new HTTPRequest(sFullURL);
    JSONObject hJSONObject = new JSONObject();

    AddHeaders(hHTTPRequest);

    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/shavit-styles.cfg");

    if (FileExists(sPath))
    {
        File fFile = OpenFile(sPath, "rb");

        if (fFile != null && fFile.Seek(0, SEEK_END))
        {
            int iSize = fFile.Position;
            fFile.Seek(0, SEEK_SET);

            char[] sFileContents = new char[iSize + 1];
            fFile.ReadString(sFileContents, iSize + 1, iSize);
            delete fFile;

            char[] sFileContentsEncoded = new char[iSize * 2];
            Crypt_Base64Encode(sFileContents, sFileContentsEncoded, iSize * 2, iSize);

            hJSONObject.SetString("data", sFileContentsEncoded);
        }
        else {
            delete fFile;
            delete hJSONObject;
            delete hHTTPRequest;
            return;
        }
    }
    else {
        // Cleaning up handles before failing
        delete hJSONObject;
        delete hHTTPRequest;
        SetFailState("Couldnt find configs/shavit-styles.cfg");
        return;
    }

    hHTTPRequest.Post(hJSONObject, Callback_OnStyleMapping);

    delete hJSONObject;
}

public void Callback_OnStyleMapping(HTTPResponse resp, any value)
{
    if (resp.Status != HTTPStatus_OK || resp.Data == null) return;

    JSONObject data = view_as<JSONObject>(resp.Data);
    char s_Data[512];
    data.GetString("data", s_Data, sizeof(s_Data));
    
    gM_StyleMapping.Clear();
    char parts[512][8];
    int count = ExplodeString(s_Data, ",", parts, sizeof(parts), sizeof(parts[]));

    for (int i = 0; i < count - 1; i += 2)
    {
        gM_StyleMapping.SetValue(parts[i], StringToInt(parts[i + 1]));
    }
}

int ConvertStyle(int style)
{
    if (gM_StyleMapping == null)
    {
        DebugLog("[OSdb] Style mapping is null in ConvertStyle");
        return -1;
    }
    
    char s[16];
    IntToString(style, s, sizeof(s));

    DebugLog("[OSdb] Converting style %d (key: %s)", style, s);

    int out;
    if (gM_StyleMapping.GetValue(s, out))
    {
        DebugLog("[OSdb] Style %d converted to %d", style, out);
        return out;
    }

    DebugLog("[OSdb] Style %d not found in mapping, returning -1", style);
    return -1;
}

void HashStyleConfig()
{
    char sPath[PLATFORM_MAX_PATH];
    char hash[160];
    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/shavit-styles.cfg");
    if (FileExists(sPath))
    {
        File fFile = OpenFile(sPath, "r");
        if (!SHA1File(fFile, hash))
        {
            DebugLog("Failed to hash shavit-styles.cfg");
            delete fFile;
            return;
        }

        delete fFile;
    }
    else {
        DebugLog("[OSdb] Failed to find shavit-styles.cfg");
        return;
    }

    gS_StyleHash = hash;
}

public Action Command_SendWR(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "Use !send_wr <map>");
    }
    else
    {
        char map[64];
        GetCmdArgString(map, sizeof(map));
        if (StrEqual(map, "."))
        {
            GetCurrentMap(map, sizeof(map));
        }

        char q[1024];
        Format(q, sizeof(q), 
            "SELECT a.map, a.auth AS steamid, u.name, a.time, a.jumps, a.strafes, a.sync, a.date FROM %splayertimes a " ...
            "JOIN (SELECT MIN(time) time, map, style, track FROM %splayertimes GROUP BY map, style, track) b " ... 
            "JOIN %susers u ON a.time = b.time AND a.auth = u.auth AND a.map = b.map AND a.style = b.style AND a.track = b.track " ...
            "WHERE a.map = '%s' AND a.track = 0 " ...
            "ORDER BY a.date DESC;", gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix, map);

        gH_Database.Query(SQL_SendWR_Callback, q, 0, DBPrio_Normal);
    }

    return Plugin_Handled;
}

public void SQL_SendWR_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if ((results == null) || (results.RowCount == 0) || !results.FetchRow())
	{
        DebugLog("[odb-wr-sender] SQL_SendWR_Callback: No results from record selection query.");
		return;
	}

    char map[64];
	results.FetchString(0, map, sizeof(map));

	char steamID[32];
	results.FetchString(1, steamID, sizeof(steamID));
    if (StrContains(steamID, "[U:1:", false) == -1)
    {
        Format(steamID, sizeof(steamID), "[U:1:%s]", steamID);
    }

    char name[MAX_NAME_LENGTH];
	results.FetchString(2, name, MAX_NAME_LENGTH);

    int date = results.FetchInt(7);

    float time = results.FetchFloat(3);
    int jumps = results.FetchInt(4);
    int strafes = results.FetchInt(5);
    float sync = results.FetchFloat(6);
    int style = results.FetchInt(8);

    char replaypath[PLATFORM_MAX_PATH * 2];
    gCV_ReplaysDir.GetString(replaypath, sizeof(replaypath));
    Format(replaypath, sizeof(replaypath), "%s/%s.replay", replaypath, map);

    SendODBWR(map, steamID, name, time, sync, strafes, jumps, date, replaypath, style);
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    gCV_URL.GetString(gS_URL, sizeof(gS_URL));
    gCV_AuthKey.GetString(gS_AuthKey, sizeof(gS_AuthKey));
    gCV_GameDir.GetString(gS_GameDir, sizeof(gS_GameDir));
    gB_Debug = (gCV_Debug != null) ? gCV_Debug.BoolValue : false;
}

public void OnMapStart()
{
    gCV_URL.GetString(gS_URL, sizeof(gS_URL));
    gCV_AuthKey.GetString(gS_AuthKey, sizeof(gS_AuthKey));
    gCV_GameDir.GetString(gS_GameDir, sizeof(gS_GameDir));
    gB_Debug = (gCV_Debug != null) ? gCV_Debug.BoolValue : false;
}

public void Shavit_OnReplaySaved(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, bool istoolong, ArrayList replaypaths, ArrayList frames, int preframes, int postframes, const char[] name)
{
    if (track != 0 || !isbestreplay)
    {
        return;
    }

    if (time > Shavit_GetWorldRecord(style, track))
	{
		return;
	}

    char map[64];
    GetCurrentMap(map, sizeof(map));
    
    char steamID[32];
    GetClientAuthId(client, AuthId_Steam3, steamID, sizeof(steamID));
    
    int date = GetTime();

    char replaypath[PLATFORM_MAX_PATH * 2];
    gCV_ReplaysDir.GetString(replaypath, sizeof(replaypath));
    Format(replaypath, sizeof(replaypath), "%s/%s.replay", replaypath, map);

    SendODBWR(map, steamID, name, time, sync, strafes, jumps, date, replaypath, style);
}

void SendODBWR(char[] map, char[] steamID, const char[] name, float time, float sync, int strafes, int jumps, int date, const char[] replaypath, int style)
{
    if (strlen(gS_ODBAuthKey) == 0)
	{
        gCV_Authentication.GetString(gS_ODBAuthKey, sizeof(gS_ODBAuthKey));
	}
	gCV_Authentication.SetString("");

	char publicIP[32];
	gCV_PublicIP.GetString(publicIP, sizeof(publicIP));

    char hostname[128];
	gCV_Hostname.GetString(hostname, sizeof(hostname));

    int n_Style = ConvertStyle(style);
    if (n_Style == -1)
    {
        DebugLog("[OSdb] Style conversion failed for style %d, aborting record submission", style);
        return;
    }

    JSONObject data = new JSONObject();
    data.SetString("map", map);
    data.SetString("steamid", steamID);
    data.SetString("name", name);
    data.SetFloat("time", time);
    data.SetFloat("sync", sync);
    data.SetInt("strafes", strafes);
    data.SetInt("jumps", jumps);
	data.SetInt("date", date);
	data.SetInt("tickrate", tickrate);
    data.SetString("hostname", hostname);
    data.SetString("public_ip", publicIP);
    data.SetString("private_key", gS_ODBAuthKey);
    data.SetInt("style", n_Style);
    
    char replayFullPath[PLATFORM_MAX_PATH];
    Format(replayFullPath, sizeof(replayFullPath), "%s/%s", gS_GameDir, replaypath);
    data.SetString("replay_path", replayFullPath);

    HTTPRequest req = new HTTPRequest(gS_URL);
    req.SetHeader("X-API-Key", gS_AuthKey);
    req.SetHeader("Content-Type", "application/json");

    req.Post(data, OnSendODBWR_Callback);
}

void OnSendODBWR_Callback(HTTPResponse response, any value)
{
    if ((response.Status != HTTPStatus_Accepted) && (response.Status != HTTPStatus_OK))
    {
		DebugLog("[odb-wr-sender] Failed. Status: %d", response.Status);
    }
}

void DebugLog(const char[] fmt, any ...)
{
    if (!gB_Debug)
    {
        return;
    }

    char buffer[512];
    VFormat(buffer, sizeof(buffer), fmt, 2);
    LogMessage("%s", buffer);
}

// stocks from shavit.inc
// connects synchronously to the bhoptimer database
// calls errors if needed
Database GetTimerDatabaseHandle()
{
	char err[255];
	Database db = null;
	if (SQL_CheckConfig("shavit"))
	{
		if ((db = SQL_Connect("shavit", true, err, sizeof(err))) == null)
		{
            SetFailState("[odb-wr-sender] plugin startup failed. Reason: %s", err);
		}
	}
	else
	{
		db = SQLite_UseDatabase("shavit", err, sizeof(err));
	}

	return db;
}

// retrieves the table prefix defined in configs/shavit-prefix.txt
void GetTimerSQLPrefix(char[] buffer, int maxlen)
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/shavit-prefix.txt");

	File file = OpenFile(path, "r");
	if (file == null)
	{
        SetFailState("[odb-wr-sender] Cannot open \"configs/shavit-prefix.txt\". Make sure this file exists and that the server has read permissions to it.");
	}

	char line[PLATFORM_MAX_PATH * 2];
	if (file.ReadLine(line, sizeof(line)))
	{
		TrimString(line);
		strcopy(buffer, maxlen, line);
	}

	delete file;
}

void AddHeaders(HTTPRequest req)
{
    char sPublicIP[32];
    gCV_PublicIP.GetString(sPublicIP, sizeof(sPublicIP));

    char sHostname[128];
    // This finds the server's actual hostname automatically
    FindConVar("hostname").GetString(sHostname, sizeof(sHostname));

    req.SetHeader("public_ip", sPublicIP);
    req.SetHeader("hostname", sHostname);
    
    // Use the AuthKey from your ConVar
    char sAuth[64];
    gCV_AuthKey.GetString(sAuth, sizeof(sAuth));
    req.SetHeader("auth", sAuth);
    
    // Tell the website this is a shavit record
    req.SetHeader("timer_plugin", "shavit");
}

int Crypt_Base64Encode(const char[] sString, char[] sResult, int len, int sourcelen = 0)
{
    char base64_sTable[]  = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    int  base64_cFillChar = '=';

    int  nLength;
    int  resPos;

    if (sourcelen > 0)
    {
        nLength = sourcelen;
    }
    else
    {
        nLength = strlen(sString);
    }

    for (int nPos = 0; nPos < nLength; nPos++)
    {
        int cCode;

        cCode = (sString[nPos] >> 2) & 0x3f;
        resPos += FormatEx(sResult[resPos], len - resPos, "%c", base64_sTable[cCode]);
        cCode = (sString[nPos] << 4) & 0x3f;

        if (++nPos < nLength)
        {
            cCode |= (sString[nPos] >> 4) & 0x0f;
        }

        resPos += FormatEx(sResult[resPos], len - resPos, "%c", base64_sTable[cCode]);

        if (nPos < nLength)
        {
            cCode = (sString[nPos] << 2) & 0x3f;

            if (++nPos < nLength)
            {
                cCode |= (sString[nPos] >> 6) & 0x03;
            }

            resPos += FormatEx(sResult[resPos], len - resPos, "%c", base64_sTable[cCode]);
        }
        else
        {
            nPos++;
            resPos += FormatEx(sResult[resPos], len - resPos, "%c", base64_cFillChar);
        }

        if (nPos < nLength)
        {
            cCode = sString[nPos] & 0x3f;
            resPos += FormatEx(sResult[resPos], len - resPos, "%c", base64_sTable[cCode]);
        }
        else
        {
            resPos += FormatEx(sResult[resPos], len - resPos, "%c", base64_cFillChar);
        }
    }

    return resPos;
}
