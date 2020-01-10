#include "sourcemod"
#include "sdktools"
#include "sdkhooks"
#include "dhooks"

#define SNAME "[momsurffix] "

#include "glib/memutils"
#include "momsurffix/x86opcodes.sp"

public Plugin myinfo = {
    name = "Momentum surf fix",
    author = "GAMMA CASE",
    description = "Ported surf fix from momentum mod.",
    version = "1.0.0",
    url = "http://steamcommunity.com/id/_GAMMACASE_/"
};

enum OSType
{
	OSUnknown = 0,
	OSWindows = 1,
	OSLinux = 2
};

#define VARIABLES_SIZE 24
#define SAFE_FUNCTION_THRESHOLD 250

OSType gOSType;

PatchHandler gGlobalPatch,
	gFunctionPatch;
ArrayList gGlobalJmpPatches;

public void OnPluginStart()
{
	GameData gd = new GameData("momsurffix.games");
	ASSERT(gd);
	
	ValidateGameData(gd);
	SaveBytes(gd);
	StartPatching(gd);
	ReallocBytes(gd);
	FindPlaceForFunction(gd);
	InsertCall(gd);
	InsertFunction();
	
	SetupDhook();
	
	delete gd;
}

public void OnPluginEnd()
{
	for(int i = 0; i < gGlobalJmpPatches.Length; i++)
		view_as<PatchHandler>(gGlobalJmpPatches.Get(i)).Restore();
	
	gGlobalPatch.Restore();
	gFunctionPatch.Restore();
}

void FindPlaceForFunction(GameData gd)
{
	Address end = gd.GetAddress("ModuleStart");
	end += LoadFromAddress(end + gd.GetOffset("ModuleSizeOffset"), NumberType_Int32);
	
	int len = 0;
	for(int i = view_as<int>(end) - 1, atmpt = 0; len < SAFE_FUNCTION_THRESHOLD; i--, len++)
	{
		if(len == SAFE_FUNCTION_THRESHOLD - 1)
			PrintToServer(SNAME..."Address: %i", i);
		if(LoadFromAddress(view_as<Address>(i), NumberType_Int8) != 0)
		{
			if(len != 0 && ++atmpt > 10)
				SetFailState(SNAME..."Failed to find place for a function after %i attempts!", atmpt);
			
			len = 0;
		}
	}
	
	gFunctionPatch = PatchHandler(end - len);
	gFunctionPatch.Save(len);
}

void SetupDhook()
{
	Handle dhook = DHookCreateDetour(gFunctionPatch.Address + VARIABLES_SIZE, CallConv_STDCALL, ReturnType_Int, ThisPointer_Ignore);
	
	DHookAddParam(dhook, HookParamType_Int);
	DHookAddParam(dhook, HookParamType_Int);
	
	ASSERT(DHookEnableDetour(dhook, true, Dhook_Callback));
}

public MRESReturn Dhook_Callback(Handle hReturn, Handle hParams)
{
	int p1 = DHookGetParam(hParams, 1);
	int p2 = DHookGetParam(hParams, 2);
	
	int ret = DHookGetReturn(hReturn);
	
	PrintToServer(SNAME..."Dhook triggered: p1: %i [Data: %f], p2: %i, ret: %i", p1, LoadFromAddress(p1 + 28, NumberType_Int32), p2, ret);
	
	return MRES_Ignored;
}

