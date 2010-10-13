#pragma semicolon 1
#include <sourcemod>
#include <tf2items>
#include <adminmenu>
#include <colors>

#define VERSION	"0.0.2"
#define MAXITEMS	128


new bool:g_bEnabled;
new bool:g_bDefault;		//true == replace weapons by default, unless told so with sm_toggleunlock <iIDI>
new String:g_sCfgFile[255];

new Handle:g_hCvarDefault;
new Handle:g_hCvarEnabled;
new Handle:g_hCvarFile;

new Handle:g_hTopMenu = INVALID_HANDLE;

new bool:g_bSomethingChanged = false;

public Plugin:myinfo = {
	name        = "tNoUnlocksPls",
	author      = "Thrawn",
	description = "Removes attributes from weapons or replaces them with the original.",
	version     = VERSION,
	url         = "http://aaa.wallbash.com"
};

enum Item {
	iIDX,
	String:trans[256],
	toggled
}

new g_xItems[MAXITEMS][Item];
new g_iWeaponCount = 0;

public OnPluginStart() {
	CreateConVar("sm_tnounlockspls_version", VERSION, "[TF2] tNoUnlocksPls", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	g_hCvarDefault = CreateConVar("sm_tnounlockspls_default", "1", "1 == replace weapons by default, unless told so with sm_toggleunlock <iIDI>", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCvarEnabled = CreateConVar("sm_tnounlockspls_enable", "1", "Enable disable this plugin", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCvarFile = CreateConVar("sm_tnounlockspls_cfgfile", "tNoUnlocksPls.cfg", "File to store configuration in", FCVAR_PLUGIN);

	HookConVarChange(g_hCvarDefault, Cvar_Changed);
	HookConVarChange(g_hCvarEnabled, Cvar_Changed);
	HookConVarChange(g_hCvarFile, Cvar_Changed);

	decl String:translationPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, translationPath, PLATFORM_MAX_PATH, "translations/weapons.phrases.tf.txt");

	if(FileExists(translationPath)) {
		LoadTranslations("weapons.phrases.tf.txt");
	} else {
		SetFailState("No translation file found.");
	}

	RegAdminCmd("sm_toggleunlock", Command_ToggleUnlock, ADMFLAG_ROOT);

	/* Account for late loading */
	new Handle:topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE)) {
		OnAdminMenuReady(topmenu);
	}
}

public Cvar_Changed(Handle:convar, const String:oldValue[], const String:newValue[]) {
	if(convar == g_hCvarFile) {
		GetConVarString(g_hCvarFile, g_sCfgFile, sizeof(g_sCfgFile));
		BuildPath(Path_SM, g_sCfgFile, sizeof(g_sCfgFile), "configs/%s", g_sCfgFile);

		g_bSomethingChanged = true;
	} else {
		g_bDefault = GetConVarBool(g_hCvarDefault);
		g_bEnabled = GetConVarBool(g_hCvarEnabled);
	}
}

public OnConfigsExecuted() {
	g_bDefault = GetConVarBool(g_hCvarDefault);
	g_bEnabled = GetConVarBool(g_hCvarEnabled);

	GetConVarString(g_hCvarFile, g_sCfgFile, sizeof(g_sCfgFile));
	BuildPath(Path_SM, g_sCfgFile, sizeof(g_sCfgFile), "configs/%s", g_sCfgFile);

	PopulateItemsArray();
}

public OnAdminMenuReady(Handle:topmenu)
{
	/* Block us from being called twice*/
	if (topmenu == g_hTopMenu) {
		return;
	}

	/* Save the Handle */
	g_hTopMenu = topmenu;

	new TopMenuObject:topMenuServerCommands = FindTopMenuCategory(g_hTopMenu, ADMINMENU_SERVERCOMMANDS);
	AddToTopMenu(g_hTopMenu, "sm_toggleunlock", TopMenuObject_Item, AdminMenu_Unlocks, topMenuServerCommands, "", ADMFLAG_ROOT);
}

public AdminMenu_Unlocks(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength) {
    if (action == TopMenuAction_DisplayOption) {
        Format(buffer, maxlength, "Unlocks");
    } else if (action == TopMenuAction_SelectOption) {
        BuildUnlockMenu(param);
    }
}

