enum struct CGameMovementOffsets
{
	int player;
	int mv;
	//...
	int m_pTraceListData;
	int m_nTraceCount;
}

enum struct CMoveDataOffsets
{
	//...
	int m_vecVelocity;
	//...
	int m_vecAbsOrigin;
}

enum struct GameMoventOffsets
{
	CGameMovementOffsets cgmoffsets;
	CMoveDataOffsets cmdoffsets;
}
static GameMoventOffsets offsets;

methodmap CMoveData < AddressBase
{
	//...
	
	property Vector m_vecVelocity
	{
		public get() { return view_as<Vector>(this.Address + offsets.cmdoffsets.m_vecVelocity); }
	}
	
	//...
	
	property Vector m_vecAbsOrigin
	{
		public get() { return view_as<Vector>(this.Address + offsets.cmdoffsets.m_vecAbsOrigin); }
	}
}

methodmap CGameMovement < AddressBase
{
	property CBasePlayer player
	{
		public get() { return view_as<CBasePlayer>(LoadFromAddress(this.Address + offsets.cgmoffsets.player, NumberType_Int32)); }
	}
	
	property CMoveData mv
	{
		public get() { return view_as<CMoveData>(LoadFromAddress(this.Address + offsets.cgmoffsets.mv, NumberType_Int32)); }
	}
	
	//...
	
	property ITraceListData m_pTraceListData
	{
		public get() { return view_as<ITraceListData>(LoadFromAddress(this.Address + offsets.cgmoffsets.m_pTraceListData, NumberType_Int32)); }
	}
	
	property int m_nTraceCount
	{
		public get() { return LoadFromAddress(this.Address + offsets.cgmoffsets.m_nTraceCount, NumberType_Int32); }
		public set(int _tracecount) { StoreToAddress(this.Address + offsets.cgmoffsets.m_nTraceCount, _tracecount, NumberType_Int32); }
	}
}

static Handle gAddToTouched;

methodmap IMoveHelper < AddressBase
{
	public bool AddToTouched(CGameTrace trace, Vector vec)
	{
		return SDKCall(gAddToTouched, this.Address, trace, vec);
	}
}

enum //Collision_Group_t
{
	COLLISION_GROUP_NONE  = 0,
	COLLISION_GROUP_DEBRIS,			// Collides with nothing but world and static stuff
	COLLISION_GROUP_DEBRIS_TRIGGER, // Same as debris, but hits triggers
	COLLISION_GROUP_INTERACTIVE_DEBRIS,	// Collides with everything except other interactive debris or debris
	COLLISION_GROUP_INTERACTIVE,	// Collides with everything except interactive debris or debris
	COLLISION_GROUP_PLAYER,
	COLLISION_GROUP_BREAKABLE_GLASS,
	COLLISION_GROUP_VEHICLE,
	COLLISION_GROUP_PLAYER_MOVEMENT,  // For HL2, same as Collision_Group_Player, for
										// TF2, this filters out other players and CBaseObjects
	COLLISION_GROUP_NPC,			// Generic NPC group
	COLLISION_GROUP_IN_VEHICLE,		// for any entity inside a vehicle
	COLLISION_GROUP_WEAPON,			// for any weapons that need collision detection
	COLLISION_GROUP_VEHICLE_CLIP,	// vehicle clip brush to restrict vehicle movement
	COLLISION_GROUP_PROJECTILE,		// Projectiles!
	COLLISION_GROUP_DOOR_BLOCKER,	// Blocks entities not permitted to get near moving doors
	COLLISION_GROUP_PASSABLE_DOOR,	// Doors that the player shouldn't collide with
	COLLISION_GROUP_DISSOLVING,		// Things that are dissolving are in this group
	COLLISION_GROUP_PUSHAWAY,		// Nonsolid on client and server, pushaway in player code

	COLLISION_GROUP_NPC_ACTOR,		// Used so NPCs in scripts ignore the player.
	COLLISION_GROUP_NPC_SCRIPTED,	// USed for NPCs in scripts that should not collide with each other

	LAST_SHARED_COLLISION_GROUP
};

static Handle gClipVelocity, gLockTraceFilter, gUnlockTraceFilter, gGetPlayerMins, gGetPlayerMaxs, gTracePlayerBBox;
static IMoveHelper sm_pSingleton;

