#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.1"
#define CONFIG_NAME "umbrella_weapon_restrict"
#define REPLY_PREFIX "[UWR]"
#define TEAM_BOTH 0
#define TEAM_INDEX_T 0
#define TEAM_INDEX_CT 1
#define TEAM_INDEX_COUNT 2
#define NOTIFY_DELAY 1.5
#define DEFAULT_RESTRICT_SOUND "sound/buttons/weapon_cant_buy.wav"
#define PERPLAYER_CONFIG "configs/umbrella_weapon_restrict/perplayerrestrict.txt"
#define PERPLAYER_INVALID -3
#define PERPLAYER_UNSET -2
#define WEAPON_GROUP_INVALID -1
#define WEAPON_GROUP_PISTOLS 0
#define WEAPON_GROUP_SMGS 1
#define WEAPON_GROUP_SHOTGUNS 2
#define WEAPON_GROUP_RIFLES 3
#define WEAPON_GROUP_SNIPERS 4
#define WEAPON_GROUP_GRENADES 5
#define WEAPON_GROUP_ARMOR 6
#define WEAPON_GROUP_COUNT 7

EngineVersion g_Engine;
bool g_LateLoaded;
bool g_WeaponCvarsReady;
bool g_EnforceQueued;
bool g_MapStarted;

ArrayList g_WeaponIds;
StringMap g_WeaponIdCache;
TopMenu g_AdminMenu = null;

ConVar g_CvarEnabled = null;
ConVar g_CvarAllowPickup = null;
ConVar g_CvarAdminImmunity = null;
ConVar g_CvarNotify = null;
ConVar g_CvarRestrictSound = null;
ConVar g_CvarPerPlayerEnabled = null;
ConVar g_CvarPerPlayerBots = null;
ConVar g_CvarPerPlayerSpecs = null;
ConVar g_CvarVersion = null;
ConVar g_RestrictCvars[CSWeapon_MAX_WEAPONS][TEAM_INDEX_COUNT];

int g_MenuWeapon[MAXPLAYERS + 1];
int g_MenuGroup[MAXPLAYERS + 1];
int g_MenuTeam[MAXPLAYERS + 1];
int g_DefaultRestrictions[CSWeapon_MAX_WEAPONS][TEAM_INDEX_COUNT];
int g_PerPlayerLimits[CSWeapon_MAX_WEAPONS][MAXPLAYERS + 1];
float g_NextNotify[MAXPLAYERS + 1];
bool g_ClientHooked[MAXPLAYERS + 1];
bool g_PerPlayerReady;
bool g_ApplyingPerPlayer;
bool g_PerPlayerApplied;
bool g_PerPlayerDirty;
bool g_RestrictSoundReady;
int g_LastPickupNotifyRef[MAXPLAYERS + 1];
int g_LastPerPlayerCount = -1;
char g_ChatPrefix[32];
char g_RestrictSound[PLATFORM_MAX_PATH];

public Plugin myinfo =
{
	name = "Umbrella Weapon Restrict",
	author = "Ayrton09",
	description = "Weapon restriction plugin for CS:S and CS:GO",
	version = PLUGIN_VERSION,
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
	g_Engine = GetEngineVersion();
	if (g_Engine != Engine_CSS && g_Engine != Engine_CSGO)
	{
		strcopy(error, errMax, "Umbrella Weapon Restrict only supports CS:S and CS:GO.");
		return APLRes_Failure;
	}

	g_LateLoaded = late;
	g_MapStarted = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_WeaponIds = new ArrayList();
	g_WeaponIdCache = new StringMap();

	InitChatPrefix();
	InitPerPlayerStorage();
	LoadTranslations("umbrella_weapon_restrict.phrases");
	CreateCoreConVars();

	RegAdminCmd("sm_restrictmenu", Command_OpenMenu, ADMFLAG_CONVARS);
	RegAdminCmd("sm_wrmenu", Command_OpenMenu, ADMFLAG_CONVARS);
	RegAdminCmd("sm_restrict", Command_Restrict, ADMFLAG_CONVARS);
	RegAdminCmd("sm_unrestrict", Command_Unrestrict, ADMFLAG_CONVARS);
	RegAdminCmd("sm_remove_restricted", Command_RemoveRestricted, ADMFLAG_CONVARS);

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_PostNoCopy);

	if (LibraryExists("adminmenu"))
	{
		TopMenu topmenu = GetAdminTopMenu();
		if (topmenu != null)
		{
			OnAdminMenuReady(topmenu);
		}
	}

	if (g_LateLoaded)
	{
		CreateTimer(0.1, Timer_LateLoad, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

void InitChatPrefix()
{
	if (g_Engine == Engine_CSS)
	{
		Format(g_ChatPrefix, sizeof(g_ChatPrefix), "\x07%s[UWR]\x04 ", "CC3333");
		return;
	}

	strcopy(g_ChatPrefix, sizeof(g_ChatPrefix), "\x02[UWR]\x04 ");
}

public void OnMapStart()
{
	g_MapStarted = true;
	ResetAllPickupNotify();
	EnsureWeaponCvars();
	CacheRestrictSound();
	QueueEnforce();
}

public void OnConfigsExecuted()
{
	RefreshRuntimeConfiguration();
	QueueEnforce();
}

public void OnMapEnd()
{
	RestorePerPlayerDefaultsIfApplied();
	g_MapStarted = false;
}

public void OnClientPutInServer(int client)
{
	HookClient(client);
	g_MenuGroup[client] = WEAPON_GROUP_INVALID;
	g_MenuWeapon[client] = 0;
	g_MenuTeam[client] = TEAM_BOTH;
	g_NextNotify[client] = 0.0;
	g_LastPickupNotifyRef[client] = INVALID_ENT_REFERENCE;
	ApplyPerPlayerRestrictions();
}

public void OnClientDisconnect(int client)
{
	g_ClientHooked[client] = false;
	g_MenuGroup[client] = WEAPON_GROUP_INVALID;
	g_MenuWeapon[client] = 0;
	g_MenuTeam[client] = TEAM_BOTH;
	g_NextNotify[client] = 0.0;
	g_LastPickupNotifyRef[client] = INVALID_ENT_REFERENCE;
}

public void OnClientDisconnect_Post(int client)
{
	ApplyPerPlayerRestrictions();
}

public void OnPluginEnd()
{
	RestorePerPlayerDefaultsIfApplied();

	for (int client = 1; client <= MaxClients; client++)
	{
		if (g_ClientHooked[client] && IsClientInGame(client))
		{
			SDKUnhook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);
		}

		g_ClientHooked[client] = false;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "adminmenu"))
	{
		g_AdminMenu = null;
	}
}

public void OnAdminMenuReady(Handle topmenu)
{
	TopMenu adminMenu = TopMenu.FromHandle(topmenu);
	if (adminMenu == g_AdminMenu)
	{
		return;
	}

	g_AdminMenu = adminMenu;

	TopMenuObject category = g_AdminMenu.FindCategory("umbrella_weapon_restrict");
	if (category == INVALID_TOPMENUOBJECT)
	{
		category = g_AdminMenu.AddCategory("umbrella_weapon_restrict", AdminMenu_Category);
	}

	if (category == INVALID_TOPMENUOBJECT)
	{
		return;
	}

	g_AdminMenu.AddItem("umbrella_weapon_restrict_menu", AdminMenu_OpenMenu, category, "sm_restrictmenu", ADMFLAG_CONVARS);
}