public BuildUnlockMenu(iClient) {
	new Handle:menu = CreateMenu(ChooserMenu_Handler);

	if(g_bDefault) {
 		SetMenuTitle(menu, "Enabled:");
 	} else {
 		SetMenuTitle(menu, "Disabled:");
 	}
	SetMenuExitBackButton(menu, true);

	new cnt = 0;
	for(new i = 0; i < g_iWeaponCount; i++) {
		new String:sName[128];
		Format(sName, sizeof(sName), "%T (%s)", g_xItems[i][trans], iClient, g_xItems[i][toggled] == 1 ? "yes" : "no");

		new String:sIdx[4];
		IntToString(g_xItems[i][iIDX], sIdx, 4);

		AddMenuItem(menu, sIdx, sName);
		cnt++;
	}

	if(cnt == 0) {
		PrintToChat(iClient, "No weapons found - something must be configured incorrectly.");
		DisplayTopMenu(g_hTopMenu, iClient, TopMenuPosition_LastCategory);
	} else {
		DisplayMenu(menu, iClient, 0);
	}
}

public ChooserMenu_Handler(Handle:menu, MenuAction:action, param1, param2) {
	//param1:: client
	//param2:: item

	if(action == MenuAction_Select) {
		new String:sIdx[4];

		/* Get item info */
		GetMenuItem(menu, param2, sIdx, sizeof(sIdx));
		new iIdx = StringToInt(sIdx);
		//LogMessage("Toggling item %i", iIdx);
		ToggleItem(iIdx);

		if (IsClientInGame(param1) && !IsClientInKickQueue(param1))
			BuildUnlockMenu(param1);
	} else if (action == MenuAction_Cancel) {
		if (param2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE) {
			DisplayTopMenu(g_hTopMenu, param1, TopMenuPosition_LastCategory);
		}
	} else if (action == MenuAction_End) {
		CloseHandle(menu);
	}
}

public PopulateItemsArray() {
	new Handle:kv = CreateKeyValues("WeaponToggles");
	FileToKeyValues(kv, g_sCfgFile);
	KvGotoFirstSubKey(kv, false);

	new String:path[255];
	BuildPath(Path_SM, path, sizeof(path), "configs/weapons.cfg");
	new Handle:hKvWeaponT = CreateKeyValues("WeaponNames");

	FileToKeyValues(hKvWeaponT, path);
	KvGotoFirstSubKey(hKvWeaponT, true);

	g_iWeaponCount = 0;
	do
	{
		new String:sSection[255];
		KvGetSectionName(kv, sSection, sizeof(sSection));

		new String:sValue[255];
		KvGetString(kv, "", sValue, sizeof(sValue));
		if(!StrEqual(sValue, "")) {
			//We have a value, so this is a pair
			new iIDI = StringToInt(sSection);
			new iState = StringToInt(sValue);

			new String:sTrans[255];
			KvGetString(hKvWeaponT, sSection, sTrans, sizeof(sTrans));

			g_xItems[g_iWeaponCount][iIDX] = iIDI;
			g_xItems[g_iWeaponCount][toggled] = iState;
			strcopy(g_xItems[g_iWeaponCount][trans], 255, sTrans);

			//PrintToServer("Found item %T (%i) (%i)", g_xItems[g_iWeaponCount][trans], 0, g_xItems[g_iWeaponCount][iIDX], g_xItems[g_iWeaponCount][toggled]);
			//PrintToServer("Found item %s (%i) (%i)", g_xItems[g_iWeaponCount][trans], g_xItems[g_iWeaponCount][iIDX], g_xItems[g_iWeaponCount][toggled]);

			g_iWeaponCount++;
		}

	} while (KvGotoNextKey(kv, false));

	LogMessage("Found %i items in your config.", g_iWeaponCount);

	CloseHandle(hKvWeaponT);
	CloseHandle(kv);
}