void InsertFunction()
{
	/*	Locals offsets win: 
	*	planes:
	*	plane[0].x = [esp + 84]
	*	plane[0].y = [esp + 88]
	*	plane[0].z = [esp + 92]
	*	
	*	plane[1].x = [esp + 96]
	*	plane[1].y = [esp + 100]
	*	plane[1].z = [esp + 104]
	*	
	*	original_velocity.x = [esp + 36]
	*	original_velocity.y = [esp + 40]
	*	original_velocity.z = [esp + 44]
	*	
	*	mv = [edi + 8]
	*	mv->m_vecVelocity.x = [mv + 64]
	*	mv->m_vecVelocity.y = [mv + 68]
	*	
	*	$exit = 159
	*/
	
	/*	win:
	*	55							push ebp
	*	8B EC						mov ebp, esp
	*	51							push ecx
	*	52							push edx
	*								
	*	8B 55 08					mov edx, [ebp + 8]
	*								
	*	F3 0F 10 25 ?? ?? ?? ??		movss xmm4, $fabs
	*								
	*	F3 0F 10 0D ?? ?? ?? ??		movss xmm1, $epsilon
	*								
	*	F3 0F 10 52 54				movss xmm2, [edx + 84]
	*	F3 0F 10 5A 60				movss xmm3, [edx + 96]
	*	F3 0F 5C D3					subss xmm2, xmm3
	*								
	*	0F 54 D4					andps xmm2, xmm4
	*	0F 2F CA					comiss xmm1, xmm2
	*								
	*	B8 00 00 00 00				mov eax, 0
	*	72 ??						jb $exit
	*								
	*	F3 0F 10 52 58				movss xmm2, [edx + 88]
	*	F3 0F 10 5A 64				movss xmm3, [edx + 100]
	*	F3 0F 5C D3					subss xmm2, xmm3
	*								
	*	0F 54 D4					andps xmm2, xmm4
	*	0F 2F CA					comiss xmm1, xmm2
	*								
	*	B8 00 00 00 00				mov eax, 0
	*	72 ??						jb $exit
	*								
	*	F3 0F 10 52 5C				movss xmm2, [edx + 92]
	*	F3 0F 10 5A 68				movss xmm3, [edx + 104]
	*	F3 0F 5C D3					subss xmm2, xmm3
	*								
	*	0F 54 D4					andps xmm2, xmm4
	*	0F 2F CA					comiss xmm1, xmm2
	*								
	*	B8 00 00 00 00				mov eax, 0
	*	72 ??						jb $exit
	*								
	*	F3 0F 10 05 ?? ?? ?? ??		movss xmm0, $scale
	*								
	*	F3 0F 10 4A 54				movss xmm1, [edx + 84]
	*	F3 0F 10 52 58				movss xmm2, [edx + 88]
	*								
	*	F3 0F 59 C8					mulss xmm1, xmm0
	*	F3 0F 59 D0					mulss xmm2, xmm0
	*								
	*	F3 0F 58 4A 24				addss xmm1, [edx + 36]
	*	F3 0F 58 52 28				addss xmm2, [edx + 40]
	*								
	*	8B 4D 0C					mov ecx, [ebp + 12]
	*								
	*	F3 0F 11 49 40				movss [ecx + 64], xmm1
	*	F3 0F 11 51 44				movss [ecx + 68], xmm2
	*								
	*	B8 01 00 00 00				mov eax, 1
	*								
	*	$exit:
	*	5A							pop edx
	*	59							pop ecx
	*	8B E5						mov esp, ebp
	*	5D							pop ebp
	*	C2 08 00					ret 8
	*/
	
	Address start = gFunctionPatch.Address + VARIABLES_SIZE;
	Address fabs = start - 24;
	Address epsilon = start - 8;
	Address scale = start - 4
	
	//Creating fabs mask
	StoreToAddress(fabs, 0x7FFFFFFF, NumberType_Int32);
	StoreToAddress(fabs + 4, 0x7FFFFFFF, NumberType_Int32);
	StoreToAddress(fabs + 8, 0x7FFFFFFF, NumberType_Int32);
	StoreToAddress(fabs + 12, 0x7FFFFFFF, NumberType_Int32);
	
	//Epsilon value: 1.1920929e-7
	StoreToAddress(epsilon, 0x34000000, NumberType_Int32);
	
	//Scale: 20.0f
	StoreToAddress(scale, 0x47c35000, NumberType_Int32);
	
	StoreToAddress(start, 0x51_EC_8B_55, NumberType_Int32);
	StoreToAddress(start + 4, 0x08_55_8B_52, NumberType_Int32);
	StoreToAddress(start + 8, 0x25_10_0F_F3, NumberType_Int32);
	StoreToAddress(start + 12, view_as<int>(fabs), NumberType_Int32);
	StoreToAddress(start + 16, 0x0D_10_0F_F3, NumberType_Int32);
	StoreToAddress(start + 20, view_as<int>(epsilon), NumberType_Int32);
	StoreToAddress(start + 24, 0x52_10_0F_F3, NumberType_Int32);
	StoreToAddress(start + 28, 0x10_0F_F3_54, NumberType_Int32);
	StoreToAddress(start + 32, 0x0F_F3_60_5A, NumberType_Int32);
	StoreToAddress(start + 36, 0x54_0F_D3_5C, NumberType_Int32);
	StoreToAddress(start + 40, 0xCA_2F_0F_D4, NumberType_Int32);
	StoreToAddress(start + 44, 0x00_00_00_B8, NumberType_Int32);
	StoreToAddress(start + 48, 0x72_00, NumberType_Int16);
	
	StoreToAddress(start + 50, 159 - 50, NumberType_Int8);
	
	StoreToAddress(start + 51, 0x52_10_0F_F3, NumberType_Int32);
	StoreToAddress(start + 55, 0x10_0F_F3_58, NumberType_Int32);
	StoreToAddress(start + 59, 0x0F_F3_64_5A, NumberType_Int32);
	StoreToAddress(start + 63, 0x54_0F_D3_5C, NumberType_Int32);
	StoreToAddress(start + 67, 0xCA_2F_0F_D4, NumberType_Int32);
	StoreToAddress(start + 71, 0x00_00_00_B8, NumberType_Int32);
	StoreToAddress(start + 75, 0x72_00, NumberType_Int16);
	
	StoreToAddress(start + 77, 159 - 77, NumberType_Int8);
	
	StoreToAddress(start + 78, 0x52_10_0F_F3, NumberType_Int32);
	StoreToAddress(start + 82, 0x10_0F_F3_5C, NumberType_Int32);
	StoreToAddress(start + 86, 0x0F_F3_68_5A, NumberType_Int32);
	StoreToAddress(start + 90, 0x54_0F_D3_5C, NumberType_Int32);
	StoreToAddress(start + 94, 0xCA_2F_0F_D4, NumberType_Int32);
	StoreToAddress(start + 98, 0x00_00_00_B8, NumberType_Int32);
	StoreToAddress(start + 102, 0x72_00, NumberType_Int16);
	
	StoreToAddress(start + 104, 159 - 104, NumberType_Int8);
	
	StoreToAddress(start + 105, 0x05_10_0F_F3, NumberType_Int32);
	StoreToAddress(start + 109, view_as<int>(scale), NumberType_Int32);
	StoreToAddress(start + 113, 0x4A_10_0F_F3, NumberType_Int32);
	StoreToAddress(start + 117, 0x10_0F_F3_54, NumberType_Int32);
	StoreToAddress(start + 121, 0x0F_F3_58_52, NumberType_Int32);
	StoreToAddress(start + 125, 0x0F_F3_C8_59, NumberType_Int32);
	StoreToAddress(start + 129, 0x0F_F3_D0_59, NumberType_Int32);
	StoreToAddress(start + 133, 0xF3_24_4A_58, NumberType_Int32);
	StoreToAddress(start + 137, 0x28_52_58_0F, NumberType_Int32);
	StoreToAddress(start + 141, 0xF3_0C_4D_8B, NumberType_Int32);
	StoreToAddress(start + 145, 0x40_49_11_0F, NumberType_Int32);
	StoreToAddress(start + 149, 0x51_11_0F_F3, NumberType_Int32);
	StoreToAddress(start + 153, 0x00_01_B8_44, NumberType_Int32);
	StoreToAddress(start + 157, 0x59_5A_00_00, NumberType_Int32);
	StoreToAddress(start + 161, 0xC2_5D_E5_8B, NumberType_Int32);
	StoreToAddress(start + 165, 0x00_08, NumberType_Int16);
	
	DumpOnAddress(start - 24, 200, 20);
}