public void AdminMenu_Category(TopMenu topmenu, TopMenuAction action, TopMenuObject objectId, int client, char[] buffer, int maxLength)
{
	int target = GetTranslationTarget(client);
	switch (action)
	{
		case TopMenuAction_DisplayTitle:
		{
			Format(buffer, maxLength, "%T", "Weapon Restriction Menu Title", target);
		}
		case TopMenuAction_DisplayOption:
		{
			Format(buffer, maxLength, "%T", "Weapon Restriction Menu Title", target);
		}
	}
}

public void AdminMenu_OpenMenu(TopMenu topmenu, TopMenuAction action, TopMenuObject objectId, int client, char[] buffer, int maxLength)
{
	int target = GetTranslationTarget(client);
	switch (action)
	{
		case TopMenuAction_DisplayOption:
		{
			Format(buffer, maxLength, "%T", "Configure Restrictions", target);
		}
		case TopMenuAction_SelectOption:
		{
			DisplayWeaponMenu(client);
		}
	}
}

public Action Timer_LateLoad(Handle timer)
{
	EnsureWeaponCvars();

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			HookClient(client);
		}
	}

	ExecConfigIfExists();
	CreateTimer(0.2, Timer_LateConfigRefresh, _, TIMER_FLAG_NO_MAPCHANGE);
	g_LateLoaded = false;
	return Plugin_Stop;
}

public Action Timer_LateConfigRefresh(Handle timer)
{
	RefreshRuntimeConfiguration();
	QueueEnforce();
	return Plugin_Stop;
}

void RefreshRuntimeConfiguration()
{
	EnsureWeaponCvars();
	RestorePerPlayerDefaultsIfApplied();
	RefreshDefaultRestrictions();
	LoadPerPlayerConfig();
	CacheRestrictSound();
	ApplyPerPlayerRestrictions();
}

void ResetAllPickupNotify()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		g_LastPickupNotifyRef[client] = INVALID_ENT_REFERENCE;
	}
}

void HookClient(int client)
{
	if (g_ClientHooked[client])
	{
		return;
	}

	SDKHook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse);
	g_ClientHooked[client] = true;
}

void ExecConfigIfExists()
{
	char configPath[PLATFORM_MAX_PATH];
	Format(configPath, sizeof(configPath), "cfg/sourcemod/%s.cfg", CONFIG_NAME);
	if (!FileExists(configPath))
	{
		return;
	}

	ServerCommand("exec sourcemod/%s.cfg", CONFIG_NAME);
}

void CreateCoreConVars()
{
	g_CvarEnabled = CreateConVar("sm_uwr_enabled", "1", "", _, true, 0.0, true, 1.0);
	g_CvarAllowPickup = CreateConVar("sm_uwr_allow_restricted_pickup", "0", "", _, true, 0.0, true, 1.0);
	g_CvarAdminImmunity = CreateConVar("sm_uwr_admin_immunity", "0", "", _, true, 0.0, true, 1.0);
	g_CvarNotify = CreateConVar("sm_uwr_notify", "1", "", _, true, 0.0, true, 1.0);
	g_CvarRestrictSound = CreateConVar("sm_uwr_restricted_sound", DEFAULT_RESTRICT_SOUND, "");
	g_CvarPerPlayerEnabled = CreateConVar("sm_uwr_perplayer_enabled", "0", "", _, true, 0.0, true, 1.0);
	g_CvarPerPlayerBots = CreateConVar("sm_uwr_perplayer_count_bots", "1", "", _, true, 0.0, true, 1.0);
	g_CvarPerPlayerSpecs = CreateConVar("sm_uwr_perplayer_count_specs", "1", "", _, true, 0.0, true, 1.0);
	g_CvarVersion = CreateConVar("sm_umbrella_weaponrestrict_version", PLUGIN_VERSION, "", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_CvarVersion.SetString(PLUGIN_VERSION, true, false);

	g_CvarEnabled.AddChangeHook(OnCoreCvarChanged);
	g_CvarAllowPickup.AddChangeHook(OnCoreCvarChanged);
	g_CvarAdminImmunity.AddChangeHook(OnCoreCvarChanged);
	g_CvarNotify.AddChangeHook(OnCoreCvarChanged);
	g_CvarRestrictSound.AddChangeHook(OnCoreCvarChanged);
	g_CvarPerPlayerEnabled.AddChangeHook(OnCoreCvarChanged);
	g_CvarPerPlayerBots.AddChangeHook(OnCoreCvarChanged);
	g_CvarPerPlayerSpecs.AddChangeHook(OnCoreCvarChanged);
}

void EnsureWeaponCvars()
{
	if (g_WeaponCvarsReady || !g_MapStarted)
	{
		return;
	}

	g_WeaponIds.Clear();

	for (int rawId = 1; rawId < view_as<int>(CSWeapon_MAX_WEAPONS); rawId++)
	{
		CSWeaponID id = view_as<CSWeaponID>(rawId);
		if (!CS_IsValidWeaponID(id) || !ShouldManageWeapon(id))
		{
			continue;
		}

		char alias[64];
		if (CS_WeaponIDToAlias(id, alias, sizeof(alias)) <= 0 || alias[0] == '\0')
		{
			continue;
		}

		ToLowerString(alias);
		if (ShouldSkipAlias(alias))
		{
			continue;
		}

		g_WeaponIds.Push(rawId);
		CreateWeaponCvar(id, alias, TEAM_INDEX_T, "t");
		CreateWeaponCvar(id, alias, TEAM_INDEX_CT, "ct");
	}

	g_WeaponCvarsReady = true;
	AutoExecConfig(true, CONFIG_NAME);
}

void CreateWeaponCvar(CSWeaponID id, const char[] alias, int teamIndex, const char[] suffix)
{
	char cvarName[96];
	Format(cvarName, sizeof(cvarName), "sm_restrict_%s_%s", alias, suffix);

	int rawId = view_as<int>(id);
	g_RestrictCvars[rawId][teamIndex] = CreateConVar(cvarName, "-1", "", _, true, -1.0, true, 64.0);
	g_RestrictCvars[rawId][teamIndex].AddChangeHook(OnRestrictionCvarChanged);
	g_DefaultRestrictions[rawId][teamIndex] = -1;
}

public void OnCoreCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == g_CvarRestrictSound)
	{
		CacheRestrictSound();
		return;
	}

	if (convar == g_CvarPerPlayerEnabled || convar == g_CvarPerPlayerBots || convar == g_CvarPerPlayerSpecs)
	{
		g_PerPlayerDirty = true;
		g_LastPerPlayerCount = -1;
		ApplyPerPlayerRestrictions();
		return;
	}

	QueueEnforce();
}

public void OnRestrictionCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (g_ApplyingPerPlayer)
	{
		return;
	}

	SyncDefaultRestriction(convar);
	g_PerPlayerDirty = true;
	if (g_CvarPerPlayerEnabled != null && g_CvarPerPlayerEnabled.BoolValue)
	{
		ApplyPerPlayerRestrictions();
	}

	QueueEnforce();
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	ApplyPerPlayerRestrictions();
	QueueEnforce();
	return Plugin_Continue;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	ApplyPerPlayerRestrictions();
	return Plugin_Continue;
}

