#pragma semicolon 1
#pragma newdecls required

enum struct PresetEnum
{
	char Name[16];
	Function Func;
	ArrayList Classes;
}

enum struct SoundEnum
{
	char Path[PLATFORM_MAX_PATH];
	float Time;
	int Volume;
}

enum struct WaveEnum
{
	int Group;
	int Tickets;
	int Type;
	ArrayList Classes;

	bool ShowSCPs;
	char Message[32];
	char Trigger[32];
	char TriggerPre[32]; 

	SoundEnum Sound;
	SoundEnum SoundTeam;

	int TicketsLeft;
}

enum
{
	Music_JoinAlt = -4,
	Music_Join = -3,
	Music_Timeleft = -2,
	Music_Alone = -1
}

static int TeamColors[][] =
{
	{ 255, 200, 200, 255 },
	{ 255, 165, 0, 255 },
	{ 0, 100, 220, 255 },
	{ 139, 0, 0, 255 }
};

static int PlayerArrayOffset = -1;
static Function GameCondition;
static Function GameRoundStart;
static StringMap GameInfo;

static int PlayerQueue[MAXPLAYERS + 1];
static int MaxQueueIndex;

static ArrayList Presets;
static ArrayList SetupList;

static Handle WaveTimer;
static Handle WavePreTimer;
static int WaveIndex = -1;
static Function WaveFunc;
static float WaveTimes[2];
static float WavePreTime;
static ArrayList WaveList;

static SoundEnum MusicJoin;
static SoundEnum MusicJoinAlt;
static SoundEnum MusicTimeleft;
static SoundEnum MusicAlone;
static SoundEnum MusicFloors[10];

int VIPsAlive;
bool DebugPreventRoundWin;

ArrayList Gamemode_Setup(KeyValues main, KeyValues map)
{
	// Delete any arrays inside the arrays
	PresetEnum preset;
	if(Presets)
	{
		int length = Presets.Length;
		for(int i; i<length; i++)
		{
			Presets.GetArray(i, preset);
			delete preset.Classes;
		}
		delete Presets;
	}

	WaveEnum wave;
	if(WaveList)
	{
		int length = WaveList.Length;
		for(int i; i<length; i++)
		{
			WaveList.GetArray(i, wave);
			delete wave.Classes;
		}
		delete WaveList;
	}

	main.Rewind();
	KeyValues kv = main;
	if(map)	// Check if the map has it's own gamemode config
	{
		map.Rewind();
		if(map.JumpToKey("Gamemode"))
			kv = map;
	}

	GameCondition = KvGetFunction(kv, "wincondition");
	GameRoundStart = KvGetFunction(kv, "roundstart");
	if(kv.GetNum("noachieve"))
		CvarAchievement.BoolValue = false;

	if(kv.JumpToKey("presets"))
	{
		Presets = new ArrayList(sizeof(PresetEnum));
		if(kv.GotoFirstSubKey())
		{
			do	// Grab all presets
			{
				if(!kv.GetSectionName(preset.Name, sizeof(preset.Name)))
					continue;

				preset.Func = KvGetFunction(kv, "type");
				if(preset.Func == INVALID_FUNCTION)
				{
					LogError("[Config] Preset '%s' has invalid function for 'type'", preset.Name);
					continue;
				}

				preset.Classes = GrabClassList(kv);
				Presets.PushArray(preset);
			} while(kv.GotoNextKey());
			kv.GoBack();
		}
		kv.GoBack();
	}
	else
	{
		Presets = null;
	}

	if(kv.JumpToKey("setup"))
	{
		SetupList = GrabClassList(kv);
		kv.GoBack();
	}

	if(kv.JumpToKey("waves"))
	{
		WaveFunc = KvGetFunction(kv, "type");
		if(WaveFunc != INVALID_FUNCTION)
		{
			// RNG wave timer
			kv.GetString("time", preset.Name, sizeof(preset.Name));
			char buffers[2][8];
			int amount = ExplodeString(preset.Name, ";", buffers, sizeof(buffers), sizeof(buffers[]));
			if(amount > 1)
			{
				WaveTimes[0] = StringToFloat(buffers[0]);
				WaveTimes[1] = StringToFloat(buffers[1]);
			}
			else
			{
				WaveTimes[0] = StringToFloat(preset.Name);
				WaveTimes[1] = WaveTimes[0];
			}
			
			WavePreTime = kv.GetFloat("pretime");

			WaveList = new ArrayList(sizeof(WaveEnum));
			if(kv.GotoFirstSubKey())
			{
				do
				{
					if(!kv.GetSectionName(preset.Name, sizeof(preset.Name)))
						continue;

					wave.Group = StringToInt(preset.Name);
					wave.Tickets = kv.GetNum("tickets");
					wave.Type = kv.GetNum("type");
					wave.ShowSCPs = view_as<bool>(kv.GetNum("showscps"));
					kv.GetString("message", wave.Message, sizeof(wave.Message));
					if(!TranslationPhraseExists(wave.Message))
						wave.Message[0] = 0;
					kv.GetString("trigger", wave.Trigger, sizeof(wave.Trigger));
					kv.GetString("trigger_pre", wave.TriggerPre, sizeof(wave.TriggerPre));
					
					KvGetSound(kv, "sound", wave.Sound);
					KvGetSound(kv, "sound_team", wave.SoundTeam, wave.Sound);

					wave.Classes = GrabClassList(kv);
					WaveList.PushArray(wave);
				} while(kv.GotoNextKey());
				kv.GoBack();
			}
		}
		else
		{
			WaveList = null;
		}

		kv.GoBack();
	}
	else
	{
		WaveList = null;
	}

	if(kv.JumpToKey("music"))
	{
		KvGetSound(kv, "join", MusicJoin);
		KvGetSound(kv, "joinalt", MusicJoinAlt);
		KvGetSound(kv, "timeleft", MusicTimeleft);
		KvGetSound(kv, "alone", MusicAlone);

		if(kv.JumpToKey("floors"))
		{
			char buffer[3];
			for(int i; i<10; i++)
			{
				IntToString(i, buffer, sizeof(buffer));
				KvGetSound(kv, buffer, MusicFloors[i]);
			}
			kv.GoBack();
		}
		kv.GoBack();
	}

	if(kv.JumpToKey("downloads"))
	{
		int table = FindStringTable("downloadables");
		bool save = LockStringTables(false);
		char buffer[PLATFORM_MAX_PATH];
		for(int i=1; ; i++)
		{
			IntToString(i, preset.Name, sizeof(preset.Name));
			kv.GetString(preset.Name, buffer, sizeof(buffer));
			if(!buffer[0])
				break;

			if(!FileExists(buffer, true))
			{
				LogError("[Config] 'Gamemode' has missing file '%s'", buffer);
				continue;
			}

			AddToStringTable(table, buffer);
		}
		LockStringTables(save);
		kv.GoBack();
	}

	if(kv.JumpToKey("commands"))
	{
		char buffer[2048];
		for(int i=1; ; i++)
		{
			IntToString(i, preset.Name, sizeof(preset.Name));
			kv.GetString(preset.Name, buffer, sizeof(buffer));
			if(!buffer[0])
				break;

			ServerCommand(buffer);
		}
		kv.GoBack();
	}

	ArrayList list;
	if(kv.JumpToKey("classes"))
	{
		list = GrabClassList(kv);
		kv.GoBack();
	}
	return list;
}