void InsertCall(GameData gd)
{
	/*	win:
	*	FF 77 08			push [edi+8]
	*	54					push esp
	*	E8 ?? ?? ?? ??		call $fnc
	*	83 F8 01			cmp eax, 1
	*	0F 84 ?? ?? ?? ??	je $break
	*/
	
	Address callstart = gd.GetAddress("ReallocationStart");
	x86JumpInstruction instr;
	char soffs[32], key[128];
	GetOSKey(key, sizeof(key));
	Format(key, sizeof(key), "%sbreak", key);
	
	gd.GetKeyValue(key, soffs, sizeof(soffs));
	
	instr.ResolveInstruction(gd.GetAddress("TryPlayerMove_Start") + StringToInt(soffs), soffs);
	
	StoreToAddress(callstart, 0x54_08_77_FF, NumberType_Int32);
	StoreToAddress(callstart + 4, 0xE8, NumberType_Int8);
	StoreToAddress(callstart + 5, view_as<int>((gFunctionPatch.Address + VARIABLES_SIZE) - (callstart + 9)), NumberType_Int32);
	StoreToAddress(callstart + 9, 0x0F_01_F8_83, NumberType_Int32);
	StoreToAddress(callstart + 13, 0x84, NumberType_Int8);
	StoreToAddress(callstart + 14, view_as<int>(instr.GetJmpTo() - (callstart + 18)), NumberType_Int32);
}