public Action Command_OpenMenu(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "%s %T", REPLY_PREFIX, "Command In Game Only", GetTranslationTarget(client));
		return Plugin_Handled;
	}

	DisplayWeaponMenu(client);
	return Plugin_Handled;
}

public Action Command_RemoveRestricted(int client, int args)
{
	EnsureWeaponCvars();
	EnforceRestrictions();
	ReplyToCommand(client, "%s %T", REPLY_PREFIX, "Restrictions Applied", GetTranslationTarget(client));
	return Plugin_Handled;
}

public Action Command_Restrict(int client, int args)
{
	if (args < 1 || args > 3)
	{
		ReplyToCommand(client, "%s %T", REPLY_PREFIX, "Restrict Usage", GetTranslationTarget(client));
		return Plugin_Handled;
	}

	char weapon[64];
	GetCmdArg(1, weapon, sizeof(weapon));

	int amount = 0;
	if (args >= 2)
	{
		char amountText[16];
		GetCmdArg(2, amountText, sizeof(amountText));
		if (!ParseLimit(amountText, amount))
		{
			ReplyToCommand(client, "%s %T", REPLY_PREFIX, "Invalid Amount", GetTranslationTarget(client));
			return Plugin_Handled;
		}
	}

	int team = TEAM_BOTH;
	if (args >= 3)
	{
		char teamText[16];
		GetCmdArg(3, teamText, sizeof(teamText));
		if (!ParseTeam(teamText, team))
		{
			ReplyToCommand(client, "%s %T", REPLY_PREFIX, "Invalid Team", GetTranslationTarget(client));
			return Plugin_Handled;
		}
	}

	ApplyRestrictionCommand(client, weapon, team, amount);
	return Plugin_Handled;
}

public Action Command_Unrestrict(int client, int args)
{
	if (args < 1 || args > 2)
	{
		ReplyToCommand(client, "%s %T", REPLY_PREFIX, "Unrestrict Usage", GetTranslationTarget(client));
		return Plugin_Handled;
	}

	char weapon[64];
	GetCmdArg(1, weapon, sizeof(weapon));

	int team = TEAM_BOTH;
	if (args == 2)
	{
		char teamText[16];
		GetCmdArg(2, teamText, sizeof(teamText));
		if (!ParseTeam(teamText, team))
		{
			ReplyToCommand(client, "%s %T", REPLY_PREFIX, "Invalid Team", GetTranslationTarget(client));
			return Plugin_Handled;
		}
	}

	ApplyRestrictionCommand(client, weapon, team, -1);
	return Plugin_Handled;
}

void ApplyRestrictionCommand(int client, const char[] weaponText, int team, int amount)
{
	EnsureWeaponCvars();

	if (StrEqual(weaponText, "all", false) || StrEqual(weaponText, "@all", false))
	{
		for (int i = 0; i < g_WeaponIds.Length; i++)
		{
			CSWeaponID id = view_as<CSWeaponID>(g_WeaponIds.Get(i));
			SetRestriction(id, team, amount);
		}

		char teamName[24];
		int target = GetTranslationTarget(client);
		GetTeamNameForCommand(team, target, teamName, sizeof(teamName));
		ReplyToCommand(client, "%s %T", REPLY_PREFIX, "All Weapons Restricted", target, teamName, amount);
		QueueEnforce();
		return;
	}

	int group = WEAPON_GROUP_INVALID;
	if (ParseWeaponGroup(weaponText, group))
	{
		if (ApplyGroupRestriction(group, team, amount) == 0)
		{
			ReplyToCommand(client, "%s %T", REPLY_PREFIX, "Invalid Weapon", GetTranslationTarget(client), weaponText);
			return;
		}

		char groupName[32];
		char teamName[24];
		int target = GetTranslationTarget(client);
		GetWeaponGroupName(group, target, groupName, sizeof(groupName));
		GetTeamNameForCommand(team, target, teamName, sizeof(teamName));
		ReplyToCommand(client, "%s %T", REPLY_PREFIX, "Weapon Group Restricted", target, groupName, teamName, amount);
		QueueEnforce();
		return;
	}

	CSWeaponID id = WeaponIdFromText(weaponText);
	if (!IsTrackedWeapon(id))
	{
		ReplyToCommand(client, "%s %T", REPLY_PREFIX, "Invalid Weapon", GetTranslationTarget(client), weaponText);
		return;
	}

	SetRestriction(id, team, amount);

	char alias[64];
	char teamName[24];
	int target = GetTranslationTarget(client);
	GetWeaponAlias(id, target, alias, sizeof(alias));
	GetTeamNameForCommand(team, target, teamName, sizeof(teamName));
	ReplyToCommand(client, "%s %T", REPLY_PREFIX, "Weapon Restricted", target, alias, teamName, amount);
	QueueEnforce();
}

void DisplayWeaponMenu(int client)
{
	EnsureWeaponCvars();

	Menu menu = new Menu(MenuHandler_Weapon);
	int target = GetTranslationTarget(client);
	menu.SetTitle("%T", "Weapon Restriction Menu Title", target);
	menu.ExitBackButton = (g_AdminMenu != null);

	char info[16];
	char display[128];
	char alias[64];

	Format(display, sizeof(display), "%T", "Weapon Groups Option", target);
	menu.AddItem("group", display);

	for (int i = 0; i < g_WeaponIds.Length; i++)
	{
		CSWeaponID id = view_as<CSWeaponID>(g_WeaponIds.Get(i));
		GetWeaponAlias(id, target, alias, sizeof(alias));
		FormatWeaponMenuLine(target, id, alias, display, sizeof(display));
		IntToString(view_as<int>(id), info, sizeof(info));
		menu.AddItem(info, display);
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Weapon(Menu menu, MenuAction action, int client, int item)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if (item == MenuCancel_ExitBack && g_AdminMenu != null)
			{
				DisplayTopMenu(g_AdminMenu, client, TopMenuPosition_LastCategory);
			}
		}
		case MenuAction_Select:
		{
			char info[16];
			menu.GetItem(item, info, sizeof(info));
			if (StrEqual(info, "group"))
			{
				DisplayGroupMenu(client);
				return 0;
			}

			g_MenuGroup[client] = WEAPON_GROUP_INVALID;
			g_MenuWeapon[client] = StringToInt(info);
			DisplayTeamMenu(client);
		}
	}

	return 0;
}

void DisplayGroupMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Group);
	int target = GetTranslationTarget(client);
	menu.SetTitle("%T", "Weapon Group Menu Title", target);
	menu.ExitBackButton = true;

	char info[16];
	char display[64];
	for (int group = 0; group < WEAPON_GROUP_COUNT; group++)
	{
		if (!GroupHasTrackedWeapons(group))
		{
			continue;
		}

		IntToString(group, info, sizeof(info));
		GetWeaponGroupName(group, target, display, sizeof(display));
		menu.AddItem(info, display);
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Group(Menu menu, MenuAction action, int client, int item)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if (item == MenuCancel_ExitBack)
			{
				DisplayWeaponMenu(client);
			}
		}
		case MenuAction_Select:
		{
			char info[16];
			menu.GetItem(item, info, sizeof(info));
			g_MenuGroup[client] = StringToInt(info);
			g_MenuWeapon[client] = 0;
			DisplayTeamMenu(client);
		}
	}

	return 0;
}

void DisplayTeamMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Team);
	int target = GetTranslationTarget(client);
	menu.SetTitle("%T", "Team Menu Title", target);
	menu.ExitBackButton = true;
	char display[64];
	Format(display, sizeof(display), "%T", "Team Terrorists", target);
	menu.AddItem("2", display);
	Format(display, sizeof(display), "%T", "Team Counter Terrorists", target);
	menu.AddItem("3", display);
	Format(display, sizeof(display), "%T", "Team Both", target);
	menu.AddItem("0", display);
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Team(Menu menu, MenuAction action, int client, int item)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if (item == MenuCancel_ExitBack)
			{
				if (g_MenuGroup[client] != WEAPON_GROUP_INVALID)
				{
					DisplayGroupMenu(client);
				}
				else
				{
					DisplayWeaponMenu(client);
				}
			}
		}
		case MenuAction_Select:
		{
			char info[16];
			menu.GetItem(item, info, sizeof(info));
			g_MenuTeam[client] = StringToInt(info);
			DisplayAmountMenu(client);
		}
	}

	return 0;
}

void DisplayAmountMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Amount);
	int target = GetTranslationTarget(client);
	menu.SetTitle("%T", "Limit Menu Title", target);
	menu.ExitBackButton = true;
	char display[64];
	Format(display, sizeof(display), "%T", "Unlimited Option", target);
	menu.AddItem("-1", display);
	Format(display, sizeof(display), "%T", "Blocked Option", target);
	menu.AddItem("0", display);

	char amount[16];
	for (int i = 1; i <= MaxClients && i <= 64; i++)
	{
		IntToString(i, amount, sizeof(amount));
		menu.AddItem(amount, amount);
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Amount(Menu menu, MenuAction action, int client, int item)
{
	switch (action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if (item == MenuCancel_ExitBack)
			{
				DisplayTeamMenu(client);
			}
		}
		case MenuAction_Select:
		{
			char info[16];
			menu.GetItem(item, info, sizeof(info));
			int amount = StringToInt(info);
			int team = g_MenuTeam[client];
			int group = g_MenuGroup[client];
			CSWeaponID id = view_as<CSWeaponID>(g_MenuWeapon[client]);
			if ((group == WEAPON_GROUP_INVALID && !IsTrackedWeapon(id)) || (group != WEAPON_GROUP_INVALID && !IsValidWeaponGroup(group)) || (team != TEAM_BOTH && team != CS_TEAM_T && team != CS_TEAM_CT))
			{
				PrintToChat(client, "%s%T", g_ChatPrefix, "Invalid Selection", GetTranslationTarget(client));
				DisplayWeaponMenu(client);
				return 0;
			}

			if (group != WEAPON_GROUP_INVALID)
			{
				if (ApplyGroupRestriction(group, team, amount) == 0)
				{
					PrintToChat(client, "%s%T", g_ChatPrefix, "Invalid Selection", GetTranslationTarget(client));
					DisplayWeaponMenu(client);
					return 0;
				}
			}
			else
			{
				SetRestriction(id, team, amount);
			}

			QueueEnforce();

			int target = GetTranslationTarget(client);
			char teamName[24];
			GetTeamNameForCommand(team, target, teamName, sizeof(teamName));
			if (group != WEAPON_GROUP_INVALID)
			{
				char groupName[32];
				GetWeaponGroupName(group, target, groupName, sizeof(groupName));
				PrintToChat(client, "%s%T", g_ChatPrefix, "Weapon Group Restricted", target, groupName, teamName, amount);
			}
			else
			{
				char alias[64];
				GetWeaponAlias(id, target, alias, sizeof(alias));
				PrintToChat(client, "%s%T", g_ChatPrefix, "Weapon Restricted", target, alias, teamName, amount);
			}

			DisplayWeaponMenu(client);
		}
	}

	return 0;
}

public Action CS_OnBuyCommand(int client, const char[] weapon)
{
	if (!CanEvaluateClient(client))
	{
		return Plugin_Continue;
	}

	CSWeaponID id = WeaponIdFromText(weapon);
	if (!IsTrackedWeapon(id))
	{
		return Plugin_Continue;
	}

	if (IsClientImmune(client))
	{
		return Plugin_Continue;
	}

	int team = GetClientTeam(client);
	if (CanAddWeaponToTeam(client, team, id))
	{
		return Plugin_Continue;
	}

	NotifyRestricted(client, id, GetRestriction(id, team));
	return Plugin_Handled;
}

public Action Hook_WeaponCanUse(int client, int weapon)
{
	if (!CanEvaluateClient(client) || g_CvarAllowPickup.BoolValue || IsClientImmune(client))
	{
		return Plugin_Continue;
	}

	CSWeaponID id = WeaponIdFromEntity(weapon);
	if (!IsTrackedWeapon(id))
	{
		return Plugin_Continue;
	}

	int team = GetClientTeam(client);
	if (CanAddWeaponToTeam(client, team, id))
	{
		return Plugin_Continue;
	}

	NotifyRestricted(client, id, GetRestriction(id, team), EntIndexToEntRef(weapon));
	return Plugin_Handled;
}

bool CanEvaluateClient(int client)
{
	if (!g_CvarEnabled.BoolValue || !IsClientInGame(client) || GetClientTeam(client) < CS_TEAM_T)
	{
		return false;
	}

	return true;
}

bool CanAddWeaponToTeam(int client, int team, CSWeaponID id)
{
	int limit = GetRestriction(id, team);
	if (limit < 0)
	{
		return true;
	}

	if (limit == 0)
	{
		return false;
	}

	if (!IsStackableWeapon(id) && PlayerHasWeapon(client, id))
	{
		return true;
	}

	return CountTeamWeapons(team, id) < limit;
}

bool IsClientImmune(int client)
{
	return g_CvarAdminImmunity.BoolValue && CheckCommandAccess(client, "umbrella_weapon_restrict_immunity", ADMFLAG_ROOT);
}

void InitPerPlayerStorage()
{
	for (int rawId = 0; rawId < view_as<int>(CSWeapon_MAX_WEAPONS); rawId++)
	{
		for (int teamIndex = 0; teamIndex < TEAM_INDEX_COUNT; teamIndex++)
		{
			g_DefaultRestrictions[rawId][teamIndex] = -1;
		}

		for (int count = 0; count <= MAXPLAYERS; count++)
		{
			g_PerPlayerLimits[rawId][count] = PERPLAYER_UNSET;
		}
	}
}

void RefreshDefaultRestrictions()
{
	if (!g_WeaponCvarsReady)
	{
		return;
	}

	for (int i = 0; i < g_WeaponIds.Length; i++)
	{
		int rawId = g_WeaponIds.Get(i);
		for (int teamIndex = 0; teamIndex < TEAM_INDEX_COUNT; teamIndex++)
		{
			if (g_RestrictCvars[rawId][teamIndex] != null)
			{
				g_DefaultRestrictions[rawId][teamIndex] = g_RestrictCvars[rawId][teamIndex].IntValue;
			}
		}
	}
}

void SyncDefaultRestriction(ConVar convar)
{
	for (int i = 0; i < g_WeaponIds.Length; i++)
	{
		int rawId = g_WeaponIds.Get(i);
		for (int teamIndex = 0; teamIndex < TEAM_INDEX_COUNT; teamIndex++)
		{
			if (g_RestrictCvars[rawId][teamIndex] == convar)
			{
				g_DefaultRestrictions[rawId][teamIndex] = convar.IntValue;
				return;
			}
		}
	}
}

