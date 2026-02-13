#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <convar_class>
#include <ripext>

int tickrate;

Convar gCV_URL = null;
Convar gCV_AuthKey = null;
Convar gCV_GameDir = null;
Convar gCV_ReplaysDir = null;
Convar gCV_Hostname = null;

char gS_SJAuthKey[64];
ConVar gCV_Authentication = null;
ConVar gCV_PublicIP = null;

char gS_URL[128];
char gS_AuthKey[64];
char gS_GameDir[PLATFORM_MAX_PATH];

char gS_MySQLPrefix[32];
Database gH_Database = null;

public Plugin myinfo =
{
	name = "sj-wr-sender",
	author = "happydez",
	description = "✿˘✧.*☆*✲☆⋆❤˘━✧.*",
	version = "1.0.0",
	url = "https://github.com/happydez/sj-wr-sender"
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

    gCV_PublicIP = new Convar("sourcejump_public_ip", "127.0.0.1:27015", "Input the IP:PORT of the game server here. It will be used to identify the game server.");
	gCV_Authentication = new Convar("sourcejump_private_key", "", "Fill in your SourceJump API access key here. This key can be used to submit records to the database using your server key - abuse will lead to removal.");

    gCV_AuthKey = new Convar("sj_wr_sender_auth_key", "authKey1", "API Key");
    gCV_URL = new Convar("sj_wr_sender_url", "http://127.0.0.1:4175/sourcejump/send-wr", "URL");
    gCV_GameDir = new Convar("sj_wr_game_dir", "/app/cstrike", "Game dir");
    gCV_ReplaysDir = new Convar("sj_wr_replays_dir", "replaybot/0", "Replays dir");
    gCV_Hostname = new Convar("sj_wr_hostname", "insert your hostname here", "hostname");

    gCV_AuthKey.AddChangeHook(OnConVarChanged);
    gCV_URL.AddChangeHook(OnConVarChanged);
    gCV_GameDir.AddChangeHook(OnConVarChanged);

    Convar.AutoExecConfig();

    RegAdminCmd("sm_send_wr", Command_SendWR, ADMFLAG_RCON);
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
            "WHERE a.map = '%s' AND a.style = 0 AND a.track = 0 " ...
            "ORDER BY a.date DESC;", gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix, map);

        gH_Database.Query(SQL_SendWR_Callback, q, 0, DBPrio_Normal);
    }

    return Plugin_Handled;
}

public void SQL_SendWR_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if ((results == null) || (results.RowCount == 0) || !results.FetchRow())
	{
        LogMessage("[sj-wr-sender] SQL_SendWR_Callback: No results from record selection query.");
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

	char date[32];
	FormatTime(date, sizeof(date), "%Y-%m-%d %H:%M:%S", results.FetchInt(7));

    float time = results.FetchFloat(3);
    int jumps = results.FetchInt(4);
    int strafes = results.FetchInt(5);
    float sync = results.FetchFloat(6);

    char replaypath[PLATFORM_MAX_PATH * 2];
    gCV_ReplaysDir.GetString(replaypath, sizeof(replaypath));
    Format(replaypath, sizeof(replaypath), "%s/%s.replay", replaypath, map);

    SendSJWR(map, steamID, name, time, sync, strafes, jumps, date, replaypath);
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    gCV_URL.GetString(gS_URL, sizeof(gS_URL));
    gCV_AuthKey.GetString(gS_AuthKey, sizeof(gS_AuthKey));
    gCV_GameDir.GetString(gS_GameDir, sizeof(gS_GameDir));
}

public void OnMapStart()
{
    gCV_URL.GetString(gS_URL, sizeof(gS_URL));
    gCV_AuthKey.GetString(gS_AuthKey, sizeof(gS_AuthKey));
    gCV_GameDir.GetString(gS_GameDir, sizeof(gS_GameDir));
}

public void Shavit_OnReplaySaved(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, bool istoolong, ArrayList replaypaths, ArrayList frames, int preframes, int postframes, const char[] name)
{
    if (style != 0 || track != 0 || !isbestreplay)
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
    
    char date[32];
    FormatTime(date, sizeof(date), "%Y-%m-%d %H:%M:%S", GetTime());

    char replaypath[PLATFORM_MAX_PATH * 2];
    gCV_ReplaysDir.GetString(replaypath, sizeof(replaypath));
    Format(replaypath, sizeof(replaypath), "%s/%s.replay", replaypath, map);

    SendSJWR(map, steamID, name, time, sync, strafes, jumps, date, replaypath);
}

void SendSJWR(char[] map, char[] steamID, const char[] name, float time, float sync, int strafes, int jumps, char[] date, const char[] replaypath)
{
    if (strlen(gS_SJAuthKey) == 0)
	{
		gCV_Authentication.GetString(gS_SJAuthKey, sizeof(gS_SJAuthKey));
	}
	gCV_Authentication.SetString("");

	char publicIP[32];
	gCV_PublicIP.GetString(publicIP, sizeof(publicIP));

    char hostname[128];
	gCV_Hostname.GetString(hostname, sizeof(hostname));

    JSONObject data = new JSONObject();
    data.SetString("map", map);
    data.SetString("steamid", steamID);
    data.SetString("name", name);
    data.SetFloat("time", time);
    data.SetFloat("sync", sync);
    data.SetInt("strafes", strafes);
    data.SetInt("jumps", jumps);
    data.SetString("date", date);
	data.SetInt("tickrate", tickrate);
    data.SetString("hostname", hostname);
    data.SetString("public_ip", publicIP);
	data.SetString("private_key", gS_SJAuthKey);
    
    char replayFullPath[PLATFORM_MAX_PATH];
    Format(replayFullPath, sizeof(replayFullPath), "%s/%s", gS_GameDir, replaypath);
    data.SetString("replay_path", replayFullPath);

    HTTPRequest req = new HTTPRequest(gS_URL);
    req.SetHeader("X-API-Key", gS_AuthKey);
    req.SetHeader("Content-Type", "application/json");

    req.Post(data, OnSendSJWR_Callback);
}

void OnSendSJWR_Callback(HTTPResponse response, any value)
{
    if ((response.Status != HTTPStatus_Accepted) && (response.Status != HTTPStatus_OK))
    {
        LogError("[sj-wr-sender] Failed. Status: %d", response.Status);
    }
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
			SetFailState("[sj-wr-sender] plugin startup failed. Reason: %s", err);
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
		SetFailState("[sj-wr-sender] Cannot open \"configs/shavit-prefix.txt\". Make sure this file exists and that the server has read permissions to it.");
	}

	char line[PLATFORM_MAX_PATH * 2];
	if (file.ReadLine(line, sizeof(line)))
	{
		TrimString(line);
		strcopy(buffer, maxlen, line);
	}

	delete file;
}