stock void InitGameMovement(GameData gd)
{
	char buff[128];
	
	//CGameMovement
	ASSERT_FMT(gd.GetKeyValue("CGameMovement::player", buff, sizeof(buff)), "Can't get \"CGameMovement::player\" offset from gamedata.");
	offsets.cgmoffsets.player = StringToInt(buff);
	ASSERT_FMT(gd.GetKeyValue("CGameMovement::mv", buff, sizeof(buff)), "Can't get \"CGameMovement::mv\" offset from gamedata.");
	offsets.cgmoffsets.mv = StringToInt(buff);
	ASSERT_FMT(gd.GetKeyValue("CGameMovement::m_pTraceListData", buff, sizeof(buff)), "Can't get \"CGameMovement::m_pTraceListData\" offset from gamedata.");
	offsets.cgmoffsets.m_pTraceListData = StringToInt(buff);
	ASSERT_FMT(gd.GetKeyValue("CGameMovement::m_nTraceCount", buff, sizeof(buff)), "Can't get \"CGameMovement::m_nTraceCount\" offset from gamedata.");
	offsets.cgmoffsets.m_nTraceCount = StringToInt(buff);
	
	//CMoveData
	ASSERT_FMT(gd.GetKeyValue("CMoveData::m_vecVelocity", buff, sizeof(buff)), "Can't get \"CMoveData::m_vecVelocity\" offset from gamedata.");
	offsets.cmdoffsets.m_vecVelocity = StringToInt(buff);
	ASSERT_FMT(gd.GetKeyValue("CMoveData::m_vecAbsOrigin", buff, sizeof(buff)), "Can't get \"CMoveData::m_vecAbsOrigin\" offset from gamedata.");
	offsets.cmdoffsets.m_vecAbsOrigin = StringToInt(buff);
	
	//sm_pSingleton
	sm_pSingleton = view_as<IMoveHelper>(gd.GetAddress("sm_pSingleton"));
	ASSERT(sm_pSingleton.Address != Address_Null);
	
	//AddToTouched
	StartPrepSDKCall(SDKCall_Raw);
	
	PrepSDKCall_SetVirtual(gd.GetOffset("AddToTouched"));
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	
	gAddToTouched = EndPrepSDKCall();
	ASSERT(gAddToTouched);
	
	//ClipVelocity
	StartPrepSDKCall(SDKCall_Raw);
	
	PrepSDKCall_SetVirtual(gd.GetOffset("ClipVelocity"));
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	
	gClipVelocity = EndPrepSDKCall();
	ASSERT(gClipVelocity);
	
	//LockTraceFilter
	StartPrepSDKCall(SDKCall_Raw);
	
	PrepSDKCall_SetVirtual(gd.GetOffset("LockTraceFilter"));
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	
	gLockTraceFilter = EndPrepSDKCall();
	ASSERT(gLockTraceFilter);
	
	//UnlockTraceFilter
	StartPrepSDKCall(SDKCall_Raw);
	
	PrepSDKCall_SetVirtual(gd.GetOffset("UnlockTraceFilter"));
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer);
	
	gUnlockTraceFilter = EndPrepSDKCall();
	ASSERT(gUnlockTraceFilter);
	
	//GetPlayerMins
	StartPrepSDKCall(SDKCall_Raw);
	
	PrepSDKCall_SetVirtual(gd.GetOffset("GetPlayerMins"));
	
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	
	gGetPlayerMins = EndPrepSDKCall();
	ASSERT(gGetPlayerMins);
	
	//GetPlayerMaxs
	StartPrepSDKCall(SDKCall_Raw);
	
	PrepSDKCall_SetVirtual(gd.GetOffset("GetPlayerMaxs"));
	
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	
	gGetPlayerMaxs = EndPrepSDKCall();
	ASSERT(gGetPlayerMaxs);
	
	//TracePlayerBBox
	StartPrepSDKCall(SDKCall_Raw);
	
	PrepSDKCall_SetVirtual(gd.GetOffset("TracePlayerBBox"));
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	
	gTracePlayerBBox = EndPrepSDKCall();
	ASSERT(gTracePlayerBBox);
}

stock void TracePlayerBBox(CGameMovement pThis, Vector start, Vector end, int mask, int collisionGroup, CGameTrace trace)
{
	SDKCall(gTracePlayerBBox, pThis, start, end, mask, collisionGroup, trace);
}

stock CTraceFilterSimple LockTraceFilter(CGameMovement pThis, int collisionGroup)
{
	ASSERT(pThis.Address != Address_Null);
	return SDKCall(gLockTraceFilter, pThis.Address, collisionGroup);
}

stock void UnlockTraceFilter(CGameMovement pThis, CTraceFilterSimple filter)
{
	ASSERT(pThis.Address != Address_Null);
	SDKCall(gUnlockTraceFilter, pThis.Address, filter.Address);
}

stock int ClipVelocity(CGameMovement pThis, Vector invec, Vector normal, Vector out, float overbounce)
{
	ASSERT(pThis.Address != Address_Null);
	return SDKCall(gClipVelocity, pThis.Address, invec.Address, normal.Address, out.Address, overbounce);
}

stock Vector GetPlayerMins(CGameMovement pThis)
{
	return SDKCall(gGetPlayerMins, pThis.Address);
}

stock Vector GetPlayerMaxs(CGameMovement pThis)
{
	return SDKCall(gGetPlayerMaxs, pThis.Address);
}

stock IMoveHelper MoveHelper()
{
	return sm_pSingleton;
}