void ResetPerPlayerLimits()
{
	for (int rawId = 0; rawId < view_as<int>(CSWeapon_MAX_WEAPONS); rawId++)
	{
		for (int count = 0; count <= MAXPLAYERS; count++)
		{
			g_PerPlayerLimits[rawId][count] = PERPLAYER_UNSET;
		}
	}
}

void LoadPerPlayerConfig()
{
	ResetPerPlayerLimits();
	g_PerPlayerReady = false;
	g_PerPlayerDirty = true;
	g_LastPerPlayerCount = -1;

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), PERPLAYER_CONFIG);
	if (!FileExists(path))
	{
		return;
	}

	KeyValues kv = new KeyValues("PerPlayer");
	if (!kv.ImportFromFile(path))
	{
		delete kv;
		LogError("Failed to parse %s", PERPLAYER_CONFIG);
		return;
	}

	if (kv.GotoFirstSubKey())
	{
		do
		{
			char section[64];
			kv.GetSectionName(section, sizeof(section));

			CSWeaponID id = WeaponIdFromText(section);
			if (!IsTrackedWeapon(id))
			{
				LogError("Invalid per-player weapon section: %s", section);
				continue;
			}

			int rawId = view_as<int>(id);
			int current = ClampLimit(kv.GetNum("default", -1));
			int lastIndex = 0;

			for (int threshold = 0; threshold <= MAXPLAYERS; threshold++)
			{
				char key[8];
				IntToString(threshold, key, sizeof(key));
				int next = kv.GetNum(key, PERPLAYER_INVALID);
				if (next == PERPLAYER_INVALID)
				{
					continue;
				}

				for (int count = lastIndex; count < threshold && count <= MAXPLAYERS; count++)
				{
					g_PerPlayerLimits[rawId][count] = current;
				}

				lastIndex = threshold;
				current = ClampLimit(next);
			}

			for (int count = lastIndex; count <= MAXPLAYERS; count++)
			{
				g_PerPlayerLimits[rawId][count] = current;
			}
		}
		while (kv.GotoNextKey());
	}

	delete kv;
	g_PerPlayerReady = true;
}

void ApplyPerPlayerRestrictions()
{
	if (!g_WeaponCvarsReady || g_CvarPerPlayerEnabled == null)
	{
		return;
	}

	g_ApplyingPerPlayer = true;
	if (!g_CvarPerPlayerEnabled.BoolValue)
	{
		if (g_PerPlayerApplied)
		{
			RestorePerPlayerDefaultsIfApplied();
			QueueEnforce();
		}

		g_PerPlayerApplied = false;
		g_PerPlayerDirty = false;
		g_LastPerPlayerCount = -1;
		g_ApplyingPerPlayer = false;
		return;
	}

	if (!g_PerPlayerReady)
	{
		if (g_PerPlayerApplied)
		{
			RestorePerPlayerDefaultsIfApplied();
			QueueEnforce();
		}

		g_PerPlayerApplied = false;
		g_PerPlayerDirty = false;
		g_LastPerPlayerCount = -1;
		g_ApplyingPerPlayer = false;
		return;
	}

	int playerCount = GetPerPlayerCount();
	if (g_PerPlayerApplied && !g_PerPlayerDirty && g_LastPerPlayerCount == playerCount)
	{
		g_ApplyingPerPlayer = false;
		return;
	}

	if (g_PerPlayerApplied)
	{
		RestorePerPlayerDefaultsIfApplied();
	}

	bool appliedAny = false;
	for (int i = 0; i < g_WeaponIds.Length; i++)
	{
		CSWeaponID id = view_as<CSWeaponID>(g_WeaponIds.Get(i));
		int rawId = view_as<int>(id);
		if (g_PerPlayerLimits[rawId][0] == PERPLAYER_UNSET)
		{
			continue;
		}

		SetRestriction(id, TEAM_BOTH, g_PerPlayerLimits[rawId][playerCount]);
		appliedAny = true;
	}

	g_LastPerPlayerCount = playerCount;
	g_PerPlayerDirty = false;
	g_ApplyingPerPlayer = false;
	g_PerPlayerApplied = appliedAny;
	QueueEnforce();
}

void RestoreDefaultRestrictions()
{
	for (int i = 0; i < g_WeaponIds.Length; i++)
	{
		int rawId = g_WeaponIds.Get(i);
		for (int teamIndex = 0; teamIndex < TEAM_INDEX_COUNT; teamIndex++)
		{
			if (g_RestrictCvars[rawId][teamIndex] != null)
			{
				g_RestrictCvars[rawId][teamIndex].SetInt(g_DefaultRestrictions[rawId][teamIndex]);
			}
		}
	}
}

void RestorePerPlayerDefaultsIfApplied()
{
	if (!g_PerPlayerApplied || !g_WeaponCvarsReady)
	{
		return;
	}

	bool wasApplying = g_ApplyingPerPlayer;
	g_ApplyingPerPlayer = true;
	RestoreDefaultRestrictions();
	g_ApplyingPerPlayer = wasApplying;

	g_PerPlayerApplied = false;
	g_PerPlayerDirty = true;
	g_LastPerPlayerCount = -1;
}

int GetPerPlayerCount()
{
	int count = 0;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
		{
			continue;
		}

		if (!g_CvarPerPlayerBots.BoolValue && IsFakeClient(client))
		{
			continue;
		}

		if (!g_CvarPerPlayerSpecs.BoolValue && GetClientTeam(client) < CS_TEAM_T)
		{
			continue;
		}

		count++;
	}

	return count;
}

int ClampLimit(int amount)
{
	if (amount < -1)
	{
		return -1;
	}

	if (amount > 64)
	{
		return 64;
	}

	return amount;
}

void CacheRestrictSound()
{
	g_RestrictSoundReady = false;
	g_RestrictSound[0] = '\0';

	if (g_CvarRestrictSound == null)
	{
		return;
	}

	char configured[PLATFORM_MAX_PATH];
	g_CvarRestrictSound.GetString(configured, sizeof(configured));
	TrimString(configured);
	if (configured[0] == '\0')
	{
		return;
	}

	if (!IsSafeSoundPath(configured))
	{
		LogError("Unsafe restrict sound path rejected: %s", configured);
		return;
	}

	char downloadPath[PLATFORM_MAX_PATH];
	strcopy(downloadPath, sizeof(downloadPath), configured);

	if (StrContains(configured, "sound/", false) == 0)
	{
		if (configured[6] == '\0')
		{
			LogError("Restrict sound path is empty after sound/ prefix.");
			return;
		}

		strcopy(g_RestrictSound, sizeof(g_RestrictSound), configured[6]);
	}
	else
	{
		strcopy(g_RestrictSound, sizeof(g_RestrictSound), configured);
		Format(downloadPath, sizeof(downloadPath), "sound/%s", configured);
	}

	if (!FileExists(downloadPath, true))
	{
		LogError("Restrict sound does not exist: %s", downloadPath);
		g_RestrictSound[0] = '\0';
		return;
	}

	AddFileToDownloadsTable(downloadPath);
	if (!PrecacheSound(g_RestrictSound, true))
	{
		LogError("Failed to precache restrict sound: %s", g_RestrictSound);
		g_RestrictSound[0] = '\0';
		return;
	}

	g_RestrictSoundReady = true;
}