void ValidateGameData(GameData gd)
{
	gOSType = view_as<OSType>(gd.GetOffset("WinOrLin"));
	if(gOSType == OSUnknown)
		SetFailState(SNAME..."Unsupported OS Type found!");
	
	Address addr = gd.GetAddress("TryPlayerMove_Start");
	ASSERT(addr != Address_Null);
	
	addr = gd.GetAddress("TryPlayerMove_End");
	ASSERT(addr != Address_Null);
	
	addr = gd.GetAddress("FirstPatch");
	ASSERT(addr != Address_Null);
	
	addr = gd.GetAddress("SecondPatch");
	ASSERT(addr != Address_Null);
	
	addr = gd.GetAddress("ReallocationStart");
	ASSERT(addr != Address_Null);
	
	addr = gd.GetAddress("ModuleStart");
	ASSERT(addr != Address_Null);
	
	int offs = gd.GetOffset("FirstPatchSize");
	ASSERT(offs > 0);
	
	offs = gd.GetOffset("SecondPatchSizePt1");
	ASSERT(offs > 0);
	
	offs = gd.GetOffset("SecondPatchSizeSkip");
	ASSERT(offs > 0);
	
	offs = gd.GetOffset("SecondPatchSizePt2");
	ASSERT(offs > 0);
	
	offs = gd.GetOffset("ModuleSizeOffset");
	ASSERT(offs > 0);
}

void SaveBytes(GameData gd)
{
	gGlobalJmpPatches = new ArrayList();
	gGlobalPatch = PatchHandler(gd.GetAddress("ReallocationStart"));
	
	int patchLen = view_as<int>(gd.GetAddress("SecondPatch")) - 
		gGlobalPatch.Any +
		gd.GetOffset("SecondPatchSizePt1") + 
		gd.GetOffset("SecondPatchSizeSkip") +
		gd.GetOffset("SecondPatchSizePt2");
	
	gGlobalPatch.Save(patchLen);
}

enum struct Section
{
	Address start;
	Address end;
}

#define NUM_SECTIONS 2

void ReallocBytes(GameData gd)
{
	Section sections[NUM_SECTIONS];
	
	sections[0].start = gd.GetAddress("ReallocationStart");
	sections[0].end = gd.GetAddress("FirstPatch");
	
	sections[1].start = gd.GetAddress("FirstPatch") + gd.GetOffset("FirstPatchSize");
	sections[1].end = gd.GetAddress("SecondPatch");
	
	int patchSize = gd.GetOffset("SecondPatchSizePt1");
	
	MoveBytes(sections[1].end + patchSize, sections[1].end, gd.GetOffset("SecondPatchSizeSkip"));
	sections[1].end += patchSize;
	
	FixupJumpInstructions(gd, gd.GetAddress("TryPlayerMove_Start"), sections);
	
	CutNCopyBytes(sections[1].start, sections[1].start + gd.GetOffset("SecondPatchSizePt1") + gd.GetOffset("SecondPatchSizePt2"), view_as<int>(sections[1].end - sections[1].start));
	CutNCopyBytes(sections[0].start, sections[0].start + gd.GetOffset("SecondPatchSizePt1") 
													+ gd.GetOffset("SecondPatchSizePt2")
													+ gd.GetOffset("FirstPatchSize"), view_as<int>(sections[0].end - sections[0].start));
}