public OnMapEnd() {
	if(g_bSomethingChanged) {
		//We need to save our changes
		new Handle:kv = CreateKeyValues("WeaponToggles");

		for(new i = 0; i < g_iWeaponCount; i++) {
			new String:sIDX[4];
			IntToString(g_xItems[i][iIDX], sIDX, sizeof(sIDX));
			KvSetNum(kv, sIDX, g_xItems[i][toggled]);
		}

		KeyValuesToFile(kv, g_sCfgFile);
		CloseHandle(kv);
	}
}

public Action:Command_ToggleUnlock(client, args) {
	if(!g_bEnabled) {
		ReplyToCommand(client, "This command has no effect until you enable tNoUnlocksPls");
	}

	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_toggleunlock <id> (id can be found in items_game.txt");
	}

	new String:arg1[4];
	GetCmdArg(1, arg1, sizeof(arg1));
	ToggleItem(StringToInt(arg1));

	return Plugin_Handled;
}

public FindItemWithID(iIDI) {
	for(new i = 0; i < g_iWeaponCount; i++) {
		if(g_xItems[i][iIDX] == iIDI)
			return i;
	}

	return -1;
}

public ToggleItem(iIDI) {
	new id = FindItemWithID(iIDI);
	if(id != -1) {
		if(g_xItems[id][toggled] == 1)
			g_xItems[id][toggled] = 0;
		else
			g_xItems[id][toggled] = 1;

		g_bSomethingChanged = true;
	}
}

public EnabledForItem(iIDI) {
	new id = FindItemWithID(iIDI);
	if(id != -1) {
		new bool:bIsToggled = false;
		if(g_xItems[id][toggled] == 1)
			bIsToggled = true;

		new bool:bResult = g_bDefault;
		if(bIsToggled)
			bResult = !bResult;

		return bResult;
	}

	return false;
}


public Action:TF2Items_OnGiveNamedItem(iClient, String:strClassName[], iItemDefinitionIndex, &Handle:hItemOverride) {

	//PrintToChat(iClient, "giving item %i", iItemDefinitionIndex);
	if(!g_bEnabled)
		return Plugin_Continue;

	if (hItemOverride != INVALID_HANDLE)
		return Plugin_Continue;

	if(!EnabledForItem(iItemDefinitionIndex))
		return Plugin_Continue;

	//PrintToChat(iClient, "treating item %i", iItemDefinitionIndex);

	if (IsStripable(iItemDefinitionIndex)) {
		new id = FindItemWithID(iItemDefinitionIndex);
		if(id != -1) {
			new Handle:hTest = TF2Items_CreateItem(OVERRIDE_ATTRIBUTES);
			TF2Items_SetNumAttributes(hTest, 0);
			hItemOverride = hTest;

			CPrintToChat(iClient, "Stripped attributes of your '{olive}%T{default}'", g_xItems[id][trans], iClient);
			return Plugin_Changed;
		}
	}

	new String:sClass[64];
	new idToBe;
	//PrintToChat(iClient, "replacing item %i", iItemDefinitionIndex);
	if (NeedsReplacement(iItemDefinitionIndex, sClass, sizeof(sClass), idToBe)) {

		new Handle:hTest = TF2Items_CreateItem(OVERRIDE_CLASSNAME | OVERRIDE_ITEM_DEF | OVERRIDE_ITEM_LEVEL | OVERRIDE_ITEM_QUALITY | OVERRIDE_ATTRIBUTES);
		TF2Items_SetClassname(hTest, sClass);
		TF2Items_SetItemIndex(hTest, idToBe);
		TF2Items_SetLevel(hTest, 1);
		TF2Items_SetQuality(hTest, 0);
		TF2Items_SetNumAttributes(hTest, 0);
		hItemOverride = hTest;

		new idPrev = FindItemWithID(iItemDefinitionIndex);
		if(idPrev != -1) {
			CPrintToChat(iClient, "Replaced your '{olive}%T{default}'", g_xItems[idPrev][trans], iClient);
		}


		return Plugin_Changed;
	}

	return Plugin_Continue;
}