bool IsSafeSoundPath(const char[] path)
{
	if (path[0] == '\0' || path[0] == '/' || path[0] == '\\')
	{
		return false;
	}

	if (StrContains(path, "\\", false) != -1 || StrContains(path, "//", false) != -1 || StrContains(path, ":", false) != -1 || StrContains(path, "..", false) != -1)
	{
		return false;
	}

	return true;
}

void PlayRestrictSound(int client)
{
	if (!g_RestrictSoundReady || g_RestrictSound[0] == '\0' || !IsClientInGame(client))
	{
		return;
	}

	EmitSoundToClient(client, g_RestrictSound);
}

void QueueEnforce()
{
	if (g_EnforceQueued)
	{
		return;
	}

	g_EnforceQueued = true;
	CreateTimer(0.1, Timer_Enforce, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Enforce(Handle timer)
{
	g_EnforceQueued = false;
	EnforceRestrictions();
	return Plugin_Stop;
}

void EnforceRestrictions()
{
	if (!g_WeaponCvarsReady || !g_CvarEnabled.BoolValue)
	{
		return;
	}

	bool immune[MAXPLAYERS + 1];
	for (int client = 1; client <= MaxClients; client++)
	{
		immune[client] = IsClientInGame(client) && IsClientImmune(client);
	}

	for (int i = 0; i < g_WeaponIds.Length; i++)
	{
		CSWeaponID id = view_as<CSWeaponID>(g_WeaponIds.Get(i));
		EnforceWeaponTeam(id, CS_TEAM_T, immune);
		EnforceWeaponTeam(id, CS_TEAM_CT, immune);
	}
}

void EnforceWeaponTeam(CSWeaponID id, int team, const bool[] immune)
{
	int limit = GetRestriction(id, team);
	if (limit < 0)
	{
		return;
	}

	int remaining = limit;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || GetClientTeam(client) != team || immune[client])
		{
			continue;
		}

		EnforceClientWeaponLimit(client, id, remaining);
	}
}

bool PlayerHasWeapon(int client, CSWeaponID id)
{
	return CountClientWeapons(client, id) > 0;
}

int CountClientWeapons(int client, CSWeaponID id)
{
	if (ClientHasSpecialItem(client, id))
	{
		return 1;
	}

	if (!IsClientInGame(client) || !HasEntProp(client, Prop_Send, "m_hMyWeapons"))
	{
		return 0;
	}

	int count = 0;
	int weaponCount = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for (int i = 0; i < weaponCount; i++)
	{
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if (weapon > MaxClients && IsValidEntity(weapon) && WeaponIdFromEntity(weapon) == id)
		{
			count++;
		}
	}

	return count;
}

int CountTeamWeapons(int team, CSWeaponID id)
{
	int count = 0;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || GetClientTeam(client) != team || IsClientImmune(client))
		{
			continue;
		}

		count += CountClientWeapons(client, id);
	}

	return count;
}

void EnforceClientWeaponLimit(int client, CSWeaponID id, int &remaining)
{
	if (IsSpecialItem(id))
	{
		if (!ClientHasSpecialItem(client, id))
		{
			return;
		}

		if (remaining > 0)
		{
			remaining--;
			return;
		}

		RemoveClientSpecialItem(client, id);
		return;
	}

	if (!HasEntProp(client, Prop_Send, "m_hMyWeapons"))
	{
		return;
	}

	int weaponCount = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for (int i = 0; i < weaponCount; i++)
	{
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if (weapon <= MaxClients || !IsValidEntity(weapon) || WeaponIdFromEntity(weapon) != id)
		{
			continue;
		}

		if (remaining > 0)
		{
			remaining--;
			continue;
		}

		RemovePlayerItem(client, weapon);
		AcceptEntityInput(weapon, "Kill");
	}
}

CSWeaponID WeaponIdFromEntity(int entity)
{
	if (entity <= MaxClients || !IsValidEntity(entity))
	{
		return CSWeapon_NONE;
	}

	char classname[64];
	if (!GetEntityClassname(entity, classname, sizeof(classname)))
	{
		return CSWeapon_NONE;
	}

	int cached;
	if (g_WeaponIdCache.GetValue(classname, cached))
	{
		return view_as<CSWeaponID>(cached);
	}

	CSWeaponID id = WeaponIdFromText(classname);
	g_WeaponIdCache.SetValue(classname, view_as<int>(id));
	return id;
}

CSWeaponID WeaponIdFromText(const char[] text)
{
	char alias[64];
	NormalizeWeaponText(text, alias, sizeof(alias));
	if (alias[0] == '\0')
	{
		return CSWeapon_NONE;
	}

	return CS_AliasToWeaponID(alias);
}

void NormalizeWeaponText(const char[] text, char[] alias, int maxLength)
{
	char translated[64];
	CS_GetTranslatedWeaponAlias(text, translated, sizeof(translated));
	strcopy(alias, maxLength, translated);
	TrimString(alias);
	ToLowerString(alias);

	if (StrContains(alias, "weapon_", false) == 0)
	{
		StripAliasPrefix(alias, maxLength, 7);
	}
	else if (StrContains(alias, "item_", false) == 0)
	{
		StripAliasPrefix(alias, maxLength, 5);
	}
}

void StripAliasPrefix(char[] alias, int maxLength, int prefixLength)
{
	char stripped[64];
	strcopy(stripped, sizeof(stripped), alias[prefixLength]);
	strcopy(alias, maxLength, stripped);
}

void ToLowerString(char[] text)
{
	for (int i = 0; text[i] != '\0'; i++)
	{
		text[i] = CharToLower(text[i]);
	}
}

bool ShouldManageWeapon(CSWeaponID id)
{
	switch (id)
	{
		case CSWeapon_KNIFE,
			 CSWeapon_KNIFE_GG,
			 CSWeapon_KNIFE_T,
			 CSWeapon_KNIFE_GHOST,
			 CSWeapon_C4,
			 CSWeapon_NIGHTVISION,
			 CSWeapon_DEFUSER,
			 CSWeapon_CUTTERS,
			 CSWeapon_HEALTHSHOT,
			 CSWeapon_TABLET:
		{
			return false;
		}
	}

	return view_as<int>(id) < 500;
}

bool ShouldSkipAlias(const char[] alias)
{
	return StrContains(alias, "knife", false) == 0 || StrEqual(alias, "bayonet", false);
}

bool IsStackableWeapon(CSWeaponID id)
{
	switch (id)
	{
		case CSWeapon_HEGRENADE,
			 CSWeapon_SMOKEGRENADE,
			 CSWeapon_FLASHBANG,
			 CSWeapon_MOLOTOV,
			 CSWeapon_DECOY,
			 CSWeapon_INCGRENADE,
			 CSWeapon_TAGGRENADE,
			 CSWeapon_BREACHCHARGE,
			 CSWeapon_FIREBOMB,
			 CSWeapon_DIVERSION,
			 CSWeapon_FRAGGRENADE,
			 CSWeapon_SNOWBALL,
			 CSWeapon_BUMPMINE:
		{
			return true;
		}
	}

	return false;
}

bool IsSpecialItem(CSWeaponID id)
{
	switch (id)
	{
		case CSWeapon_KEVLAR,
			 CSWeapon_ASSAULTSUIT,
			 CSWeapon_HEAVYASSAULTSUIT:
		{
			return true;
		}
	}

	return false;
}

