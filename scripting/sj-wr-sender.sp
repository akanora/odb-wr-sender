#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <convar_class>
#include <ripext>

int tickrate;

Convar gCV_URL = null;
Convar gCV_AuthKey = null;
Convar gCV_GameDir = null;

char gS_URL[128];
char gS_AuthKey[64];
char gS_GameDir[PLATFORM_MAX_PATH];

public Plugin myinfo =
{
	name = "sj-wr-sender",
	author = "happydez",
	description = "✿˘✧.*☆*✲☆⋆❤˘━✧.*",
	version = "1.0.0",
	url = "https://github.com/happydez/sj-wr-sender"
}

native float Shavit_GetWorldRecord(int style, int track);
forward void Shavit_OnReplaySaved(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, bool istoolong, bool iscopy, const char[] replaypath);

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("Shavit_GetWorldRecord");

	return APLRes_Success;
}

public void OnPluginStart()
{
    tickrate = RoundToZero(1.0 / GetTickInterval());

    gCV_AuthKey = new Convar("sj_wr_sender_auth_key", "authKey1", "API Key");
    gCV_URL = new Convar("sj_wr_sender_url", "http://127.0.0.1:4175/sourcejump/send-wr", "URL");
    gCV_GameDir = new Convar("sj_wr_game_dir", "/app/cstrike", "Game dir");

    gCV_AuthKey.AddChangeHook(OnConVarChanged);
    gCV_URL.AddChangeHook(OnConVarChanged);
    gCV_GameDir.AddChangeHook(OnConVarChanged);

    Convar.AutoExecConfig();
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

public void Shavit_OnReplaySaved(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, bool istoolong, bool iscopy, const char[] replaypath)
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
    
    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    
    char date[32];
    FormatTime(date, sizeof(date), "%Y-%m-%d %H:%M:%S", GetTime());

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