stock IsStripable(iIDI) {
	if(
			iIDI == 35	||	//Kritzkrieg
			iIDI == 36	||	//Blutsauger
			iIDI == 37	||	//Ubersaw
			iIDI == 38	||	//Axtinguisher
			iIDI == 40	||	//Backburner
			iIDI == 41	||	//Natascha
			iIDI == 43	||	//Killing Gloves of Boxing
			iIDI == 44	||	//Sandman
			iIDI == 45	||	//Force-A-Nature
			iIDI == 59	||	//Dead Ringer
			iIDI == 60	||	//Cloak and Dagger
			iIDI == 61	||	//Ambassador
			iIDI == 127	||	//Direct Hit
			iIDI == 128	||	//Equalizer
			iIDI == 130	||	//Scottish Resistance
			//iIDI == 132	||	//Eyelander
			iIDI == 141	||	//Frontier Justice
			iIDI == 153	||	//Homewrecker
			iIDI == 154	||	//Pain Train
			iIDI == 171	||	//Tribalman\'s Shiv
			iIDI == 172	||	//Scotsman\'s Skullcutter
			iIDI == 214	||	//TF_ThePowerjack
			iIDI == 215	||	//TF_TheDegreaser
			iIDI == 221	||	//TF_TheHolyMackerel
			iIDI == 224	||	//TF_LEtranger
			iIDI == 225	||	//TF_EternalReward
			iIDI == 228	||	//TF_TheBlackBox
			iIDI == 230	||	//TF_SydneySleeper
			iIDI == 232	||	//TF_TheBushwacka
			iIDI == 237	||	//TF_Weapon_RocketLauncher_Jump
			iIDI == 239	||	//TF_Unique_Gloves_of_Running_Urgently
			iIDI == 173		//TF_Unique_BattleSaw

							)
								return true;
	return false;
}


stock bool:NeedsReplacement(iIDI, String:class[], size, &replacement) {
	//Replace with Bottle
	if(iIDI == 132) {	//Eyelander
		strcopy(class, size, "tf_weapon_bottle");
		replacement = 1;
		return true;
	}

	//Replace with Shotgun
	if(iIDI == 39) {	//Flaregun
		strcopy(class, size, "tf_weapon_shotgun_pyro");
		replacement = 12;
		return true;
	}

	//Replace with Shotgun
	if(iIDI == 42 || iIDI == 159) {	//Sandvich & Dalokohs Bar
		strcopy(class, size, "tf_weapon_shotgun_hwg");
		replacement = 11;
		return true;
	}

	//Replace with Pistol
	if(iIDI == 46 || iIDI == 163 || iIDI == 222) {	//Bonk! Atomic Punch & Crit-a-Cola & TF_MadMilk
		//strcopy(class, size, "tf_weapon_pistol_scout");
		//replacement = 23;
		strcopy(class, size, "tf_weapon_pistol");
		replacement = 160;
		return true;
	}

	//Replace with Pistol
	if(iIDI == 140) {	//Wrangler
		strcopy(class, size, "tf_weapon_pistol");
		replacement = 22;
		return true;
	}

	//Replace with Wrench
	if(iIDI == 142 || iIDI == 155) {	//Gunslinger & Southern Hospitality
		strcopy(class, size, "tf_weapon_wrench");
		replacement = 7;
		return true;
	}

	//Replace with SMG
	if(iIDI == 58 || iIDI == 57 || iIDI == 231) {	//Razorback & Jarate & TF_DarwinsDangerShield
		strcopy(class, size, "tf_weapon_smg");
		replacement = 16;
		return true;
	}

	//Replace with Stickybomb Launcher
	if(iIDI == 131) {	//CharginTarge
		strcopy(class, size, "tf_weapon_pipebomblauncher");
		replacement = 20;
		return true;
	}

	//Replace with Sniper Rifle
	if(iIDI == 56) {	//Huntsman
		strcopy(class, size, "tf_weapon_sniperrifle");
		replacement = 14;
		return true;
	}

	//Replace with Shotgun
	if(iIDI == 129 || iIDI == 133 || iIDI == 226) {	//Buff Banner & Gunboats & TF_TheBattalionsBackup
		strcopy(class, size, "tf_weapon_shotgun_soldier");
		replacement = 10;
		return true;
	}

	//Replace with Scattergun
	if(iIDI == 220) {	//ShortStop
		strcopy(class, size, "tf_weapon_scattergun");
		replacement = 13;
		return true;
	}

	return false;
}