bool ClientHasSpecialItem(int client, CSWeaponID id)
{
	if (!IsClientInGame(client))
	{
		return false;
	}

	switch (id)
	{
		case CSWeapon_KEVLAR:
		{
			return GetClientSendPropInt(client, "m_ArmorValue") > 0 && GetClientSendPropInt(client, "m_bHasHelmet") == 0;
		}
		case CSWeapon_ASSAULTSUIT:
		{
			return GetClientSendPropInt(client, "m_ArmorValue") > 0 && GetClientSendPropInt(client, "m_bHasHelmet") != 0;
		}
		case CSWeapon_HEAVYASSAULTSUIT:
		{
			return GetClientSendPropInt(client, "m_bHasHeavyArmor") != 0;
		}
	}

	return false;
}

void RemoveClientSpecialItem(int client, CSWeaponID id)
{
	switch (id)
	{
		case CSWeapon_KEVLAR:
		{
			if (GetClientSendPropInt(client, "m_bHasHelmet") == 0)
			{
				SetClientSendPropIntIfExists(client, "m_ArmorValue", 0);
			}
		}
		case CSWeapon_ASSAULTSUIT:
		{
			SetClientSendPropIntIfExists(client, "m_ArmorValue", 0);
			SetClientSendPropIntIfExists(client, "m_bHasHelmet", 0);
		}
		case CSWeapon_HEAVYASSAULTSUIT:
		{
			SetClientSendPropIntIfExists(client, "m_bHasHeavyArmor", 0);
		}
	}
}

int GetClientSendPropInt(int client, const char[] propName)
{
	if (!HasEntProp(client, Prop_Send, propName))
	{
		return 0;
	}

	return GetEntProp(client, Prop_Send, propName);
}

void SetClientSendPropIntIfExists(int client, const char[] propName, int value)
{
	if (HasEntProp(client, Prop_Send, propName))
	{
		SetEntProp(client, Prop_Send, propName, value);
	}
}

bool IsTrackedWeapon(CSWeaponID id)
{
	int rawId = view_as<int>(id);
	if (rawId <= 0 || rawId >= view_as<int>(CSWeapon_MAX_WEAPONS))
	{
		return false;
	}

	return g_RestrictCvars[rawId][TEAM_INDEX_T] != null || g_RestrictCvars[rawId][TEAM_INDEX_CT] != null;
}

void SetRestriction(CSWeaponID id, int team, int amount)
{
	if (!IsTrackedWeapon(id))
	{
		return;
	}

	int rawId = view_as<int>(id);
	if ((team == TEAM_BOTH || team == CS_TEAM_T) && g_RestrictCvars[rawId][TEAM_INDEX_T] != null)
	{
		g_RestrictCvars[rawId][TEAM_INDEX_T].SetInt(amount);
	}

	if ((team == TEAM_BOTH || team == CS_TEAM_CT) && g_RestrictCvars[rawId][TEAM_INDEX_CT] != null)
	{
		g_RestrictCvars[rawId][TEAM_INDEX_CT].SetInt(amount);
	}
}

int GetRestriction(CSWeaponID id, int team)
{
	int teamIndex = TeamToIndex(team);
	if (teamIndex == -1)
	{
		return -1;
	}

	int rawId = view_as<int>(id);
	if (rawId <= 0 || rawId >= view_as<int>(CSWeapon_MAX_WEAPONS) || g_RestrictCvars[rawId][teamIndex] == null)
	{
		return -1;
	}

	return g_RestrictCvars[rawId][teamIndex].IntValue;
}

int ApplyGroupRestriction(int group, int team, int amount)
{
	int applied = 0;
	for (int i = 0; i < g_WeaponIds.Length; i++)
	{
		CSWeaponID id = view_as<CSWeaponID>(g_WeaponIds.Get(i));
		if (GetWeaponGroup(id) == group)
		{
			SetRestriction(id, team, amount);
			applied++;
		}
	}

	return applied;
}

bool GroupHasTrackedWeapons(int group)
{
	for (int i = 0; i < g_WeaponIds.Length; i++)
	{
		CSWeaponID id = view_as<CSWeaponID>(g_WeaponIds.Get(i));
		if (GetWeaponGroup(id) == group)
		{
			return true;
		}
	}

	return false;
}

int GetWeaponGroup(CSWeaponID id)
{
	switch (id)
	{
		case CSWeapon_P228,
			 CSWeapon_GLOCK,
			 CSWeapon_ELITE,
			 CSWeapon_FIVESEVEN,
			 CSWeapon_USP,
			 CSWeapon_DEAGLE,
			 CSWeapon_TEC9,
			 CSWeapon_HKP2000,
			 CSWeapon_P250,
			 CSWeapon_USP_SILENCER,
			 CSWeapon_CZ75A,
			 CSWeapon_REVOLVER:
		{
			return WEAPON_GROUP_PISTOLS;
		}
		case CSWeapon_MAC10,
			 CSWeapon_UMP45,
			 CSWeapon_MP5NAVY,
			 CSWeapon_TMP,
			 CSWeapon_P90,
			 CSWeapon_BIZON,
			 CSWeapon_MP7,
			 CSWeapon_MP9:
		{
			return WEAPON_GROUP_SMGS;
		}
		case CSWeapon_XM1014,
			 CSWeapon_M3,
			 CSWeapon_MAG7,
			 CSWeapon_SAWEDOFF,
			 CSWeapon_NOVA:
		{
			return WEAPON_GROUP_SHOTGUNS;
		}
		case CSWeapon_AUG,
			 CSWeapon_GALIL,
			 CSWeapon_FAMAS,
			 CSWeapon_M4A1,
			 CSWeapon_SG552,
			 CSWeapon_AK47,
			 CSWeapon_GALILAR,
			 CSWeapon_M4A1_SILENCER,
			 CSWeapon_SG556,
			 CSWeapon_M249,
			 CSWeapon_NEGEV:
		{
			return WEAPON_GROUP_RIFLES;
		}
		case CSWeapon_SCOUT,
			 CSWeapon_SG550,
			 CSWeapon_AWP,
			 CSWeapon_G3SG1,
			 CSWeapon_SCAR17,
			 CSWeapon_SCAR20,
			 CSWeapon_SSG08:
		{
			return WEAPON_GROUP_SNIPERS;
		}
		case CSWeapon_HEGRENADE,
			 CSWeapon_SMOKEGRENADE,
			 CSWeapon_FLASHBANG,
			 CSWeapon_MOLOTOV,
			 CSWeapon_DECOY,
			 CSWeapon_INCGRENADE,
			 CSWeapon_TAGGRENADE,
			 CSWeapon_BREACHCHARGE,
			 CSWeapon_FIREBOMB,
			 CSWeapon_DIVERSION,
			 CSWeapon_FRAGGRENADE,
			 CSWeapon_SNOWBALL,
			 CSWeapon_BUMPMINE:
		{
			return WEAPON_GROUP_GRENADES;
		}
		case CSWeapon_KEVLAR,
			 CSWeapon_ASSAULTSUIT,
			 CSWeapon_HEAVYASSAULTSUIT:
		{
			return WEAPON_GROUP_ARMOR;
		}
	}

	return WEAPON_GROUP_INVALID;
}

