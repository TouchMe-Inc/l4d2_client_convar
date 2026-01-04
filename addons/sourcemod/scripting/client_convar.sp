#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <colors>


public Plugin myinfo = {
    name        = "ClientConVar",
    author      = "ConfoglTeam, TouchMe",
    description = "The plugin allows you to check client ConVars",
    version     = "build_0002",
    url         = "https://github.com/TouchMe-Inc/l4d2_client_convar"
}


/*
 * File names.
 */
#define TRANSLATIONS            "client_convar.phrases"

/*
 * Teams.
 */
#define TEAM_SPECTATOR          1

/*
 * String length.
 */
#define MAXLENGTH_CVAR_NAME     64


enum
{
    Action_Kick = 0,
    Action_Spec
};

enum struct ConVarInfo
{
    bool hasMin;
    float min;
    bool hasMax;
    float max;
    int action;
    char cvar[MAXLENGTH_CVAR_NAME];
}

ArrayList g_aClientConVars = null;

bool g_bCheckStarted = false;

Handle g_hTimer[MAXPLAYERS + 1];

int g_iIndex[MAXPLAYERS + 1];


public void OnPluginStart()
{
    g_aClientConVars = new ArrayList(sizeof(ConVarInfo));

    LoadTranslations(TRANSLATIONS);

    /* Using Server Cmd instead of admin because these shouldn't really be changed on the fly */
    RegServerCmd("sm_trackclientcvar", Cmd_TrackClientCvar, "Add a Client ConVar to be tracked and enforced");
    RegServerCmd("sm_resetclientcvars", Cmd_ResetTracking, "Remove all tracked client cvars");
    RegServerCmd("sm_startclientchecking", Cmd_StartClientChecking, "Start checking and enforcing client cvars tracked by this plugin");

    g_bCheckStarted = false;
}

Action Cmd_TrackClientCvar(int iArgs)
{
    if (iArgs < 3 || iArgs == 4)
    {
        PrintToServer("Usage: sm_trackclientcvar <cvar> <hasMin> <min> [<hasMax> <max> [<action>]]");

        return Plugin_Handled;
    }

    char szBuffer[MAXLENGTH_CVAR_NAME], cvar[MAXLENGTH_CVAR_NAME];
    bool hasMax;
    float max;
    int action = Action_Spec;

    GetCmdArg(1, cvar, sizeof(cvar));

    if (!strlen(cvar) || strlen(cvar) >= MAXLENGTH_CVAR_NAME) {
        LogError("ConVar Specified (%s) is longer than max cvar length (%d)", cvar, MAXLENGTH_CVAR_NAME);
        return Plugin_Handled;
    }

    GetCmdArg(2, szBuffer, sizeof(szBuffer));
    bool hasMin = view_as<bool>(StringToInt(szBuffer));

    GetCmdArg(3, szBuffer, sizeof(szBuffer));
    float min = StringToFloat(szBuffer);

    if (iArgs >= 5)
    {
        GetCmdArg(4, szBuffer, sizeof(szBuffer));
        hasMax = view_as<bool>(StringToInt(szBuffer));

        GetCmdArg(5, szBuffer, sizeof(szBuffer));
        max = StringToFloat(szBuffer);
    }

    if (iArgs >= 6) {
        GetCmdArg(6, szBuffer, sizeof(szBuffer));
        action = StringToInt(szBuffer);
    }

    if (!(hasMin || hasMax)) {
        LogError("Client ConVar %s specified without max or min", cvar);
        return Plugin_Handled;
    }

    if (hasMin && hasMax && max < min) {
        LogError("Client ConVar %s specified max < min (%f < %f)", cvar, max, min);
        return Plugin_Handled;
    }

    int iSize = g_aClientConVars.Length;

    ConVarInfo newEntry;

    for (int i = 0; i < iSize; i++)
    {
        g_aClientConVars.GetArray(i, newEntry, sizeof(newEntry));

        if (strcmp(newEntry.cvar, cvar, false) == 0)
        {
            LogError("Attempt to track ConVar %s, which is already being tracked.", cvar);
            return Plugin_Handled;
        }
    }

    newEntry.hasMin = hasMin;
    newEntry.min = min;
    newEntry.hasMax = hasMax;
    newEntry.max = max;
    newEntry.action = action;
    strcopy(newEntry.cvar, MAXLENGTH_CVAR_NAME, cvar);

    g_aClientConVars.PushArray(newEntry, sizeof(newEntry));

    return Plugin_Handled;
}

Action Cmd_ResetTracking(int iArgs)
{
    if (g_bCheckStarted) {
        return Plugin_Handled;
    }

    g_aClientConVars.Clear();

    PrintToServer("Client ConVar Tracking Information Reset!");

    return Plugin_Handled;
}

Action Cmd_StartClientChecking(int iArgs)
{
    g_bCheckStarted = true;

    return Plugin_Handled;
}

