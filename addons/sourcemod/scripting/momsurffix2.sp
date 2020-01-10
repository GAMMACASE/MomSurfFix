#include "sourcemod"
#include "sdktools"
#include "sdkhooks"
#include "dhooks"

#define SNAME "[momsurffix2] "

public Plugin myinfo = {
    name = "Momentum surf fix \'2",
    author = "GAMMA CASE",
    description = "Ported surf fix from momentum mod.",
    version = "1.0.0",
    url = "http://steamcommunity.com/id/_GAMMACASE_/"
};

#define FLT_EPSILON 1.192092896e-07
#define MAX_CLIP_PLANES 5

enum OSType
{
	OSUnknown = 0,
	OSWindows = 1,
	OSLinux = 2
};

OSType gOSType;

#define CUSTOM_ASSERTION_FAILSTATE
#define FAILSTATE_FUNC SetFailStateCustom
#include "glib/memutils"
#include "momsurffix/utils.sp"
#include "momsurffix/gametrace.sp"
#include "momsurffix/baseplayer.sp"
#include "momsurffix/gamemovement.sp"

ConVar gRampBumpCount, gBounce, gRampInitialRetraceLength;

float vec3_origin[3] = {0.0, 0.0, 0.0};

public void OnPluginStart()
{
	//RegAdminCmd("sm_testmem", SM_TestMem, ADMFLAG_ROOT);
	RegAdminCmd("sm_mom_dumpmempool", SM_Dumpmempool, ADMFLAG_ROOT, "Dumps active momory pool. Mainly for debugging.");
	
	gRampBumpCount = CreateConVar("momsuffix_ramp_bumpcount", "8", "Helps with fixing surf/ramp bugs", .hasMin = true, .min = 4.0, .hasMax = true, .max = 16.0);
	gRampInitialRetraceLength = CreateConVar("momsuffix_ramp_initial_retrace_length", "0.2", "Amount of units used in offset for retraces", .hasMin = true, .min = 0.2, .hasMax = true, .max = 5.0);
	gBounce = FindConVar("sv_bounce");
	ASSERT(gBounce);
	
	AutoExecConfig();
	
	GameData gd = new GameData("momsurffix2.games");
	ASSERT_FINAL(gd);
	
	ValidateGameData(gd);
	
	InitUtils(gd);
	InitGameTrace(gd);
	InitBasePlayer(gd);
	InitGameMovement(gd);
	
	SetupDhooks(gd);
	
	delete gd;
}

public void OnPluginEnd()
{
	CleanUpUtils();
}

public Action SM_Dumpmempool(int client, int args)
{
	DumpMemoryUsage();
	
	return Plugin_Handled;
}

/*public Action SM_TestMem(int client, int args)
{
	
	return Plugin_Handled;
}*/

void ValidateGameData(GameData gd)
{
	gOSType = view_as<OSType>(gd.GetOffset("OSType"));
	ASSERT_MSG(gOSType != OSUnknown, "Failed to get OS type.");
}

void SetupDhooks(GameData gd)
{
	Handle dhook = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Int, ThisPointer_Address);
	
	DHookSetFromConf(dhook, gd, SDKConf_Signature, "CGameMovement::TryPlayerMove");
	DHookAddParam(dhook, HookParamType_Int);
	DHookAddParam(dhook, HookParamType_Int);
	
	ASSERT(DHookEnableDetour(dhook, false, TryPlayerMove_Dhook));
}

public MRESReturn TryPlayerMove_Dhook(Address pThis, Handle hReturn, Handle hParams)
{
	Address pFirstDest = DHookGetParam(hParams, 1);
	Address pFirstTrace = DHookGetParam(hParams, 2);
	
	DHookSetReturn(hReturn, TryPlayerMove(view_as<CGameMovement>(pThis), view_as<Vector>(pFirstDest), view_as<CGameTrace>(pFirstTrace)));
	
	return MRES_Supercede;
}

