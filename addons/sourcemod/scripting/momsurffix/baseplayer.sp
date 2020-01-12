enum struct CBasePlayerOffsets
{
	//...
	int m_surfaceFriction;
	//...
	int m_hGroundEntity;
	//...
	int m_MoveType;
	//...
}

enum struct BasePlayerOffsets
{
	CBasePlayerOffsets cbpoffsets;
}
static BasePlayerOffsets offsets;

methodmap CBasePlayer < AddressBase
{
	property float m_surfaceFriction
	{
		public get() { return view_as<float>(LoadFromAddress(this.Address + offsets.cbpoffsets.m_surfaceFriction, NumberType_Int32)); }
	}
	
	//...
	
	property Address m_hGroundEntity
	{
		public get() { return view_as<Address>(LoadFromAddress(this.Address + offsets.cbpoffsets.m_hGroundEntity, NumberType_Int32)); }
	}
	
	//...
	
	property MoveType m_MoveType
	{
		public get() { return view_as<MoveType>(LoadFromAddress(this.Address + offsets.cbpoffsets.m_MoveType, NumberType_Int8)); }
	}
}

stock bool InitBasePlayer(GameData gd)
{
	char buff[128];
	
	//CBasePlayer
	ASSERT_FMT(gd.GetKeyValue("CBasePlayer::m_surfaceFriction", buff, sizeof(buff)), "Can't get \"CBasePlayer::m_surfaceFriction\" offset from gamedata.");
	offsets.cbpoffsets.m_surfaceFriction = StringToInt(buff);
	
	offsets.cbpoffsets.m_hGroundEntity = FindSendPropInfo("CBasePlayer", "m_hGroundEntity");
	ASSERT_FMT(offsets.cbpoffsets.m_hGroundEntity > 0, "Can't get \"CBasePlayer::m_hGroundEntity\" offset from FindSendPropInfo().");
	
	if(IsValidEntity(0))
	{
		offsets.cbpoffsets.m_MoveType = FindDataMapInfo(0, "m_MoveType");
		ASSERT_FMT(offsets.cbpoffsets.m_MoveType != -1, "Can't get \"CBasePlayer::m_MoveType\" offset from FindDataMapInfo().");
	}
	else
		return false;
	
	return true;
}

stock void LateInitBasePlayer(GameData gd)
{
	ASSERT(IsValidEntity(0));
	offsets.cbpoffsets.m_MoveType = FindDataMapInfo(0, "m_MoveType");
	ASSERT_FMT(offsets.cbpoffsets.m_MoveType != -1, "Can't get \"CBasePlayer::m_MoveType\" offset from FindDataMapInfo().");
}