public void OnClientPostAdminCheck(int iClient)
{
    if (!g_bCheckStarted) {
        return;
    }

    if (!IsFakeClient(iClient)) {
        SetTimer(g_hTimer[iClient], CreateTimer(1.0, Timer_CheckCvars, GetClientUserId(iClient)));
    }
}

public void OnClientDisconnect(int iClient)
{
    if (!g_bCheckStarted) {
        return;
    }

    if (!IsFakeClient(iClient))
    {
        g_iIndex[iClient] = 0;
        SetTimer(g_hTimer[iClient], INVALID_HANDLE);
    }
}

Action Timer_CheckCvars(Handle hTimer, int iUserId)
{
    int iClient = GetClientOfUserId(iUserId);

    if (iClient <= 0) {
        return Plugin_Stop;
    }

    g_iIndex[iClient] = 0;
    SetTimer(g_hTimer[iClient], CreateTimer(GetRandomFloat(0.1, 0.5), Timer_QueryNextCvar, iUserId, TIMER_REPEAT));

    return Plugin_Stop;
}

Action Timer_QueryNextCvar(Handle hTimer, int iUserId)
{
    if (g_aClientConVars.Length == 0) {
        return Plugin_Stop;
    }

    int iClient = GetClientOfUserId(iUserId);

    if (iClient <= 0) {
        return Plugin_Stop;
    }

    if (g_iIndex[iClient] >= g_aClientConVars.Length)
    {
        SetTimer(g_hTimer[iClient], CreateTimer(GetRandomFloat(10.0, 60.0), Timer_CheckCvars, iUserId));

        return Plugin_Stop;
    }

    ConVarInfo cvi;
    g_aClientConVars.GetArray(g_iIndex[iClient], cvi, sizeof(cvi));

    if (QueryClientConVar(iClient, cvi.cvar, QueryReply_EnforceCliSettings, (GetClientSerial(iClient) << 16) | g_iIndex[iClient]) == QUERYCOOKIE_FAILED) {
        return Plugin_Continue;
    }

    g_iIndex[iClient]++;

    return Plugin_Continue;
}

void QueryReply_EnforceCliSettings(QueryCookie cookie, int iClient, ConVarQueryResult result, \
                                                const char[] szCvarName, const char[] cvarValue, int data)
{
    int iIndex  = data & 0xFFFF;
    int iSerial = data >> 16;

    if (GetClientFromSerial(iSerial) != iClient) {
        return;
    }

    if (result)
    {
        LogMessage("Couldn't retrieve cvar %s from %L, kicked from server", szCvarName, iClient);
        KickClient(iClient, "ConVar '%s' protected or missing!", szCvarName);
        return;
    }

    float fCvarVal = StringToFloat(cvarValue);

    ConVarInfo cvi;
    g_aClientConVars.GetArray(iIndex, cvi, sizeof cvi);

    if ((cvi.hasMin && fCvarVal < cvi.min) || (cvi.hasMax && fCvarVal > cvi.max))
    {
        switch (cvi.action)
        {
            case Action_Kick:
            {
                LogMessage("Kicking %L for bad %s value (%f). Min: %d %f Max: %d %f", \
                                    iClient, szCvarName, fCvarVal, cvi.hasMin, \
                                        cvi.min, cvi.hasMax, cvi.max);

                CPrintToChatAll("%t%t", "TAG", "KICKED", iClient, szCvarName, fCvarVal);

                char szKickMessage[256] = "Illegal Client Value for ";
                Format(szKickMessage, sizeof(szKickMessage), "%s%s (%.2f)", szKickMessage, szCvarName, fCvarVal);

                if (cvi.hasMin) {
                    Format(szKickMessage, sizeof(szKickMessage), "%s, Min %.2f", szKickMessage, cvi.min);
                }

                if (cvi.hasMax) {
                    Format(szKickMessage, sizeof(szKickMessage), "%s, Max %.2f", szKickMessage, cvi.max);
                }

                KickClient(iClient, "%s", szKickMessage);
            }

            case Action_Spec:
            {
                if (GetClientTeam(iClient) == TEAM_SPECTATOR) {
                    return;
                }

                LogMessage("Client %L has a bad %s value (%f). Min: %d %f Max: %d %f", \
                                    iClient, szCvarName, fCvarVal, cvi.hasMin, \
                                        cvi.min, cvi.hasMax, cvi.max);

                CPrintToChatAll("%t%t", "TAG", "MOVE_TO_SPEC", iClient, szCvarName, fCvarVal);

                ChangeClientTeam(iClient, TEAM_SPECTATOR);
            }
        }
    }
}

void SetTimer(Handle &hTimer, Handle hNewTimer = INVALID_HANDLE)
{
    if (hTimer != INVALID_HANDLE)
    {
        KillTimer(hTimer);
        hTimer = INVALID_HANDLE;
    }

    hTimer = hNewTimer;
}