int TryPlayerMove(CGameMovement pThis, Vector pFirstDest, CGameTrace pFirstTrace)
{
	float original_velocity[3], primal_velocity[3], fixed_origin[3], valid_plane[3], new_velocity[3], end[3], dir[3];
	float allFraction, d, time_left = GetGameFrameTime(), planes[MAX_CLIP_PLANES][3];
	int bumpcount, blocked, numplanes, numbumps = gRampBumpCount.IntValue, i, j, h;
	bool stuck_on_ramp, has_valid_plane;
	CGameTrace pm = CGameTrace();
	
	Vector vecVelocity = pThis.mv.m_vecVelocity;
	vecVelocity.ToArray(original_velocity);
	vecVelocity.ToArray(primal_velocity);
	pThis.mv.m_vecAbsOrigin.ToArray(fixed_origin);
	
	Vector plane_normal;
	static Vector alloced_vector;
	
	if(alloced_vector.Address == Address_Null)
		alloced_vector = Vector();
	
	for(bumpcount = 0; bumpcount < numbumps; bumpcount++)
	{
		if(vecVelocity.LengthSqr() == 0.0)
			break;
		
		if(stuck_on_ramp)
		{
			if(!has_valid_plane)
			{
				plane_normal = pm.plane.normal;
				if(!CloseEnough(VectorToArray(plane_normal), view_as<float>({0.0, 0.0, 0.0})) &&
					!IsEqual(valid_plane, VectorToArray(plane_normal)))
				{
					plane_normal.ToArray(valid_plane);
					has_valid_plane = true;
				}
				else
				{
					for(i = numplanes; i-- > 0;)
					{
						if(!CloseEnough(planes[i], view_as<float>({0.0, 0.0, 0.0})) &&
							FloatAbs(planes[i][0]) <= 1.0 && FloatAbs(planes[i][1]) <= 1.0 && FloatAbs(planes[i][2]) <= 1.0 &&
							!IsEqual(valid_plane, planes[i]))
						{
							VectorCopy(planes[i], valid_plane);
							has_valid_plane = true;
							break;
						}
					}
				}
			}
			
			if(has_valid_plane)
			{
				alloced_vector.FromArray(valid_plane);
				if(valid_plane[2] >= 0.7 && valid_plane[2] <= 1.0)
				{
					ClipVelocity(pThis, vecVelocity, alloced_vector, vecVelocity, 1.0);
					vecVelocity.ToArray(original_velocity);
				}
				else
				{
					ClipVelocity(pThis, vecVelocity, alloced_vector, vecVelocity, 1.0 + gBounce.FloatValue * (1.0 - pThis.player.m_surfaceFriction));
					vecVelocity.ToArray(original_velocity);
				}
				alloced_vector.ToArray(valid_plane);
			}
			else
			{
				float offsets[3];
				offsets[0] = (bumpcount * 2.0) * -gRampInitialRetraceLength.FloatValue;
				offsets[2] = (bumpcount * 2.0) * gRampInitialRetraceLength.FloatValue;
				int valid_planes = 0;
				
				VectorCopy(view_as<float>({0.0, 0.0, 0.0}), valid_plane);
				
				float offset[3], offset_mins[3], offset_maxs[3], buff[3];
				Ray_t ray = Ray_t();
				for(i = 0; i < 3; i++)
				{
					for(j = 0; j < 3; j++)
					{
						for(h = 0; h < 3; h++)
						{
							offset[0] = offsets[i];
							offset[1] = offsets[j];
							offset[2] = offsets[h];
							
							VectorCopy(offset, offset_mins);
							ScaleVector(offset_mins, 0.5);
							VectorCopy(offset, offset_maxs);
							ScaleVector(offset_maxs, 0.5);
							
							if(offset[0] > 0.0)
								offset_mins[0] /= 2.0;
							if(offset[1] > 0.0)
								offset_mins[1] /= 2.0;
							if(offset[2] > 0.0)
								offset_mins[2] /= 2.0;
							
							if(offset[0] < 0.0)
								offset_maxs[0] /= 2.0;
							if(offset[1] < 0.0)
								offset_maxs[1] /= 2.0;
							if(offset[2] < 0.0)
								offset_maxs[2] /= 2.0;
							
							ray.Init((AddVectors(fixed_origin, offset, buff), buff), (SubtractVectors(end, offset, offset), offset),
									(SubtractVectors(VectorToArray(GetPlayerMins(pThis)), offset_mins, offset_mins), offset_mins), 
									(AddVectors(VectorToArray(GetPlayerMaxs(pThis)), offset_maxs, offset_maxs), offset_maxs));
							UTIL_TraceRay(ray, MASK_PLAYERSOLID, pThis, COLLISION_GROUP_PLAYER_MOVEMENT, pm);
							
							plane_normal = pm.plane.normal;
							//PrintToServer(SNAME..."DEBUG: TraceFired! plane_normal: [%f | %f | %f]", plane_normal.x, plane_normal.y, plane_normal.z);
							
							if(FloatAbs(plane_normal.x) <= 1.0 && FloatAbs(plane_normal.y) <= 1.0 &&
								FloatAbs(plane_normal.z) <= 1.0 && pm.fraction > 0.0 && pm.fraction < 1.0 && !pm.startsolid)
							{
								valid_planes++;
								plane_normal.ToArray(valid_plane);
							}
						}
					}
				}
				ray.Free();
				
				if(valid_planes > 0 && !CloseEnough(valid_plane, view_as<float>({0.0, 0.0, 0.0})))
				{
					has_valid_plane = true;
					VectorNormalize(valid_plane);
					continue;
				}
			}
			
			if(has_valid_plane)
			{
				VectorMA(fixed_origin, gRampInitialRetraceLength.FloatValue, valid_plane, fixed_origin);
			}
			else
			{
				stuck_on_ramp = false;
				continue;
			}
		}
		
		VectorMA(fixed_origin, time_left, VectorToArray(vecVelocity), end);
		
		if(pFirstDest.Address != Address_Null && IsEqual(end, VectorToArray(pFirstDest)))
		{
			pm.Free();
			pm = pFirstTrace;
		}
		else
		{
			Vector vec1 = Vector();
			vec1.FromArray(end);
			
			if(stuck_on_ramp && has_valid_plane)
			{
				alloced_vector.FromArray(fixed_origin);
				TracePlayerBBox(pThis, alloced_vector, vec1, MASK_PLAYERSOLID, COLLISION_GROUP_PLAYER_MOVEMENT, pm);
				pm.plane.normal.FromArray(valid_plane);
			}
			else
				TracePlayerBBox(pThis, pThis.mv.m_vecAbsOrigin, vec1, MASK_PLAYERSOLID, COLLISION_GROUP_PLAYER_MOVEMENT, pm);
			
			vec1.Free();
		}
		
		if(bumpcount > 0 && pThis.player.m_hGroundEntity == view_as<Address>(-1) && !IsValidMovementTrace(pThis, pm))
		{
			has_valid_plane = false;
			stuck_on_ramp = true;
			continue;
		}
		
		if(pm.allsolid)
		{
			vecVelocity.FromArray(vec3_origin);
			
			pm.Free();
			return 4;
		}
		
		if(pm.fraction > 0.0)
		{
			if((bumpcount == 0 || pThis.player.m_hGroundEntity != view_as<Address>(-1)) && numbumps > 0 && pm.fraction == 1.0)
			{
				CGameTrace stuck = CGameTrace();
				TracePlayerBBox(pThis, pm.endpos, pm.endpos, MASK_PLAYERSOLID, COLLISION_GROUP_PLAYER_MOVEMENT, stuck);
				
				if((stuck.startsolid || stuck.fraction != 1.0) && bumpcount == 0)
				{
					has_valid_plane = false;
					stuck_on_ramp = true;
					
					stuck.Free();
					continue;
				}
				else if(stuck.startsolid || stuck.fraction != 1.0)
				{
					vecVelocity.FromArray(vec3_origin);
					
					stuck.Free();
					break;
				}
				
				stuck.Free();
			}
			
			has_valid_plane = false;
			stuck_on_ramp = false;
			
			vecVelocity.ToArray(original_velocity);
			pThis.mv.m_vecAbsOrigin.FromArray(VectorToArray(pm.endpos));
			pThis.mv.m_vecAbsOrigin.ToArray(fixed_origin);
			allFraction += pm.fraction;
			numplanes = 0;
		}
		
		if(CloseEnoughFloat(pm.fraction, 1.0))
			break;
		
		MoveHelper().AddToTouched(pm, vecVelocity);
		
		if(pm.plane.normal.z >= 0.7)
			blocked |= 1;
		
		if(CloseEnoughFloat(pm.plane.normal.z, 0.0))
			blocked |= 2;
		
		time_left -= time_left * pm.fraction;
		
		if(numplanes >= MAX_CLIP_PLANES)
		{
			vecVelocity.FromArray(vec3_origin);
			break;
		}
		
		pm.plane.normal.ToArray(planes[numplanes]);
		numplanes++;
		
		if(numplanes == 1 && pThis.player.m_MoveType == MOVETYPE_WALK && pThis.player.m_hGroundEntity != view_as<Address>(-1))
		{
			Vector vec1 = Vector();
			Vector vec2 = Vector();
			if(planes[0][2] >= 0.7)
			{
				vec1.FromArray(original_velocity);
				vec2.FromArray(planes[0]);
				alloced_vector.FromArray(new_velocity);
				ClipVelocity(pThis, vec1, vec2, alloced_vector, 1.0);
				alloced_vector.ToArray(original_velocity);
				alloced_vector.ToArray(new_velocity);
			}
			else
			{
				vec1.FromArray(original_velocity);
				vec2.FromArray(planes[0]);
				alloced_vector.FromArray(new_velocity);
				ClipVelocity(pThis, vec1, vec2, alloced_vector, 1.0 + gBounce.FloatValue * (1.0 - pThis.player.m_surfaceFriction));
				alloced_vector.ToArray(new_velocity);
			}
			
			vecVelocity.FromArray(new_velocity);
			VectorCopy(new_velocity, original_velocity);
			
			vec1.Free();
			vec2.Free();
		}
		else
		{
			Vector vec1 = Vector();
			for(i = 0; i < numplanes; i++)
			{
				vec1.FromArray(original_velocity);
				alloced_vector.FromArray(planes[i]);
				ClipVelocity(pThis, vec1, alloced_vector, vecVelocity, 1.0);
				alloced_vector.ToArray(planes[i]);
				
				for(j = 0; j < numplanes; j++)
					if(j != i)
						if(vecVelocity.Dot(planes[j]) < 0.0)
							break;
				
				if(j == numplanes)
					break;
			}
			vec1.Free();
			
			if(i != numplanes)
			{
				
			}
			else
			{
				if(numplanes != 2)
				{
					vecVelocity.FromArray(vec3_origin);
					break;
				}
				
				if(CloseEnough(planes[0], planes[1]))
				{
					VectorMA(original_velocity, 20.0, planes[0], new_velocity);
					vecVelocity.x = new_velocity[0];
					vecVelocity.y = new_velocity[1];
					
					break;
				}
				
				GetVectorCrossProduct(planes[0], planes[1], dir);
				VectorNormalize(dir);
				
				d = vecVelocity.Dot(dir);
				
				ScaleVector(dir, d);
				vecVelocity.FromArray(dir);
			}
			
			d = vecVelocity.Dot(primal_velocity);
			if(d <= 0.0)
			{
				vecVelocity.FromArray(vec3_origin);
				break;
			}
		}
	}
	
	if(CloseEnoughFloat(allFraction, 0.0))
		vecVelocity.FromArray(vec3_origin);
	
	pm.Free();
	return blocked;
}

