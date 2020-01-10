enum //x86RelativeJumpOpcodes
{
	X86_SHORT_START	= 0x70,
	X86_SHORT_JO	= X86_SHORT_START,
	X86_SHORT_JNO	= 0x71,
	X86_SHORT_JB	= 0x72,
	X86_SHORT_JAE	= 0x73,
	X86_SHORT_JE	= 0x74,
	X86_SHORT_JNZ	= 0x75,
	X86_SHORT_JBE	= 0x76,
	X86_SHORT_JA	= 0x77,
	X86_SHORT_JS	= 0x78,
	X86_SHORT_JNS	= 0x79,
	X86_SHORT_JP	= 0x7A,
	X86_SHORT_JPO	= 0x7B,
	X86_SHORT_JL	= 0x7C,
	X86_SHORT_JGE	= 0x7D,
	X86_SHORT_JLE	= 0x7E,
	X86_SHORT_JG	= 0x7F,
	X86_SHORT_END	= X86_SHORT_JG,
	X86_SHORT_JECXZ	= 0xE3,
	X86_NEAR_FIRST	= 0x0F,
	X86_NEAR_START	= 0x800F,
	X86_NEAR_JO		= X86_NEAR_START,
	X86_NEAR_JNO	= 0x810F,
	X86_NEAR_JB		= 0x820F,
	X86_NEAR_JAE	= 0x830F,
	X86_NEAR_JE		= 0x840F,
	X86_NEAR_JNE	= 0x850F,
	X86_NEAR_JBE	= 0x860F,
	X86_NEAR_JA		= 0x870F,
	X86_NEAR_JS		= 0x880F,
	X86_NEAR_JNS	= 0x890F,
	X86_NEAR_JP		= 0x8A0F,
	X86_NEAR_JPO	= 0x8B0F,
	X86_NEAR_JL		= 0x8C0F,
	X86_NEAR_JGE	= 0x8D0F,
	X86_NEAR_JLE	= 0x8E0F,
	X86_NEAR_JG		= 0x8F0F,
	X86_NEAR_END	= X86_NEAR_JG,
	X86_NEAR_CALL	= 0xE8,
	X86_SHORT_JMP	= 0xEB,
	X86_NEAR_JMP	= 0xE9
}

stock bool IsX86JumpOpcode(int op)
{
	return X86_SHORT_START <= op <= X86_SHORT_END || op == X86_SHORT_JECXZ || X86_NEAR_START <= op <= X86_NEAR_END || op == X86_SHORT_JMP || op == X86_NEAR_JMP || op == X86_NEAR_CALL;
}

stock NumberType GetX86JumpOpcodeJumpSize(int op)
{
	ASSERT(IsX86JumpOpcode(op))
	
	if(X86_SHORT_START <= op <= X86_SHORT_END || op == X86_SHORT_JECXZ || op == X86_SHORT_JMP)
		return NumberType_Int8;
	else if(X86_NEAR_START <= op <= X86_NEAR_END || op == X86_NEAR_JMP || op == X86_NEAR_CALL)
		return NumberType_Int32;
	else
		return view_as<NumberType>(-1); //Should never happen
}

enum struct x86JumpInstruction
{
	Address base;
	Address jmpOffs;
	int baseLen;
	int jmpLen;
	int opcode;
	
	void ResolveInstruction(Address addr, const char[] soffs)
	{
		ASSERT(addr != Address_Null);
		
		this.base = addr;
		
		this.opcode = LoadFromAddress(this.base, NumberType_Int8);
		this.baseLen = 1;
		
		if(this.opcode == X86_NEAR_FIRST)
		{
			this.opcode = LoadFromAddress(this.base, NumberType_Int16);
			this.baseLen = 2;
		}
		
		ASSERT_FMT(IsX86JumpOpcode(this.opcode), "Jump instruction at \"%s\" offset cannot be found!", soffs);
		
		NumberType type = GetX86JumpOpcodeJumpSize(this.opcode);
		switch(type)
		{
			case NumberType_Int8:
				this.jmpLen = 1;
			
			case NumberType_Int16:
				this.jmpLen = 2;
			
			case NumberType_Int32:
				this.jmpLen = 4;
		}
		
		this.jmpOffs = view_as<Address>(LoadFromAddress(this.base + this.baseLen, type));
	}
	
	void SetJmpOffset(any offs)
	{
		ASSERT((this.jmpLen == 1 && -128 <= offs < 128) || this.jmpLen > 1)
		
		this.jmpOffs = offs;
		StoreToAddress(this.base + this.baseLen, offs, GetX86JumpOpcodeJumpSize(this.opcode));
	}
	
	Address GetJmpTo()
	{
		return this.base + this.baseLen + this.jmpLen + this.jmpOffs;
	}
}