bool Gamemode_RoundStart()
{
	GameInfo = new StringMap();

	if(GameRoundStart != INVALID_FUNCTION)
	{
		Call_StartFunction(null, GameRoundStart);
		Call_Finish();
	}

	// Assign queue indices here
	for(int client = 1; client <= MaxClients; client++)
	{
		if(!IsValidClient(client))
		{
			// Invalid client with a queue index, unassign him
			if(Client[client].QueueIndex != -1)
				Gamemode_UnassignQueueIndex(client);
		}
		else
		{
			if (Client[client].QueueIndex == -1)
			{
				// Valid client with no queue index, assign him one
				Gamemode_AssignQueueIndex(client);
			}
			
			// clean up decals from previous round
			ClientCommand(client, "r_cleardecals");			
		}		
	}

	// This was done to prevent RNG just being funky against repeating classes
	if(PlayerArrayOffset == -1)
	{
		int players = 0;

		for (int client = 1; client <= MaxClients; client++)
		{
			if(IsClientInGame(client) && GetClientTeam(client)>view_as<int>(TFTeam_Spectator))
				players++;
		}
		
		PlayerArrayOffset = GetRandomInt(0, players-1);
	}
	else
	{
		PlayerArrayOffset = 1;
	}
	
	// Shift queue indices
	if(PlayerArrayOffset > 0)
	{
		int start = PlayerArrayOffset;
		int[] clientBuffer = new int[MaxClients]; // We'll add those clients to the end of the queue
		for(int i = 0, j; PlayerQueue[i] != 0; i++)
		{
			if(i < start)
			{
				clientBuffer[j++] = PlayerQueue[i];
			}
			else
			{
				int client = PlayerQueue[i];
				Client[client].QueueIndex = i - start;
				PlayerQueue[Client[client].QueueIndex] = client;
				PlayerQueue[i] = -1;
			}
		}

		// Add clients from clientBuffer back to the queue;
		for(int i = 0, j; PlayerQueue[i] != 0; i++)
		{
			if (PlayerQueue[i] == -1)
			{
				int client = clientBuffer[j++];
				Client[client].QueueIndex = i;
				PlayerQueue[i] = client;
			}
		}
	}

	ArrayList players = new ArrayList();

	// Fill the players ArrayList
	for(int i = 0; PlayerQueue[i] != 0; i++)
	{
		int client = PlayerQueue[i];

		if(IsValidClient(client) && GetClientTeam(client)>view_as<int>(TFTeam_Spectator))
		{
			Client[client].NextSongAt = 0.0;
			players.Push(client);
		}
		else
		{
			Client[client].Class = 0;
		}
	}

	int length = players.Length;
	if(!length)
	{
		delete players;
		return false;
	}

	ArrayList classes = Gamemode_MakeClassList(SetupList, length);
	int client = classes.Length;
	if(length > client)
		length = client;

	ClassEnum class;
	for(int i; i<length; i++)
	{
		client = players.Get(i);
		Client[client].Class = classes.Get(i);
		static char buffer[16];
		if(Classes_GetByIndex(Client[client].Class, class))
		{
			strcopy(buffer, sizeof(buffer), class.Name);
			switch(Forward_OnClassPre(client, ClassSpawn_RoundStart, buffer, sizeof(buffer)))
			{
				case Plugin_Changed:
				{
					Client[client].Class = Classes_GetByName(buffer, class);
					if(Client[client].Class == -1)
					{
						Client[client].Class = 0;
						Classes_GetByIndex(0, class);
					}
				}
				case Plugin_Handled:
				{
					players.Erase(i--);
					int size = players.Length;
					if(length > size)
						length = size;

					Client[client].Class = Classes_GetByName(buffer, class);
					if(Client[client].Class == -1)
					{
						Client[client].Class = 0;
						Classes_GetByIndex(0, class);
					}
				}
				case Plugin_Stop:
				{
					players.Erase(i--);
					int size = players.Length;
					if(length > size)
						length = size;

					Client[client].Class = 0;
					continue;
				}
			}
		}
		else
		{
			Client[client].Class = 0;
			Classes_GetByIndex(Client[client].Class, class);
			strcopy(buffer, sizeof(buffer), class.Name);
			switch(Forward_OnClassPre(client, ClassSpawn_RoundStart, buffer, sizeof(buffer)))
			{
				case Plugin_Changed:
				{
					Client[client].Class = Classes_GetByName(buffer, class);
					if(Client[client].Class == -1)
					{
						Client[client].Class = 0;
						Classes_GetByIndex(0, class);
					}
				}
				case Plugin_Handled:
				{
					players.Erase(i--);
					int size = players.Length;
					if(length > size)
						length = size;

					Client[client].Class = Classes_GetByName(buffer, class);
					if(Client[client].Class == -1)
					{
						Client[client].Class = 0;
						Classes_GetByIndex(0, class);
					}
				}
				case Plugin_Stop:
				{
					players.Erase(i--);
					int size = players.Length;
					if(length > size)
						length = size;

					continue;
				}
				default:
				{
					continue;
				}
			}
		}

		ChangeClientTeamEx(client, class.Team>TFTeam_Spectator ? class.Team : class.Team+view_as<TFTeam>(2));
		TF2_SetPlayerClass(client, class.Class, _, false);
		Forward_OnClass(client, ClassSpawn_RoundStart, class.Name);
	}
	delete classes;
	delete players;

	if(WaveList)
	{
		WaveEnum wave;
		length = WaveList.Length;
		for(int i; i<length; i++)
		{
			WaveList.GetArray(i, wave);
			wave.TicketsLeft = wave.Tickets;
			WaveList.SetArray(i, wave);
		}

		float WaveTime = GetRandomFloat(WaveTimes[0], WaveTimes[1]);
		
		// Send a notification to the map before the actual spawn happens
		// allows the map to setup something like a helicopter animation beforehand
		if ((WaveTime > 0.0) && (WavePreTime > 0.0))
		{
			// note: this will also chose the wave to spawn as it needs the correct team-specific trigger
			// note2: the pre-timer system currently only works with the ticket system!
			WavePreTimer = CreateTimer(WaveTime - WavePreTime, Gamemode_WavePreTimer, _, TIMER_FLAG_NO_MAPCHANGE);
		}
			
		WaveTimer = CreateTimer(WaveTime, Gamemode_WaveTimer, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	return true;
}

void Gamemode_CheckRound()
{
	if ((GameCondition != INVALID_FUNCTION) && !DebugPreventRoundWin)
	{
		bool endround;
		int team;
		Call_StartFunction(null, GameCondition);
		Call_PushCellRef(team);
		Call_Finish(endround);

		if(endround)
		{
			Enabled = false;
			EndRound(team);
		}
	}
}

void Gamemode_RoundEnd()
{
	delete GameInfo;
	GameInfo = null;

	if(WaveTimer)
	{
		KillTimer(WaveTimer);
		WaveTimer = null;
	}
	if(WavePreTimer)
	{
		KillTimer(WavePreTimer);
		WavePreTimer = null;
	}
}

int Gamemode_AssignQueueIndex(int client)
{
	if(IsValidClient(client))
	{
		if(Client[client].QueueIndex != -1)
		{
			LogError("%N (%i) already has a queue index %i", client, client, Client[client].QueueIndex);
		}
		else
		{
			Client[client].QueueIndex = MaxQueueIndex++;
			PlayerQueue[Client[client].QueueIndex] = client;
		}

		return Client[client].QueueIndex;
	}
	else
	{
		LogError("Client %i is not valid", client);
		return -1;
	}
}

void Gamemode_UnassignQueueIndex(int client)
{
	if(Client[client].QueueIndex == -1)
	{
		LogError("Attempting to unassign queue index from %N (%i) with no queue index", client, client);
	}
	else
	{
		PlayerQueue[Client[client].QueueIndex] = 0;

		for(int i = Client[client].QueueIndex + 1; i < MaxQueueIndex; i++)
		{
			PlayerQueue[i-1] = PlayerQueue[i];
			--Client[PlayerQueue[i]].QueueIndex;
			PlayerQueue[i] = 0;
		}

		if(MaxQueueIndex != -1)
			--MaxQueueIndex;

		Client[client].QueueIndex = -1;
	}
}

public Action Gamemode_WavePreTimer(Handle timer)
{
	// assumes ticket system!!
	WaveIndex = -1;
	
	ArrayList players = DeadPlayersList();
	Gamemode_ChooseWaveIndex(players);
	delete players;
	
	if (WaveIndex != -1)
	{
		WaveEnum wave;
		WaveList.GetArray(WaveIndex, wave);
		TriggerRelays(wave.TriggerPre);
	}

	return Plugin_Continue;
}

public Action Gamemode_WaveTimer(Handle timer)
{
	ArrayList players = DeadPlayersList();

	ArrayList classes;
	float next;
	Call_StartFunction(null, WaveFunc);
	Call_PushCellRef(classes);
	Call_PushCellRef(players);
	Call_Finish(next);

	if(classes)
	{
		ClassEnum class;
		int length = classes.Length;
		for(int i; i<length; i++)
		{
			int client = players.Get(i);
			Client[client].Class = classes.Get(i);
			static char buffer[16];
			if(Classes_GetByIndex(Client[client].Class, class))
			{
				strcopy(buffer, sizeof(buffer), class.Name);
				switch(Forward_OnClassPre(client, ClassSpawn_WaveSystem, buffer, sizeof(buffer)))
				{
					case Plugin_Changed:
					{
						Client[client].Class = Classes_GetByName(buffer, class);
						if(Client[client].Class == -1)
						{
							Client[client].Class = 0;
							Classes_GetByIndex(0, class);
						}
					}
					case Plugin_Handled:
					{
						players.Erase(i--);
						int size = players.Length;
						if(length > size)
							length = size;

						Client[client].Class = Classes_GetByName(buffer, class);
						if(Client[client].Class == -1)
						{
							Client[client].Class = 0;
							Classes_GetByIndex(0, class);
						}
					}
					case Plugin_Stop:
					{
						players.Erase(i--);
						int size = players.Length;
						if(length > size)
							length = size;

						Client[client].Class = 0;
						continue;
					}
				}
			}
			else
			{
				Client[client].Class = 0;
				Classes_GetByIndex(Client[client].Class, class);
				strcopy(buffer, sizeof(buffer), class.Name);
				switch(Forward_OnClassPre(client, ClassSpawn_WaveSystem, buffer, sizeof(buffer)))
				{
					case Plugin_Changed:
					{
						Client[client].Class = Classes_GetByName(buffer, class);
						if(Client[client].Class == -1)
						{
							Client[client].Class = 0;
							Classes_GetByIndex(0, class);
						}
					}
					case Plugin_Handled:
					{
						players.Erase(i--);
						int size = players.Length;
						if(length > size)
							length = size;

						Client[client].Class = Classes_GetByName(buffer, class);
						if(Client[client].Class == -1)
						{
							Client[client].Class = 0;
							Classes_GetByIndex(0, class);
						}
					}
					case Plugin_Stop:
					{
						players.Erase(i--);
						int size = players.Length;
						if(length > size)
							length = size;

						continue;
					}
					default:
					{
						continue;
					}
				}
			}

			TF2_RespawnPlayer(client);
			Forward_OnClass(client, ClassSpawn_WaveSystem, class.Name);
		}
		delete classes;
	}
	delete players;

	if(next > 0)
	{
		WaveTimer = CreateTimer(next, Gamemode_WaveTimer, _, TIMER_FLAG_NO_MAPCHANGE);
	
		// Send a notification to the map before the actual spawn happens
		// allows the map to setup something like a helicopter animation beforehand
		if ((next > 0.0) && (WavePreTime > 0.0))
			WavePreTimer = CreateTimer(next - WavePreTime, Gamemode_WavePreTimer, _, TIMER_FLAG_NO_MAPCHANGE);	
		else
			WavePreTimer = null;
	}
	else
	{
		WaveTimer = null;
		WavePreTimer = null;
	}
	return Plugin_Continue;
}

float Gamemode_GetMusic(int client, int floor, char path[PLATFORM_MAX_PATH], int &volume)
{
	switch(floor)
	{
		case Music_JoinAlt:
		{
			strcopy(path, sizeof(path), MusicJoinAlt.Path);
			volume = MusicJoinAlt.Volume;
			return MusicJoinAlt.Time;
		}
		case Music_Join:
		{
			strcopy(path, sizeof(path), MusicJoin.Path);
			volume = MusicJoin.Volume;
			return MusicJoin.Time;
		}
		case Music_Timeleft:
		{
			strcopy(path, sizeof(path), MusicTimeleft.Path);
			volume = MusicTimeleft.Volume;
			return MusicTimeleft.Time;
		}
	}

	if(Client[client].AloneIn < GetGameTime())
	{
		strcopy(path, sizeof(path), MusicAlone.Path);
		volume = MusicAlone.Volume;
		return MusicAlone.Time;
	}

	if(floor<0 || floor>10)
		return 0.0;

	strcopy(path, sizeof(path), MusicFloors[floor].Path);
	volume = MusicFloors[floor].Volume;
	return MusicFloors[floor].Time;
}

void Gamemode_AddValue(const char[] key, int amount=1)
{
	if(GameInfo)
	{
		int value;
		GameInfo.GetValue(key, value);
		GameInfo.SetValue(key, value+amount);
	}
}

bool Gamemode_GetValue(const char[] key, int &value)
{
	return GameInfo.GetValue(key, value);
}

void Gamemode_GiveTicket(int group, int amount)
{
	WaveEnum wave;
	int length = WaveList.Length;
	for(int i; i<length; i++)
	{
		WaveList.GetArray(i, wave);
		if(wave.Group == group)
		{
			wave.TicketsLeft += amount;
			WaveList.SetArray(i, wave);
		}
	}
}

void Gamemode_GetWaveTimes(float &min, float &max)
{
	min = WaveTimes[0];
	max = WaveTimes[1];
}

bool Gamemode_GetWave(int index, WaveEnum wave)
{
	if(index<0 || index>=WaveList.Length)
		return false;

	WaveList.GetArray(index, wave);
	return true;
}

void Gamemode_SetWave(int index, WaveEnum wave)
{
	WaveList.SetArray(index, wave);
}

ArrayList Gamemode_MakeClassList(ArrayList classes, int max)
{
	ArrayList list = new ArrayList();
	int length = classes.Length;
	char buffer[16];
	for(int i; i<max; i++)
	{
		if(i < length)	// Allows using the last string until we're done
			classes.GetString(i, buffer, sizeof(buffer));

		int class = PresetToClass(buffer, list);	// Turn string into a class index
		if(class == -1)
		{
			if(i >= length)	// Don't want to keep reusing an invalid class
				break;

			max++;	// Make more
		}
		else
		{
			list.Push(class);
		}
	}
	return list;
}

static ArrayList GrabClassList(KeyValues kv)
{
	char buffer[16];
	ArrayList list = new ArrayList(16);
	for(int i=1; ; i++)
	{
		IntToString(i, buffer, sizeof(buffer));
		kv.GetString(buffer, buffer, sizeof(buffer));
		if(!buffer[0])
			break;

		list.PushString(buffer);
	}
	return list;
}

static int PresetToClass(const char[] name, ArrayList current)
{
	int index = Classes_GetByName(name);
	if(index==-1 && Presets)
	{
		PresetEnum preset;
		int length = Presets.Length;
		for(int i; i<length; i++)
		{
			Presets.GetArray(i, preset);
			if(!StrEqual(name, preset.Name, false))
				continue;

			Call_StartFunction(null, preset.Func);
			Call_PushCell(preset.Classes);
			Call_PushCell(current);
			Call_Finish(index);
			break;
		}
	}
	return index;
}

static ArrayList DeadPlayersList()
{
	int spec = Classes_GetByName("spec");
	ArrayList list = new ArrayList();
	for(int client=1; client<=MaxClients; client++)
	{
		if(!IsValidClient(client))
			continue;

		if(!TF2_IsPlayerInCondition(client, TFCond_HalloweenGhostMode))	// If not a dead ghost
		{
			// Check if player is alive or in spectator team
			if((IsPlayerAlive(client) && spec!=Client[client].Class) || GetClientTeam(client)<=view_as<int>(TFTeam_Spectator))
				continue;
		}

		list.Push(client);
	}
	list.Sort(Sort_Random, Sort_Integer);
	return list;
}

static bool EndRoundRelay(int group)
{
	int entity = -1;
	while((entity=FindEntityByClassname(entity, "logic_relay")) != -1)
	{
		static char name[32];
		GetEntPropString(entity, Prop_Data, "m_iName", name, sizeof(name));
		if(StrEqual(name, "scp_roundend", false))
		{
			switch(group)
			{
				case 1:
					AcceptEntityInput(entity, "FireUser1");

				case 2:
					AcceptEntityInput(entity, "FireUser2");

				case 3:
					AcceptEntityInput(entity, "FireUser3");

				default:
					AcceptEntityInput(entity, "FireUser4");
			}
			return true;
		}
	}
	return false;
}

static void KvGetSound(KeyValues kv, const char[] string, SoundEnum sound, const SoundEnum defaul = {})
{
	static char buffers[3][PLATFORM_MAX_PATH];
	kv.GetString(string, buffers[0], sizeof(buffers[]));
	if(buffers[0][0])
	{
		switch(ExplodeString(buffers[0], ";", buffers, sizeof(buffers), sizeof(buffers[])))
		{
			case 1:
			{
				sound.Time = 0.0;
				strcopy(sound.Path, sizeof(sound.Path), buffers[0]);
				if(sound.Path[0])
					PrecacheSound(sound.Path, true);
			}
			case 2:
			{
				sound.Time = StringToFloat(buffers[0]);
				strcopy(sound.Path, sizeof(sound.Path), buffers[1]);
				sound.Volume = 2;
				if(sound.Path[0])
					PrecacheSound(sound.Path, true);
			}
			default:
			{
				sound.Time = StringToFloat(buffers[0]);
				strcopy(sound.Path, sizeof(sound.Path), buffers[1]);
				sound.Volume = StringToInt(buffers[2]);
				if(sound.Path[0])
					PrecacheSound(sound.Path, true);
			}
		}
	}
	else
	{
		sound = defaul;
	}
}

public bool Gamemode_ConditionClassic(TFTeam &team)
{
	ClassEnum class;
	bool salive, ralive, balive;
	for(int i=1; i<=MaxClients; i++)
	{
		if(!IsValidClient(i) || IsSpec(i) || !Classes_GetByIndex(Client[i].Class, class))
			continue;

		if(class.Vip)
			return false;

		if(class.Human && Client[i].Disarmer)
			continue;

		if(!class.Group)	// SCPs
		{
			salive = true;
		}
		else if(class.Group == 1)// Chaos
		{
			ralive = true;
		}
		else if(class.Group > 1)	// Guards and MTF Squads
		{
			balive = true;
		}
	}

	if(balive && (salive || ralive))
		return false;

	int descape, dtotal, sescape, stotal, pkill, ptotal;
	GameInfo.GetValue("descape", descape);
	GameInfo.GetValue("dtotal", dtotal);
	GameInfo.GetValue("sescape", sescape);
	GameInfo.GetValue("stotal", stotal);
	GameInfo.GetValue("pkill", pkill);
	GameInfo.GetValue("ptotal", ptotal);

	int group;
	if(descape || (GameInfo.GetValue("scapture", group) && group))	//  Class-D escaped or Scientist captured
	{
		if(balive)	// MTF still alive
		{
			team = TFTeam_Unassigned;// Stalemate
			group = 0;
		}
		else
		{
			team = TFTeam_Red;	// Class-D win
			group = 1;
		}
	}
	else if(salive)	// SCP alive
	{
		team = TFTeam_Red;	// SCPs win
		group = 3;
	}
	else if(sescape || (GameInfo.GetValue("dcapture", group) && group))	// Scientist escaped or Class-D captured
	{
		team = TFTeam_Blue;	// MTF win
		group = 2;
	}
	else	// Nobody escaped, no SCPs alive
	{
		team = TFTeam_Unassigned;// Stalemate
		group = 0;
	}

	EndRoundRelay(group);

	int minutes, seconds;
	TimeToMinutesSeconds(GetGameTime() - RoundStartAt, minutes, seconds);

	char buffer[16];
	FormatEx(buffer, sizeof(buffer), "team_%d", group);
	SetHudTextParamsEx(-1.0, 0.3, 17.5, TeamColors[group], {255, 255, 255, 255}, 1, 2.0, 1.0, 1.0);
	for(int client=1; client<=MaxClients; client++)
	{
		if(!IsValidClient(client))
			continue;

		SetGlobalTransTarget(client);
		ShowSyncHudText(client, HudGame, "%t", "end_screen", buffer, descape, dtotal, sescape, stotal, pkill, ptotal, minutes, seconds);
	}
	return true;
}

public bool Gamecode_CountVIPs()
{
	ClassEnum class;
	bool salive;
	
	VIPsAlive = 0;
	for(int i=1; i<=MaxClients; i++)
	{
		if(!IsValidClient(i) || IsSpec(i) || !Classes_GetByIndex(Client[i].Class, class))
			continue;

		if(class.Vip)	// Class-D and Scientists
			VIPsAlive++;

		if(!class.Group)	// SCPs
			salive = true;
	}
	
	return salive;
}

public bool Gamemode_ConditionVip(TFTeam &team)
{
	bool salive = Gamecode_CountVIPs();
	if (VIPsAlive > 0)
		return false;

	int descape, dcapture, dtotal, sescape, scapture, stotal, pkill, ptotal;
	GameInfo.GetValue("descape", descape);
	GameInfo.GetValue("dcapture", dcapture);
	GameInfo.GetValue("dtotal", dtotal);
	GameInfo.GetValue("sescape", sescape);
	GameInfo.GetValue("scapture", scapture);
	GameInfo.GetValue("stotal", stotal);
	GameInfo.GetValue("pkill", pkill);
	GameInfo.GetValue("ptotal", ptotal);

	int group;
	if(sescape > descape)	// More Scientists than Class-D
	{
		team = TFTeam_Blue;
		group = 2;
	}
	else if(sescape<descape || scapture>dcapture)	// More Class-D than Scientists || More Scientists than Class-D
	{
		team = TFTeam_Red;
		group = 1;
	}
	else if(scapture < dcapture)	// More Class-D than Scientists
	{
		team = TFTeam_Blue;
		group = 2;
	}
	else if(salive && !sescape && !scapture)	// SCP alive and none escaped/captured
	{
		team = TFTeam_Red;
		group = 3;
	}
	else	// Tied escapes & captures
	{
		team = TFTeam_Unassigned;
		group = 0;
	}

	EndRoundRelay(group);

	int minutes, seconds;
	TimeToMinutesSeconds(GetGameTime() - RoundStartAt, minutes, seconds);	

	char buffer[16];
	FormatEx(buffer, sizeof(buffer), "team_%d", group);
	SetHudTextParamsEx(-1.0, 0.3, 17.5, TeamColors[group], {255, 255, 255, 255}, 1, 2.0, 1.0, 1.0);
	for(int client=1; client<=MaxClients; client++)
	{
		if(!IsValidClient(client))
			continue;

		SetGlobalTransTarget(client);
		ShowSyncHudText(client, HudGame, "%t", "end_screen_vip", buffer, descape, dtotal, dcapture, sescape, stotal, scapture, pkill, ptotal, minutes, seconds);
	}
	return true;
}

public bool Gamemode_ConditionVipAlt(TFTeam &team)	// Alternate vip mode, disarmed/captured escapes count as one score just like normal escapes.
{
	bool salive = Gamecode_CountVIPs();
	if (VIPsAlive > 0)
		return false;

	int descape, dcapture, dtotal, sescape, scapture, stotal, pkill, ptotal;
	GameInfo.GetValue("descape", descape);
	GameInfo.GetValue("dcapture", dcapture);
	GameInfo.GetValue("dtotal", dtotal);
	GameInfo.GetValue("sescape", sescape);
	GameInfo.GetValue("scapture", scapture);
	GameInfo.GetValue("stotal", stotal);
	GameInfo.GetValue("pkill", pkill);
	GameInfo.GetValue("ptotal", ptotal);

	int group;
	int sscore = sescape + dcapture;
	int dscore = descape + scapture;
	if(sscore > dscore)	// More Scientists(and Captured dboi) than Class-D
	{
		team = TFTeam_Blue;
		group = 2;
	}
	else if(sscore < dscore)	// More Class-D(and Captured sci) than Scientists
	{
		team = TFTeam_Red;
		group = 1;
	}
	else if(salive && !sescape && !dcapture && !descape && !scapture)	// SCP alive and none escaped
	{
		team = TFTeam_Red;
		group = 3;
	}
	else	// Tied escapes & captures
	{
		team = TFTeam_Unassigned;
		group = 0;
	}

	EndRoundRelay(group);

	int minutes, seconds;
	TimeToMinutesSeconds(GetGameTime() - RoundStartAt, minutes, seconds);	

	char buffer[16];
	FormatEx(buffer, sizeof(buffer), "team_%d", group);
	SetHudTextParamsEx(-1.0, 0.3, 17.5, TeamColors[group], {255, 255, 255, 255}, 1, 2.0, 1.0, 1.0);
	for(int client=1; client<=MaxClients; client++)
	{
		if(!IsValidClient(client))
			continue;

		SetGlobalTransTarget(client);
		ShowSyncHudText(client, HudGame, "%t", "end_screen_vip", buffer, descape, dtotal, dcapture, sescape, stotal, scapture, pkill, ptotal, minutes, seconds);
	}
	return true;
}

public bool Gamemode_ConditionSlNew(TFTeam &team)	// Tweaked version of scp-sl's game rule. It is recommended to use this with the addition of an auto-nuke.
{
	ClassEnum class;
	bool salive, ralive, balive;
	for(int i=1; i<=MaxClients; i++)
	{
		if(!IsValidClient(i) || IsSpec(i) || !Classes_GetByIndex(Client[i].Class, class))
			continue;

		if(class.Vip)
			return false;

		if(class.Human && Client[i].Disarmer)
			continue;

		if(!class.Group)	// SCPs
		{
			salive = true;
		}
		else if(class.Group == 1)// Chaos
		{
			ralive = true;
		}
		else if(class.Group > 1)	// Guards and MTF Squads
		{
			balive = true;
		}
	}

	if(balive && (salive || ralive))
		return false;
	
	int descape, dcapture, dtotal, sescape, scapture, stotal, pkill, ptotal, dpkill, spkill;
	GameInfo.GetValue("descape", descape);
	GameInfo.GetValue("dcapture", dcapture);
	GameInfo.GetValue("dtotal", dtotal);
	GameInfo.GetValue("sescape", sescape);
	GameInfo.GetValue("scapture", scapture);
	GameInfo.GetValue("stotal", stotal);
	GameInfo.GetValue("pkill", pkill);
	GameInfo.GetValue("ptotal", ptotal);
	GameInfo.GetValue("dpkill", dpkill);
	GameInfo.GetValue("spkill", spkill);
	
	int dtkill = 3 * dpkill;
	int stkill = 3 * spkill;
	int sscore = sescape + stkill - scapture;
	int dscore = descape + dtkill - dcapture;
	//int pscore = ptotal - pkill;
	int group;
	
	if(!salive)
	{
		if(ralive)	//  Only Class-D and Chaos
		{
			if(sscore > dscore)	// Foundation score more than Chaos Insurgency score
			{
				team = TFTeam_Unassigned; // Stalemate
				group = 0;
			}
			else
			{
				team = TFTeam_Red;	// Class-D win
				group = 1;
			}
		}
		else if(balive)	// Only MTF
		{
			if(sscore > dscore) // Foundation score more than Chaos Insurgency score
			{
				team = TFTeam_Blue;	// MTF win
				group = 2;
			}	
			else
			{
				team = TFTeam_Unassigned; // Stalemate
				group = 0;
			}
		}
		else	// Nobody escaped, no SCPs alive
		{
			team = TFTeam_Unassigned;// Stalemate
			group = 0;
		}
	}
	else
	{
		Gamecode_CountVIPs();
		
		if((VIPsAlive <= 0 && !sescape && !dcapture && !descape && !scapture) || (!balive && !ralive))
		{
			team = TFTeam_Red;    // SCPs win
			group = 3;
		}
		else
		{
			return false;
		}
	}

	EndRoundRelay(group);

	int minutes, seconds;
	TimeToMinutesSeconds(GetGameTime() - RoundStartAt, minutes, seconds);
	
	char buffer[16];
	FormatEx(buffer, sizeof(buffer), "team_%d", group);
	SetHudTextParamsEx(-1.0, 0.3, 17.5, TeamColors[group], {255, 255, 255, 255}, 1, 2.0, 1.0, 1.0);
	for(int client=1; client<=MaxClients; client++)
	{
		if(!IsValidClient(client))
			continue;

		SetGlobalTransTarget(client);
		ShowSyncHudText(client, HudGame, "%t", "end_screen_vip", buffer, descape, dtotal, dcapture, sescape, stotal, scapture, pkill, ptotal, minutes, seconds);
	}
	return true;
}

public bool Gamemode_ConditionBoss(TFTeam &team)
{
	ClassEnum class;
	for(int i=1; i<=MaxClients; i++)
	{
		if(!IsValidClient(i) || IsSpec(i) || !Classes_GetByIndex(Client[i].Class, class))
			continue;

		if(class.Vip)
			return false;
	}

	int descape, dtotal;
	GameInfo.GetValue("descape", descape);
	GameInfo.GetValue("dtotal", dtotal);

	int group;
	if(descape)
	{
		for(int i=1; i<=MaxClients; i++)
		{
			if(IsValidClient(i) && !IsSpec(i) && GetClientTeam(i)==view_as<int>(TFTeam_Red))
				ChangeClientTeamEx(i, TFTeam_Blue);
		}

		team = TFTeam_Blue;
		group = 2;
	}
	else
	{
		team = TFTeam_Unassigned;
		group = 3;
	}

	EndRoundRelay(group);

	char buffer[16];
	FormatEx(buffer, sizeof(buffer), "team_%d", group);
	SetHudTextParamsEx(-1.0, 0.3, 17.5, TeamColors[group], {255, 255, 255, 255}, 1, 2.0, 1.0, 1.0);
	for(int client=1; client<=MaxClients; client++)
	{
		if(!IsValidClient(client))
			continue;

		SetGlobalTransTarget(client);
		ShowSyncHudText(client, HudGame, "%t", "end_screen_boss", buffer, descape, dtotal);
	}
	return true;
}

public float Gamemode_WaveStartCountdown(ArrayList &list, ArrayList &players)
{
	EndRoundIn = GetGameTime()+121.0;
	return 0.0;
}

public void Gamemode_ChooseWaveIndex(ArrayList &players)
{
	int length = players.Length;
	if (length)
	{
		WaveEnum wave;
		ArrayList list = new ArrayList();
		int i = WaveList.Length;
		for (int a; a < i; a++)
		{
			WaveList.GetArray(a, wave);
			for (int b; b < wave.TicketsLeft; b++)
			{
				list.Push(a);
			}
		}

		if (!list.Length)
		{
			delete list;
			list = null;
		}

		WaveIndex = list.Get(GetRandomInt(0, list.Length - 1));
		delete list;	
	}
}

public float Gamemode_WaveRespawnTickets(ArrayList &list, ArrayList &players)
{	
	int length = players.Length;
	float wavetime = GetRandomFloat(WaveTimes[0], WaveTimes[1]);
	if(length)
	{
		// if we have a pre-time trigger set, that will choose the wave for us beforehand
		// otherwise we need to do it here
		if (WaveIndex == -1)
			Gamemode_ChooseWaveIndex(players);
		
		if (WaveIndex == -1)
		{
			EndRoundIn = GetGameTime()+GetRandomFloat(wavetime);
			return 0.0;
		}
	
		WaveEnum wave;
		WaveList.GetArray(WaveIndex, wave);

		if(length > wave.TicketsLeft)
			length = wave.TicketsLeft;

		switch(wave.Type)
		{
			case 0:
				wave.TicketsLeft -= length;

			case 1:
				wave.TicketsLeft = 0;
		}

		WaveList.SetArray(WaveIndex, wave);

		int count;
		float engineTime = GetGameTime();
		ClassEnum class;
		for(int i=1; i<=MaxClients; i++)
		{
			if(!IsValidClient(i))
				continue;

			bool found = Classes_GetByIndex(Client[i].Class, class);
			if(found && !class.Group)
				count++;

			if(!wave.TicketsLeft && IsSpec(i))
				CPrintToChat(i, "%s%t", PREFIX, "spawn_ranout");

			if(wave.Message[0])
			{
				CPrintToChat(i, "%s%t", PREFIX, wave.Message);
				Client[i].ResetThinkIsDead();
			}

			if(players.FindValue(i) == -1)
			{
				if(!found || class.Group!=wave.Group)
				{
					if(wave.Sound.Path[0])
					{
						ChangeSong(i, engineTime+wave.Sound.Time, wave.Sound.Path);
						if(!wave.Message[0])
							Client[i].ResetThinkIsDead();
					}
					continue;
				}
			}

			if(wave.SoundTeam.Path[0])
			{
				ChangeSong(i, engineTime+wave.SoundTeam.Time, wave.SoundTeam.Path, 1);
				if(!wave.Message[0])
					Client[i].ResetThinkIsDead();
			}
		}

		if(wave.ShowSCPs)
		{
			if(count > 5)
			{
				CPrintToChatAll("%s%t", PREFIX, "mtf_spawn_scp_over");
			}
			else if(count)
			{
				CPrintToChatAll("%s%t", PREFIX, "mtf_spawn_scp", count);
			}
		}
		
		if (wave.Trigger[0])
		{
			// Send a notification to the map that a spawn happened
			TriggerRelays(wave.Trigger);
		}			

		list = Gamemode_MakeClassList(wave.Classes, length);
	}
	
	return wavetime;
}

public int Gamemode_PresetOrdered(ArrayList list, ArrayList current)
{
	static int index;
	static ArrayList previous;
	int length = list.Length;
	int attempts;
	
	if (previous != current)
	{
		// New array, reset order index
		index = 0;
		previous = current;
	}
	
	do
	{
		if (index >= length)
			index = 0;	// Reset back to loop it
		
		static char buffer[16];
		list.GetString(index, buffer, sizeof(buffer));
		
		index++;
		attempts++;
		
		int class = PresetToClass(buffer, current);
		if (class != -1)
			return class;
	}
	while (attempts < length);
	
	return -1;
}

public int Gamemode_PresetRandom(ArrayList list, ArrayList current)
{
	static char buffer[16];
	list.GetString(GetRandomInt(0, list.Length-1), buffer, sizeof(buffer));
	return PresetToClass(buffer, current);
}

public int Gamemode_PresetRandomOnce(ArrayList list, ArrayList current)
{
	list.Sort(Sort_Random, Sort_String);
	static char buffer[16];
	int length = list.Length;
	for(int i; i<length; i++)
	{
		list.GetString(i, buffer, sizeof(buffer));
		int class = PresetToClass(buffer, current);
		if(current.FindValue(class) == -1)
			return class;
	}
	return -1;
}