stock void VectorMA(float start[3], float scale, float dir[3], float dest[3])
{
	dest[0] = start[0] + dir[0] * scale;
	dest[1] = start[1] + dir[1] * scale;
	dest[2] = start[2] + dir[2] * scale;
}

stock float VectorNormalize(float vec[3])
{
	float iradius = 1.0 / ( SquareRoot(vec[0]*vec[0] + vec[1]*vec[1] + vec[2]*vec[2]) + FLT_EPSILON);
	
	vec[0] *= iradius;
	vec[1] *= iradius;
	vec[2] *= iradius;
	
	return iradius;
}

stock void VectorCopy(float from[3], float to[3])
{
	to[0] = from[0];
	to[1] = from[1];
	to[2] = from[2];
}

stock float[] VectorToArray(Vector vec)
{
	float ret[3];
	vec.ToArray(ret);
	return ret;
}

stock bool IsEqual(float a[3], float b[3])
{
	return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
}

stock bool CloseEnough(float a[3], float b[3], float eps = FLT_EPSILON)
{
	return FloatAbs(a[0] - b[0]) <= eps &&
		FloatAbs(a[1] - b[1]) <= eps &&
		FloatAbs(a[2] - b[2]) <= eps;
}

stock bool CloseEnoughFloat(float a, float b, float eps = FLT_EPSILON)
{
	return FloatAbs(a - b) <= eps;
}