void FixupJumpInstructions(GameData gd, Address start, Section[] sections)
{
	char key[128];
	
	GetOSKey(key, sizeof(key));
	
	int patch1Length = view_as<int>(sections[1].start - sections[0].end);
	int patch2Length = gd.GetOffset("SecondPatchSizePt1") + gd.GetOffset("SecondPatchSizePt2");
	
	x86JumpInstruction instr;
	PatchHandler ptch;
	char buff[128], soffs[32];
	for(int i = 1;; i++)
	{
		Format(buff, sizeof(buff), "%s%i", key, i);
		if(!gd.GetKeyValue(buff, soffs, sizeof(soffs)))
			break;
		
		instr.ResolveInstruction(start + StringToInt(soffs), soffs);
		
		ptch = PatchHandler(instr.base + instr.baseLen);
		ptch.Save(instr.jmpLen);
		gGlobalJmpPatches.Push(ptch);
		
		//uhh?
		switch(DetermineSection(sections, instr.GetJmpTo()))
		{
			case 0:
			{
				switch(DetermineSection(sections, instr.base))
				{
					case 0:
						LogError(SNAME..."Redundant Jump on \"%s\" offset!", soffs);
					
					case 1:
						instr.SetJmpOffset(instr.jmpOffs + patch1Length);
					
					case -1:
						instr.SetJmpOffset(instr.jmpOffs + patch1Length + patch2Length);
					
					case -2:
						instr.SetJmpOffset(instr.jmpOffs + patch1Length + patch2Length);
					
					default:
						SetFailState(SNAME..."Unimplemented section returned!");
				}
			}
			
			case 1:
			{
				switch(DetermineSection(sections, instr.base))
				{
					case 0:
						instr.SetJmpOffset(instr.jmpOffs - patch1Length);
					
					case 1:
						LogError(SNAME..."Redundant Jump on \"%s\" offset!", soffs);
					
					case -2:
						instr.SetJmpOffset(instr.jmpOffs + patch2Length);
					
					default:
						SetFailState(SNAME..."Unimplemented section returned!");
				}
			}
			
			case -2:
			{
				
				switch(DetermineSection(sections, instr.base))
				{
					case 0:
						instr.SetJmpOffset(instr.jmpOffs - patch1Length - patch2Length);
					
					case 1:
						instr.SetJmpOffset(instr.jmpOffs - patch2Length);
					
					case -2:
						LogError(SNAME..."Redundant Jump on \"%s\" offset!", soffs);
					
					default:
						SetFailState(SNAME..."Unimplemented section returned!");
				}
			}
			
			default:
				SetFailState(SNAME..."Unimplemented section returned!");
		}
	}
}

stock int DetermineSection(Section[] sections1, Address addr)
{
	for(int i = 0; i < NUM_SECTIONS; i++)
		if(sections1[i].start <= addr <= sections1[i].end)
			return i;
	
	return addr < sections1[0].start ? -2 : -1;
}

void StartPatching(GameData gd)
{
	Address patchAddr = gd.GetAddress("FirstPatch");
	int patchSize = gd.GetOffset("FirstPatchSize");
	
	PatchArea(patchAddr, patchSize);
	
	patchAddr = gd.GetAddress("SecondPatch");
	patchSize = gd.GetOffset("SecondPatchSizePt1");
	
	PatchArea(patchAddr, patchSize);
	
	patchAddr += patchSize + gd.GetOffset("SecondPatchSizeSkip");
	patchSize = gd.GetOffset("SecondPatchSizePt2");
	
	PatchArea(patchAddr, patchSize);
}

stock void GetOSKey(char[] key, int len)
{
	switch(gOSType)
	{
		case OSWindows:
			strcopy(key, len, "win_jmp_instruction_");
		
		case OSLinux:
			strcopy(key, len, "lin_jmp_instruction_");
		
		default:
			SetFailState(SNAME..."Unsupported OS Type found!");
	}
}