bool IsValidWeaponGroup(int group)
{
	return group >= 0 && group < WEAPON_GROUP_COUNT;
}

bool ParseWeaponGroup(const char[] text, int &group)
{
	char normalized[32];
	strcopy(normalized, sizeof(normalized), text);
	TrimString(normalized);
	ToLowerString(normalized);

	if (StrEqual(normalized, "pistol") || StrEqual(normalized, "pistols"))
	{
		group = WEAPON_GROUP_PISTOLS;
		return true;
	}
	if (StrEqual(normalized, "smg") || StrEqual(normalized, "smgs"))
	{
		group = WEAPON_GROUP_SMGS;
		return true;
	}
	if (StrEqual(normalized, "shotgun") || StrEqual(normalized, "shotguns"))
	{
		group = WEAPON_GROUP_SHOTGUNS;
		return true;
	}
	if (StrEqual(normalized, "rifle") || StrEqual(normalized, "rifles"))
	{
		group = WEAPON_GROUP_RIFLES;
		return true;
	}
	if (StrEqual(normalized, "sniper") || StrEqual(normalized, "snipers"))
	{
		group = WEAPON_GROUP_SNIPERS;
		return true;
	}
	if (StrEqual(normalized, "grenade") || StrEqual(normalized, "grenades"))
	{
		group = WEAPON_GROUP_GRENADES;
		return true;
	}
	if (StrEqual(normalized, "armor") || StrEqual(normalized, "armour"))
	{
		group = WEAPON_GROUP_ARMOR;
		return true;
	}

	group = WEAPON_GROUP_INVALID;
	return false;
}

int TeamToIndex(int team)
{
	if (team == CS_TEAM_T)
	{
		return TEAM_INDEX_T;
	}

	if (team == CS_TEAM_CT)
	{
		return TEAM_INDEX_CT;
	}

	return -1;
}

bool ParseLimit(const char[] text, int &amount)
{
	int read = StringToIntEx(text, amount);
	if (read != strlen(text))
	{
		return false;
	}

	return amount >= -1 && amount <= 64;
}

bool ParseTeam(const char[] text, int &team)
{
	if (StrEqual(text, "t", false) || StrEqual(text, "terrorist", false) || StrEqual(text, "terrorists", false))
	{
		team = CS_TEAM_T;
		return true;
	}

	if (StrEqual(text, "ct", false) || StrEqual(text, "counter", false) || StrEqual(text, "counter-terrorist", false) || StrEqual(text, "counter-terrorists", false))
	{
		team = CS_TEAM_CT;
		return true;
	}

	if (StrEqual(text, "both", false) || StrEqual(text, "all", false) || StrEqual(text, "ambos", false))
	{
		team = TEAM_BOTH;
		return true;
	}

	return false;
}

void FormatWeaponMenuLine(int target, CSWeaponID id, const char[] alias, char[] buffer, int maxLength)
{
	int tLimit = GetRestriction(id, CS_TEAM_T);
	int ctLimit = GetRestriction(id, CS_TEAM_CT);
	char tName[16];
	char ctName[16];

	Format(tName, sizeof(tName), "%T", "Team Terrorists Short", target);
	Format(ctName, sizeof(ctName), "%T", "Team Counter Terrorists Short", target);

	if (tLimit < 0 && ctLimit < 0)
	{
		strcopy(buffer, maxLength, alias);
	}
	else if (tLimit >= 0 && ctLimit >= 0)
	{
		Format(buffer, maxLength, "%s  %s:%d %s:%d", alias, tName, tLimit, ctName, ctLimit);
	}
	else if (tLimit >= 0)
	{
		Format(buffer, maxLength, "%s  %s:%d", alias, tName, tLimit);
	}
	else
	{
		Format(buffer, maxLength, "%s  %s:%d", alias, ctName, ctLimit);
	}
}

void GetWeaponAlias(CSWeaponID id, int target, char[] alias, int maxLength)
{
	if (CS_WeaponIDToAlias(id, alias, maxLength) <= 0)
	{
		Format(alias, maxLength, "%T", "Unknown Weapon", target);
	}
}

int GetTranslationTarget(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientConnected(client))
	{
		return LANG_SERVER;
	}

	int language = GetClientLanguage(client);
	return IsPluginLanguageSupported(language) ? client : LANG_SERVER;
}

bool IsPluginLanguageSupported(int language)
{
	return IsTranslatedForLanguage("Weapon Restriction Menu Title", language);
}

void GetWeaponGroupName(int group, int target, char[] name, int maxLength)
{
	switch (group)
	{
		case WEAPON_GROUP_PISTOLS:
		{
			Format(name, maxLength, "%T", "Group Pistols", target);
		}
		case WEAPON_GROUP_SMGS:
		{
			Format(name, maxLength, "%T", "Group SMGs", target);
		}
		case WEAPON_GROUP_SHOTGUNS:
		{
			Format(name, maxLength, "%T", "Group Shotguns", target);
		}
		case WEAPON_GROUP_RIFLES:
		{
			Format(name, maxLength, "%T", "Group Rifles", target);
		}
		case WEAPON_GROUP_SNIPERS:
		{
			Format(name, maxLength, "%T", "Group Snipers", target);
		}
		case WEAPON_GROUP_GRENADES:
		{
			Format(name, maxLength, "%T", "Group Grenades", target);
		}
		case WEAPON_GROUP_ARMOR:
		{
			Format(name, maxLength, "%T", "Group Armor", target);
		}
		default:
		{
			Format(name, maxLength, "%T", "Unknown Weapon", target);
		}
	}
}

void GetTeamNameForCommand(int team, int target, char[] name, int maxLength)
{
	switch (team)
	{
		case CS_TEAM_T:
		{
			Format(name, maxLength, "%T", "Team Terrorists Short", target);
		}
		case CS_TEAM_CT:
		{
			Format(name, maxLength, "%T", "Team Counter Terrorists Short", target);
		}
		default:
		{
			Format(name, maxLength, "%T", "Team Both", target);
		}
	}
}

void NotifyRestricted(int client, CSWeaponID id, int limit, int weaponRef = INVALID_ENT_REFERENCE)
{
	if (weaponRef != INVALID_ENT_REFERENCE)
	{
		if (g_LastPickupNotifyRef[client] != INVALID_ENT_REFERENCE && EntRefToEntIndex(g_LastPickupNotifyRef[client]) == INVALID_ENT_REFERENCE)
		{
			g_LastPickupNotifyRef[client] = INVALID_ENT_REFERENCE;
		}

		if (g_LastPickupNotifyRef[client] == weaponRef)
		{
			return;
		}

		g_LastPickupNotifyRef[client] = weaponRef;
	}
	else
	{
		float now = GetGameTime();
		if (now < g_NextNotify[client])
		{
			return;
		}

		g_NextNotify[client] = now + NOTIFY_DELAY;
	}

	PlayRestrictSound(client);
	if (!g_CvarNotify.BoolValue)
	{
		return;
	}

	char alias[64];
	int target = GetTranslationTarget(client);
	GetWeaponAlias(id, target, alias, sizeof(alias));

	if (limit == 0)
	{
		PrintToChat(client, "%s%T", g_ChatPrefix, "Weapon Blocked For Team", target, alias);
	}
	else
	{
		PrintToChat(client, "%s%T", g_ChatPrefix, "Weapon Limit Reached", target, alias, limit);
	}
}