public void SetFailStateCustom(const char[] fmt, any ...)
{
	char buff[ASSERT_FMT_STRING_LEN];
	VFormat(buff, sizeof(buff), fmt, 2);
	
	CleanUpUtils();
	
	SetFailState(buff);
}

stock bool IsValidMovementTrace(CGameMovement pThis, CGameTrace tr)
{
	if(tr.allsolid || tr.startsolid)
		return false;
	
	if(CloseEnoughFloat(tr.fraction, 0.0))
		return false;
	
	Vector plane_normal = tr.plane.normal;
	if(FloatAbs(plane_normal.x) > 1.0 || FloatAbs(plane_normal.y) > 1.0 || FloatAbs(plane_normal.z) > 1.0)
		return false;
	
	CGameTrace stuck = CGameTrace();
	
	TracePlayerBBox(pThis, tr.endpos, tr.endpos, MASK_PLAYERSOLID, COLLISION_GROUP_PLAYER_MOVEMENT, stuck)
	if(stuck.startsolid || !CloseEnoughFloat(stuck.fraction, 1.0))
	{
		stuck.Free();
		return false;
	}
	
	stuck.Free();
	return true;
}

/*stock void TracePlayerBBox(CGameMovement pThis, float start[3], float end[3], int mask, int collisionGroup, CGameTrace trace)
{
	Ray_t ray = Ray_t();
	
	ray.Init(start, end, VectorToArray(GetPlayerMins(pThis)), VectorToArray(GetPlayerMaxs(pThis)));
	UTIL_TraceRay(ray, mask, pThis, collisionGroup, trace);
	
	ray.Free();
}*/

stock void UTIL_TraceRay(Ray_t ray, int mask, CGameMovement gm, int collisionGroup, CGameTrace trace)
{
	CTraceFilterSimple filter = LockTraceFilter(gm, collisionGroup);
	
	gm.m_nTraceCount++;
	ITraceListData tracelist = gm.m_pTraceListData;
	
	if(tracelist.Address != Address_Null && tracelist.CanTraceRay(ray))
		TraceRayAgainstLeafAndEntityList(ray, tracelist, mask, filter, trace);
	else
		TraceRay(ray, mask, filter, trace);
	
	UnlockTraceFilter(gm, filter);
}