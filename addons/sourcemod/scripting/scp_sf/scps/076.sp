#pragma semicolon 1
#pragma newdecls required

static const float Speeds[] = {240.0, 246.0, 252.0, 258.0, 264.0, 276.0};
static const int MaxHeads = 5;
static const int HealthKill = 15;
static const int HealthRage = 250;

public bool SCP076_Create(int client)
{
	Classes_VipSpawn(client);

	Client[client].Extra2 = 0;

	int weapon = SpawnWeapon(client, "tf_weapon_sword", 195, 1, 13, "2 ; 1.5 ; 28 ; 0.5 ; 219 ; 1 ; 252 ; 0.8 ; 412 ; 0.8", false);
	if(weapon > MaxClients)
	{
		ApplyStrangeRank(weapon, 11);
		SetEntProp(weapon, Prop_Send, "m_iAccountID", GetSteamAccountID(client, false));
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", weapon);
		CreateTimer(15.0, Timer_UpdateClientHud, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	return false;
}

public void SCP076_OnSpeed(int client, float &speed)
{
	int value = Client[client].Extra2;
	if(value >= sizeof(Speeds))
		value = sizeof(Speeds)-1;

	speed = Speeds[value];
}

public void SCP076_OnKill(int client, int victim)
{
	Client[client].Extra2++;
	if(Client[client].Extra2 == MaxHeads)
	{
		TF2_AddCondition(client, TFCond_CritCola);
		TF2_StunPlayer(client, 2.0, 0.5, TF_STUNFLAG_SLOWDOWN|TF_STUNFLAG_NOSOUNDOREFFECT);
		ClientCommand(client, "playgamesound items/powerup_pickup_knockback.wav");

		TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
		SetEntityHealth(client, GetClientHealth(client)+HealthRage);

		int weapon = SpawnWeapon(client, "tf_weapon_sword", 266, 90, 13, "2 ; 11 ; 5 ; 1.15 ; 252 ; 0 ; 326 ; 1.67 ; 412 ; 0.8", 2, true);
		if(weapon > MaxClients)
		{
			ApplyStrangeRank(weapon, 18);
			SetEntProp(weapon, Prop_Send, "m_iAccountID", GetSteamAccountID(client, false));
			SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", weapon);
		}
	}
	else if(Client[client].Extra2 < MaxHeads)
	{
		SetEntityHealth(client, GetClientHealth(client)+HealthKill);
	}
	else
	{
		SetEntityHealth(client, GetClientHealth(client)+HealthRage);
	}

	SDKCall_SetSpeed(client);
}

public void SCP076_OnDeath(int client, Event event)
{
	Classes_DeathScp(client, event);
	CreateTimer(5.0, Timer_DissolveRagdoll, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public void SCP076_DoorTouch(int client, int entity)
{
	if(Client[client].Extra2 >= MaxHeads)
	{
		if (!DestroyOrOpenDoor(entity))
		{
			static char buffer[16];
			GetEntPropString(entity, Prop_Data, "m_iName", buffer, sizeof(buffer));
			if(!StrContains(buffer, "scp", false))
				AcceptEntityInput(entity, "FireUser1", client, client);
		}
	}
}
